# ==============================================================================
# Projet Filling - RO03
#
# Structure du dossier (tout au même niveau) :
#   io.jl, resolution.jl, generation.jl, main.jl
#   data/instanceTest.txt
#   res/cplex/
#
# Lancer depuis ce dossier :
#   julia> include("main.jl")
#   julia> testReadInstance()
#   julia> testSolve()
#   julia> generateAndSolve()
# ==============================================================================

include("generation.jl")   # → resolution.jl → io.jl

# ------------------------------------------------------------------
# Test 1 : Lecture et affichage d'une instance
# ------------------------------------------------------------------
function testReadInstance(path::String = "data/instanceTest.txt")
    println("\n=== readInputFile ===")
    n, m, grid, maxVal = readInputFile(path)
    println("Grille $(n)×$(m), maxVal=$maxVal")
    displayGrid(n, m, grid)
    return n, m, grid, maxVal
end

# ------------------------------------------------------------------
# Test 2 : Résolution exacte CPLEX + callback
# ------------------------------------------------------------------
function testSolve(path::String = "data/instanceTest.txt")
    println("\n=== cplexSolve (avec callback) ===")
    n, m, grid, maxVal = readInputFile(path)

    println("Grille initiale :")
    displayGrid(n, m, grid)

    isOptimal, solveTime, assign = cplexSolve(n, m, grid, maxVal)

    if isOptimal
        println("\n✅ Solution trouvée en $(round(solveTime, digits=4)) s")
        displaySolution(n, m, assign)
    else
        println("\n❌ Pas de solution ($(round(solveTime, digits=4)) s)")
    end
    return isOptimal, solveTime, assign
end

# ------------------------------------------------------------------
# Test 3 : Génération + résolution du dataset complet
# ------------------------------------------------------------------
function generateAndSolve()
    println("\n=== Génération du dataset ===")
    generateDataSet("data/")

    println("\n=== Résolution du dataset ===")
    solveDataSet("data/", "res/cplex")

    println("\n=== Tableau des résultats ===")
    resultsArray("data/", "res/cplex")
end
