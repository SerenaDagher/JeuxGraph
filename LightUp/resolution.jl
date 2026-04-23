using JuMP, CPLEX
include("io.jl")

# ==============================================================================
# Fonctions utilitaires : calcul des segments et voisins
# ==============================================================================

"""
Retourne true si la case (i,j) est blanche (peut recevoir une lampe).
"""
function isWhite(grid::Matrix{String}, i::Int, j::Int)
    return grid[i, j] == "."
end

"""
Retourne true si la case (i,j) est noire (bloque la lumière).
"""
function isBlack(grid::Matrix{String}, i::Int, j::Int)
    c = grid[i, j]
    return c == "N" || (length(c) == 1 && isdigit(c[1]))
end

"""
Pour une case blanche (i0, j0), retourne l'ensemble des cases blanches
qui peuvent l'éclairer (même ligne ou colonne, sans case noire entre elles,
y compris la case elle-même).
Correspond à L(c) dans le modèle.
"""
function visibleFrom(grid::Matrix{String}, n::Int, m::Int, i0::Int, j0::Int)
    visible = Set{Tuple{Int,Int}}()
    push!(visible, (i0, j0))

    # Vers le haut
    for i in (i0-1):-1:1
        isBlack(grid, i, j0) && break
        push!(visible, (i, j0))
    end
    # Vers le bas
    for i in (i0+1):n
        isBlack(grid, i, j0) && break
        push!(visible, (i, j0))
    end
    # Vers la gauche
    for j in (j0-1):-1:1
        isBlack(grid, i0, j) && break
        push!(visible, (i0, j))
    end
    # Vers la droite
    for j in (j0+1):m
        isBlack(grid, i0, j) && break
        push!(visible, (i0, j))
    end

    return visible
end

"""
Calcule tous les segments maximaux horizontaux et verticaux de cases blanches.
Un segment est un ensemble maximal de cases blanches consécutives sur une ligne
ou colonne (délimité par les bords ou les cases noires).
"""
function computeSegments(grid::Matrix{String}, n::Int, m::Int)
    segments = Vector{Vector{Tuple{Int,Int}}}()

    # Segments horizontaux
    for i in 1:n
        j = 1
        while j <= m
            if isWhite(grid, i, j)
                seg = [(i, j)]
                j += 1
                while j <= m && isWhite(grid, i, j)
                    push!(seg, (i, j))
                    j += 1
                end
                if length(seg) >= 2
                    push!(segments, seg)
                end
            else
                j += 1
            end
        end
    end

    # Segments verticaux
    for j in 1:m
        i = 1
        while i <= n
            if isWhite(grid, i, j)
                seg = [(i, j)]
                i += 1
                while i <= n && isWhite(grid, i, j)
                    push!(seg, (i, j))
                    i += 1
                end
                if length(seg) >= 2
                    push!(segments, seg)
                end
            else
                i += 1
        end
        end
    end

    return segments
end

"""
Retourne les voisins (haut, bas, gauche, droite) blancs d'une case noire numérotée.
Correspond à N(b) dans le modèle.
"""
function whiteNeighbors(grid::Matrix{String}, n::Int, m::Int, i::Int, j::Int)
    neighbors = Vector{Tuple{Int,Int}}()
    for (di, dj) in [(-1,0),(1,0),(0,-1),(0,1)]
        ni, nj = i+di, j+dj
        if 1 <= ni <= n && 1 <= nj <= m && isWhite(grid, ni, nj)
            push!(neighbors, (ni, nj))
        end
    end
    return neighbors
end

# ==============================================================================
# Résolution exacte CPLEX
# ==============================================================================

"""
Résout une instance Lightup par PLNE avec CPLEX.

Retourne :
  - isOptimal : Bool indiquant si une solution optimale (réalisable) a été trouvée
  - solveTime : Float64, durée de résolution en secondes
  - x_val     : Matrix{Float64} n×m, valeurs des variables (1.0 = lampe, 0.0 = non)
"""
function cplexSolve(n::Int, m::Int, grid::Matrix{String})

    m_model = Model(CPLEX.Optimizer)

    # Désactiver les sorties CPLEX
    set_optimizer_attribute(m_model, "CPX_PARAM_SCRIND", 0)

    # ------------------------------------------------------------------
    # Variables : x[i,j] = 1 si une lampe est placée en (i,j), 0 sinon
    # Défini uniquement pour les cases blanches ; les cases noires = 0
    # ------------------------------------------------------------------
    @variable(m_model, x[1:n, 1:m], Bin)

    # Fixer les cases noires à 0
    for i in 1:n, j in 1:m
        if isBlack(grid, i, j)
            @constraint(m_model, x[i, j] == 0)
        end
    end

    # ------------------------------------------------------------------
    # Fonction objectif : minimiser 0 (on cherche une solution réalisable)
    # ------------------------------------------------------------------
    @objective(m_model, Min, 0)

    # ------------------------------------------------------------------
    # Contrainte 1 : chaque case blanche doit être éclairée
    # Pour chaque case blanche c, au moins une lampe dans L(c)
    # ------------------------------------------------------------------
    for i in 1:n, j in 1:m
        if isWhite(grid, i, j)
            visible = visibleFrom(grid, n, m, i, j)
            @constraint(m_model, sum(x[vi, vj] for (vi, vj) in visible) >= 1)
        end
    end

    # ------------------------------------------------------------------
    # Contrainte 2 : au plus une lampe par segment (non-visibilité mutuelle)
    # ∀S segment, Σ_{v∈S} x_v ≤ 1
    # ------------------------------------------------------------------
    segments = computeSegments(grid, n, m)
    for seg in segments
        @constraint(m_model, sum(x[si, sj] for (si, sj) in seg) <= 1)
    end

    # ------------------------------------------------------------------
    # Contrainte 3 : cases noires numérotées
    # ∀b case noire avec valeur kb, Σ_{v∈N(b)} x_v = kb
    # ------------------------------------------------------------------
    for i in 1:n, j in 1:m
        c = grid[i, j]
        if length(c) == 1 && isdigit(c[1])
            kb = parse(Int, c)
            neighbors = whiteNeighbors(grid, n, m, i, j)
            if length(neighbors) == 0 && kb > 0
                # Contrainte infaisable si aucun voisin blanc mais kb > 0
                @constraint(m_model, 0 >= 1)
            elseif length(neighbors) > 0
                @constraint(m_model, sum(x[ni, nj] for (ni, nj) in neighbors) == kb)
            end
        end
    end

    # ------------------------------------------------------------------
    # Résolution
    # ------------------------------------------------------------------
    start = time()
    optimize!(m_model)
    solveTime = time() - start

    isOptimal = termination_status(m_model) == MOI.OPTIMAL ||
                termination_status(m_model) == MOI.FEASIBLE_POINT

    x_val = zeros(Float64, n, m)
    if isOptimal
        for i in 1:n, j in 1:m
            x_val[i, j] = value(x[i, j])
        end
    end

    return isOptimal, solveTime, x_val
end

# ==============================================================================
# Heuristique de résolution (pour le dataset)
# ==============================================================================

"""
Heuristique gloutonne pour Lightup.

Principe :
  1. Trier les cases blanches par nombre de cases qu'elles éclairent (décroissant).
  2. Placer une lampe sur la case qui éclaire le plus de cases non encore éclairées,
     sous réserve de ne pas violer les contraintes de segment ni de cases noires.
  3. Répéter jusqu'à ce que toutes les cases blanches soient éclairées ou qu'on ne
     puisse plus placer de lampe.

Note : l'heuristique ne garantit pas d'obtenir une solution valide dans tous les cas.

Retourne :
  - isComplete : Bool (true si toutes les cases sont éclairées)
  - solveTime  : Float64
  - x_val      : Matrix{Float64}
"""
function heuristicSolve(n::Int, m::Int, grid::Matrix{String})
    start = time()

    x_val = zeros(Float64, n, m)

    # Ensemble des cases blanches non encore éclairées
    unlit = Set{Tuple{Int,Int}}()
    for i in 1:n, j in 1:m
        if isWhite(grid, i, j)
            push!(unlit, (i, j))
        end
    end

    # Nombre de lampes dans chaque segment (pour vérifier la contrainte ≤ 1)
    segments = computeSegments(grid, n, m)
    # Associer chaque case à ses segments
    cellSegments = Dict{Tuple{Int,Int}, Vector{Int}}()
    for (si, seg) in enumerate(segments)
        for cell in seg
            if !haskey(cellSegments, cell)
                cellSegments[cell] = Int[]
            end
            push!(cellSegments[cell], si)
        end
    end
    segLampCount = zeros(Int, length(segments))

    # Compteur de lampes adjacentes aux cases noires numérotées
    blackLampCount = Dict{Tuple{Int,Int}, Int}()
    for i in 1:n, j in 1:m
        c = grid[i, j]
        if length(c) == 1 && isdigit(c[1])
            blackLampCount[(i,j)] = 0
        end
    end

    # Vérifie si on peut placer une lampe en (i,j)
    function canPlace(i, j)
        isWhite(grid, i, j) || return false
        x_val[i, j] > 0.9 && return false
        # Vérifier les contraintes de segment (≤ 1 lampe par segment)
        if haskey(cellSegments, (i,j))
            for si in cellSegments[(i,j)]
                segLampCount[si] >= 1 && return false
            end
        end
        # Vérifier les cases noires numérotées adjacentes (ne pas dépasser kb)
        for (di, dj) in [(-1,0),(1,0),(0,-1),(0,1)]
            ni, nj = i+di, j+dj
            if 1 <= ni <= n && 1 <= nj <= m
                c = grid[ni, nj]
                if length(c) == 1 && isdigit(c[1])
                    kb = parse(Int, c)
                    blackLampCount[(ni,nj)] >= kb && return false
                end
            end
        end
        return true
    end

    # Place une lampe en (i,j) et met à jour les structures
    function placeLamp(i, j)
        x_val[i, j] = 1.0
        visible = visibleFrom(grid, n, m, i, j)
        for cell in visible
            delete!(unlit, cell)
        end
        if haskey(cellSegments, (i,j))
            for si in cellSegments[(i,j)]
                segLampCount[si] += 1
            end
        end
        for (di, dj) in [(-1,0),(1,0),(0,-1),(0,1)]
            ni, nj = i+di, j+dj
            if haskey(blackLampCount, (ni,nj))
                blackLampCount[(ni,nj)] += 1
            end
        end
    end

    # Boucle principale : placer des lampes tant qu'il reste des cases non éclairées
    while !isempty(unlit)
        bestCell = nothing
        bestScore = -1

        for (i, j) in collect(unlit)
            canPlace(i, j) || continue
            visible = visibleFrom(grid, n, m, i, j)
            score = length(intersect(visible, unlit))
            if score > bestScore
                bestScore = score
                bestCell = (i, j)
            end
        end

        bestCell === nothing && break
        placeLamp(bestCell[1], bestCell[2])
    end

    solveTime = time() - start
    isComplete = isempty(unlit)

    return isComplete, solveTime, x_val
end

# ==============================================================================
# Résolution de l'ensemble du dataset
# ==============================================================================

"""
Résout toutes les instances dans dataDir et stocke les résultats dans resDir.
"""
function solveDataSet(dataDir::String = "../data", resDir::String = "../res/cplex")
    mkpath(resDir)
    files = filter(f -> endswith(f, ".txt"), readdir(dataDir))
    sort!(files)

    for fname in files
        println("\n📁 Résolution de $fname ...")
        path = joinpath(dataDir, fname)
        n, m, grid = readInputFile(path)

        isOptimal, solveTime, x_val = cplexSolve(n, m, grid)

        # Affichage
        println("   Taille : $(n)×$(m)")
        println("   Optimal : $isOptimal")
        println("   Temps   : $(round(solveTime, digits=4)) s")
        if isOptimal
            displaySolution(n, m, grid, x_val)
        end

        # Sauvegarde des résultats
        resPath = joinpath(resDir, fname)
        open(resPath, "w") do f
            println(f, "solveTime = $(round(solveTime, digits=6))")
            println(f, "isOptimal = $isOptimal")
        end
    end
end
