# Filling – main entry point
#
# Usage (from the Filling/ directory in Julia REPL):
#   include("main.jl")
#   testReadInstance()
#   testSolve()
#   testHeuristic()
#   generateAndSolve()

include("src/resolution.jl")   # includes generation.jl → io.jl

# ---------------------------------------------------------------------------
# Test 1 : read and display an instance
# ---------------------------------------------------------------------------
function testReadInstance(path::String = "data/instanceTest.txt")
    println("\n=== Test readInputFile ===")
    n, m, grid = readInputFile(path)
    println("Grid $(n)×$(m) loaded successfully.")
    println("\nInitial grid:")
    displayGrid(n, m, grid)
    return n, m, grid
end

# ---------------------------------------------------------------------------
# Test 2 : exact resolution with CPLEX
# ---------------------------------------------------------------------------
function testSolve(path::String = "data/instanceTest.txt")
    println("\n=== Test cplexSolve ===")
    n, m, grid = readInputFile(path)
    isOptimal, solveTime, sol = cplexSolve(n, m, grid)
    println("Optimal: ", isOptimal, "  |  Time: ", round(solveTime, digits=4), "s")
    if isOptimal
        println("\nSolution:")
        displaySolution(n, m, sol)
        println("Valid: ", checkSolution(n, m, sol))
    else
        println("No solution found.")
    end
    return isOptimal, solveTime, sol
end

# ---------------------------------------------------------------------------
# Test 3 : greedy heuristic
# ---------------------------------------------------------------------------
function testHeuristic(path::String = "data/instanceTest.txt")
    println("\n=== Test heuristicSolve ===")
    n, m, grid = readInputFile(path)
    isValid, solveTime, sol = heuristicSolve(n, m, grid)
    println("Valid: ", isValid, "  |  Time: ", round(solveTime, digits=4), "s")
    println("\nHeuristic solution:")
    displaySolution(n, m, sol)
    return isValid, solveTime, sol
end

# ---------------------------------------------------------------------------
# Test 4 : generate dataset and solve everything
# ---------------------------------------------------------------------------
function generateAndSolve()
    println("\n=== generateAndSolve ===")
    generateDataSet()
    solveDataSet()
end