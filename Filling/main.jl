
include("src/resolution.jl")

function testReadInstance(path::String = "data/instanceTest.txt")
    println("\n=== Test readInputFile ===")
    n, m, grid = readInputFile(path)
    println("Grid $(n)×$(m)")
    println("\nInitial grid:")
    displayGrid(n, m, grid)
    return n, m, grid
end

function testSolve(path::String = "data/instanceTest.txt")
    println("\n=== Test cplexSolve ===")
    n, m, grid = readInputFile(path)
    isOptimal, solveTime, sol = cplexSolve(n, m, grid)
    println("Solution found: ", isOptimal, "  |  Time: ", round(solveTime, digits=4), "s")
    if isOptimal
        println("\nSolution:")
        displaySolution(n, m, sol)
        println("Valid: ", checkSolution(n, m, sol))
    else
        println("No solution found.")
    end
    return isOptimal, solveTime, sol
end

function testHeuristic(path::String = "data/instanceTest.txt")
    println("\n=== Test heuristicSolve ===")
    n, m, grid = readInputFile(path)
    isValid, solveTime, sol = heuristicSolve(n, m, grid)
    println("Valid: ", isValid, "  |  Time: ", round(solveTime, digits=4), "s")
    if isValid
        println("\nHeuristic solution:")
    else
        println("\nLast heuristic try (filled grid, invalid):")
    end
    displaySolution(n, m, sol)
    return isValid, solveTime, sol
end

function generateAndSolve(; methods::Vector{String}=["heuristic"],
                            force::Bool=true,
                            csvFile::String="res/results.csv")
    println("\n=== generateAndSolve ===")
    generateDataSet(clean=true)
    solveDataSet(methods=methods, force=force, csvFile=csvFile)
end
