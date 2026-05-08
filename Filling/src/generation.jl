# generation.jl for Filling

include("io.jl")
include("solutions.jl")

# ---------------------------------------------------------------------------
# Instance generator
# ---------------------------------------------------------------------------

"""
Generate a random Filling instance from a known solution.
  - Exactly one clue per region is revealed.

Returns: n, m, grid
"""
function generateInstance(n::Int, m::Int)
    haskey(KNOWN_SOLUTIONS, (n, m)) ||
        error("No known solution for $(n)×$(m). Add one to src/solutions.jl.")

    sol = KNOWN_SOLUTIONS[(n, m)]

    grid    = zeros(Int, n, m)
    visited = falses(n, m)

    for i in 1:n, j in 1:m
        visited[i, j] && continue
        v = sol[i, j]

        # BFS to collect the full region
        comp  = Tuple{Int,Int}[]
        queue = [(i, j)]
        visited[i, j] = true
        while !isempty(queue)
            ci, cj = popfirst!(queue)
            push!(comp, (ci, cj))
            for (ni, nj) in getNeighbors(n, m, ci, cj)
                if !visited[ni, nj] && sol[ni, nj] == v
                    visited[ni, nj] = true
                    push!(queue, (ni, nj))
                end
            end
        end

        # Always reveal one clue per region
        clue = rand(comp)
        grid[clue[1], clue[2]] = v
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
        println(fout, join(grid[i, :], ", "))
    end
    close(fout)
end

# ---------------------------------------------------------------------------
# Dataset generator
# ---------------------------------------------------------------------------

"""
Generate a dataset of Filling instances from known solutions and save to data/.
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

    sizes      = [3, 4, 5, 6,7, 8, 9, 10, 11, 12, 13, 14, 15]
    nbInstances = 50

    for n in sizes
        haskey(KNOWN_SOLUTIONS, (n, n)) ||
            (println("Skipping $(n)×$(n): no known solution."); continue)

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
