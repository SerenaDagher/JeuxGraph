include("resolution.jl")
using Random

# ==============================================================================
# generation.jl — Génération d'instances aléatoires pour Filling
# ==============================================================================
#
# Principe de génération :
#   1. On génère d'abord une solution valide (grille complète) :
#      - On parcourt les cases dans un ordre aléatoire.
#      - Pour chaque case non encore affectée, on choisit une valeur k
#        et on tente d'étendre une zone connexe de taille k à partir de cette case.
#      - Si ce n'est pas possible (pas assez de cases libres adjacentes),
#        on essaie une autre valeur.
#   2. On cache ensuite une partie des cases (on met 0) pour créer l'instance.
#
# Note : les instances générées ne sont pas nécessairement à solution unique.
# ==============================================================================

"""
Génère une grille Filling valide de taille n×m en utilisant un remplissage
glouton aléatoire.
"""
function generateValidGrid(n::Int, m::Int, maxK::Int, rng::AbstractRNG)
    assign = zeros(Int, n, m)

    # Parcourir les cases dans un ordre aléatoire
    cells = shuffle(rng, [(i,j) for i in 1:n, j in 1:m])

    function freeNeighbors(i, j)
        nb = Tuple{Int,Int}[]
        for (di,dj) in ((-1,0),(1,0),(0,-1),(0,1))
            ni, nj = i+di, j+dj
            1<=ni<=n && 1<=nj<=m && assign[ni,nj]==0 && push!(nb,(ni,nj))
        end
        return nb
    end

    for (i0, j0) in cells
        assign[i0, j0] != 0 && continue   # déjà affecté

        # Chercher les valeurs possibles (petites en priorité = plus facile à placer)
        maxK_here = min(maxK, n*m)
        ks = shuffle(rng, 1:min(maxK_here, 6))

        placed = false
        for k in ks
            k == 1 && assign[i0,j0]==0 || true  # toujours essayable
            # Vérifier qu'on peut former une zone de taille k depuis (i0,j0)
            # via BFS glouton dans les cases libres
            if k == 1
                assign[i0, j0] = 1
                placed = true
                break
            end

            # BFS pour trouver k-1 cases libres adjacentes
            zone = [(i0, j0)]
            frontier = freeNeighbors(i0, j0)
            shuffle!(rng, frontier)
            tmp_assign = copy(assign)
            tmp_assign[i0, j0] = k

            success = false
            while length(zone) < k && !isempty(frontier)
                ci, cj = popfirst!(frontier)
                tmp_assign[ci,cj] != 0 && continue
                push!(zone, (ci,cj))
                tmp_assign[ci, cj] = k
                new_nb = [(i+di, j+dj)
                          for (i,j) in [(ci,cj)]
                          for (di,dj) in ((-1,0),(1,0),(0,-1),(0,1))
                          if 1<=i+di<=n && 1<=j+dj<=m && tmp_assign[i+di,j+dj]==0]
                shuffle!(rng, new_nb)
                append!(frontier, new_nb)
            end

            if length(zone) == k
                # Appliquer la zone
                for (zi,zj) in zone
                    assign[zi,zj] = k
                end
                placed = true
                break
            end
        end

        # Si on n'a pas réussi, affecter 1 (cas de secours)
        if !placed
            assign[i0, j0] = 1
        end
    end

    # Corriger les erreurs résiduelles : zones de valeur k de taille ≠ k
    # (peut arriver avec l'heuristique gloutonne) → on les met à 1
    visited = falses(n, m)
    for i in 1:n, j in 1:m
        visited[i,j] && continue
        comp = Tuple{Int,Int}[]
        q = [(i,j)]; visited[i,j]=true
        k = assign[i,j]
        while !isempty(q)
            ci,cj = popfirst!(q)
            push!(comp,(ci,cj))
            for (di,dj) in ((-1,0),(1,0),(0,-1),(0,1))
                ni,nj=ci+di,cj+dj
                1<=ni<=n && 1<=nj<=m && !visited[ni,nj] && assign[ni,nj]==k &&
                    (visited[ni,nj]=true; push!(q,(ni,nj)))
            end
        end
        if length(comp) != k
            for (ci,cj) in comp; assign[ci,cj]=1; end
        end
    end

    return assign
end

"""
Génère une instance Filling aléatoire et la sauvegarde dans path.

Paramètres :
  - n, m          : taille de la grille
  - revealRatio   : proportion de cases pré-remplies dans l'instance (défaut 0.3)
  - maxK          : valeur maximale autorisée dans la grille (défaut 6)
  - path          : chemin du fichier de sortie
"""
function generateInstance(n::Int            = 6,
                          m::Int            = 6,
                          revealRatio::Float64 = 0.30,
                          maxK::Int         = 6,
                          path::String      = "../data/instance_$(n)x$(m)_$(rand(1000:9999)).txt";
                          seed::Int         = rand(1:100000))
    rng = MersenneTwister(seed)

    solution = generateValidGrid(n, m, maxK, rng)

    # Masquer des cases (mettre à 0)
    grid = copy(solution)
    for i in 1:n, j in 1:m
        rand(rng) > revealRatio && (grid[i,j] = 0)
    end

    mkpath(dirname(path) == "" ? "." : dirname(path))
    open(path, "w") do f
        for i in 1:n
            println(f, join(grid[i,:], ", "))
        end
    end

    println("Instance générée : $path  ($(n)×$(m), maxK=$maxK)")
    return path
end

"""
Génère un dataset d'instances de tailles variées.
"""
function generateDataSet(dataDir::String = "../data", seed::Int = 42)
    Random.seed!(seed)
    mkpath(dataDir)

    # (n, m, revealRatio, maxK, nb_instances)
    configs = [
        (3, 3, 0.40, 3, 3),
        (4, 4, 0.35, 4, 3),
        (5, 5, 0.30, 5, 3),
        (6, 6, 0.30, 6, 3),
        (7, 7, 0.28, 7, 3),
        (8, 8, 0.25, 8, 2),
        (9, 9, 0.25, 9, 2),
    ]

    k = 1
    for (n, m, rr, mk, count) in configs
        for rep in 1:count
            fname = "instance_$(lpad(k,3,'0'))_$(n)x$(m).txt"
            generateInstance(n, m, rr, mk, joinpath(dataDir, fname); seed=seed+k)
            k += 1
        end
    end
    println("\n✅ $(k-1) instances générées dans $dataDir")
end
