# resolution.jl — Filling game (sans murs)
#
# Corrections apportées par rapport à la version précédente :
#   1. isIntegerPoint : utilise CPXcallbackcandidateispoint (version du prof).
#   2. Contrainte C3 (count) ajoutée avec for-loop explicite pour éviter
#      les problèmes de portée des macros JuMP.
#   3. Pas de C5 (condition de voisinage) : trop restrictive sur la
#      relaxation LP ; le callback gère la connexité.
#   4. heuristicSolve : retourne la dernière tentative (et non copy(grid)).
#   5. Statut CPLEX plus robuste (termination_status + primal_status).

using CPLEX
using JuMP
const MOI = JuMP.MOI

include("generation.jl")

const TOL = 1e-5

# ---------------------------------------------------------------------------
# Helper callback (identique à l'exemple du prof)
# ---------------------------------------------------------------------------

"""
Retourne true si le callback est déclenché par une solution entière.
Identique à isIntegerPoint dans resolutionWithCallback.jl du professeur.
"""
function isIntegerPoint(cb_data::CPLEX.CallbackContext, context_id::Clong)
    context_id != CPX_CALLBACKCONTEXT_CANDIDATE && return false
    ispoint_p = Ref{Cint}()
    ret = CPXcallbackcandidateispoint(cb_data, ispoint_p)
    return ret == 0 && ispoint_p[] != 0
end

# ---------------------------------------------------------------------------
# CPLEX + callback (règle difficile : connexité exacte)
# ---------------------------------------------------------------------------

"""
Résout une instance Filling par PLNE avec callback de connexité.

Modèle ILP
──────────
  Variables :
    x[i,j,k] ∈ {0,1}   = 1 si la case (i,j) a la valeur k
    n_k[k]   ∈ ℤ≥0     = nombre de régions de valeur k

  Contraintes encodées directement :
    C1 — chaque case a exactement une valeur
    C2 — cases pré-remplies fixées
    C3 — comptage : Σ x[i,j,k] = k × n_k[k]  (for-loop explicite)
    C4 — pour k=1 : deux cases adjacentes ne peuvent pas être toutes les 2 = 1

  Règle difficile (connexité) → callback :
    Pour chaque composante S de valeur k avec |S| ≠ k :
      Σ_{(i,j)∈S} x[i,j,k] ≤ |S| − 1
    Même schéma que callback_manhattan du prof (Section 4 du sujet).

Retourne : (SolutionFound, solveTime, sol)
"""
function cplexSolve(n::Int, m::Int, grid::Array{Int,2})

    maxVal = max(maximum(grid), min(n*m, 9))

    model = Model(CPLEX.Optimizer)
    set_optimizer_attribute(model, "CPX_PARAM_SCRIND", 0)  # sortie silencieuse

    @variable(model, x[1:n, 1:m, 1:maxVal], Bin)
    @variable(model, n_k[1:maxVal] >= 0, Int)

    # C1 — une seule valeur par case
    for i in 1:n, j in 1:m
        @constraint(model, sum(x[i,j,k] for k in 1:maxVal) == 1)
    end

    # C2 — indices pré-remplis
    for i in 1:n, j in 1:m
        if grid[i,j] > 0
            @constraint(model, x[i,j,grid[i,j]] == 1)
        end
    end

    # C3 — comptage (for-loop explicite pour éviter les problèmes de portée JuMP)
    for k in 1:maxVal
        @constraint(model,
            sum(x[i,j,k] for i in 1:n for j in 1:m) == k * n_k[k])
    end

    # C4 — isolation pour k=1
    for i in 1:n, j in 1:m
        for (ni, nj) in getNeighbors(n, m, i, j)
            if (ni > i) || (ni == i && nj > j)
                @constraint(model, x[i,j,1] + x[ni,nj,1] <= 1)
            end
        end
    end

    # Objectif : minimiser le nombre total de régions (aide CPLEX)
    @objective(model, Min, sum(n_k[k] for k in 1:maxVal))

    # ── Callback (règle difficile : connexité) ─────────────────────────────
    # Identique au schéma callback_manhattan du professeur :
    #   1. Vérifier que c'est un point entier.
    #   2. Charger les valeurs primales.
    #   3. BFS pour chaque valeur k.
    #   4. Si |composante| ≠ k → couper : Σ x[S,k] ≤ |S| − 1.
    function callback_filling(cb_data::CPLEX.CallbackContext, context_id::Clong)

        isIntegerPoint(cb_data, context_id) || return
        CPLEX.load_callback_variable_primal(cb_data, context_id)
        x_val = callback_value.(cb_data, x)

        for k in 1:maxVal
            visited = falses(n, m)

            for i in 1:n, j in 1:m
                (x_val[i,j,k] > 0.9 && !visited[i,j]) || continue

                # BFS — connexité 4-connexe standard
                component = Tuple{Int,Int}[]
                queue     = [(i,j)]
                visited[i,j] = true

                while !isempty(queue)
                    ci, cj = popfirst!(queue)
                    push!(component, (ci,cj))
                    for (ni,nj) in getNeighbors(n, m, ci, cj)
                        if !visited[ni,nj] && x_val[ni,nj,k] > 0.9
                            visited[ni,nj] = true
                            push!(queue, (ni,nj))
                        end
                    end
                end

                sz = length(component)
                sz == k && continue   # composante valide, rien à faire

                # Couper cette composante invalide
                # (même forme que x[pTopLeft]+x[p]+x[p2] ≤ 2 du prof)
                cstr = @build_constraint(
                    sum(x[component[idx][1], component[idx][2], k]
                        for idx in 1:sz) <= sz - 1
                )
                MOI.submit(model, MOI.LazyConstraint(cb_data), cstr)
            end
        end
    end

    # Thread unique obligatoire avec callback (identique au code du prof)
    MOI.set(model, MOI.NumberOfThreads(), 1)
    MOI.set(model, CPLEX.CallbackFunction(), callback_filling)

    startTime = time()
    optimize!(model)
    solveTime = time() - startTime

    # Vérification robuste du statut (corrigé par rapport à la version initiale)
    status        = termination_status(model)
    SolutionFound = (status == MOI.OPTIMAL ||
                     status == MOI.LOCALLY_SOLVED ||
                     primal_status(model) == MOI.FEASIBLE_POINT)

    sol = zeros(Int, n, m)
    if SolutionFound
        x_val = JuMP.value.(x)
        for i in 1:n, j in 1:m
            for k in 1:maxVal
                if x_val[i,j,k] > TOL
                    sol[i,j] = k
                    break
                end
            end
        end
    end

    return SolutionFound, solveTime, sol
end

# ---------------------------------------------------------------------------
# Heuristique gloutonne (non-énumérative)
# ---------------------------------------------------------------------------

"""
Résolution heuristique par croissance de régions depuis les indices.

Algorithme (non-énumératif, obligatoire pour le jeu le plus difficile) :
  1. Créer des régions germes depuis les cases pré-remplies (BFS).
  2. Étendre la région avec la plus grande capacité restante vers une case
     vide adjacente (priorité à la case avec le moins de voisins assignés).
  3. Gap-fill : les cases encore vides héritent de la valeur voisine
     la plus fréquente.
  4. Valider ; si invalide, relancer jusqu'à maxRestarts fois avec
     un ordre mélangé (pour sortir des optima locaux).

Correction : retourne la dernière tentative (et non copy(grid) si échec).
"""
function heuristicSolve(n::Int, m::Int, grid::Array{Int,2};
                         maxRestarts::Int = 80)

    startTime = time()
    best_sol  = copy(grid)   # ← correction : garder la meilleure tentative

    for attempt in 1:maxRestarts

        sol      = copy(grid)
        assigned = (sol .!= 0)

        # ── Étape 1 : régions germes depuis les indices ───────────────────────
        regions = Vector{Tuple{Int, Vector{Tuple{Int,Int}}, Int}}()
        visited = falses(n, m)

        for i in 1:n, j in 1:m
            (sol[i,j] > 0 && !visited[i,j]) || continue
            v     = sol[i,j]
            comp  = Tuple{Int,Int}[]
            queue = [(i,j)]
            visited[i,j] = true

            while !isempty(queue)
                ci, cj = popfirst!(queue)
                push!(comp, (ci,cj))
                for (ni,nj) in getNeighbors(n, m, ci, cj)
                    if !visited[ni,nj] && sol[ni,nj] == v
                        visited[ni,nj] = true
                        push!(queue, (ni,nj))
                    end
                end
            end

            push!(regions, (v, comp, v))
        end

        # Mélange à partir du 2e essai pour sortir des optima locaux
        attempt > 1 && shuffle!(regions)

        # ── Étape 2 : croissance gloutonne ────────────────────────────────────
        for _ in 1:n*m*20
            all(assigned) && break

            # Plus grande capacité restante en premier
            sort!(regions, by = r -> r[3] - length(r[2]), rev = true)

            grew = false
            for ridx in eachindex(regions)
                (v, cells, target) = regions[ridx]
                length(cells) >= target && continue

                # Cases vides adjacentes à la région
                boundary = Tuple{Int,Int}[]
                for (ci,cj) in cells
                    for (ni,nj) in getNeighbors(n, m, ci, cj)
                        !assigned[ni,nj] && push!(boundary, (ni,nj))
                    end
                end
                unique!(boundary)
                isempty(boundary) && continue

                # Choisir la case frontière avec le moins de voisins assignés
                best_cell  = boundary[1]
                best_score = typemax(Int)
                for bc in boundary
                    sc = count(assigned[ni,nj]
                               for (ni,nj) in getNeighbors(n, m, bc[1], bc[2]))
                    if sc < best_score
                        best_score = sc; best_cell = bc
                    end
                end

                sol[best_cell[1], best_cell[2]] = v
                assigned[best_cell[1], best_cell[2]] = true
                push!(cells, best_cell)
                regions[ridx] = (v, cells, target)
                grew = true
                break
            end

            grew || break
        end

        # ── Étape 3 : gap-fill ────────────────────────────────────────────────
        changed = true
        while changed
            changed = false
            for i in 1:n, j in 1:m
                assigned[i,j] && continue
                freq = Dict{Int,Int}()
                for (ni,nj) in getNeighbors(n, m, i, j)
                    sol[ni,nj] > 0 &&
                        (freq[sol[ni,nj]] = get(freq, sol[ni,nj], 0) + 1)
                end
                isempty(freq) && continue
                sol[i,j]      = argmax(freq)
                assigned[i,j] = true
                changed       = true
            end
        end

        # ── Correction : sauvegarder cette tentative ──────────────────────────
        best_sol = copy(sol)

        # ── Étape 4 : validation ──────────────────────────────────────────────
        checkSolution(n, m, sol, grid) && return true, time()-startTime, sol
    end

    # Retourne la dernière tentative (même invalide) — et non copy(grid)
    return false, time()-startTime, best_sol
end

# ---------------------------------------------------------------------------
# Résolution du dataset
# ---------------------------------------------------------------------------

"""
Résout toutes les instances du dossier data/ avec les méthodes choisies.
Les résultats sont écrits dans res/<méthode>/<fichier>.txt.
Chaque fichier contient solveTime et SolutionFound (requis par resultsArray).
"""
function solveDataSet(dataFolder::String = "data/",
                      resFolder::String  = "res/";
                      methods::Vector{String} = ["cplex","heuristic"],
                      force::Bool = false)

    isdir(dataFolder) || error("Dossier introuvable : $dataFolder")
    isdir(resFolder)  || mkpath(resFolder)
    for method in methods
        isdir(joinpath(resFolder, method)) || mkpath(joinpath(resFolder, method))
    end

    global SolutionFound = false
    global solveTime     = -1.0

    for file in sort(filter(x -> endswith(x,".txt"), readdir(dataFolder)))
        println("── $file")
        n, m, grid = readInputFile(joinpath(dataFolder, file))

        for method in methods
            outputFile = joinpath(resFolder, method, file)
            if !force && isfile(outputFile)
                include(outputFile)
                println("  [$method] (cache) SolutionFound=$SolutionFound  t=$(round(solveTime,sigdigits=3))s")
                continue
            end

            solved = false; rtime = -1.0; sol = zeros(Int,n,m)

            if method == "cplex"
                solved, rtime, sol = cplexSolve(n, m, grid)
            elseif method == "heuristic"
                solved, rtime, sol = heuristicSolve(n, m, grid)
            end

            open(outputFile, "w") do fout
                solved && writeSolution(fout, sol)
                println(fout, "solveTime = ",    rtime)
                println(fout, "SolutionFound = ", solved)
            end

            println("  [$method] SolutionFound=$solved  t=$(round(rtime,sigdigits=3))s")
        end
    end
end