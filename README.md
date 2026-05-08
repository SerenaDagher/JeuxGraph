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
│   ├── res/           # résultats CPLEX et heuristique
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
        └── generation.jl
```

Chaque jeu suit la même organisation : un point d'entrée `main.jl`, un module de lecture/affichage, un module de résolution et un module de génération d'instances.

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

### Résultats

Toutes les instances réelles testées sont résolues, y compris des grilles **50×50 en 0.038s**. La taille n'est pas le facteur limitant — c'est la faisabilité de l'instance qui détermine si une solution existe.

---

## Filling

### Règles

Remplir une grille avec des chiffres. Chaque chiffre `k` doit former une zone **connexe** de exactement `k` cases de valeur `k`. Des murs peuvent séparer des cases adjacentes.

### Modèle PLNE

- **Variable** : `x[i,j,k] ∈ {0,1}` — 1 si la case (i,j) a la valeur k
- **C1** : chaque case a exactement une valeur — `Σ_k x[i,j,k] = 1`
- **C2** : cases pré-remplies fixées — `x[i,j,grid[i,j]] = 1`
- **Callback** : connexité exacte via coupes paresseuses

### Callback CPLEX

La contrainte de connexité ne peut pas s'écrire directement dans le modèle sans un nombre exponentiel de contraintes. On utilise un **callback** : à chaque solution entière candidate, on vérifie les composantes connexes par BFS et on ajoute une coupe si une composante a la mauvaise taille.

Deux types de coupes selon la situation :

```
Composante C trop grande (|C| > k) :
    Σ_{(i,j)∈C} x[i,j,k]  ≤  |C| − 1

Composante C trop petite (|C| < k) :
    Σ_{(i,j)∈C} x[i,j,k]  ≤  |C| − 1  +  Σ_{(ni,nj)∈N(C)} x[ni,nj,k]
```

### Format d'instance

```
0, 0, 0, 0, 4
4, 0, 0, 3, 0
0, 0, 5, 0, 0
0, 5, 2, 4, 0
0, 0, 0, 0, 2
WALLS
H 3 3
V 4 2
V 4 3
```

`0` = case vide, valeur > 0 = case pré-remplie.  
`H r c` = mur horizontal entre (r,c) et (r+1,c).  
`V r c` = mur vertical entre (r,c) et (r,c+1).

### Résultats

Les instances 4×4 à 6×6 sont résolues en moins de 0.25s. Les instances générées aléatoirement sont souvent infaisables — c'est la faisabilité, et non la taille, qui conditionne la résolution.

---

## Génération d'instances

Les deux jeux disposent d'un générateur aléatoire produisant des datasets de tailles variées. Les instances générées ne sont pas garanties faisables — certaines contiennent des contradictions locales inévitables avec une génération purement aléatoire.

```julia
julia> generateDataSet()   # génère les instances dans data/
julia> solveDataSet()      # résout et écrit les résultats dans res/
```

---

## Rapports

Les rapports complets (modélisation, implémentation, résultats, analyse) sont disponibles dans le dépôt :

- `rapport_lightup.pdf`
- `rapport_filling.pdf`
