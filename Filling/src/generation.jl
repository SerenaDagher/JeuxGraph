# generation.jl — Filling game (sans murs)

include("io.jl")

# ---------------------------------------------------------------------------
# Génération d'une solution complète valide
# ---------------------------------------------------------------------------

"""
Génère une solution Filling complète valide pour une grille n×m.

Stratégie : croissance aléatoire de régions connexes par BFS.
Chaque région reçoit la valeur = sa taille réelle.

Retourne : sol::Matrix{Int}
"""
function generateSolution(n::Int, m::Int, maxVal::Int = min(9, n*m))
    sol       = zeros(Int, n, m)
    remaining = Set{Tuple{Int,Int}}((i,j) for i in 1:n for j in 1:m)

    while !isempty(remaining)
        start = rand(collect(remaining))

        # Taille cible aléatoire
        target = rand(1:min(maxVal, length(remaining)))

        # Croissance BFS depuis start
        region   = [start]
        in_reg   = Set([start])
        delete!(remaining, start)

        frontier = [nb for nb in getNeighbors(n, m, start[1], start[2])
                       if nb in remaining]

        while length(region) < target && !isempty(frontier)
            idx  = rand(1:length(frontier))
            next = frontier[idx]
            push!(region, next); push!(in_reg, next)
            delete!(remaining, next)
            deleteat!(frontier, idx)

            for nb in getNeighbors(n, m, next[1], next[2])
                nb in remaining && nb ∉ in_reg && push!(frontier, nb)
            end
        end

        v = length(region)          # valeur = taille réelle de la région
        for (ri, rj) in region
            sol[ri, rj] = v
        end
    end

    return sol
end

# ---------------------------------------------------------------------------
# Génération d'une instance (grille partielle = indices)
# ---------------------------------------------------------------------------

"""
Génère une instance Filling (grille partiellement remplie) à partir d'une
solution complète.

Pour chaque région connexe, un seul indice est révélé (sauf si density > 0
pour révéler des cases supplémentaires).

Retourne : (n, m, grid)
"""
function generateInstance(n::Int, m::Int;
                           maxVal::Int      = min(9, n*m),
                           density::Float64 = 0.0)
    sol  = generateSolution(n, m, maxVal)
    grid = zeros(Int, n, m)

    visited = falses(n, m)
    for i in 1:n, j in 1:m
        visited[i,j] && continue
        v     = sol[i,j]
        comp  = Tuple{Int,Int}[]
        queue = [(i,j)]
        visited[i,j] = true

        while !isempty(queue)
            ci, cj = popfirst!(queue)
            push!(comp, (ci,cj))
            for (ni, nj) in getNeighbors(n, m, ci, cj)
                if !visited[ni,nj] && sol[ni,nj] == v
                    visited[ni,nj] = true
                    push!(queue, (ni,nj))
                end
            end
        end

        # Toujours révéler au moins un indice par région
        clue = rand(comp)
        grid[clue[1], clue[2]] = v

        # Révéler des cases supplémentaires selon density
        for cell in comp
            cell == clue && continue
            rand() < density && (grid[cell[1], cell[2]] = v)
        end
    end

    return n, m, grid
end

# ---------------------------------------------------------------------------
# Sauvegarde d'une instance
# ---------------------------------------------------------------------------

"""Sauvegarde une instance dans un fichier texte."""
function writeInstance(fileName::String, n::Int, m::Int, grid::Array{Int,2})
    open(fileName, "w") do f
        for i in 1:n
            println(f, join(grid[i,:], ", "))
        end
    end
end

# ---------------------------------------------------------------------------
# Génération d'un jeu de données
# ---------------------------------------------------------------------------

"""
Génère un ensemble d'instances et les sauvegarde dans data/.
"""
function generateDataSet(; clean::Bool = false)
    dataFolder = "data/"
    isdir(dataFolder) || mkpath(dataFolder)

    if clean
        for file in filter(x -> startswith(x,"instance_") && endswith(x,".txt"),
                           readdir(dataFolder))
            rm(joinpath(dataFolder, file))
        end
        println("Instances précédentes supprimées.")
    end

    # (taille, maxVal, nb instances)
    configs = [
        (4,  4,  10),
        (6,  6,  10),
        (8,  8,  10),
        (10, 9,  10),
        (12, 9,  10),
        (15, 9,  10),
    ]

    for (sz, mv, nb) in configs
        for k in 1:nb
            fname = dataFolder * "instance_$(sz)x$(sz)_$(k).txt"
            isfile(fname) && continue
            n, m, grid = generateInstance(sz, sz; maxVal=mv)
            writeInstance(fname, n, m, grid)
            println("Généré : $fname")
        end
    end

    println("Dataset prêt dans ", dataFolder)
end