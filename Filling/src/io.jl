using JuMP, CPLEX

# ==============================================================================
# io.jl — Lecture / affichage / résultats pour le jeu Filling
# ==============================================================================
# Format du fichier d'instance :
#   - Une ligne par rangée de la grille, valeurs séparées par des virgules.
#   - 0 = case vide (à remplir), entier positif = case pré-remplie.
#
# Exemple de grille 4×4 :
#   3, 0, 0, 2
#   0, 0, 0, 0
#   0, 2, 0, 0
#   3, 0, 0, 3
# ==============================================================================

"""
Lit un fichier d'instance Filling.
Retourne :
  - n       : nombre de lignes
  - m       : nombre de colonnes
  - grid    : Matrix{Int} n×m  (0 = vide, k>0 = valeur imposée)
  - maxVal  : valeur maximale présente dans la grille (borne sur k)
"""
function readInputFile(path::String)
    lines = filter(l -> strip(l) != "", readlines(path))
    n = length(lines)

    rows = [[parse(Int, strip(v)) for v in split(l, ",")] for l in lines]
    m = maximum(length(r) for r in rows)

    grid = zeros(Int, n, m)
    for i in 1:n, j in 1:length(rows[i])
        grid[i, j] = rows[i][j]
    end

    # La valeur max connue borne les valeurs possibles
    maxVal = max(maximum(grid), n * m)
    # En pratique on plafonne à n*m (taille de la grille)
    maxVal = min(maxVal, n * m)

    return n, m, grid, maxVal
end

# ==============================================================================
# Affichage grille initiale
# ==============================================================================

"""
Affiche la grille non résolue (0 = case vide affichée comme '.').
"""
function displayGrid(n::Int, m::Int, grid::Matrix{Int})
    sep = "+" * repeat("----+", m)
    println(sep)
    for i in 1:n
        row = "|"
        for j in 1:m
            v = grid[i, j]
            row *= v == 0 ? "  . |" : lpad(string(v), 3) * " |"
        end
        println(row)
        println(sep)
    end
end

# ==============================================================================
# Affichage solution
# ==============================================================================

"""
Affiche la grille résolue.
assign[i,j] = valeur affectée à la case (i,j).
"""
function displaySolution(n::Int, m::Int, assign::Matrix{Int})
    sep = "+" * repeat("----+", m)
    println(sep)
    for i in 1:n
        row = "|"
        for j in 1:m
            row *= lpad(string(assign[i, j]), 3) * " |"
        end
        println(row)
        println(sep)
    end
end

# ==============================================================================
# Tableau de résultats
# ==============================================================================

"""
Affiche le tableau récapitulatif des résultats pour le dataset.
"""
function resultsArray(dataDir::String = "../data",
                      resDir::String  = "../res/cplex")
    println("\n" * "="^70)
    println(rpad("Instance", 28) * rpad("Taille", 10) *
            rpad("Optimal", 10) * rpad("Temps (s)", 12))
    println("="^70)

    files = sort(filter(f -> endswith(f, ".txt"), readdir(dataDir)))
    for fname in files
        resFile = joinpath(resDir, fname)
        isfile(resFile) || continue
        n, m, _, _ = readInputFile(joinpath(dataDir, fname))
        solveTime = "?"; isOptimal = "?"
        for l in readlines(resFile)
            startswith(l, "solveTime") && (solveTime = strip(split(l, "=")[2]))
            startswith(l, "isOptimal") && (isOptimal  = strip(split(l, "=")[2]))
        end
        println(rpad(fname, 28) * rpad("$(n)×$(m)", 10) *
                rpad(isOptimal, 10) * rpad(solveTime, 12))
    end
    println("="^70 * "\n")
end
