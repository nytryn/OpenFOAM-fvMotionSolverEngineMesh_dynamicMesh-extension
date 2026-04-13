# Canted-Valves Engines in OpenFOAM

## Background
- 3D motion is build on top of uni-directional engine motion (`engineMesh`+ `dynamicMesh`)
- Predominantly developed to allow canted-valve engine simulation directly in OpenFOAM's engine solvers
- As side effect brings in arbitrary 3D mesh motion via `dynamicMesh`
- Dedicated tutorial uses a heavily simplified 2D engine model with to boxes symbolising the non-vertically up-/down-moving canted valves
- Former implementation relied on per-solver extension, e.g. `engineFoam` - now all centralised in `fvMotionSolverEngineMesh` instead
- Falls back to legacy behaviour if new keyword `motionType` is missing in `<constant>/engineGeometry`


## Prerequisites
- Developed for and tested with v2206 ... v2512 (openfoam.com fork)
- Compile modified `fvMotionSolverEngineMesh` (`$FOAM_SRC/engine/engineMesh`) using `wmake`


## Run Tutorial
- Run `Allrun` script
- Switch to legacy behaviour (`engineMesh`/vertical valves only) by omitting or setting the `motionType` keyword in `<constant>/engineGeometry` to `engineMesh` - will "break" the tutorial (expected behaviour -> feature)

![demo](https://github.com/user-attachments/assets/d22e7a70-0aba-412c-8993-1349dbe9dec7)



