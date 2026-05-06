# This file contains methods to read, display and write results for Filling

using JuMP
using Plots
import GR

# ---------------------------------------------------------------------------
# Read
# ---------------------------------------------------------------------------

"""
Read a Filling instance from a text file.
Format: one row per line, values separated by commas.
  0  -> empty cell (to be filled)
  k  -> pre-filled cell with value k (k ≥ 1)

Returns: n (rows), m (cols), grid (n×m Array{Int,2})
"""
function readInputFile(inputFile::String)
    datafile = open(inputFile)
    data = readlines(datafile)
    close(datafile)

    n = length(data)
    firstRow = [strip(c) for c in split(data[1], ",")]
    m = length(firstRow)

    grid = zeros(Int, n, m)
    for (i, line) in enumerate(data)
        cells = [strip(c) for c in split(line, ",")]
        for (j, c) in enumerate(cells)
            grid[i, j] = parse(Int, c)
        end
    end

    return n, m, grid
end

# ---------------------------------------------------------------------------
# Display
# ---------------------------------------------------------------------------

"""
Display the initial (unsolved) Filling grid.
  0 -> '_' (empty)
  k -> digit k (pre-filled)
"""
function displayGrid(n::Int, m::Int, grid::Array{Int,2})
    sep = "+" * repeat("---+", m)
    println(sep)
    for i in 1:n
        print("|")
        for j in 1:m
            v = grid[i, j]
            print(v == 0 ? " _ " : " $(v) ")
            print("|")
        end
        println()
        println(sep)
    end
end

"""
Display the solved Filling grid (complete assignment).
  k -> digit k
"""
function displaySolution(n::Int, m::Int, sol::Array{Int,2})
    sep = "+" * repeat("---+", m)
    println(sep)
    for i in 1:n
        print("|")
        for j in 1:m
            v = sol[i, j]
            print(v == 0 ? " ? " : " $(v) ")
            print("|")
        end
        println()
        println(sep)
    end
end

# ---------------------------------------------------------------------------
# Validation helper
# ---------------------------------------------------------------------------

"""
Check that a complete Filling solution is valid:
every connected component of value v has exactly v cells.
"""
function checkSolution(n::Int, m::Int, sol::Array{Int,2})
    visited = falses(n, m)
    for i in 1:n, j in 1:m
        visited[i, j] && continue
        v = sol[i, j]
        v == 0 && return false   # incomplete

        # BFS to find the connected component
        component = Tuple{Int,Int}[]
        queue = [(i, j)]
        visited[i, j] = true
        while !isempty(queue)
            ci, cj = popfirst!(queue)
            push!(component, (ci, cj))
            for (di, dj) in [(-1,0),(1,0),(0,-1),(0,1)]
                ni, nj = ci+di, cj+dj
                if 1<=ni<=n && 1<=nj<=m && !visited[ni,nj] && sol[ni,nj] == v
                    visited[ni, nj] = true
                    push!(queue, (ni, nj))
                end
            end
        end

        length(component) != v && return false
    end
    return true
end

# ---------------------------------------------------------------------------
# Results (provided by template — do not modify)
# ---------------------------------------------------------------------------

"""
Create a pdf performance diagram from the ../res folder.
"""
function performanceDiagram(outputFile::String)

    resultFolder = "../res/"

    maxSize = 0
    subfolderCount = 0
    folderName = Array{String,1}()

    for file in readdir(resultFolder)
        path = resultFolder * file
        if isdir(path)
            folderName = vcat(folderName, file)
            subfolderCount += 1
            folderSize = size(readdir(path), 1)
            maxSize < folderSize && (maxSize = folderSize)
        end
    end

    results = fill(Inf, subfolderCount, maxSize)
    folderCount = 0
    maxSolveTime = 0

    for file in readdir(resultFolder)
        path = resultFolder * file
        if isdir(path)
            folderCount += 1
            fileCount = 0
            for resultFile in filter(x -> occursin(".txt", x), readdir(path))
                fileCount += 1
                include(path * "/" * resultFile)
                if isOptimal
                    results[folderCount, fileCount] = solveTime
                    solveTime > maxSolveTime && (maxSolveTime = solveTime)
                end
            end
        end
    end

    results = sort(results, dims=2)
    println("Max solve time: ", maxSolveTime)

    for dim in 1:size(results, 1)
        x = Float64[0]; y = Float64[0]
        currentId = 1
        while currentId <= size(results, 2) && results[dim, currentId] != Inf
            append!(x, results[dim, currentId])
            append!(y, currentId - 1)
            currentId += 1
        end
        append!(x, maxSolveTime); append!(y, currentId - 1)
        if dim == 1
            plot(x, y, label=folderName[dim], legend=:bottomright,
                 xaxis="Time (s)", yaxis="Solved instances", linewidth=3)
        else
            savefig(plot!(x, y, label=folderName[dim], linewidth=3), outputFile)
        end
    end
end

"""
Create a latex array with results from the ../res folder.
"""
function resultsArray(outputFile::String)

    resultFolder = "../res/"
    dataFolder   = "../data/"

    maxSize = 0
    subfolderCount = 0
    fout = open(outputFile, "w")

    println(fout, raw"""\documentclass{article}
\usepackage[french]{babel}
\usepackage[utf8]{inputenc}
\begin{document}""")

    header = raw"""
\begin{center}
\renewcommand{\arraystretch}{1.4}
\begin{tabular}{l"""

    folderName      = String[]
    solvedInstances = String[]

    for file in readdir(resultFolder)
        path = resultFolder * file
        if isdir(path)
            push!(folderName, file)
            subfolderCount += 1
            folderSize = length(readdir(path))
            for f2 in filter(x -> occursin(".txt", x), readdir(path))
                push!(solvedInstances, f2)
            end
            maxSize < folderSize && (maxSize = folderSize)
        end
    end
    unique!(solvedInstances)

    for _ in folderName; header *= "rr"; end
    header *= "}\n\t\\hline\n"
    for f in folderName; header *= " & \\multicolumn{2}{c}{\\textbf{$f}}"; end
    header *= "\\\\\n\\textbf{Instance}"
    for _ in folderName; header *= " & \\textbf{Time (s)} & \\textbf{Optimal?}"; end
    header *= "\\\\\\hline\n"
    footer = "\\hline\\end{tabular}\n\\end{center}\n\n"

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
                isOptimal && print(fout, "\$\\times\$")
            else
                print(fout, " & - & -")
            end
        end
        println(fout, "\\\\")
        id += 1
    end
    println(fout, footer)
    println(fout, "\\end{document}")
    close(fout)
end