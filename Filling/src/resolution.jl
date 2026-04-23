include("io.jl")
using JuMP, CPLEX

# ==============================================================================
# resolution.jl — Résolution du jeu Filling par PLNE + callback CPLEX
# ==============================================================================
#
# Règle du jeu : remplir la grille par des chiffres de façon à ce que
# chaque chiffre x figure dans une zone CONNEXE de x cases de valeur x.
#
# Modèle PLNE :
#   Variables : x[i,j,k] ∈ {0,1} = 1 si la case (i,j) reçoit la valeur k
#
#   (C1) Chaque case reçoit exactement une valeur :
#        ∀(i,j) :  Σ_k x[i,j,k] = 1
#
#   (C2) Cases pré-remplies :
#        ∀(i,j) telle que grid[i,j] = v > 0 : x[i,j,v] = 1
#
#   (C3) Divisibilité : le nombre total de cases de valeur k
#        doit être un multiple de k :
#        ∀k :  Σ_{i,j} x[i,j,k] = k * n_k,   n_k ∈ ℤ⁺
#
#   (C4) Isolation des 1 (cas particulier simple) :
#        Deux cases adjacentes ne peuvent pas être toutes les deux de valeur 1 :
#        ∀ paire adjacente (u,v) : x[u,1] + x[v,1] ≤ 1
#
#   Règle difficile (gérée par callback) :
#        Chaque composante connexe de cases de valeur k a exactement k cases.
#        → Si CPLEX trouve une solution avec une composante de taille s ≠ k,
#          on ajoute la contrainte :
#          Σ_{(i,j) ∈ composante} x[i,j,k]  ≤  |composante| - 1
#          (au moins une case de cette composante doit changer de valeur)
# ==============================================================================

# ---------------------------------------------------------------------------
# Utilitaire : BFS pour trouver la composante connexe d'une case
# ---------------------------------------------------------------------------
function bfsComponent(assign::Matrix{Int}, visited::Matrix{Bool},
                      n::Int, m::Int, i0::Int, j0::Int)
    k = assign[i0, j0]
    component = Tuple{Int,Int}[]
    queue = Tuple{Int,Int}[(i0, j0)]
    visited[i0, j0] = true
    while !isempty(queue)
        ci, cj = popfirst!(queue)
        push!(component, (ci, cj))
        for (di, dj) in ((-1,0),(1,0),(0,-1),(0,1))
            ni, nj = ci+di, cj+dj
            if 1<=ni<=n && 1<=nj<=m && !visited[ni,nj] && assign[ni,nj]==k
                visited[ni, nj] = true
                push!(queue, (ni, nj))
            end
        end
    end
    return component
end

# ---------------------------------------------------------------------------
# Utilitaire : vérifie la solution et retourne les composantes invalides
# Chaque composante invalide est (valeur_k, liste_des_cases)
# ---------------------------------------------------------------------------
function findInvalidComponents(assign::Matrix{Int}, n::Int, m::Int)
    invalid = Vector{Tuple{Int, Vector{Tuple{Int,Int}}}}()
    visited = falses(n, m)
    for i in 1:n, j in 1:m
        visited[i, j] && continue
        comp = bfsComponent(assign, visited, n, m, i, j)
        k    = assign[i, j]
        if length(comp) != k
            push!(invalid, (k, comp))
        end
    end
    return invalid
end

# ==============================================================================
# Résolution exacte avec callback
# ==============================================================================

"""
Résout une instance Filling par PLNE + callback CPLEX (LazyConstraints).

Retourne :
  - isOptimal : Bool
  - solveTime : Float64 (secondes)
  - assign    : Matrix{Int} n×m  (valeur affectée à chaque case, 0 si non résolu)
"""
function cplexSolve(n::Int, m::Int, grid::Matrix{Int}, maxVal::Int)

    # ---- Borner maxVal à la vraie valeur utile ----
    # Un groupe de valeur k nécessite k cases ; k ne peut donc pas dépasser n*m.
    # En pratique les instances du prof ont des valeurs ≤ 9.
    K = min(maxVal, n * m)

    model = Model(CPLEX.Optimizer)
    set_optimizer_attribute(model, "CPX_PARAM_SCRIND", 0)   # silence
    # IMPORTANT : 1 seul thread obligatoire avec un callback
    MOI.set(model, MOI.NumberOfThreads(), 1)

    # ---- Variables ----
    @variable(model, x[1:n, 1:m, 1:K], Bin)
    # Variables de comptage pour la contrainte de divisibilité
    @variable(model, nk[1:K] >= 0, Int)

    # ---- Objectif (trouver une solution réalisable) ----
    @objective(model, Min, 0)

    # ---- (C1) Chaque case reçoit exactement une valeur ----
    for i in 1:n, j in 1:m
        @constraint(model, sum(x[i, j, k] for k in 1:K) == 1)
    end

    # ---- (C2) Cases pré-remplies ----
    for i in 1:n, j in 1:m
        v = grid[i, j]
        if v > 0
            @constraint(model, x[i, j, v] == 1)
        end
    end

    # ---- (C3) Divisibilité : Σ_{i,j} x[i,j,k] = k * nk[k] ----
    for k in 1:K
        @constraint(model,
            sum(x[i, j, k] for i in 1:n, j in 1:m) == k * nk[k])
    end

    # ---- (C4) Isolation des 1 : deux cases adjacentes ≠ 1 simultanément ----
    for i in 1:n, j in 1:m
        for (di, dj) in ((-1,0),(0,-1))          # chaque paire une seule fois
            ni, nj = i+di, j+dj
            if 1<=ni<=n && 1<=nj<=m
                @constraint(model, x[i,j,1] + x[ni,nj,1] <= 1)
            end
        end
    end

    # =========================================================================
    # Callback : vérification de la connexité des composantes
    # =========================================================================
    #
    # Appelé par CPLEX à chaque solution entière trouvée.
    # Si une composante connexe de valeur k a une taille ≠ k,
    # on ajoute la coupe "no-good" :
    #   Σ_{(i,j) ∈ composante} x[i,j,k]  ≤  |composante| - 1
    #
    # Cette coupe :
    #   - invalide la solution courante (au moins une case doit changer)
    #   - est ciblée (ne concerne qu'une composante précise)
    #   - est ajoutée à la volée → évite d'avoir un nombre exponentiel
    #     de contraintes dès le départ
    # =========================================================================

    function callback_filling(cb_data::CPLEX.CallbackContext, context_id::Clong)

        # On n'intervient que lorsque CPLEX a trouvé une solution entière
        context_id == CPLEX.CPX_CALLBACKCONTEXT_CANDIDATE || return

        ispoint_p = Ref{Cint}()
        ret = CPLEX.CPXcallbackcandidateispoint(cb_data, ispoint_p)
        (ret != 0 || ispoint_p[] == 0) && return

        # Charger les valeurs de la solution entière courante
        CPLEX.load_callback_variable_primal(cb_data, context_id)

        # Récupérer l'affectation : pour chaque case, quelle valeur ?
        assign = zeros(Int, n, m)
        for i in 1:n, j in 1:m, k in 1:K
            if callback_value(cb_data, x[i, j, k]) > 0.9
                assign[i, j] = k
                break
            end
        end

        # Chercher les composantes connexes invalides
        invalid = findInvalidComponents(assign, n, m)

        for (k, comp) in invalid
            # Coupe : au moins une case de cette composante doit changer
            cstr = @build_constraint(
                sum(x[ci, cj, k] for (ci, cj) in comp) <= length(comp) - 1
            )
            MOI.submit(model, MOI.LazyConstraint(cb_data), cstr)
        end
    end

    # Enregistrer le callback
    MOI.set(model, CPLEX.CallbackFunction(), callback_filling)

    # ---- Résolution ----
    t0 = time()
    optimize!(model)
    solveTime = time() - t0

    st = termination_status(model)
    isOptimal = (st == MOI.OPTIMAL || st == MOI.FEASIBLE_POINT)

    assign = zeros(Int, n, m)
    if isOptimal
        for i in 1:n, j in 1:m, k in 1:K
            if value(x[i, j, k]) > 0.9
                assign[i, j] = k
                break
            end
        end
    end

    return isOptimal, solveTime, assign
end

# ==============================================================================
# Résolution du dataset complet
# ==============================================================================

"""
Résout toutes les instances .txt du répertoire dataDir et sauvegarde les résultats.
"""
function solveDataSet(dataDir::String = "../data",
                      resDir::String  = "../res/cplex")
    mkpath(resDir)
    files = sort(filter(f -> endswith(f, ".txt"), readdir(dataDir)))

    for fname in files
        println("\n📁 $fname ...")
        n, m, grid, maxVal = readInputFile(joinpath(dataDir, fname))
        isOptimal, solveTime, assign = cplexSolve(n, m, grid, maxVal)

        println("   $(n)×$(m)  |  optimal=$isOptimal  |  $(round(solveTime, digits=4)) s")
        if isOptimal
            displaySolution(n, m, assign)
        else
            println("   Aucune solution trouvée.")
        end

        open(joinpath(resDir, fname), "w") do f
            println(f, "solveTime = $(round(solveTime, digits=6))")
            println(f, "isOptimal = $isOptimal")
        end
    end
end
