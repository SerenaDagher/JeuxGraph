# Filling — main entry point (with wall support)
#
# Usage (from the Filling/ directory in Julia REPL):
#   include("main.jl")
#   testReadInstance()
#   testSolve()
#   testHeuristic()
#   generateAndSolve()

include("src/resolution.jl")   # includes generation.jl → io.jl

function testReadInstance(path::String = "data/instanceTest.txt")
    println("\n=== Test readInputFile ===")
    n, m, grid, walls = readInputFile(path)
    println("Grid $(n)×$(m) — $(length(walls)) wall(s)")
    println("\nInitial grid:")
    displayGrid(n, m, grid, walls)
    return n, m, grid, walls
end

function testSolve(path::String = "data/instanceTest.txt")
    println("\n=== Test cplexSolve ===")
    n, m, grid, walls = readInputFile(path)
    isOptimal, solveTime, sol = cplexSolve(n, m, grid, walls)
    println("Optimal: ", isOptimal, "  |  Time: ", round(solveTime, digits=4), "s")
    if isOptimal
        println("\nSolution:")
        displaySolution(n, m, sol, walls)
        println("Valid: ", checkSolution(n, m, sol, walls))
    else
        println("No solution found.")
    end
    return isOptimal, solveTime, sol
end

function testHeuristic(path::String = "data/instanceTest.txt")
    println("\n=== Test heuristicSolve ===")
    n, m, grid, walls = readInputFile(path)
    isValid, solveTime, sol = heuristicSolve(n, m, grid, walls)
    println("Valid: ", isValid, "  |  Time: ", round(solveTime, digits=4), "s")
    println("\nHeuristic solution:")
    displaySolution(n, m, sol, walls)
    return isValid, solveTime, sol
end

function generateAndSolve()
    println("\n=== generateAndSolve ===")
    generateDataSet()
    solveDataSet()
end