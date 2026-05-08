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

# ---------------------------------------------------------------------------
# CPLEX PLNE + callback pour la connexité
# ---------------------------------------------------------------------------
function cplexSolve(n::Int, m::Int, grid::Array{Int,2})

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
                        for (ni,nj) in getNeighbors(n,m,ci,cj)
                            if !visited[ni,nj] && x_val[ni,nj,k] > 0.5
                                visited[ni,nj] = true
                                push!(queue,(ni,nj))
                            end
                        end
                    end

                    sz = length(component)
                    sz == k && continue  # composante correcte

                    if sz > k
                        cstr = @build_constraint(
                            sum(x[ci, cj, k] for (ci, cj) in component) <= sz - 1
                        )
                        MOI.submit(m_model, MOI.LazyConstraint(cb_data), cstr)
                    else
                        # trop petite : au moins une case doit s'étendre
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

# ---------------------------------------------------------------------------
# Heuristique avec backtracking et verification locale
# ---------------------------------------------------------------------------
function heuristicSolve(n::Int, m::Int, grid::Matrix{Int})
    startTime = time()
    TIME_LIMIT = 5.0

    sol = copy(grid)
    maxK = n * m

    # ------------------------------------------------------------
    # Voisinage
    # ------------------------------------------------------------
    directions = [(-1,0), (1,0), (0,-1), (0,1)]

    function neighbors(i::Int, j::Int)
        result = Tuple{Int,Int}[]
        for (di, dj) in directions
            ni, nj = i + di, j + dj
            if 1 <= ni <= n && 1 <= nj <= m
                push!(result, (ni, nj))
            end
        end
        return result
    end

    # ------------------------------------------------------------
    # Composante connexe d'une valeur donnée
    # ------------------------------------------------------------
    function getComponent(mat::Matrix{Int}, startCell::Tuple{Int,Int}, value::Int)
        visited = Set{Tuple{Int,Int}}()
        queue = [startCell]
        push!(visited, startCell)

        while !isempty(queue)
            ci, cj = popfirst!(queue)

            for nb in neighbors(ci, cj)
                ni, nj = nb
                if mat[ni, nj] == value && !(nb in visited)
                    push!(visited, nb)
                    push!(queue, nb)
                end
            end
        end

        return visited
    end

    # ------------------------------------------------------------
    # Toutes les composantes d'une valeur
    # ------------------------------------------------------------
    function getAllComponents(mat::Matrix{Int}, value::Int)
        seen = falses(n, m)
        components = Vector{Vector{Tuple{Int,Int}}}()

        for i in 1:n, j in 1:m
            if seen[i,j] || mat[i,j] != value
                continue
            end

            component = Tuple{Int,Int}[]
            queue = [(i,j)]
            seen[i,j] = true

            while !isempty(queue)
                ci, cj = popfirst!(queue)
                push!(component, (ci,cj))

                for (ni,nj) in neighbors(ci,cj)
                    if !seen[ni,nj] && mat[ni,nj] == value
                        seen[ni,nj] = true
                        push!(queue, (ni,nj))
                    end
                end
            end

            push!(components, component)
        end

        return components
    end

    # ------------------------------------------------------------
    # Une composante incomplete peut-elle encore grandir ?
    # ------------------------------------------------------------
    function hasEmptyNeighbor(mat::Matrix{Int}, component)
        for (ci, cj) in component
            for (ni, nj) in neighbors(ci, cj)
                if mat[ni, nj] == 0
                    return true
                end
            end
        end
        return false
    end

    # ------------------------------------------------------------
    # Verification locale apres un placement
    # ------------------------------------------------------------
    function localCheck(mat::Matrix{Int}, i::Int, j::Int, value::Int)
        component = getComponent(mat, (i,j), value)
        sizeComponent = length(component)

        if sizeComponent > value
            return false
        end

        if sizeComponent < value && !hasEmptyNeighbor(mat, component)
            return false
        end

        return true
    end

    # ------------------------------------------------------------
    # Verification finale de toute la grille
    # ------------------------------------------------------------
    function globalCheck(mat::Matrix{Int})
        # Toutes les cases doivent etre remplies
        for i in 1:n, j in 1:m
            mat[i,j] == 0 && return false
        end

        # Chaque composante de valeur k doit avoir exactement k cases
        for value in 1:maximum(mat)
            components = getAllComponents(mat, value)
            for component in components
                length(component) == value || return false
            end
        end

        return true
    end

    # ------------------------------------------------------------
    # Ordre des cases vides : les plus contraintes d'abord
    # ------------------------------------------------------------
    emptyCells = [(i,j) for i in 1:n, j in 1:m if grid[i,j] == 0]

    function fixedNeighborCount(cell)
        i, j = cell
        countFixed = 0

        for (ni, nj) in neighbors(i, j)
            if grid[ni, nj] > 0
                countFixed += 1
            end
        end

        return -countFixed
    end

    sort!(emptyCells, by=fixedNeighborCount)

    # ------------------------------------------------------------
    # Ordre des valeurs : d'abord les valeurs voisines
    # ------------------------------------------------------------
    function possibleValues(cell)
        i, j = cell
        nearbyValues = Set{Int}()

        for (ni, nj) in neighbors(i, j)
            if sol[ni, nj] > 0
                push!(nearbyValues, sol[ni, nj])
            end
        end

        values = collect(nearbyValues)

        for k in 1:maxK
            if !(k in nearbyValues)
                push!(values, k)
            end
        end

        return values
    end

    # ------------------------------------------------------------
    # Backtracking
    # ------------------------------------------------------------
    function search(pos::Int)
        if time() - startTime > TIME_LIMIT
            return false
        end

        if pos > length(emptyCells)
            return globalCheck(sol)
        end

        i, j = emptyCells[pos]

        for value in possibleValues((i,j))
            sol[i,j] = value

            if localCheck(sol, i, j, value)
                if search(pos + 1)
                    return true
                end
            end

            sol[i,j] = 0
        end

        return false
    end

    success = search(1)
    solveTime = time() - startTime

    return success, solveTime, sol
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
        println(csv, "instance,n,m,method,solved,valid,solve_time")

        for file in sort(filter(x -> endswith(x, ".txt"), readdir(dataFolder)))
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
                    string(solveTime)
                ], ","))
            end
        end
    end

    println("CSV results written to ", csvFile)
end
