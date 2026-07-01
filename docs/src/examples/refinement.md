# Refinement

Delone.jl supports **uniform**, **marked adaptive**, and **second-order**
refinement. All h-refinement paths are **geometry-aware**: new boundary nodes are
projected onto the true curved boundary (circle, sphere, CAD face), not placed at
chord midpoints.

## Uniform refinement

```julia
using Delone

geom = geometry2d(Circle(0.0, 0.0, 1.0, "d", "c"))
mesh = generate_mesh(geom; maxh=0.4)

ne0 = Delone.Internals.GetNE(mesh)
refine!(mesh)                    # in place
Delone.Internals.GetNE(mesh) > ne0         # more elements
```

On a 3D sphere built with OCC, boundary vertices stay on the surface after
`refine!` (radius 1 within floating-point tolerance).

## Marked bisection (adaptive)

Mark elements, then bisect:

```julia
mesh = generate_mesh(geom; maxh=0.4)
Delone.Internals.UpdateTopology(mesh)

ne = Delone.Internals.GetNE(mesh)
marked = falses(ne)
marked[1:ne÷4] .= true            # refine first quarter of elements

mark_for_refinement!(mesh, marked)
bisect!(mesh)
```

`BisectionOptions` fields (`refine_p`, `refine_hp`, …) are available on the C++
type if you need marked p- or hp-refinement at the bisection step; Julian session
helpers wrap the common cases (see [Tags, hp-adaptivity & FEM data](@ref "Tags, hp-adaptivity & FEM data")).

## Second-order curving

Add edge midpoints and curve them onto the geometry:

```julia
np0 = Delone.Internals.GetNP(mesh)
make_second_order!(mesh)
Delone.Internals.GetNP(mesh) > np0         # new midpoint nodes
```

Second-order curving is **in-place** on the same mesh level: it does not append a
new multigrid level (unlike `refine!`). Snapshots of that level must be refreshed
after curving (`generation` changes in a live session).

## Parent nodes after refinement

`parent_nodes(mesh)` returns a `2×np` matrix: for each fine node, the two coarse
parent node indices (or `(0,0)` if the node existed on the coarse mesh with the
**same index**):

```julia
coarse = generate_mesh(geom; maxh=0.5)
fine   = copy_mesh(coarse)
refine!(fine)

P = parent_nodes(fine)
Xc, Xf = points(coarse), points(fine)

for j in axes(P, 2)
    a, b = P[1, j], P[2, j]
    a == 0 && continue
    # New node j splits edge (a,b) on the coarse mesh; Xf[:,j] is on the geometry.
end
```

On a unit disk, parents on the boundary lie at radius 1, the chord midpoint sits
inside (`r < 1`), but the new node is projected back to `r = 1`.

## Low-level refinement API

The 1:1 stack is:

```
GetGeometry(mesh) → GetRefinement(geom) → Refine / Bisect / MakeSecondOrder
```

`refine!`, `bisect!`, and `make_second_order!` are thin wrappers around that
chain.

Next: [Mesh hierarchies & sessions](@ref "Mesh hierarchies & sessions") for multi-level workflows and snapshot
export.
