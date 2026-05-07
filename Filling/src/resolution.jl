# resolution.jl

using CPLEX
using JuMP
const MOI = JuMP.MOI

include("generation.jl")

TOL = 1e-5

# ---------------------------------------------------------------------------
# Utilitaires
# ---------------------------------------------------------------------------

# Vérifie si c'est un point entier dans le callback
function isIntegerPoint(cb_data::CPLEX.CallbackContext, context_id::Clong)
    return context_id == CPLEX.CPX_CALLBACKCONTEXT_CANDIDATE
end

# Renvoie les voisins accessibles d'une case (i,j) en respectant les murs
function getNeighbors(n::Int, m::Int, walls::Set{Tuple{Tuple{Int,Int},Tuple{Int,Int}}}, i::Int, j::Int)
    neighbors = Tuple{Int,Int}[]
    for (di,dj) in [(0,1),(1,0),(0,-1),(-1,0)]
        ni, nj = i+di, j+dj
        if 1 <= ni <= n && 1 <= nj <= m
            if !(( (i,j),(ni,nj) ) in walls || ( (ni,nj),(i,j) ) in walls)
                push!(neighbors, (ni,nj))
            end
        end
    end
    return neighbors
end

# ---------------------------------------------------------------------------
# CPLEX PLNE + callback pour la connexité
# ---------------------------------------------------------------------------
function cplexSolve(n::Int, m::Int, grid::Array{Int,2},
                    walls::Set{Tuple{Tuple{Int,Int},Tuple{Int,Int}}}=Set())

    maxVal = max(maximum(grid), min(n*m,9))
    m_model = Model(CPLEX.Optimizer)
    set_optimizer_attribute(m_model, "CPX_PARAM_SCRIND", 0)

    # Variables binaires x[i,j,k]
    @variable(m_model, x[1:n, 1:m, 1:maxVal], Bin)
    @objective(m_model, Min, 0)

    # --- C1 : chaque case a exactement une valeur ---
    for i in 1:n, j in 1:m
        @constraint(m_model, sum(x[i,j,k] for k in 1:maxVal) == 1)
    end

    # --- C2 : cases pré-remplies ---
    for i in 1:n, j in 1:m
        if grid[i,j] > 0
            @constraint(m_model, x[i,j,grid[i,j]] == 1)
        end
    end

    # --- Callback : connexité exacte ---
    function callback_filling(cb_data::CPLEX.CallbackContext, context_id::Clong)
        if isIntegerPoint(cb_data, context_id)
            CPLEX.load_callback_variable_primal(cb_data, context_id)
            x_val = callback_value.(cb_data, x)

            for k in 1:maxVal
                visited = falses(n,m)
                for i in 1:n, j in 1:m
                    (visited[i,j] || x_val[i,j,k] < 0.5) && continue

                    # BFS pour trouver la composante connexe
                    component = Tuple{Int,Int}[]
                    queue = [(i,j)]
                    visited[i,j] = true
                    while !isempty(queue)
                        ci,cj = popfirst!(queue)
                        push!(component,(ci,cj))
                        for (ni,nj) in getNeighbors(n,m,walls,ci,cj)
                            if !visited[ni,nj] && x_val[ni,nj,k] > 0.5
                                visited[ni,nj] = true
                                push!(queue,(ni,nj))
                            end
                        end
                    end

                    sz = length(component)
                    sz == k && continue  # composante correcte

                    if sz > k
                        # Composante trop grande :
                        # on interdit seulement cette composante exacte,
                        # pas toutes les façons de garder k cases dedans.
                        cstr = @build_constraint(
                            sum(x[ci, cj, k] for (ci, cj) in component) <= sz - 1
                        )
                        MOI.submit(m_model, MOI.LazyConstraint(cb_data), cstr)
                    else
                        # trop petite : au moins une case doit s'étendre
                        neighbors_C = Set{Tuple{Int,Int}}()
                        for (ci,cj) in component
                            for (ni,nj) in getNeighbors(n,m,walls,ci,cj)
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

# ---------------------------------------------------------------------------
# Heuristique gloutonne fiable (zones exactes + murs)
# ---------------------------------------------------------------------------
function heuristicSolve(n::Int, m::Int, grid::Array{Int,2},
                        walls::Set{Tuple{Tuple{Int,Int},Tuple{Int,Int}}}=Set())

    startTime = time()
    sol = copy(grid)
    remaining_cells = [(i,j) for i in 1:n, j in 1:m if sol[i,j] == 0]

    maxVal = maximum(grid)
    maxVal = max(maxVal,1)

    # BFS interne respectant les murs
    function bfs_zone(start::Tuple{Int,Int}, free_cells::Set{Tuple{Int,Int}})
        visited = Set([start])
        queue = [start]
        while !isempty(queue)
            ci,cj = popfirst!(queue)
            for (ni,nj) in getNeighbors(n,m,walls,ci,cj)
                if (ni,nj) in free_cells && !((ni,nj) in visited)
                    push!(visited,(ni,nj))
                    push!(queue,(ni,nj))
                end
            end
        end
        return visited
    end

    free_cells = Set(remaining_cells)

    # placer les chiffres du plus grand au plus petit
    for k in maxVal:-1:1
        assigned = true
        while assigned
            assigned = false
            for cell in collect(free_cells)
                zone = bfs_zone(cell, free_cells)
                length(zone) >= k || continue
                # Prendre exactement k cases
                zone_list = collect(zone)[1:k]
                for (i,j) in zone_list
                    sol[i,j] = k
                    delete!(free_cells, (i,j))
                end
                assigned = true
                break
            end
        end
    end

    # remplir le reste par 1
    for (i,j) in free_cells
        sol[i,j] = 1
    end

    solveTime = time() - startTime
    isValid = checkSolution(n,m,sol,walls)
    return isValid, solveTime, sol
end

# ---------------------------------------------------------------------------
# Solve dataset
# ---------------------------------------------------------------------------
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

    global isOptimal = false
    global solveTime = -1.0
    global isValid = false

    csvEscape(value) = "\"" * replace(string(value), "\"" => "\"\"") * "\""

    open(csvFile, "w") do csv
        println(csv, "instance,n,m,method,solved,valid,solve_time,walls")

        for file in sort(filter(x -> endswith(x, ".txt"), readdir(dataFolder)))
            inputFile = joinpath(dataFolder, file)
            println("-- Resolution of ", file)
            n, m, grid, walls = readInputFile(inputFile)

            for method in methods
                outputFile = joinpath(resFolder, method, file)

                if force || !isfile(outputFile)
                    local resolutionTime = -1.0
                    local solved = false

                    if method == "cplex"
                        solved, resolutionTime, _ = cplexSolve(n, m, grid, walls)
                    elseif method == "heuristic"
                        solved, resolutionTime, _ = heuristicSolve(n, m, grid, walls)
                    end

                    open(outputFile, "w") do fout
                        println(fout, "solveTime = ", resolutionTime)
                        println(fout, "isOptimal = ", solved)
                        if method == "heuristic"
                            println(fout, "isValid = ", solved)
                        end
                    end
                end

                global isValid = false
                include(outputFile)
                local rowValid = method == "heuristic" ? isValid : isOptimal
                if method == "heuristic"
                    println(method, " valid: ", isValid)
                else
                    println(method, " solution found: ", isOptimal)
                end
                println(method, " time: ", round(solveTime, sigdigits=2), "s\n")

                println(csv, join([
                    csvEscape(file),
                    string(n),
                    string(m),
                    csvEscape(method),
                    string(isOptimal),
                    string(rowValid),
                    string(solveTime),
                    string(length(walls))
                ], ","))
            end
        end
    end

    println("CSV results written to ", csvFile)
end
