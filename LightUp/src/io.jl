# This file contains functions related to reading, writing and displaying a LightUp instance

using JuMP
using Plots
import GR

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

"""
Return true if cell (i,j) is a black cell (numbered or not)
"""
isBlack(grid::Array{String,2}, i::Int, j::Int) = grid[i,j] != "."

"""
Return true if cell (i,j) is a white cell
"""
isWhite(grid::Array{String,2}, i::Int, j::Int) = grid[i,j] == "."

# ---------------------------------------------------------------------------
# Read
# ---------------------------------------------------------------------------

"""
Read a LightUp instance from a text file.

Format: each line = one row, cells separated by commas.
  "."        -> white cell
  "N"        -> black cell (no constraint)
  "0".."4"   -> numbered black cell

Returns: n (rows), m (cols), grid (n×m Array{String,2})
"""
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

# ---------------------------------------------------------------------------
# Display
# ---------------------------------------------------------------------------

"""
Display the initial (unsolved) LightUp grid in the console.
  '.' -> white cell
  '#' -> unnumbered black cell
  '0'..'4' -> numbered black cell
"""
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
                print(c, " ")   # "." or digit
            end
        end
        println("|")
    end
    println(sep)
end

"""
Display the solved LightUp grid in the console.
  'L'  -> lamp placed on this white cell
  '·'  -> lit white cell (no lamp)
  '#'  -> unnumbered black cell
  '0'..'4' -> numbered black cell
"""
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
                print("· ")
            end
        end
        println("|")
    end
    println(sep)
end

# ---------------------------------------------------------------------------
# Results (provided by the template — do not modify)
# ---------------------------------------------------------------------------

"""
Create a pdf file which contains a performance diagram associated to the results of the ../res folder.
Display one curve for each subfolder of the ../res folder.

Arguments
- outputFile: path of the output file

Prerequisites:
- Each subfolder must contain text files
- Each text file correspond to the resolution of one instance
- Each text file contains a variable "solveTime" and a variable "isOptimal"
"""
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

    results = Array{Float64}(undef, subfolderCount, maxSize)
    for i in 1:subfolderCount
        for j in 1:maxSize
            results[i, j] = Inf
        end
    end

    folderCount = 0
    maxSolveTime = 0

    for file in readdir(resultFolder)
        path = resultFolder * file
        if isdir(path)
            folderCount += 1
            fileCount = 0
            for resultFile in filter(x->occursin(".txt", x), readdir(path))
                fileCount += 1
                include(path * "/" * resultFile)
                if isOptimal
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
        x = Array{Float64, 1}()
        y = Array{Float64, 1}()
        previousX = 0
        previousY = 0
        append!(x, previousX)
        append!(y, previousY)
        currentId = 1
        while currentId != size(results, 2) && results[dim, currentId] != Inf
            identicalValues = 1
            while results[dim, currentId] == previousX && currentId <= size(results, 2)
                currentId += 1
                identicalValues += 1
            end
            append!(x, previousX)
            append!(y, currentId - 1)
            if results[dim, currentId] != Inf
                append!(x, results[dim, currentId])
                append!(y, currentId - 1)
            end
            previousX = results[dim, currentId]
            previousY = currentId - 1
        end
        append!(x, maxSolveTime)
        append!(y, currentId - 1)
        if dim == 1
            plot(x, y, label = folderName[dim], legend = :bottomright,
                 xaxis = "Time (s)", yaxis = "Solved instances", linewidth=3)
        else
            savefig(plot!(x, y, label = folderName[dim], linewidth=3), outputFile)
        end
    end
end

"""
Create a latex file which contains an array with the results of the ../res folder.
Each subfolder of the ../res folder contains the results of a resolution method.

Arguments
- outputFile: path of the output file

Prerequisites:
- Each subfolder must contain text files
- Each text file correspond to the resolution of one instance
- Each text file contains a variable "solveTime" and a variable "isOptimal"
"""
function resultsArray(outputFile::String)
    
    resultFolder = "res/"
    dataFolder   = "data/"
    
    maxSize = 0
    subfolderCount = 0
    fout = open(outputFile, "w")

    println(fout, raw"""\documentclass{article}

\usepackage[french]{babel}
\usepackage [utf8] {inputenc}
\usepackage{multicol}

\setlength{\hoffset}{-18pt}
\setlength{\oddsidemargin}{0pt}
\setlength{\evensidemargin}{9pt}
\setlength{\marginparwidth}{54pt}
\setlength{\textwidth}{481pt}
\setlength{\voffset}{-18pt}
\setlength{\marginparsep}{7pt}
\setlength{\topmargin}{0pt}
\setlength{\headheight}{13pt}
\setlength{\headsep}{10pt}
\setlength{\footskip}{27pt}
\setlength{\textheight}{668pt}

\begin{document}""")

    header = raw"""
\begin{center}
\renewcommand{\arraystretch}{1.4} 
 \begin{tabular}{l"""

    folderName       = Array{String, 1}()
    solvedInstances  = Array{String, 1}()

    for file in readdir(resultFolder)
        path = resultFolder * file
        if isdir(path)
            folderName = vcat(folderName, file)
            subfolderCount += 1
            folderSize = size(readdir(path), 1)
            for file2 in filter(x->occursin(".txt", x), readdir(path))
                solvedInstances = vcat(solvedInstances, file2)
            end
            if maxSize < folderSize
                maxSize = folderSize
            end
        end
    end

    unique(solvedInstances)

    for folder in folderName
        header *= "rr"
    end
    header *= "}\n\t\\hline\n"
    for folder in folderName
        header *= " & \\multicolumn{2}{c}{\\textbf{" * folder * "}}"
    end
    header *= "\\\\\n\\textbf{Instance} "
    for folder in folderName
        header *= " & \\textbf{Temps (s)} & \\textbf{Optimal ?} "
    end
    header *= "\\\\\\hline\n"

    footer = raw"""\hline\end{tabular}
\end{center}

"""
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
                println(fout, " & ", round(solveTime, digits=2), " & ")
                if isOptimal
                    println(fout, "\$\\times\$")
                end
            else
                println(fout, " & - & - ")
            end
        end
        println(fout, "\\\\")
        id += 1
    end

    println(fout, footer)
    println(fout, "\\end{document}")
    close(fout)
end