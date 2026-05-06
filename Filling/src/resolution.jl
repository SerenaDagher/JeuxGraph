# This file contains the CPLEX resolution and heuristic for Filling

using CPLEX
using JuMP
const MOI = JuMP.MOI

include("generation.jl")

TOL = 0.00001

# ---------------------------------------------------------------------------
# Helper: check if callback was triggered by an integer solution
# ---------------------------------------------------------------------------

function isIntegerPoint(cb_data::CPLEX.CallbackContext, context_id::Clong)
    return context_id == CPLEX.CPX_CALLBACKCONTEXT_CANDIDATE
end

# ---------------------------------------------------------------------------
# CPLEX solver with callback (connectivity)
# ---------------------------------------------------------------------------

"""
Solve a Filling instance with CPLEX.
The hard rule (each connected component of value v has exactly v cells)
is enforced by a lazy-constraint callback.

Arguments:
  - n, m : grid dimensions
  - grid  : n×m Array{Int,2}  (0 = empty, k = pre-filled with value k)

Returns:
  - isOptimal  : Bool
  - solveTime  : Float64
  - sol        : Array{Int,2}  (0 if no solution found)
"""
function cplexSolve(n::Int, m::Int, grid::Array{Int,2})

    # Maximum value that can appear
    maxVal = max(maximum(grid), min(n * m, 9))

    # --- Model ---
    m_model = Model(CPLEX.Optimizer)
    set_optimizer_attribute(m_model, "CPX_PARAM_SCRIND", 0)

    # --- Variables ---
    # x[i,j,v] = 1 iff cell (i,j) has value v
    @variable(m_model, x[1:n, 1:m, 1:maxVal], Bin)

    # --- Objective (feasibility) ---
    @objective(m_model, Min, 0)

    # --- Constraint 1 : each cell has exactly one value ---
    for i in 1:n, j in 1:m
        @constraint(m_model, sum(x[i, j, v] for v in 1:maxVal) == 1)
    end

    # --- Constraint 2 : pre-filled cells are fixed ---
    for i in 1:n, j in 1:m
        if grid[i, j] > 0
            v_given = grid[i, j]
            @constraint(m_model, x[i, j, v_given] == 1)
        end
    end

    # --- Constraint 3 (partial connectivity) ---
    # A cell with value v ≥ 2 must have at least one neighbour with value v.
    # This eliminates isolated cells of value ≥ 2 without adding full connectivity.
    for i in 1:n, j in 1:m
        neighbors = [(i+di, j+dj) for (di, dj) in [(-1,0),(1,0),(0,-1),(0,1)]
                     if 1 <= i+di <= n && 1 <= j+dj <= m]
        for v in 2:maxVal
            if isempty(neighbors)
                @constraint(m_model, x[i, j, v] == 0)
            else
                @constraint(m_model,
                    x[i, j, v] <= sum(x[ni, nj, v] for (ni, nj) in neighbors))
            end
        end
    end

    # --- Callback : enforce full connectivity ---
    # When CPLEX finds an integer solution, check each connected component.
    # For any component C of value v with |C| ≠ v, add a lazy cut:
    #   Σ_{(i,j) ∈ C} x[i,j,v] ≤ |C| - 1
    # This forces CPLEX to break the invalid component.
    function callback_filling(cb_data::CPLEX.CallbackContext, context_id::Clong)
        if isIntegerPoint(cb_data, context_id)

            CPLEX.load_callback_variable_primal(cb_data, context_id)
            x_val = callback_value.(cb_data, x)

            for v in 1:maxVal
                visited = falses(n, m)

                for i in 1:n, j in 1:m
                    (visited[i, j] || x_val[i, j, v] < 0.5) && continue

                    # BFS to find the connected component
                    component = Tuple{Int,Int}[]
                    queue = [(i, j)]
                    visited[i, j] = true

                    while !isempty(queue)
                        ci, cj = popfirst!(queue)
                        push!(component, (ci, cj))
                        for (di, dj) in [(-1,0),(1,0),(0,-1),(0,1)]
                            ni, nj = ci+di, cj+dj
                            if 1<=ni<=n && 1<=nj<=m &&
                               !visited[ni,nj] && x_val[ni,nj,v] > 0.5
                                visited[ni, nj] = true
                                push!(queue, (ni, nj))
                            end
                        end
                    end

                    # If component size ≠ v → add cut
                    if length(component) != v
                        cstr = @build_constraint(
                            sum(x[ci, cj, v] for (ci, cj) in component) <=
                            length(component) - 1
                        )
                        MOI.submit(m_model, MOI.LazyConstraint(cb_data), cstr)
                    end
                end
            end
        end
    end

    MOI.set(m_model, CPLEX.CallbackFunction(), callback_filling)
    MOI.set(m_model, MOI.NumberOfThreads(), 1)   # required with callback

    # --- Solve ---
    startTime = time()
    optimize!(m_model)
    solveTime = time() - startTime

    isOptimal = primal_status(m_model) == MOI.FEASIBLE_POINT

    # Extract solution
    sol = zeros(Int, n, m)
    if isOptimal
        x_val = value.(x)
        for i in 1:n, j in 1:m
            for v in 1:maxVal
                if x_val[i, j, v] > 0.5
                    sol[i, j] = v
                    break
                end
            end
        end
    end

    return isOptimal, solveTime, sol
end

# ---------------------------------------------------------------------------
# Greedy heuristic
# ---------------------------------------------------------------------------

"""
Solve a Filling instance with a greedy heuristic.

Strategy:
  1. Each pre-filled cell seeds a region with its target value.
  2. Regions are grown greedily (largest target first) by expanding
     into adjacent empty cells.
  3. Remaining empty cells are assigned value 1 (isolated regions).

Returns:
  - isValid   : Bool  (true if the solution satisfies all Filling rules)
  - solveTime : Float64
  - sol       : Array{Int,2}
"""
function heuristicSolve(n::Int, m::Int, grid::Array{Int,2})
    startTime = time()

    sol = copy(grid)

    # region_of[i,j] = region id that owns cell (i,j), 0 = unowned
    region_of = zeros(Int, n, m)

    # regions: id -> (target_value, cells)
    regions = Dict{Int, Tuple{Int, Vector{Tuple{Int,Int}}}}()
    next_id = 1

    # Seed from pre-filled cells
    for i in 1:n, j in 1:m
        if sol[i, j] > 0
            region_of[i, j] = next_id
            regions[next_id] = (sol[i, j], [(i, j)])
            next_id += 1
        end
    end

    # Sort regions by target value descending (greedy: expand large first)
    sorted_ids = sort(collect(keys(regions)), by = id -> -regions[id][1])

    # Grow regions until no progress
    changed = true
    while changed
        changed = false
        for rid in sorted_ids
            v_target, cells = regions[rid]
            length(cells) >= v_target && continue

            for (ci, cj) in copy(cells)
                for (di, dj) in [(-1,0),(1,0),(0,-1),(0,1)]
                    ni, nj = ci+di, cj+dj
                    1<=ni<=n && 1<=nj<=m || continue
                    region_of[ni, nj] == 0 || continue  # must be unowned

                    region_of[ni, nj] = rid
                    push!(cells, (ni, nj))
                    sol[ni, nj] = v_target
                    changed = true

                    length(cells) >= v_target && @goto next_region
                end
            end
            @label next_region
        end
    end

    # Assign remaining empty cells value 1
    for i in 1:n, j in 1:m
        if sol[i, j] == 0
            sol[i, j] = 1
        end
    end

    solveTime = time() - startTime
    isValid   = checkSolution(n, m, sol)

    return isValid, solveTime, sol
end

# ---------------------------------------------------------------------------
# Solve dataset
# ---------------------------------------------------------------------------

"""
Solve all instances in ../data/ with CPLEX and heuristic.
Results are written to ../res/cplex/ and ../res/heuristic/.
"""
function solveDataSet()

    dataFolder = "../data/"
    resFolder  = "../res/"

    resolutionMethods = ["cplex", "heuristic"]
    resolutionFolders = resFolder .* resolutionMethods

    for folder in resolutionFolders
        isdir(folder) || mkpath(folder)
    end

    global isOptimal = false
    global solveTime = -1

    for file in filter(x -> occursin(".txt", x), readdir(dataFolder))
        println("-- Resolution of ", file)
        n, m, grid = readInputFile(dataFolder * file)

        for (methodId, method) in enumerate(resolutionMethods)
            outputFile = resolutionFolders[methodId] * "/" * file

            if !isfile(outputFile)
                fout = open(outputFile, "w")
                resolutionTime = -1
                isOptimal      = false

                if method == "cplex"
                    isOptimal, resolutionTime, sol = cplexSolve(n, m, grid)
                    if isOptimal
                        println("\nCPLEX solution:")
                        displaySolution(n, m, sol)
                    end

                elseif method == "heuristic"
                    isOptimal, resolutionTime, sol = heuristicSolve(n, m, grid)
                    if isOptimal
                        println("\nHeuristic solution:")
                        displaySolution(n, m, sol)
                    end
                end

                println(fout, "solveTime = ", resolutionTime)
                println(fout, "isOptimal = ", isOptimal)
                close(fout)
            end

            include(outputFile)
            println(method, " optimal: ", isOptimal,
                    "  |  time: ", round(solveTime, sigdigits=2), "s")
        end
        println()
    end
end