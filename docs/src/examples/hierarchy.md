# Mesh hierarchies & sessions

There are two complementary ways to work with multiple mesh levels:

1. **Low-level `Ngx_Mesh` maps** on a single refined mesh (`parent_nodes`, …).
2. **Live `MeshHierarchySession`** with explicit levels and optional **snapshots**.

## `Ngx_Mesh` on one mesh

After refining in place, parent data describes the immediate coarse→fine
relation on that mesh object:

```julia
using Delone

mesh = generate_mesh(geometry2d(Circle(0,0,1,"d","c")); maxh=0.4)
refine!(mesh)

P  = parent_nodes(mesh)           # 2×np vertex parents
PE = parent_elements(mesh)        # volume element parents
```

`num_levels`, `level_nvertices`, and `prolongation` help when Netgen stores
multiple embedded levels on one `Mesh`.

## Building a two-level hierarchy manually

```julia
coarse = generate_mesh(geom; maxh=0.5)
fine   = copy_mesh(coarse)
refine!(fine)

# coarse is unchanged; fine carries parent maps back to coarse
h = MeshHierarchy(coarse, fine)   # optional helper type
```

`uniform_hierarchy(geom; levels=3, maxh=0.5)` repeats copy + refine.

## Live session API

A **session** owns geometry and one mesh handle per level. Refinement **requests**
mutate the session and bump a `generation` counter:

```julia
using Delone

geom = load_step("part.step")
s = mesh_session(geom; maxh=0.5)

nlevels(s)          # 1
m1 = finest(s)      # same as level_mesh(s, 1)

request_uniform_refinement!(s)
nlevels(s)          # 2
m2 = finest(s)      # refined level

generation(s)       # incremented — snapshots may be stale
```

Other requests:

```julia
request_marked_refinement!(s, marked)   # adaptive, appends level
request_second_order!(s)                # in-place on finest level only
```

`level_mesh(s, k)` returns the **live** handle for level `k`. For an in-place
mutation that isn't one of the `request_*!` refinements, use
`mutate_level_mesh!` to keep `generation` tracking correct instead of mutating
`unsafe_level_mesh(s, k)` directly:

```julia
mutate_level_mesh!(s, 2) do m       # bump_generation=true by default
    # in-place mesh mutation via Delone.Internals if needed
end                                  # -> returns the session; generation bumped
```

## Snapshots for downstream consumers

Solvers that need **immutable** mesh data copy snapshots instead of holding live
handles:

```julia
snap = level_snapshot(s, 1)         # MeshLevelSnapshot (coordinates, connectivity, …)
supported_snapshot_topology(snap)   # :tet4_3d, :tri3_2d, etc.

hier = hierarchy_snapshot(s)
transfer = transfer_snapshot(s, 1)  # coarse → fine prolongation data
```

Snapshots record `generation` at capture time. After `request_second_order!` or
in-place hp changes, re-snapshot if `snapshot.generation != generation(s)`.

### Supported snapshot topologies

| Mesh | `volume_connectivity` | Notes |
|------|----------------------|-------|
| 3D Tet4 | yes | corners only after second-order curving |
| 3D Tri3 boundary | via surface extraction | |
| 2D Tri3 | yes | domain triangles |
| 2D Segment | boundary segments | |

Transfer weights use documented semantics (`transfer_weight_semantics` →
`:topological_bisection_default`).

## Integration contract (summary)

```
Delone.jl provides   live handles, refinement requests, parent maps,
                     region/tag data, copied snapshots, partition hints
Consumer provides    FE spaces, DOFs, operators, estimators, partition policy
```

Delone.jl does **not** assemble prolongation/restriction matrices or run linear
solvers.

Next: [Structured reports & introspection](@ref "Structured reports & introspection").
