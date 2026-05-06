# resolution.jl for Filling — with wall support

using CPLEX
using JuMP
const MOI = JuMP.MOI

include("generation.jl")

TOL = 0.00001

function isIntegerPoint(cb_data::CPLEX.CallbackContext, context_id::Clong)
    return context_id == CPLEX.CPX_CALLBACKCONTEXT_CANDIDATE
end

# ---------------------------------------------------------------------------
# CPLEX solver with callback
# ---------------------------------------------------------------------------

"""
Solve a Filling instance with CPLEX + lazy-constraint callback.

The connectivity rule (each connected component of value v has exactly v cells)
is enforced via the callback. Walls are respected: two cells separated by a wall
are never considered connected, even if they have the same value.

Returns: isOptimal, solveTime, sol (Array{Int,2})
"""
function cplexSolve(n::Int, m::Int, grid::Array{Int,2},
                     walls::Set = Set())

    maxVal = max(maximum(grid), min(n * m, 9))

    m_model = Model(CPLEX.Optimizer)
    set_optimizer_attribute(m_model, "CPX_PARAM_SCRIND", 0)

    # x[i,j,v] = 1 iff cell (i,j) has value v
    @variable(m_model, x[1:n, 1:m, 1:maxVal], Bin)
    @objective(m_model, Min, 0)

    # --- C1 : each cell has exactly one value ---
    for i in 1:n, j in 1:m
        @constraint(m_model, sum(x[i,j,v] for v in 1:maxVal) == 1)
    end

    # --- C2 : pre-filled cells are fixed ---
    for i in 1:n, j in 1:m
        if grid[i,j] > 0
            @constraint(m_model, x[i, j, grid[i,j]] == 1)
        end
    end

    # --- C3 : partial connectivity (respecting walls) ---
    # A cell with value v ≥ 2 must have at least one NON-WALL neighbour
    # with the same value v.
    for i in 1:n, j in 1:m
        nbrs = getNeighbors(n, m, walls, i, j)
        for v in 2:maxVal
            if isempty(nbrs)
                # Isolated cell (all edges are walls): can only be value 1
                @constraint(m_model, x[i, j, v] == 0)
            else
                @constraint(m_model,
                    x[i, j, v] <= sum(x[ni, nj, v] for (ni,nj) in nbrs))
            end
        end
    end

    # --- Callback : enforce full connectivity using BFS on non-wall edges ---
    # When CPLEX finds an integer solution, for each value v we find all
    # connected components (respecting walls). If a component C has |C| ≠ v,
    # we add the lazy cut:  Σ_{(i,j)∈C} x[i,j,v] ≤ |C| - 1
    function callback_filling(cb_data::CPLEX.CallbackContext, context_id::Clong)
        if isIntegerPoint(cb_data, context_id)
            CPLEX.load_callback_variable_primal(cb_data, context_id)
            x_val = callback_value.(cb_data, x)

            for v in 1:maxVal
                visited = falses(n, m)
                for i in 1:n, j in 1:m
                    (visited[i,j] || x_val[i,j,v] < 0.5) && continue

                    # BFS — only traverse non-wall edges
                    component = Tuple{Int,Int}[]
                    queue = [(i, j)]
                    visited[i, j] = true
                    while !isempty(queue)
                        ci, cj = popfirst!(queue)
                        push!(component, (ci, cj))
                        for (ni, nj) in getNeighbors(n, m, walls, ci, cj)
                            if !visited[ni,nj] && x_val[ni,nj,v] > 0.5
                                visited[ni, nj] = true
                                push!(queue, (ni, nj))
                            end
                        end
                    end

                    # Invalid component → add cut
                    if length(component) != v
                        cstr = @build_constraint(
                            sum(x[ci,cj,v] for (ci,cj) in component) <=
                            length(component) - 1
                        )
                        MOI.submit(m_model, MOI.LazyConstraint(cb_data), cstr)
                    end
                end
            end
        end
    end

    MOI.set(m_model, CPLEX.CallbackFunction(), callback_filling)
    MOI.set(m_model, MOI.NumberOfThreads(), 1)

    startTime = time()
    optimize!(m_model)
    solveTime = time() - startTime

    isOptimal = primal_status(m_model) == MOI.FEASIBLE_POINT

    sol = zeros(Int, n, m)
    if isOptimal
        x_val = value.(x)
        for i in 1:n, j in 1:m
            for v in 1:maxVal
                if x_val[i,j,v] > 0.5
                    sol[i,j] = v; break
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
Greedy heuristic for Filling with walls.

Strategy:
  1. Seed each pre-filled cell as a region starter.
  2. Expand regions greedily (largest first) through NON-WALL edges only.
  3. Remaining empty cells are assigned value 1.

Returns: isValid, solveTime, sol
"""
function heuristicSolve(n::Int, m::Int, grid::Array{Int,2},
                         walls::Set = Set())
    startTime = time()
    sol = copy(grid)
    region_of = zeros(Int, n, m)
    regions = Dict{Int, Tuple{Int, Vector{Tuple{Int,Int}}}}()
    next_id = 1

    for i in 1:n, j in 1:m
        if sol[i,j] > 0
            region_of[i,j] = next_id
            regions[next_id] = (sol[i,j], [(i,j)])
            next_id += 1
        end
    end

    # Sort by target descending
    sorted_ids = sort(collect(keys(regions)), by = id -> -regions[id][1])

    changed = true
    while changed
        changed = false
        for rid in sorted_ids
            v_target, cells = regions[rid]
            length(cells) >= v_target && continue
            for (ci, cj) in copy(cells)
                # Only expand through non-wall edges
                for (ni, nj) in getNeighbors(n, m, walls, ci, cj)
                    region_of[ni,nj] == 0 || continue
                    region_of[ni,nj] = rid
                    push!(cells, (ni,nj))
                    sol[ni,nj] = v_target
                    changed = true
                    length(cells) >= v_target && @goto next_region
                end
            end
            @label next_region
        end
    end

    # Remaining empty cells → value 1
    for i in 1:n, j in 1:m
        sol[i,j] == 0 && (sol[i,j] = 1)
    end

    solveTime = time() - startTime
    isValid   = checkSolution(n, m, sol, walls)
    return isValid, solveTime, sol
end

# ---------------------------------------------------------------------------
# Solve dataset
# ---------------------------------------------------------------------------

"""
Solve all instances in ../data/ with CPLEX and heuristic.
"""
function solveDataSet()
    dataFolder = "../data/"; resFolder = "../res/"
    methods = ["cplex", "heuristic"]
    folders = resFolder .* methods
    for f in folders; isdir(f) || mkpath(f); end

    global isOptimal = false; global solveTime = -1

    for file in filter(x -> occursin(".txt", x), readdir(dataFolder))
        println("-- Resolution of ", file)
        n, m, grid, walls = readInputFile(dataFolder * file)

        for (mid, method) in enumerate(methods)
            outFile = folders[mid] * "/" * file
            if !isfile(outFile)
                fout = open(outFile, "w")
                resTime = -1; isOptimal = false

                if method == "cplex"
                    isOptimal, resTime, sol = cplexSolve(n, m, grid, walls)
                    isOptimal && (println("\nCPLEX solution:"); displaySolution(n, m, sol, walls))
                elseif method == "heuristic"
                    isOptimal, resTime, sol = heuristicSolve(n, m, grid, walls)
                    isOptimal && (println("\nHeuristic solution:"); displaySolution(n, m, sol, walls))
                end

                println(fout, "solveTime = ", resTime)
                println(fout, "isOptimal = ", isOptimal)
                close(fout)
            end

            include(outFile)
            println(method, " optimal: ", isOptimal,
                    "  |  time: ", round(solveTime, sigdigits=2), "s")
        end
        println()
    end
end