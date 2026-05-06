# generation.jl for Filling — with wall support

include("io.jl")

# ---------------------------------------------------------------------------
# Solution generator
# ---------------------------------------------------------------------------

"""
Generate a valid complete Filling grid (no walls considered here —
walls are added separately in generateInstance).
"""
function generateSolution(n::Int, m::Int, maxVal::Int = 6,
                            walls::Set = Set())
    grid = zeros(Int, n, m)
    remaining = Set{Tuple{Int,Int}}([(i,j) for i in 1:n for j in 1:m])

    while !isempty(remaining)
        start = rand(collect(remaining))

        # Values already used by adjacent assigned regions
        blocked = Set{Int}()
        for (ni, nj) in getNeighbors(n, m, walls, start[1], start[2])
            grid[ni,nj] > 0 && push!(blocked, grid[ni,nj])
        end

        max_possible = min(maxVal, length(remaining))
        candidates = [v for v in 1:max_possible if v ∉ blocked]
        isempty(candidates) && (candidates = [1])
        v_target = rand(candidates)

        # BFS growth respecting walls
        region    = Tuple{Int,Int}[start]
        in_region = Set{Tuple{Int,Int}}([start])
        delete!(remaining, start)

        frontier = Tuple{Int,Int}[]
        for (ni, nj) in getNeighbors(n, m, walls, start[1], start[2])
            (ni,nj) in remaining && push!(frontier, (ni,nj))
        end

        while length(region) < v_target && !isempty(frontier)
            valid_next = filter(frontier) do cell
                for (ni, nj) in getNeighbors(n, m, walls, cell[1], cell[2])
                    grid[ni,nj] == v_target && (ni,nj) ∉ in_region && return false
                end
                return true
            end
            isempty(valid_next) && break

            next = rand(valid_next)
            push!(region, next); push!(in_region, next)
            delete!(remaining, next)
            filter!(c -> c != next, frontier)

            for (ni, nj) in getNeighbors(n, m, walls, next[1], next[2])
                (ni,nj) in remaining && (ni,nj) ∉ in_region && push!(frontier, (ni,nj))
            end
        end

        actual_v = length(region)
        for (ri,rj) in region; grid[ri,rj] = actual_v; end
    end

    return grid
end

# ---------------------------------------------------------------------------
# Random wall generator
# ---------------------------------------------------------------------------

"""
Generate a random set of walls for an n×m grid.
wallDensity = probability that each internal edge is a wall.
"""
function generateWalls(n::Int, m::Int, wallDensity::Float64 = 0.10)
    walls = Set{Tuple{Tuple{Int,Int},Tuple{Int,Int}}}()
    # Horizontal walls: between (i,j) and (i+1,j)
    for i in 1:n-1, j in 1:m
        rand() < wallDensity && push!(walls, ((i,j),(i+1,j)))
    end
    # Vertical walls: between (i,j) and (i,j+1)
    for i in 1:n, j in 1:m-1
        rand() < wallDensity && push!(walls, ((i,j),(i,j+1)))
    end
    return walls
end

# ---------------------------------------------------------------------------
# Instance generator
# ---------------------------------------------------------------------------

"""
Generate a random Filling instance with walls.
  1. Generate random walls.
  2. Generate a valid complete solution (respecting walls).
  3. Reveal a subset of cells as hints.

Returns: n, m, grid, walls
"""
function generateInstance(n::Int, m::Int,
                           density::Float64    = 0.35,
                           maxVal::Int         = 6,
                           wallDensity::Float64 = 0.08)
    walls = generateWalls(n, m, wallDensity)
    sol   = generateSolution(n, m, maxVal, walls)
    grid  = zeros(Int, n, m)
    for i in 1:n, j in 1:m
        rand() < density && (grid[i,j] = sol[i,j])
    end
    return n, m, grid, walls
end

# ---------------------------------------------------------------------------
# Write instance
# ---------------------------------------------------------------------------

"""
Write a Filling instance to a text file including the wall list.
"""
function writeInstance(fileName::String, n::Int, m::Int,
                        grid::Array{Int,2},
                        walls::Set = Set())
    fout = open(fileName, "w")
    for i in 1:n
        println(fout, join(grid[i,:], ", "))
    end
    if !isempty(walls)
        println(fout, "WALLS")
        for ((i1,j1),(i2,j2)) in walls
            if i1 == i2          # same row → vertical wall
                println(fout, "V ", i1, " ", min(j1,j2))
            else                 # same column → horizontal wall
                println(fout, "H ", min(i1,i2), " ", j1)
            end
        end
    end
    close(fout)
end

# ---------------------------------------------------------------------------
# Dataset generator
# ---------------------------------------------------------------------------

"""
Generate a dataset of Filling instances with walls and save to ../data/.
"""
function generateDataSet()
    dataFolder = "../data/"
    isdir(dataFolder) || mkpath(dataFolder)

    sizes = [4, 5, 6, 7, 8, 10, 12, 15]
    nbInstances = 5

    for n in sizes
        for k in 1:nbInstances
            fileName = dataFolder * "instance_$(n)x$(n)_$(k).txt"
            if !isfile(fileName)
                _, _, grid, walls = generateInstance(n, n)
                writeInstance(fileName, n, n, grid, walls)
                println("Generated: ", fileName)
            end
        end
    end
    println("Dataset ready in ", dataFolder)
end