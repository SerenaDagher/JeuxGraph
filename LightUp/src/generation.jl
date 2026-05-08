
include("io.jl")

function generateInstance(n::Int, m::Int,
                           blackRatio::Float64    = 0.30,
                           numberedRatio::Float64 = 0.50)

    grid = fill(".", n, m)

    for i in 1:n, j in 1:m
        if rand() < blackRatio
            grid[i, j] = "N"
        end
    end

    for i in 1:n, j in 1:m
        if grid[i, j] == "N" && rand() < numberedRatio
            nb_white = 0
            for (di, dj) in [(-1,0), (1,0), (0,-1), (0,1)]
                ni, nj = i + di, j + dj
                if 1 <= ni <= n && 1 <= nj <= m && grid[ni, nj] == "."
                    nb_white += 1
                end
            end
            grid[i, j] = string(rand(0:nb_white))
        end
    end

    return n, m, grid
end

function writeInstance(fileName::String, n::Int, m::Int, grid::Array{String,2})
    fout = open(fileName, "w")
    for i in 1:n
        println(fout, join(grid[i, :], ", "))
    end
    close(fout)
end

function generateDataSet()

    dataFolder = "data/"

    if !isdir(dataFolder)
        mkpath(dataFolder)
    end

    sizes       = [4, 5, 6, 7, 8, 10, 12, 15]
    nbInstances = 20

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
