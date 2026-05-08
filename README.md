# JeuxGraph — Résolution de puzzles logiques par PLNE

**Serena Dagher & Yara El Cham**  
ENSTA 2e année — Cours APM 4RO03 — Jeux et R.O

---

## Présentation

Ce projet implémente la résolution exacte de deux puzzles logiques via la **Programmation Linéaire en Nombres Entiers (PLNE)**, en utilisant Julia, JuMP et CPLEX.

| Jeu | Difficulté | Contrainte principale |
|---|---|---|
| **Light Up** | 3 | Éclairage et non-visibilité entre lampes |
| **Filling** | 8 | Connexité exacte des zones par valeur |

---

## Structure du projet

```
JeuxGraph/
├── LightUp/
│   ├── main.jl
│   ├── data/          # instances .txt
│   ├── res/           # résultats CPLEX
│   └── src/
│       ├── io.jl
│       ├── resolution.jl
│       └── generation.jl
│
└── Filling/
    ├── main.jl
    ├── data/          # instances .txt
    ├── res/           # résultats CPLEX et heuristique
    └── src/
        ├── io.jl
        ├── resolution.jl
        ├── generation.jl
        └── solutions.jl
```

---

## Dépendances

- [Julia](https://julialang.org/) ≥ 1.8  
- [JuMP.jl](https://jump.dev/)  
- [CPLEX.jl](https://github.com/jump-dev/CPLEX.jl) + licence IBM CPLEX

---

## Utilisation

```julia
# Depuis le dossier LightUp/ ou Filling/
julia> include("main.jl")

# Résoudre l'instance de test
julia> testSolve()

# Générer un dataset et tout résoudre
julia> generateAndSolve()
```

---

## Light Up

### Règles

Placer des lampes sur une grille. Chaque case blanche doit être éclairée. Deux lampes ne peuvent pas se voir. Les cases noires numérotées imposent un nombre exact de lampes adjacentes.

### Modèle PLNE

- **Variable** : `x[i,j] ∈ {0,1}` — 1 si une lampe est placée en (i,j)
- **C1** : chaque case blanche est éclairée — `Σ_{v ∈ L(c)} x_v ≥ 1`
- **C2** : deux lampes ne se voient pas — `x_u + x_v ≤ 1`
- **C3** : cases noires numérotées — `Σ_{v ∈ N(b)} x_v = k_b`

### Format d'instance

```
., ., ., ., .
., ., 2, ., .
., 3, ., 4, .
., ., N, ., .
., ., ., ., .
```

`.` = case blanche, `N` = case noire, `0`–`4` = case noire numérotée.

### Génération

Les instances sont générées aléatoirement. Cases noires et numéros sont placés en deux passes séparées pour garantir la cohérence locale. Certaines instances restent infaisables à cause de contradictions entre cases noires voisines — c'est inévitable avec une génération purement aléatoire.

### Résultats

Toutes les instances réelles testées sont résolues, y compris des grilles **50×50 en 0.038s**. La taille seule ne détermine pas la difficulté : c'est la densité et la disposition des cases noires qui conditionnent le temps de résolution.

---

## Filling

### Règles

Remplir une grille avec des chiffres. Chaque chiffre `k` doit former une zone **connexe** de exactement `k` cases de valeur `k`.

### Modèle PLNE

- **Variable** : `x[i,j,k] ∈ {0,1}` — 1 si la case (i,j) a la valeur k
- **C1** : chaque case a exactement une valeur — `Σ_k x[i,j,k] = 1`
- **C2** : cases pré-remplies fixées — `x[i,j,grid[i,j]] = 1`
- **Callback** : connexité exacte via coupes paresseuses

### Callback CPLEX

La contrainte de connexité s'applique via un **callback** : à chaque solution entière candidate, le BFS vérifie toutes les composantes connexes et ajoute une coupe si une composante a la mauvaise taille.

```
Composante C trop grande (|C| > k) :
    Σ_{(i,j)∈C} x[i,j,k]  ≤  |C| − 1

Composante C trop petite (|C| < k) :
    Σ_{(i,j)∈C} x[i,j,k]  ≤  |C| − 1  +  Σ_{(ni,nj)∈N(C)} x[ni,nj,k]
```

### Format d'instance

```
4, 2, 5, 0, 0, 2, 0, ...
0, 0, 0, 0, 0, 6, 0, ...
```

`0` = case vide, valeur > 0 = case pré-remplie. Les voisins sont les quatre cases adjacentes orthogonalement.

### Génération

Les instances sont construites à partir de **solutions valides connues** stockées dans `solutions.jl`. Pour chaque composante connexe de la solution, une case est tirée aléatoirement comme indice pré-rempli. Cette méthode garantit que toutes les instances générées sont **faisables**.

Le dataset couvre les tailles **3×3 à 12×12**, avec **50 instances par taille**.

---

## Génération du dataset

```julia
julia> generateDataSet()   # génère les instances dans data/
julia> solveDataSet()      # résout et écrit les résultats dans res/
```

---

