
using CPLEX
using JuMP
const MOI = JuMP.MOI

include("generation.jl")

TOL = 0.00001


function visibleFrom(grid::Array{String,2}, n::Int, m::Int, i0::Int, j0::Int)
    visible = Set{Tuple{Int,Int}}()
    push!(visible, (i0, j0))
    for i in (i0-1):-1:1
        isBlack(grid, i, j0) && break
        push!(visible, (i, j0))
    end
    for i in (i0+1):n
        isBlack(grid, i, j0) && break
        push!(visible, (i, j0))
    end
    for j in (j0-1):-1:1
        isBlack(grid, i0, j) && break
        push!(visible, (i0, j))
    end
    for j in (j0+1):m
        isBlack(grid, i0, j) && break
        push!(visible, (i0, j))
    end
    return visible
end

function whiteNeighbors(grid::Array{String,2}, n::Int, m::Int, i::Int, j::Int)
    neighbors = Vector{Tuple{Int,Int}}()
    for (di, dj) in [(-1,0), (1,0), (0,-1), (0,1)]
        ni, nj = i + di, j + dj
        if 1 <= ni <= n && 1 <= nj <= m && isWhite(grid, ni, nj)
            push!(neighbors, (ni, nj))
        end
    end
    return neighbors
end


function cplexSolve(n::Int, m::Int, grid::Array{String,2})

    m_model = Model(CPLEX.Optimizer)
    set_optimizer_attribute(m_model, "CPX_PARAM_SCRIND", 0)
    set_optimizer_attribute(m_model, "CPX_PARAM_TILIM", 60.0)

    @variable(m_model, x[1:n, 1:m], Bin)

    for i in 1:n, j in 1:m
        if isBlack(grid, i, j)
            @constraint(m_model, x[i, j] == 0)
        end
    end

    @objective(m_model, Min, 0)

    for i in 1:n, j in 1:m
        if isWhite(grid, i, j)
            L = visibleFrom(grid, n, m, i, j)
            @constraint(m_model, sum(x[vi, vj] for (vi, vj) in L) >= 1)
        end
    end

    added_pairs = Set{Tuple{Tuple{Int,Int}, Tuple{Int,Int}}}()

    for i in 1:n, j in 1:m
        if isWhite(grid, i, j)
            L = visibleFrom(grid, n, m, i, j)
            for (vi, vj) in L
                if (vi, vj) != (i, j)
                    pair = (i,j) <= (vi,vj) ? ((i,j),(vi,vj)) : ((vi,vj),(i,j))
                    if !(pair in added_pairs)
                        push!(added_pairs, pair)
                        @constraint(m_model, x[i,j] + x[vi,vj] <= 1)
                    end
                end
            end
        end
    end

    for i in 1:n, j in 1:m
        c = grid[i, j]
        if length(c) == 1 && isdigit(c[1])
            kb = parse(Int, c)
            neighbors = whiteNeighbors(grid, n, m, i, j)
            if !isempty(neighbors)
                @constraint(m_model, sum(x[ni, nj] for (ni, nj) in neighbors) == kb)
            end
        end
    end

    start = time()
    optimize!(m_model)
    solveTime = time() - start

    SolutionFound = primal_status(m_model) == MOI.FEASIBLE_POINT

    x_val = zeros(Float64, n, m)
    if SolutionFound
        x_val = value.(x)
    end

    return SolutionFound, solveTime, x_val
end


function solveDataSet()

    dataFolder = "data/"
    resFolder  = "res/"

    resolutionMethod = ["cplex"]
    resolutionFolder = resFolder .* resolutionMethod

    for folder in resolutionFolder
        if !isdir(folder)
            mkpath(folder)
        end
    end

    global SolutionFound = false
    global solveTime = -1

    for file in filter(x -> occursin(".txt", x), readdir(dataFolder))

        println("-- Resolution of ", file)
        n, m, grid = readInputFile(dataFolder * file)

        for methodId in 1:size(resolutionMethod, 1)

            outputFile = resolutionFolder[methodId] * "/" * file

            if !isfile(outputFile)

                fout = open(outputFile, "w")
                resolutionTime = -1
                SolutionFound      = false

                if resolutionMethod[methodId] == "cplex"

                    SolutionFound, resolutionTime, x_val = cplexSolve(n, m, grid)

                    if SolutionFound
                        displaySolution(n, m, grid, x_val)
                    end
                end

                println(fout, "solveTime = ", resolutionTime)
                println(fout, "SolutionFound = ", SolutionFound)
                close(fout)
            end

            include(outputFile)
            println(resolutionMethod[methodId], " SolutionFound: ", SolutionFound)
            println(resolutionMethod[methodId], " time: " * string(round(solveTime, sigdigits=2)) * "s\n")
        end
    end
end
