using JuMP, CPLEX

# ==============================================================================
# Lecture d'une instance Lightup
# ==============================================================================
# Format du fichier :
#   - Chaque ligne de la grille est une ligne du fichier, cellules séparées par ','
#   - '.' = case blanche (peut recevoir une lampe)
#   - 'N' = case noire sans contrainte
#   - '0','1','2','3','4' = case noire avec contrainte numérique
#
# Exemple de grille 5x5 :
#   ., ., N, ., .
#   ., 3, ., ., N
#   N, ., ., 0, .
#   ., ., N, ., .
#   ., N, ., ., .
# ==============================================================================

"""
Lit un fichier d'instance Lightup et retourne :
  - n : nombre de lignes
  - m : nombre de colonnes
  - grid : matrice n×m de String représentant chaque case
           "." = blanche, "N" = noire sans chiffre, "0"-"4" = noire chiffrée
"""
function readInputFile(path::String)
    lines = readlines(path)
    # Filtrer les lignes vides
    lines = filter(l -> strip(l) != "", lines)

    n = length(lines)
    rows = Vector{Vector{String}}()
    for line in lines
        cells = split(line, ",")
        push!(rows, [strip(c) for c in cells])
    end
    m = maximum(length(r) for r in rows)

    grid = fill(".", n, m)
    for i in 1:n
        for j in 1:length(rows[i])
            grid[i, j] = rows[i][j]
        end
    end

    return n, m, grid
end

# ==============================================================================
# Affichage de la grille non résolue
# ==============================================================================
"""
Affiche la grille initiale dans la console.
  - '.' = case blanche vide
  - '#' = case noire sans chiffre
  - chiffre = case noire avec contrainte
"""
function displayGrid(n::Int, m::Int, grid::Matrix{String})
    sep = "+" * repeat("---+", m)
    println(sep)
    for i in 1:n
        row = "|"
        for j in 1:m
            c = grid[i, j]
            if c == "."
                row *= " . |"
            elseif c == "N"
                row *= "###|"
            else
                row *= " $c |"
            end
        end
        println(row)
        println(sep)
    end
end

# ==============================================================================
# Affichage de la solution
# ==============================================================================
"""
Affiche la grille résolue dans la console.
  - 'L' = lampe placée sur une case blanche
  - '·' = case blanche éclairée (pas de lampe)
  - '#' = case noire sans chiffre
  - chiffre = case noire avec contrainte
"""
function displaySolution(n::Int, m::Int, grid::Matrix{String}, x_val::Matrix{Float64})
    sep = "+" * repeat("---+", m)
    println(sep)
    for i in 1:n
        row = "|"
        for j in 1:m
            c = grid[i, j]
            if c == "."
                if x_val[i, j] > 0.9
                    row *= " L |"   # Lampe
                else
                    row *= " · |"   # Case éclairée sans lampe
                end
            elseif c == "N"
                row *= "###|"
            else
                row *= " $c |"
            end
        end
        println(row)
        println(sep)
    end
end

# ==============================================================================
# Tableau de résultats
# ==============================================================================
"""
Affiche un tableau récapitulatif des résultats de résolution pour un dataset.
"""
function resultsArray(dataDir::String, resDir::String)
    println("\n" * "="^70)
    println(rpad("Instance", 25) *
            rpad("Taille", 10) *
            rpad("Optimal", 10) *
            rpad("Temps (s)", 12))
    println("="^70)

    files = filter(f -> endswith(f, ".txt"), readdir(dataDir))
    sort!(files)

    for fname in files
        resFile = joinpath(resDir, replace(fname, ".txt" => ".txt"))
        if isfile(resFile)
            lines = readlines(resFile)
            solveTime = "?"
            isOptimal = "?"
            gridSize  = "?"

            # Lire le fichier d'instance pour obtenir la taille
            n, m, _ = readInputFile(joinpath(dataDir, fname))
            gridSize = "$(n)×$(m)"

            for l in lines
                if startswith(l, "solveTime")
                    solveTime = split(l, "=")[2] |> strip
                end
                if startswith(l, "isOptimal")
                    isOptimal = split(l, "=")[2] |> strip
                end
            end

            println(rpad(fname, 25) *
                    rpad(gridSize, 10) *
                    rpad(isOptimal, 10) *
                    rpad(solveTime, 12))
        end
    end
    println("="^70 * "\n")
end
