
include("src/resolution.jl")

function testReadInstance(path::String = "data/instanceTest.txt")
    println("\n=== Test readInputFile ===")
    n, m, grid = readInputFile(path)
    println("Grid $(n)×$(m) loaded successfully.")
    println("\nInitial grid:")
    displayGrid(n, m, grid)
    return n, m, grid
end

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

function generateAndSolve()
    println("\n=== generateAndSolve ===")
    generateDataSet()
    solveDataSet()
end
