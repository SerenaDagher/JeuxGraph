# main.jl — Filling game

include("src/resolution.jl")

function testReadInstance(path::String = "data/instanceTest.txt")
    println("\n=== testReadInstance ===")
    n, m, grid = readInputFile(path)
    println("Grille $(n)×$(m)")
    displayGrid(n, m, grid)
    return n, m, grid
end

function testSolve(path::String = "data/instanceTest.txt")
    println("\n=== testSolve (CPLEX + callback) ===")
    n, m, grid = readInputFile(path)
    SolutionFound, solveTime, sol = cplexSolve(n, m, grid)
    println("Solution trouvée : $SolutionFound  —  temps : $(round(solveTime, digits=4)) s")
    if SolutionFound
        displaySolution(n, m, sol)
        println("Valide : ", checkSolution(n, m, sol, grid))
    end
    return SolutionFound, solveTime, sol
end

function testHeuristic(path::String = "data/instanceTest.txt")
    println("\n=== testHeuristic ===")
    n, m, grid = readInputFile(path)
    isValid, solveTime, sol = heuristicSolve(n, m, grid)
    println("Valide : $isValid  —  temps : $(round(solveTime, digits=4)) s")
    displaySolution(n, m, sol)
    return isValid, solveTime, sol
end

function generateAndSolve(; methods = ["cplex","heuristic"], force = false)
    println("\n=== generateAndSolve ===")
    generateDataSet()
    solveDataSet("data/", "res/"; methods=methods, force=force)
end