using JuMP
using Plots
import GR

isBlack(grid::Array{String,2}, i::Int, j::Int) = grid[i,j] != "."

isWhite(grid::Array{String,2}, i::Int, j::Int) = grid[i,j] == "."

function readInputFile(inputFile::String)
    datafile = open(inputFile)
    data = readlines(datafile)
    close(datafile)

    n = length(data)
    firstRow = [strip(c) for c in split(data[1], ",")]
    m = length(firstRow)

    grid = Array{String,2}(undef, n, m)

    for (i, line) in enumerate(data)
        cells = [strip(c) for c in split(line, ",")]
        for (j, c) in enumerate(cells)
            grid[i, j] = c
        end
    end

    return n, m, grid
end

function displayGrid(n::Int, m::Int, grid::Array{String,2})
    sep = "+" * repeat("-", 2*m + 1) * "+"
    println(sep)
    for i in 1:n
        print("| ")
        for j in 1:m
            c = grid[i, j]
            if c == "N"
                print("# ")
            else
                print(c, " ")
            end
        end
        println("|")
    end
    println(sep)
end

function displaySolution(n::Int, m::Int, grid::Array{String,2}, x_val::Array{Float64,2})
    sep = "+" * repeat("-", 2*m + 1) * "+"
    println(sep)
    for i in 1:n
        print("| ")
        for j in 1:m
            c = grid[i, j]
            if isBlack(grid, i, j)
                if c == "N"
                    print("# ")
                else
                    print(c, " ")
                end
            elseif x_val[i, j] > 0.5
                print("L ")
            else
                print(". ")
            end
        end
        println("|")
    end
    println(sep)
end

function performanceDiagram(outputFile::String)
    resultFolder = "res/"

    maxSize = 0
    subfolderCount = 0
    folderName = Array{String, 1}()

    for file in readdir(resultFolder)
        path = resultFolder * file
        if isdir(path)
            folderName = vcat(folderName, file)
            subfolderCount += 1
            folderSize = size(readdir(path), 1)
            if maxSize < folderSize
                maxSize = folderSize
            end
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
                if SolutionFound
                    results[folderCount, fileCount] = solveTime
                    if solveTime > maxSolveTime
                        maxSolveTime = solveTime
                    end
                end
            end
        end
    end

    results = sort(results, dims=2)
    println("Max solve time: ", maxSolveTime)

    for dim in 1:size(results, 1)
        x = Float64[0]
        y = Float64[0]
        previousX = 0
        currentId = 1

        while currentId <= size(results, 2) && results[dim, currentId] != Inf
            while currentId <= size(results, 2) && results[dim, currentId] == previousX
                currentId += 1
            end
            append!(x, previousX)
            append!(y, currentId - 1)
            if currentId <= size(results, 2) && results[dim, currentId] != Inf
                append!(x, results[dim, currentId])
                append!(y, currentId - 1)
                previousX = results[dim, currentId]
            else
                break
            end
        end

        append!(x, maxSolveTime)
        append!(y, currentId - 1)
        if dim == 1
            plot(x, y, label=folderName[dim], legend=:bottomright,
                 xaxis="Time (s)", yaxis="Solved instances", linewidth=3)
        else
            savefig(plot!(x, y, label=folderName[dim], linewidth=3), outputFile)
        end
    end
end

function resultsArray(outputFile::String)
    resultFolder = "res/"

    fout = open(outputFile, "w")
    println(fout, "\\documentclass{article}")
    println(fout, "\\usepackage[french]{babel}")
    println(fout, "\\usepackage[utf8]{inputenc}")
    println(fout, "\\usepackage{multicol}")
    println(fout, "\\begin{document}")

    header = "\\begin{center}\n\\renewcommand{\\arraystretch}{1.4}\n\\begin{tabular}{l"

    folderName = Array{String, 1}()
    solvedInstances = Array{String, 1}()

    for file in readdir(resultFolder)
        path = resultFolder * file
        if isdir(path)
            folderName = vcat(folderName, file)
            for file2 in filter(x -> occursin(".txt", x), readdir(path))
                solvedInstances = vcat(solvedInstances, file2)
            end
        end
    end

    solvedInstances = unique(solvedInstances)

    for folder in folderName
        header *= "rr"
    end
    header *= "}\n\\hline\n"
    for folder in folderName
        header *= " & \\multicolumn{2}{c}{\\textbf{" * folder * "}}"
    end
    header *= "\\\\\n\\textbf{Instance}"
    for folder in folderName
        header *= " & \\textbf{Temps (s)} & \\textbf{SolutionFound ?}"
    end
    header *= "\\\\\\hline\n"

    footer = "\\hline\\end{tabular}\n\\end{center}\n"

    println(fout, header)

    maxInstancePerPage = 30
    id = 1

    for solvedInstance in solvedInstances
        if rem(id, maxInstancePerPage) == 0
            println(fout, footer, "\\newpage")
            println(fout, header)
        end
        print(fout, replace(solvedInstance, "_" => "\\_"))
        for method in folderName
            path = resultFolder * method * "/" * solvedInstance
            if isfile(path)
                include(path)
                print(fout, " & ", round(solveTime, digits=2), " & ")
                if SolutionFound
                    print(fout, "\$\\times\$")
                end
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
