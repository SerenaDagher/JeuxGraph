# LightUp – main entry point
#
# Usage (from the LightUp/ directory in Julia REPL):
#   include("main.jl")
#   testReadInstance()
#   testSolve()
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
# Test 2 : solve with CPLEX
# ---------------------------------------------------------------------------
function testSolve(path::String = "data/instanceTest.txt")
    println("\n=== Test cplexSolve ===")
    n, m, grid = readInputFile(path)
    SolutionFound, solveTime, x_val = cplexSolve(n, m, grid)
    println("SolutionFound: ", SolutionFound, "  |  Time: ", round(solveTime, digits=4), "s")
    if SolutionFound
        println("\nSolution:")
        displaySolution(n, m, grid, x_val)
    else
        println("No solution found.")
    end
    return SolutionFound, solveTime, x_val
end

# ---------------------------------------------------------------------------
# Test 3 : generate dataset and solve all instances
# ---------------------------------------------------------------------------
function generateAndSolve()
    println("\n=== generateAndSolve ===")
    generateDataSet()
    solveDataSet()
end