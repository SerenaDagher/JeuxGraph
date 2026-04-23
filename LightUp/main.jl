# ==============================================================================
# Point d'entrée principal pour le projet Lightup - RO03
# ==============================================================================
# Usage depuis la console Julia :
#   include("main.jl")
#
# Puis appeler les fonctions selon les besoins :
#   testReadInstance()
#   testSolve()
#   testHeuristic()
#   generateAndSolve()
# ==============================================================================

include("src/generation.jl")  # inclut io.jl et resolution.jl

# ------------------------------------------------------------------
# Test 1 : Lecture d'une instance
# ------------------------------------------------------------------
function testReadInstance(path::String = "data/instanceTest.txt")
    println("\n=== Test readInputFile ===")
    n, m, grid = readInputFile(path)
    println("Grille $(n)×$(m) lue avec succès.")
    println("\nAffichage de la grille initiale :")
    displayGrid(n, m, grid)
    return n, m, grid
end

# ------------------------------------------------------------------
# Test 2 : Résolution exacte CPLEX
# ------------------------------------------------------------------
function testSolve(path::String = "data/instanceTest.txt")
    println("\n=== Test cplexSolve ===")
    n, m, grid = readInputFile(path)

    println("Grille initiale :")
    displayGrid(n, m, grid)

    isOptimal, solveTime, x_val = cplexSolve(n, m, grid)

    if isOptimal
        println("\n✅ Solution trouvée en $(round(solveTime, digits=4)) s")
        println("\nSolution :")
        displaySolution(n, m, grid, x_val)
        println("\nLampes placées :")
        for i in 1:n, j in 1:m
            x_val[i, j] > 0.9 && println("  Lampe en ($i, $j)")
        end
    else
        println("\n❌ Pas de solution trouvée (temps : $(round(solveTime, digits=4)) s)")
    end

    return isOptimal, solveTime, x_val
end

# ------------------------------------------------------------------
# Test 3 : Heuristique
# ------------------------------------------------------------------
function testHeuristic(path::String = "data/instanceTest.txt")
    println("\n=== Test heuristicSolve ===")
    n, m, grid = readInputFile(path)

    isComplete, solveTime, x_val = heuristicSolve(n, m, grid)

    if isComplete
        println("✅ Heuristique : solution complète en $(round(solveTime, digits=6)) s")
    else
        println("⚠️  Heuristique : solution incomplète en $(round(solveTime, digits=6)) s")
    end
    displaySolution(n, m, grid, x_val)
    return isComplete, solveTime, x_val
end

# ------------------------------------------------------------------
# Test 4 : Génération + résolution du dataset complet
# ------------------------------------------------------------------
function generateAndSolve()
    println("\n=== Génération du dataset ===")
    generateDataSet("data/")

    println("\n=== Résolution du dataset ===")
    solveDataSet("data/", "res/cplex")

    println("\n=== Tableau des résultats ===")
    resultsArray("data/", "res/cplex")
end
