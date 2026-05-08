# Filling — main entry point
#
# Usage (from the Filling/ directory in Julia REPL):
#   include("main.jl")
#   testReadInstance()          — affiche la grille du fichier test
#   testSolve()                 — résout le fichier test avec CPLEX
#   testHeuristic()             — résout le fichier test avec l'heuristique
#   generateAndSolve()          — génère + résout avec CPLEX et heuristique
#   generateAndSolve(methods=["cplex"])      — CPLEX uniquement
#   generateAndSolve(methods=["heuristic"]) — heuristique uniquement

include("src/resolution.jl")   # includes generation.jl → io.jl

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

function generateAndSolve(; methods::Vector{String}=["cplex"],
                            force::Bool=true,
                            csvFile::String="res/results.csv")
    println("\n=== generateAndSolve ===")
    generateDataSet(clean=true)
    solveDataSet(methods=methods, force=force, csvFile=csvFile)
end
