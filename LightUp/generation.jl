include("io.jl")
include("resolution.jl")

using Random

# ==============================================================================
# Génération d'une instance Lightup
# ==============================================================================

"""
Génère une instance aléatoire de Lightup et la sauvegarde dans path.

Paramètres :
  - n         : nombre de lignes de la grille
  - m         : nombre de colonnes de la grille
  - blackRatio: proportion approximative de cases noires (entre 0 et 1)
  - numberedRatio : proportion de cases noires qui portent un chiffre (entre 0 et 1)
  - path      : chemin du fichier de sortie

Principe de génération :
  1. Créer une grille de cases blanches.
  2. Placer aléatoirement des cases noires.
  3. Pour chaque case noire, décider (avec une probabilité numberedRatio)
     si elle porte un chiffre. Si oui, calculer combien de voisins blancs
     elle a et choisir aléatoirement un nombre entre 0 et ce max.

Note : Les instances générées ne sont pas garanties d'être uniques ou résolubles,
mais elles sont valides (contraintes cohérentes).
"""
function generateInstance(n::Int = 7,
                          m::Int = 7,
                          blackRatio::Float64 = 0.25,
                          numberedRatio::Float64 = 0.4,
                          path::String = "../data/instance_$(n)x$(m)_$(rand(1000:9999)).txt")

    grid = fill(".", n, m)

    # Placer les cases noires aléatoirement
    for i in 1:n, j in 1:m
        if rand() < blackRatio
            # Décider si la case noire est numérotée
            if rand() < numberedRatio
                # Compter le nombre de voisins blancs potentiels (cases non noires à ce stade)
                # On prend un nombre entre 0 et 4
                maxAdj = 0
                for (di, dj) in [(-1,0),(1,0),(0,-1),(0,1)]
                    ni, nj = i+di, j+dj
                    1 <= ni <= n && 1 <= nj <= m && (maxAdj += 1)
                end
                k = rand(0:min(maxAdj, 4))
                grid[i, j] = string(k)
            else
                grid[i, j] = "N"
            end
        end
    end

    # Vérification post-génération des cases numérotées :
    # S'assurer que le nombre k de la case ne dépasse pas le nombre de voisins blancs réels
    for i in 1:n, j in 1:m
        c = grid[i, j]
        if length(c) == 1 && isdigit(c[1])
            k = parse(Int, c)
            nbWhiteNeighbors = 0
            for (di, dj) in [(-1,0),(1,0),(0,-1),(0,1)]
                ni, nj = i+di, j+dj
                if 1 <= ni <= n && 1 <= nj <= m && grid[ni, nj] == "."
                    nbWhiteNeighbors += 1
                end
            end
            # Ajuster k si nécessaire
            if k > nbWhiteNeighbors
                grid[i, j] = string(nbWhiteNeighbors)
            end
        end
    end

    # Écriture du fichier
    mkpath(dirname(path))
    open(path, "w") do f
        for i in 1:n
            println(f, join(grid[i, :], ", "))
        end
    end

    println("Instance générée : $path ($(n)×$(m))")
    return path
end

# ==============================================================================
# Génération d'un dataset
# ==============================================================================

"""
Génère un ensemble d'instances de Lightup dans le répertoire dataDir.

Génère des instances de différentes tailles pour permettre l'analyse
des temps de calcul en fonction de la taille.
"""
function generateDataSet(dataDir::String = "../data",
                         seed::Int = 42)
    Random.seed!(seed)
    mkpath(dataDir)

    # Configurations : (n, m, blackRatio, numberedRatio, nb_instances)
    configs = [
        (4,  4,  0.20, 0.4, 3),   # Petites instances
        (5,  5,  0.22, 0.4, 3),
        (7,  7,  0.25, 0.4, 3),   # Instances moyennes
        (8,  8,  0.25, 0.4, 3),
        (10, 10, 0.28, 0.4, 3),   # Instances plus grandes
        (12, 12, 0.28, 0.4, 2),
        (15, 15, 0.30, 0.4, 2),   # Grandes instances
    ]

    generated = String[]
    instanceNum = 1

    for (n, m, br, nr, count) in configs
        for _ in 1:count
            fname = "instance_$(lpad(instanceNum, 3, '0'))_$(n)x$(m).txt"
            path = joinpath(dataDir, fname)
            generateInstance(n, m, br, nr, path)
            push!(generated, path)
            instanceNum += 1
        end
    end

    println("\n✅ $(length(generated)) instances générées dans $dataDir")
    return generated
end
