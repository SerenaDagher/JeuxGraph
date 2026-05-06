# This file contains methods to generate Filling instances

include("io.jl")

# ---------------------------------------------------------------------------
# Solution generator
# ---------------------------------------------------------------------------

"""
Generate a valid complete Filling grid of size n×m.

Strategy:
  - Grow connected regions one by one using BFS from a random seed.
  - Each region's value = its actual size.
  - When choosing a value for a new region, avoid values already used by
    adjacent assigned regions (to prevent two same-value regions touching).

Arguments:
  - n, m   : grid dimensions
  - maxVal : maximum allowed value for a region (default 6)

Returns: sol (n×m Array{Int,2})
"""
function generateSolution(n::Int, m::Int, maxVal::Int = 6)
    grid = zeros(Int, n, m)
    remaining = Set{Tuple{Int,Int}}([(i, j) for i in 1:n for j in 1:m])

    while !isempty(remaining)
        # Pick a random unassigned starting cell
        start = rand(collect(remaining))

        # Find values used by already-assigned neighbours
        blocked = Set{Int}()
        for (di, dj) in [(-1,0),(1,0),(0,-1),(0,1)]
            ni, nj = start[1]+di, start[2]+dj
            if 1<=ni<=n && 1<=nj<=m && grid[ni,nj] > 0
                push!(blocked, grid[ni,nj])
            end
        end

        # Choose a target size that doesn't conflict with neighbours
        max_possible = min(maxVal, length(remaining))
        candidates   = [v for v in 1:max_possible if v ∉ blocked]
        isempty(candidates) && (candidates = [1])
        v_target = rand(candidates)

        # BFS growth: expand the region to v_target cells
        region    = Tuple{Int,Int}[start]
        in_region = Set{Tuple{Int,Int}}([start])
        delete!(remaining, start)

        frontier = Tuple{Int,Int}[]
        for (di, dj) in [(-1,0),(1,0),(0,-1),(0,1)]
            ni, nj = start[1]+di, start[2]+dj
            if 1<=ni<=n && 1<=nj<=m && (ni,nj) in remaining
                push!(frontier, (ni, nj))
            end
        end

        while length(region) < v_target && !isempty(frontier)
            # Keep only frontier cells that won't merge with a same-value region
            valid_next = filter(frontier) do cell
                for (di, dj) in [(-1,0),(1,0),(0,-1),(0,1)]
                    ni, nj = cell[1]+di, cell[2]+dj
                    if 1<=ni<=n && 1<=nj<=m &&
                       grid[ni,nj] == v_target && (ni,nj) ∉ in_region
                        return false
                    end
                end
                return true
            end

            isempty(valid_next) && break

            next = rand(valid_next)
            push!(region, next)
            push!(in_region, next)
            delete!(remaining, next)
            filter!(c -> c != next, frontier)

            for (di, dj) in [(-1,0),(1,0),(0,-1),(0,1)]
                ni, nj = next[1]+di, next[2]+dj
                if 1<=ni<=n && 1<=nj<=m &&
                   (ni,nj) in remaining && (ni,nj) ∉ in_region
                    push!(frontier, (ni, nj))
                end
            end
        end

        # Assign the actual region size as the value
        actual_v = length(region)
        for (ri, rj) in region
            grid[ri, rj] = actual_v
        end
    end

    return grid
end

# ---------------------------------------------------------------------------
# Instance generator
# ---------------------------------------------------------------------------

"""
Generate a random Filling instance of size n×m.

Steps:
  1. Generate a complete valid solution with generateSolution.
  2. Reveal a random subset of cells (with probability `density`) as hints.

Arguments:
  - n, m    : grid dimensions
  - density : fraction of cells revealed (default 0.35)
  - maxVal  : maximum region size in the solution (default 6)

Returns: n, m, grid (Array{Int,2})  — 0 = empty cell
"""
function generateInstance(n::Int, m::Int,
                           density::Float64 = 0.35,
                           maxVal::Int = 6)
    sol  = generateSolution(n, m, maxVal)
    grid = zeros(Int, n, m)

    for i in 1:n, j in 1:m
        if rand() < density
            grid[i, j] = sol[i, j]
        end
    end

    return n, m, grid
end

# ---------------------------------------------------------------------------
# Write instance
# ---------------------------------------------------------------------------

"""
Write a Filling grid to a text file (one row per line, cells separated by ", ").
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
Generate a dataset of Filling instances and save them to ../data/.
5 instances are generated for each grid size in {4, 5, 6, 7, 8, 10, 12, 15}.
An instance is only generated if the corresponding file does not already exist.
"""
function generateDataSet()
    dataFolder = "../data/"
    isdir(dataFolder) || mkpath(dataFolder)

    sizes       = [4, 5, 6, 7, 8, 10, 12, 15]
    nbInstances = 5

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