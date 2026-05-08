# generation.jl for Filling

include("io.jl")

# ---------------------------------------------------------------------------
# Solution generator
# ---------------------------------------------------------------------------

"""
Generate a valid complete Filling grid.
"""
function generateSolution(n::Int, m::Int, maxVal::Int = 6)
    grid = zeros(Int, n, m)
    remaining = Set{Tuple{Int,Int}}([(i,j) for i in 1:n for j in 1:m])

    while !isempty(remaining)
        start = rand(collect(remaining))

        # Values already used by adjacent assigned regions
        blocked = Set{Int}()
        for (ni, nj) in getNeighbors(n, m, start[1], start[2])
            grid[ni,nj] > 0 && push!(blocked, grid[ni,nj])
        end

        max_possible = min(maxVal, length(remaining))
        candidates = [v for v in 1:max_possible if v ∉ blocked]
        isempty(candidates) && (candidates = [1])
        v_target = rand(candidates)

        # BFS growth
        region    = Tuple{Int,Int}[start]
        in_region = Set{Tuple{Int,Int}}([start])
        delete!(remaining, start)

        frontier = Tuple{Int,Int}[]
        for (ni, nj) in getNeighbors(n, m, start[1], start[2])
            (ni,nj) in remaining && push!(frontier, (ni,nj))
        end

        while length(region) < v_target && !isempty(frontier)
            valid_next = filter(frontier) do cell
                for (ni, nj) in getNeighbors(n, m, cell[1], cell[2])
                    grid[ni,nj] == v_target && (ni,nj) ∉ in_region && return false
                end
                return true
            end
            isempty(valid_next) && break

            next = rand(valid_next)
            push!(region, next); push!(in_region, next)
            delete!(remaining, next)
            filter!(c -> c != next, frontier)

            for (ni, nj) in getNeighbors(n, m, next[1], next[2])
                (ni,nj) in remaining && (ni,nj) ∉ in_region && push!(frontier, (ni,nj))
            end
        end

        actual_v = length(region)
        for (ri,rj) in region; grid[ri,rj] = actual_v; end
    end

    return grid
end

# ---------------------------------------------------------------------------
# Instance generator
# ---------------------------------------------------------------------------

"""
Generate a random Filling instance.
  1. Generate a valid complete solution.
  2. Reveal a subset of cells as hints.

Returns: n, m, grid
"""
function generateInstance(n::Int, m::Int,
                           density::Float64 = 0.35,
                           maxVal::Int      = 6)
    sol  = generateSolution(n, m, maxVal)
    grid = zeros(Int, n, m)
    for i in 1:n, j in 1:m
        rand() < density && (grid[i,j] = sol[i,j])
    end
    return n, m, grid
end

# ---------------------------------------------------------------------------
# Write instance
# ---------------------------------------------------------------------------

"""
Write a Filling instance to a text file.
"""
function writeInstance(fileName::String, n::Int, m::Int, grid::Array{Int,2})
    fout = open(fileName, "w")
    for i in 1:n
        println(fout, join(grid[i,:], ", "))
    end
    close(fout)
end

# ---------------------------------------------------------------------------
# Dataset generator
# ---------------------------------------------------------------------------

"""
Generate a dataset of Filling instances and save to data/.
"""
function generateDataSet(; clean::Bool = true)
    dataFolder = "data/"
    isdir(dataFolder) || mkpath(dataFolder)

    if clean
        for file in filter(x -> startswith(x, "instance_") && endswith(x, ".txt"), readdir(dataFolder))
            rm(joinpath(dataFolder, file); force=true)
        end
        println("Deleted previous generated instances in ", dataFolder)
    end

    sizes = [15]
    nbInstances = 80

    for n in sizes
        for k in 1:nbInstances
            fileName = dataFolder * "instance_$(n)x$(n)_$(k).txt"
            if !isfile(fileName)
                _, _, grid = generateInstance(n, n)
                writeInstance(fileName, n, n, grid)
                println("Generated: ", fileName)
            end
        end
    end
    println("Dataset ready in ", dataFolder)
end
