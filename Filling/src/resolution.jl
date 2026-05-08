
using CPLEX
using JuMP
const MOI = JuMP.MOI

include("generation.jl")

TOL = 1e-5


function isIntegerPoint(cb_data::CPLEX.CallbackContext, context_id::Clong)
    return context_id == CPLEX.CPX_CALLBACKCONTEXT_CANDIDATE
end

function cplexSolve(n::Int, m::Int, grid::Array{Int,2})

    maxVal = max(maximum(grid), min(n*m,9))
    m_model = Model(CPLEX.Optimizer)
    set_optimizer_attribute(m_model, "CPX_PARAM_SCRIND", 0)
    set_optimizer_attribute(m_model, "CPX_PARAM_TILIM", 60.0)

    @variable(m_model, x[1:n, 1:m, 1:maxVal], Bin)
    @objective(m_model, Min, 0)

    for i in 1:n, j in 1:m
        @constraint(m_model, sum(x[i,j,k] for k in 1:maxVal) == 1)
    end

    for i in 1:n, j in 1:m
        if grid[i,j] > 0
            @constraint(m_model, x[i,j,grid[i,j]] == 1)
        end
    end

    function callback_filling(cb_data::CPLEX.CallbackContext, context_id::Clong)
        if isIntegerPoint(cb_data, context_id)
            CPLEX.load_callback_variable_primal(cb_data, context_id)
            x_val = callback_value.(cb_data, x)

            for k in 1:maxVal
                visited = falses(n,m)
                for i in 1:n, j in 1:m
                    (visited[i,j] || x_val[i,j,k] < 0.5) && continue

                    component = Tuple{Int,Int}[]
                    queue = [(i,j)]
                    visited[i,j] = true
                    while !isempty(queue)
                        ci,cj = popfirst!(queue)
                        push!(component,(ci,cj))
                        for (ni,nj) in getNeighbors(n,m,ci,cj)
                            if !visited[ni,nj] && x_val[ni,nj,k] > 0.5
                                visited[ni,nj] = true
                                push!(queue,(ni,nj))
                            end
                        end
                    end

                    sz = length(component)
                    sz == k && continue

                    if sz > k
                        cstr = @build_constraint(
                            sum(x[ci, cj, k] for (ci, cj) in component) <= sz - 1
                        )
                        MOI.submit(m_model, MOI.LazyConstraint(cb_data), cstr)
                    else
                        neighbors_C = Set{Tuple{Int,Int}}()
                        for (ci,cj) in component
                            for (ni,nj) in getNeighbors(n,m,ci,cj)
                                x_val[ni,nj,k] < 0.5 && push!(neighbors_C,(ni,nj))
                            end
                        end

                        if isempty(neighbors_C)
                            cstr = @build_constraint(sum(x[ci,cj,k] for (ci,cj) in component) <= sz-1)
                        else
                            cstr = @build_constraint(
                                sum(x[ci,cj,k] for (ci,cj) in component) <=
                                sz-1 + sum(x[ni,nj,k] for (ni,nj) in neighbors_C)
                            )
                        end
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

    sol = zeros(Int,n,m)
    if isOptimal
        x_val = value.(x)
        for i in 1:n, j in 1:m
            for k in 1:maxVal
                x_val[i,j,k] > 0.5 && (sol[i,j] = k; break)
            end
        end
    end

    return isOptimal, solveTime, sol
end

function heuristicSolve(n::Int, m::Int, grid::Matrix{Int})
    startTime = time()
    TIME_LIMIT = 10.0

    sol  = copy(grid)
    maxK = max(maximum(grid), 9)

    function nbrs(i::Int, j::Int)
        result = Tuple{Int,Int}[]
        for (di, dj) in ((-1,0),(1,0),(0,-1),(0,1))
            ni, nj = i+di, j+dj
            1 <= ni <= n && 1 <= nj <= m && push!(result, (ni, nj))
        end
        return result
    end

    function regionOK(si, sj, v)
        visited = falses(n, m)
        queue   = [(si, sj)]
        visited[si, sj] = true
        sz       = 0
        boundary = Tuple{Int,Int}[]

        while !isempty(queue)
            ci, cj = popfirst!(queue)
            sz += 1
            for (ni, nj) in nbrs(ci, cj)
                visited[ni, nj] && continue
                if sol[ni, nj] == v
                    visited[ni, nj] = true
                    push!(queue, (ni, nj))
                elseif sol[ni, nj] == 0
                    visited[ni, nj] = true
                    push!(boundary, (ni, nj))
                end
            end
        end

        sz > v && return false
        sz == v && return true

        needed    = v - sz
        reachable = length(boundary)
        reachable < needed || return true
        isempty(boundary) && return false

        flood = copy(boundary)
        while !isempty(flood)
            ci, cj = popfirst!(flood)
            for (ni, nj) in nbrs(ci, cj)
                if !visited[ni, nj] && sol[ni, nj] == 0
                    visited[ni, nj] = true
                    reachable += 1
                    reachable >= needed && return true
                    push!(flood, (ni, nj))
                end
            end
        end

        return false
    end

    function placementOK(i, j, v)
        regionOK(i, j, v) || return false
        checked = Set{Int}((v, 0))
        for (ni, nj) in nbrs(i, j)
            w = sol[ni, nj]
            w in checked && continue
            push!(checked, w)
            regionOK(ni, nj, w) || return false
        end
        return true
    end

    function globalOK()
        for i in 1:n, j in 1:m
            sol[i,j] == 0 && return false
        end
        return checkSolution(n, m, sol)
    end

    function pickCell(unassigned::Set{Tuple{Int,Int}})
        best       = first(unassigned)
        best_score = count(nb -> sol[nb[1],nb[2]] > 0, nbrs(best...))
        for cell in unassigned
            score = count(nb -> sol[nb[1],nb[2]] > 0, nbrs(cell...))
            score > best_score && (best = cell; best_score = score)
        end
        return best
    end

    function orderedValues(i, j)
        nearby     = sort(unique(sol[ni,nj] for (ni,nj) in nbrs(i,j) if sol[ni,nj] > 0))
        nearby_set = Set(nearby)
        rest       = [k for k in 1:maxK if k ∉ nearby_set]
        return vcat(nearby, rest)
    end

    function search(unassigned::Set{Tuple{Int,Int}})
        time() - startTime > TIME_LIMIT && return false
        isempty(unassigned)             && return globalOK()

        cell = pickCell(unassigned)
        i, j = cell
        delete!(unassigned, cell)

        for v in orderedValues(i, j)
            sol[i,j] = v
            if placementOK(i, j, v) && search(unassigned)
                return true
            end
            sol[i,j] = 0
        end

        push!(unassigned, cell)
        return false
    end

    unassigned = Set{Tuple{Int,Int}}((i,j) for i in 1:n, j in 1:m if grid[i,j] == 0)
    success    = search(unassigned)
    return success, time() - startTime, sol
end

function solveDataSet(dataFolder::String="data/",
                      resFolder::String="res/";
                      methods::Vector{String}=["cplex","heuristic"],
                      force::Bool=false,
                      csvFile::String=joinpath(resFolder, "results.csv"))

    for method in methods
        method in ["cplex", "heuristic"] || error("Unknown method: $method")
    end

    isdir(dataFolder) || error("Data folder not found: $dataFolder")
    isdir(resFolder) || mkpath(resFolder)

    for method in methods
        folder = joinpath(resFolder, method)
        isdir(folder) || mkpath(folder)
    end

    global SolutionFound = false
    global solveTime = -1.0
    global isValid = false

    csvEscape(value) = "\"" * replace(string(value), "\"" => "\"\"") * "\""
    function instanceSortKey(file::String)
        m = match(r"^instance_(\d+)x(\d+)_(\d+)\.txt$", file)
        m === nothing && return (typemax(Int), typemax(Int), typemax(Int), file)
        n = parse(Int, m.captures[1])
        p = parse(Int, m.captures[2])
        k = parse(Int, m.captures[3])
        return (n, p, k, file)
    end

    open(csvFile, "w") do csv
        println(csv, "instance,n,m,method,solved,valid,solve_time")

        for file in sort(filter(x -> endswith(x, ".txt"), readdir(dataFolder)); by=instanceSortKey)
            inputFile = joinpath(dataFolder, file)
            println("-- Resolution of ", file)
            n, m, grid = readInputFile(inputFile)

            for method in methods
                outputFile = joinpath(resFolder, method, file)

                if force || !isfile(outputFile)
                    local resolutionTime = -1.0
                    local solved = false

                    if method == "cplex"
                        solved, resolutionTime, _ = cplexSolve(n, m, grid)
                    elseif method == "heuristic"
                        solved, resolutionTime, _ = heuristicSolve(n, m, grid)
                    end

                    open(outputFile, "w") do fout
                        println(fout, "solveTime = ", resolutionTime)
                        println(fout, "SolutionFound = ", solved)
                        if method == "heuristic"
                            println(fout, "isValid = ", solved)
                        end
                    end
                end

                global SolutionFound = false
                global isValid = false
                include(outputFile)
                if !occursin("SolutionFound", read(outputFile, String)) && isdefined(Main, :isOptimal)
                    SolutionFound = Main.isOptimal
                end
                local rowValid = method == "heuristic" ? isValid : SolutionFound
                if method == "heuristic"
                    println(method, " valid: ", isValid)
                else
                    println(method, " solution found: ", SolutionFound)
                end
                println(method, " time: ", round(solveTime, sigdigits=2), "s\n")

                println(csv, join([
                    csvEscape(file),
                    string(n),
                    string(m),
                    csvEscape(method),
                    string(SolutionFound),
                    string(rowValid),
                    string(solveTime)
                ], ","))
            end
        end
    end

    println("CSV results written to ", csvFile)
end
