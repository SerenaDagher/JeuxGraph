# io.jl — Filling game (sans murs)

# ---------------------------------------------------------------------------
# Lecture de l'instance
# ---------------------------------------------------------------------------

"""
Lit une instance Filling depuis un fichier texte.

Format : n lignes de m valeurs séparées par des virgules.
  0 = case vide,  k = valeur pré-remplie k

Retourne : (n, m, grid)
"""
function readInputFile(inputFile::String)
    data = filter(l -> !isempty(strip(l)), readlines(inputFile))
    n = length(data)
    m = length(split(data[1], ","))

    grid = zeros(Int, n, m)
    for (i, line) in enumerate(data)
        for (j, c) in enumerate(split(line, ","))
            grid[i, j] = parse(Int, strip(c))
        end
    end

    return n, m, grid
end

# ---------------------------------------------------------------------------
# Affichage
# ---------------------------------------------------------------------------

"""Affiche la grille initiale (cases vides = '_')."""
function displayGrid(n::Int, m::Int, grid::Array{Int,2})
    sep = "+" * repeat("---+", m)
    println(sep)
    for i in 1:n
        row = "|"
        for j in 1:m
            v = grid[i, j]
            row *= (v == 0 ? " _ " : lpad(string(v), 2) * " ") * "|"
        end
        println(row)
        println(sep)
    end
end

"""Affiche la grille résolue (cases non remplies = '?')."""
function displaySolution(n::Int, m::Int, sol::Array{Int,2})
    sep = "+" * repeat("---+", m)
    println(sep)
    for i in 1:n
        row = "|"
        for j in 1:m
            v = sol[i, j]
            row *= (v == 0 ? " ? " : lpad(string(v), 2) * " ") * "|"
        end
        println(row)
        println(sep)
    end
end

# ---------------------------------------------------------------------------
# Voisins
# ---------------------------------------------------------------------------

"""Retourne les 4 voisins orthogonaux valides de (i,j)."""
function getNeighbors(n::Int, m::Int, i::Int, j::Int)
    nbrs = Tuple{Int,Int}[]
    for (di, dj) in ((-1,0),(1,0),(0,-1),(0,1))
        ni, nj = i+di, j+dj
        1 <= ni <= n && 1 <= nj <= m && push!(nbrs, (ni, nj))
    end
    return nbrs
end

# ---------------------------------------------------------------------------
# Validation
# ---------------------------------------------------------------------------

"""
Vérifie qu'une solution Filling est valide :
  - toutes les cases sont remplies,
  - les indices pré-remplis sont respectés,
  - chaque composante connexe de valeur v contient exactement v cases.
"""
function checkSolution(n::Int, m::Int, sol::Array{Int,2},
                       grid::Array{Int,2} = zeros(Int, n, m))
    # Cases non remplies
    any(sol .== 0) && return false

    # Indices pré-remplis
    for i in 1:n, j in 1:m
        grid[i,j] > 0 && sol[i,j] != grid[i,j] && return false
    end

    # Connexité : chaque composante de valeur v a exactement v cases
    visited = falses(n, m)
    for i in 1:n, j in 1:m
        visited[i,j] && continue
        v     = sol[i,j]
        queue = [(i,j)]
        visited[i,j] = true
        sz = 0

        while !isempty(queue)
            ci, cj = popfirst!(queue)
            sz += 1
            for (ni, nj) in getNeighbors(n, m, ci, cj)
                if !visited[ni,nj] && sol[ni,nj] == v
                    visited[ni,nj] = true
                    push!(queue, (ni,nj))
                end
            end
        end

        sz != v && return false
    end

    return true
end

# ---------------------------------------------------------------------------
# Écriture des résultats
# ---------------------------------------------------------------------------

function writeSolution(fout::IOStream, sol::Array{Int,2})
    n, m = size(sol)
    println(fout, "sol = [")
    for i in 1:n
        print(fout, "[ ")
        for j in 1:m; print(fout, sol[i,j], " "); end
        println(fout, i == n ? "]" : "];")
    end
    println(fout, "]")
end

function resultsArray(outputFile::String)
    resultFolder = "res/"
    fout = open(outputFile, "w")
    println(fout, "\\documentclass{article}\n\\usepackage[utf8]{inputenc}\n\\begin{document}")

    folderName = String[]; solvedInstances = String[]
    for file in readdir(resultFolder)
        path = resultFolder * file
        if isdir(path)
            push!(folderName, file)
            for f2 in filter(x -> endswith(x,".txt"), readdir(path))
                push!(solvedInstances, f2)
            end
        end
    end
    unique!(solvedInstances)

    header = "\\begin{center}\\renewcommand{\\arraystretch}{1.4}\\begin{tabular}{l" *
             repeat("rr", length(folderName)) * "}\n\\hline\n"
    for f in folderName; header *= " & \\multicolumn{2}{c}{\\textbf{$f}}"; end
    header *= "\\\\\n\\textbf{Instance}"
    for _  in folderName; header *= " & \\textbf{Temps (s)} & \\textbf{Sol?}"; end
    header *= "\\\\\\hline\n"
    footer  = "\\hline\\end{tabular}\n\\end{center}\n\n"

    println(fout, header)
    id = 1
    for inst in solvedInstances
        id % 30 == 0 && println(fout, footer * "\\newpage\n" * header)
        print(fout, replace(inst, "_" => "\\_"))
        for method in folderName
            path = resultFolder * method * "/" * inst
            if isfile(path)
                include(path)
                print(fout, " & ", round(solveTime, digits=2), " & ")
                SolutionFound && print(fout, "\$\\times\$")
            else
                print(fout, " & - & -")
            end
        end
        println(fout, "\\\\"); id += 1
    end
    println(fout, footer, "\\end{document}")
    close(fout)
end