
using JuMP
using Plots
import GR


function getNeighbors(n::Int, m::Int, i::Int, j::Int)
    nbrs = Tuple{Int,Int}[]
    for (di, dj) in [(-1,0),(1,0),(0,-1),(0,1)]
        ni, nj = i+di, j+dj
        1<=ni<=n && 1<=nj<=m || continue
        push!(nbrs, (ni, nj))
    end
    return nbrs
end


function readInputFile(inputFile::String)
    datafile = open(inputFile)
    data = readlines(datafile)
    close(datafile)

    sep = findfirst(l -> strip(l) == "WALLS", data)
    grid_lines = sep === nothing ? data : data[1:sep-1]

    n = length(grid_lines)
    m = length(split(grid_lines[1], ","))

    grid = zeros(Int, n, m)
    for (i, line) in enumerate(grid_lines)
        cells = [strip(c) for c in split(line, ",")]
        for (j, c) in enumerate(cells)
            grid[i, j] = parse(Int, c)
        end
    end

    return n, m, grid
end


function displayGrid(n::Int, m::Int, grid::Array{Int,2})
    println("+" * repeat("---+", m))
    for i in 1:n
        print("|")
        for j in 1:m
            v = grid[i, j]
            print(v == 0 ? " _ " : lpad(v, 2) * " ")
            print("|")
        end
        println()
        if i < n
            print("+")
            for j in 1:m
                print("---+")
            end
            println()
        end
    end
    println("+" * repeat("---+", m))
end

function displaySolution(n::Int, m::Int, sol::Array{Int,2})
    println("+" * repeat("---+", m))
    for i in 1:n
        print("|")
        for j in 1:m
            v = sol[i, j]
            print(v == 0 ? " ? " : lpad(v, 2) * " ")
            print("|")
        end
        println()
        if i < n
            print("+")
            for j in 1:m
                print("---+")
            end
            println()
        end
    end
    println("+" * repeat("---+", m))
end


function checkSolution(n::Int, m::Int, sol::Array{Int,2})
    visited = falses(n, m)
    for i in 1:n, j in 1:m
        visited[i, j] && continue
        v = sol[i, j]
        v == 0 && return false

        component = Tuple{Int,Int}[]
        queue = [(i, j)]
        visited[i, j] = true
        while !isempty(queue)
            ci, cj = popfirst!(queue)
            push!(component, (ci, cj))
            for (ni, nj) in getNeighbors(n, m, ci, cj)
                if !visited[ni, nj] && sol[ni, nj] == v
                    visited[ni, nj] = true
                    push!(queue, (ni, nj))
                end
            end
        end

        length(component) != v && return false
    end
    return true
end


function performanceDiagram(outputFile::String)
    resultFolder = "res/"
    maxSize = 0; subfolderCount = 0
    folderName = String[]
    for file in readdir(resultFolder)
        path = resultFolder * file
        if isdir(path)
            push!(folderName, file); subfolderCount += 1
            folderSize = length(readdir(path))
            maxSize < folderSize && (maxSize = folderSize)
        end
    end
    results = fill(Inf, subfolderCount, maxSize)
    folderCount = 0; maxSolveTime = 0
    for file in readdir(resultFolder)
        path = resultFolder * file
        if isdir(path)
            folderCount += 1; fileCount = 0
            for rf in filter(x->occursin(".txt",x), readdir(path))
                fileCount += 1
                include(path * "/" * rf)
                resultFile = path * "/" * rf
                solutionFound = occursin("SolutionFound", read(resultFile, String)) ? Main.SolutionFound : Main.isOptimal
                if solutionFound
                    results[folderCount, fileCount] = solveTime
                    solveTime > maxSolveTime && (maxSolveTime = solveTime)
                end
            end
        end
    end
    results = sort(results, dims=2)
    for dim in 1:size(results,1)
        x = Float64[0]; y = Float64[0]
        cur = 1
        while cur <= size(results,2) && results[dim,cur] != Inf
            append!(x, results[dim,cur]); append!(y, cur-1); cur += 1
        end
        append!(x, maxSolveTime); append!(y, cur-1)
        if dim == 1
            plot(x, y, label=folderName[dim], legend=:bottomright,
                 xaxis="Time (s)", yaxis="Solved instances", linewidth=3)
        else
            savefig(plot!(x, y, label=folderName[dim], linewidth=3), outputFile)
        end
    end
end

function resultsArray(outputFile::String)
    resultFolder = "res/"; dataFolder = "data/"
    maxSize = 0; subfolderCount = 0
    fout = open(outputFile, "w")
    println(fout, "\\documentclass{article}\n\\usepackage[utf8]{inputenc}\n\\begin{document}")
    header = "\\begin{center}\\renewcommand{\\arraystretch}{1.4}\\begin{tabular}{l"
    folderName = String[]; solvedInstances = String[]
    for file in readdir(resultFolder)
        path = resultFolder * file
        if isdir(path)
            push!(folderName, file); subfolderCount += 1
            for f2 in filter(x->occursin(".txt",x), readdir(path))
                push!(solvedInstances, f2)
            end
            length(readdir(path)) > maxSize && (maxSize = length(readdir(path)))
        end
    end
    unique!(solvedInstances)
    for _ in folderName; header *= "rr"; end
    header *= "}\n\t\\hline\n"
    for f in folderName; header *= " & \\multicolumn{2}{c}{\\textbf{$f}}"; end
    header *= "\\\\\n\\textbf{Instance}"
    for _ in folderName; header *= " & \\textbf{Time (s)} & \\textbf{Solution found?}"; end
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
                include(path); print(fout, " & ", round(solveTime, digits=2), " & ")
                solutionFound = occursin("SolutionFound", read(path, String)) ? Main.SolutionFound : Main.isOptimal
                solutionFound && print(fout, "\$\\times\$")
            else; print(fout, " & - & -")
            end
        end
        println(fout, "\\\\"); id += 1
    end
    println(fout, footer); println(fout, "\\end{document}"); close(fout)
end
