# This file contains the CPLEX resolution for LightUp

using CPLEX
using JuMP

include("generation.jl")

TOL = 0.00001

# ---------------------------------------------------------------------------
# Helpers (visibility)
# ---------------------------------------------------------------------------

"""
Return the set of all white cells visible from (i0, j0), including (i0, j0) itself.
A cell is visible if it lies on the same row or column with no black cell between them.
This set L(c) is used for:
  - Constraint 1: each white cell must be lit   -> sum x[v] >= 1 for v in L(c)
  - Constraint 2: no two lamps may see each other -> x[u] + x[v] <= 1 for v in L(u), v != u
"""
function visibleFrom(grid::Array{String,2}, n::Int, m::Int, i0::Int, j0::Int)
    visible = Set{Tuple{Int,Int}}()
    push!(visible, (i0, j0))
    for i in (i0-1):-1:1          # upward
        isBlack(grid, i, j0) && break
        push!(visible, (i, j0))
    end
    for i in (i0+1):n              # downward
        isBlack(grid, i, j0) && break
        push!(visible, (i, j0))
    end
    for j in (j0-1):-1:1          # leftward
        isBlack(grid, i0, j) && break
        push!(visible, (i0, j))
    end
    for j in (j0+1):m              # rightward
        isBlack(grid, i0, j) && break
        push!(visible, (i0, j))
    end
    return visible
end

"""
Return the list of white cells orthogonally adjacent to black cell (i, j).
Used for Constraint 3 (numbered black cells).
"""
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

# ---------------------------------------------------------------------------
# CPLEX solver
# ---------------------------------------------------------------------------

"""
Solve a LightUp instance with CPLEX.

Arguments:
  - n, m : grid dimensions
  - grid  : n×m Array{String,2}

Returns:
  - isOptimal   : Bool  — true if a feasible solution was found
  - solveTime   : Float64 — resolution time in seconds
  - x_val       : Array{Float64,2} — solution matrix (1.0 = lamp, 0.0 = no lamp)
"""
function cplexSolve(n::Int, m::Int, grid::Array{String,2})

    # --- Model ---
    m_model = Model(CPLEX.Optimizer)
    set_optimizer_attribute(m_model, "CPX_PARAM_SCRIND", 0)   # silent CPLEX output

    # --- Variables ---
    @variable(m_model, x[1:n, 1:m], Bin)

    # Black cells cannot hold a lamp
    for i in 1:n, j in 1:m
        if isBlack(grid, i, j)
            @constraint(m_model, x[i, j] == 0)
        end
    end

    # --- Objective (feasibility only) ---
    @objective(m_model, Min, 0)

    # --- Constraints 1 & 2 (built together from L(c)) ---
    # We use visibleFrom for both constraints:
    #   C1: each white cell c must be illuminated  -> sum_{v in L(c)} x[v] >= 1
    #   C2: no two lamps may see each other        -> x[u] + x[v] <= 1 for v in L(u), v != u
    #
    # (u,v) and (v,u) represent the same edge, so we track added pairs to avoid duplicates.

    added_pairs = Set{Tuple{Tuple{Int,Int}, Tuple{Int,Int}}}()

    for i in 1:n, j in 1:m
        if isWhite(grid, i, j)
            L = visibleFrom(grid, n, m, i, j)

            # Constraint 1
            @constraint(m_model, sum(x[vi, vj] for (vi, vj) in L) >= 1)

            # Constraint 2  (reuse L — no separate function needed)
            for (vi, vj) in L
                if (vi, vj) != (i, j)
                    # Canonical form for the pair (smaller index first)
                    pair = (i, j) <= (vi, vj) ? ((i, j), (vi, vj)) : ((vi, vj), (i, j))
                    if !(pair in added_pairs)
                        push!(added_pairs, pair)
                        @constraint(m_model, x[i, j] + x[vi, vj] <= 1)
                    end
                end
            end
        end
    end

    # --- Constraint 3 (numbered black cells) ---
    for i in 1:n, j in 1:m
        c = grid[i, j]
        if length(c) == 1 && isdigit(c[1])
            kb        = parse(Int, c)
            neighbors = whiteNeighbors(grid, n, m, i, j)
            if isempty(neighbors) && kb > 0
                @constraint(m_model, 0 >= 1)          # force infeasibility
            elseif !isempty(neighbors)
                @constraint(m_model, sum(x[ni, nj] for (ni, nj) in neighbors) == kb)
            end
        end
    end

    # --- Solve ---
    start = time()
    optimize!(m_model)
    solveTime = time() - start

    isOptimal = JuMP.primal_status(m_model) == JuMP.MathOptInterface.FEASIBLE_POINT

    x_val = zeros(Float64, n, m)
    if isOptimal
        x_val = value.(x)
    end

    return isOptimal, solveTime, x_val
end

# ---------------------------------------------------------------------------
# Solve dataset
# ---------------------------------------------------------------------------

"""
Solve all instances in ../data/ with CPLEX.
Results are written to ../res/cplex/<instance>.txt
Each result file contains: solveTime and isOptimal
"""
function solveDataSet()

    dataFolder = "../data/"
    resFolder  = "../res/"

    resolutionMethod = ["cplex"]
    resolutionFolder = resFolder .* resolutionMethod

    # Create result folders if needed
    for folder in resolutionFolder
        if !isdir(folder)
            mkpath(folder)
        end
    end

    global isOptimal = false
    global solveTime = -1

    for file in filter(x -> occursin(".txt", x), readdir(dataFolder))

        println("-- Resolution of ", file)
        n, m, grid = readInputFile(dataFolder * file)

        for methodId in 1:size(resolutionMethod, 1)

            outputFile = resolutionFolder[methodId] * "/" * file

            if !isfile(outputFile)

                fout = open(outputFile, "w")
                resolutionTime = -1
                isOptimal      = false

                if resolutionMethod[methodId] == "cplex"

                    isOptimal, resolutionTime, x_val = cplexSolve(n, m, grid)

                    if isOptimal
                        displaySolution(n, m, grid, x_val)
                    end
                end

                println(fout, "solveTime = ", resolutionTime)
                println(fout, "isOptimal = ", isOptimal)
                close(fout)
            end

            include(outputFile)
            println(resolutionMethod[methodId], " optimal: ", isOptimal)
            println(resolutionMethod[methodId], " time: " * string(round(solveTime, sigdigits=2)) * "s\n")
        end
    end
end