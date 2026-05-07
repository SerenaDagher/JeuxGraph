# io.jl for Filling — with wall support

using JuMP
using Plots
import GR

# ---------------------------------------------------------------------------
# Wall helpers
# ---------------------------------------------------------------------------

"""
Return true if there is a wall between (i1,j1) and (i2,j2).
Walls are stored as canonical pairs (smaller index first).
"""
function hasWall(walls::Set, i1::Int, j1::Int, i2::Int, j2::Int)
    return ((i1,j1),(i2,j2)) in walls || ((i2,j2),(i1,j1)) in walls
end

"""
Return all orthogonal neighbours of (i,j) that are NOT separated by a wall.
"""
function getNeighbors(n::Int, m::Int, walls::Set, i::Int, j::Int)
    nbrs = Tuple{Int,Int}[]
    for (di, dj) in [(-1,0),(1,0),(0,-1),(0,1)]
        ni, nj = i+di, j+dj
        1<=ni<=n && 1<=nj<=m           || continue
        hasWall(walls, i, j, ni, nj)  && continue
        push!(nbrs, (ni, nj))
    end
    return nbrs
end

# ---------------------------------------------------------------------------
# Read
# ---------------------------------------------------------------------------

"""
Read a Filling instance from a text file.

Format:
  - One CSV row per grid line (0 = empty, k = pre-filled value k)
  - Optional section starting with "WALLS":
      H r c  →  horizontal wall between (r,c) and (r+1,c)
      V r c  →  vertical   wall between (r,c) and (r,c+1)

Returns: n, m, grid, walls
"""
function readInputFile(inputFile::String)
    datafile = open(inputFile)
    data = readlines(datafile)
    close(datafile)

    # Split at WALLS separator
    sep = findfirst(l -> strip(l) == "WALLS", data)
    grid_lines = sep === nothing ? data : data[1:sep-1]
    wall_lines = sep === nothing ? String[] : data[sep+1:end]

    n = length(grid_lines)
    m = length(split(grid_lines[1], ","))

    grid = zeros(Int, n, m)
    for (i, line) in enumerate(grid_lines)
        cells = [strip(c) for c in split(line, ",")]
        for (j, c) in enumerate(cells)
            grid[i, j] = parse(Int, c)
        end
    end

    # Parse walls — stored as canonical pairs
    walls = Set{Tuple{Tuple{Int,Int},Tuple{Int,Int}}}()
    for line in wall_lines
        parts = split(strip(line))
        length(parts) == 3 || continue
        r, c = parse(Int, parts[2]), parse(Int, parts[3])
        if parts[1] == "H"                 # horizontal: (r,c)↔(r+1,c)
            push!(walls, ((r,c),(r+1,c)))
        elseif parts[1] == "V"             # vertical:   (r,c)↔(r,c+1)
            push!(walls, ((r,c),(r,c+1)))
        end
    end

    return n, m, grid, walls
end

# ---------------------------------------------------------------------------
# Display
# ---------------------------------------------------------------------------

"""
Display the initial Filling grid, showing walls as thick borders.
  _  = empty cell
  k  = pre-filled cell
  #  = vertical wall between columns
  =  = horizontal wall between rows
"""
function displayGrid(n::Int, m::Int, grid::Array{Int,2},
                     walls::Set = Set())
    vwall(i,j) = j < m && hasWall(walls, i, j, i, j+1)
    hwall(i,j) = i < n && hasWall(walls, i, j, i+1, j)

    # Top border
    println("+" * repeat("---+", m))
    for i in 1:n
        # Cell row
        print("|")
        for j in 1:m
            v = grid[i, j]
            print(v == 0 ? " _ " : lpad(v, 2) * " ")
            print(vwall(i,j) ? "#" : "|")
        end
        println()
        # Separator between rows i and i+1
        if i < n
            print("+")
            for j in 1:m
                print(hwall(i,j) ? "===" : "---")
                print("+")
            end
            println()
        end
    end
    println("+" * repeat("---+", m))
end

"""
Display the solved Filling grid, showing walls as thick borders.
"""
function displaySolution(n::Int, m::Int, sol::Array{Int,2},
                          walls::Set = Set())
    vwall(i,j) = j < m && hasWall(walls, i, j, i, j+1)
    hwall(i,j) = i < n && hasWall(walls, i, j, i+1, j)

    println("+" * repeat("---+", m))
    for i in 1:n
        print("|")
        for j in 1:m
            v = sol[i, j]
            print(v == 0 ? " ? " : lpad(v, 2) * " ")
            print(vwall(i,j) ? "#" : "|")
        end
        println()
        if i < n
            print("+")
            for j in 1:m
                print(hwall(i,j) ? "===" : "---")
                print("+")
            end
            println()
        end
    end
    println("+" * repeat("---+", m))
end

# ---------------------------------------------------------------------------
# Validation
# ---------------------------------------------------------------------------

"""
Check that a complete Filling solution is valid:
every connected component (using only non-wall edges) of value v has exactly v cells.
"""
function checkSolution(n::Int, m::Int, sol::Array{Int,2},
                        walls::Set = Set())
    visited = falses(n, m)
    for i in 1:n, j in 1:m
        visited[i, j] && continue
        v = sol[i, j]
        v == 0 && return false

        # BFS through non-wall edges
        component = Tuple{Int,Int}[]
        queue = [(i, j)]
        visited[i, j] = true
        while !isempty(queue)
            ci, cj = popfirst!(queue)
            push!(component, (ci, cj))
            for (ni, nj) in getNeighbors(n, m, walls, ci, cj)
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

# ---------------------------------------------------------------------------
# Results (template — do not modify)
# ---------------------------------------------------------------------------

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
                if isOptimal
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
                include(path); print(fout, " & ", round(solveTime, digits=2), " & ")
                isOptimal && print(fout, "\$\\times\$")
            else; print(fout, " & - & -")
            end
        end
        println(fout, "\\\\"); id += 1
    end
    println(fout, footer); println(fout, "\\end{document}"); close(fout)
end
