# Delone.jl

[![Tests](https://github.com/ahojukka5/Delone.jl/actions/workflows/test.yml/badge.svg)](https://github.com/ahojukka5/Delone.jl/actions/workflows/test.yml)
[![Docs](https://github.com/ahojukka5/Delone.jl/actions/workflows/docs.yml/badge.svg)](https://github.com/ahojukka5/Delone.jl/actions/workflows/docs.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

**Delone.jl** is a high-level, LLM-friendly meshing, refinement, mesh-diagnostics,
and mesh-hierarchy package for numerical simulation workflows. It is built on
top of [**Netgen/NGSolve**](https://ngsolve.org/), a mature and powerful
open-source meshing technology — Delone.jl does not try to replace Netgen; it
provides a Julian, simulation-oriented, agent-friendly layer above it.

Geometry can come from a CAD file (STEP/IGES/BREP), be built programmatically
with OpenCASCADE (`OpenCascade.jl` + BREP interop), or be defined in 2D
(`geom2d`/`csg2d`). Refinement is **geometry-aware**: new boundary nodes are
projected onto the true curved surface.

> Transfer operators for geometric multigrid are **not** built here — this
> package exposes the meshes and the topological coarse→fine **mapping**
> (`parent_nodes` / `prolongation`); assembling prolongation/restriction
> operators is left to the consumer.

## Why Delone?

Delone.jl is named after **Boris Delone** (Delaunay), whose empty-sphere
construction became one of the foundations of Delaunay triangulation, spatial
tessellation, and modern quality mesh generation. Delone.jl continues that
tradition for agentic numerical simulation workflows: meshes should be
constructible, measurable, diagnosable, refinable, hierarchy-aware, and ready
for computation — not just a handle returned from a black-box mesher.

LLM-friendliness is a core architecture principle here, not a UI layer. See
[`AGENTS.md`](AGENTS.md) for the introspection contract (`report`, `validate`,
`readiness`, …) that Delone's public objects are expected to support.

## Netgen/NGSolve backend

Delone.jl stands on the shoulders of **Netgen/NGSolve**, a mature open-source
meshing technology. The goal of Delone.jl is not to replace Netgen, but to
provide a clean Julia API and structured feedback layer for simulation-oriented
meshing workflows. Advanced users and backend developers can access low-level
Netgen/NGSolve bindings and backend structures through **`Delone.Netgen`**;
most users and LLM agents should use the high-level `Delone` API and never need
to touch `Netgen` directly.

## The Monge → Delone → Oodi pipeline

Delone.jl is the meshing stage of the Oodi ecosystem's numerical simulation
pipeline:

```
Monge.jl    semantic CAD / constructive geometry
Delone.jl   meshing, mesh diagnostics, mesh hierarchies   (this package)
Oodi.jl     LLM-native numerical framework
```

Monge creates and understands geometric form; Delone discretizes that geometry
into simulation-ready meshes and hierarchies; Oodi builds, solves, diagnoses,
and explains the numerical model.

## Stack

```
NGSolveNetgen_jll   upstream NGSolve/Netgen binary (+ OpenCASCADE)
NetgenCxxWrap_jll   libnetgen_cxxwrap: boring 1:1 CxxWrap wrapper of Netgen's C++ API
Delone.jl           this package — Julian, LLM-friendly meshing/hierarchy/diagnostics API
  └── Delone.Netgen   the raw NetgenCxxWrap_jll bindings, re-exposed for advanced/backend use
```

## Documentation

Full docs are built with [Documenter.jl](https://github.com/JuliaDocs/Documenter.jl)
from `docs/src/` (upstream references, wrapped vs missing APIs, worked examples).
After `gen/build_local.jl`:

```julia
julia --project=docs -e 'using Pkg; Pkg.develop(path="."); Pkg.instantiate()'
julia --project=docs docs/make.jl
```

Open `docs/build/index.html`.

## Example: refine a 2D disk and read the mesh hierarchy

Mesh a unit disk coarsely, then refine it. New boundary nodes snap onto the true
circle, and `parent_nodes` tells us, for every fine node, which two coarse nodes
it came from — the topological link between the two meshes.

```julia
using Delone

# A unit disk (radius 1) built programmatically; its boundary is a true circle.
disk = Circle(0.0, 0.0, 1.0, "disk", "boundary")
geom = geometry2d(disk)

# 1. Coarse mesh.
coarse = generate_mesh(geom; maxh=0.5)

# 2. Refine (geometry-aware). copy_mesh keeps `coarse` intact as its own level.
fine = copy_mesh(coarse)
refine!(fine)

# 3. Hierarchical mapping between the two meshes: parent_nodes(fine)[:, j] gives
#    the two coarse nodes that fine node j came from, or (0, 0) if node j already
#    existed on the coarse mesh (with the SAME index there).
P = parent_nodes(fine)
```

A new boundary node is *not* the plain average of its parents — it is projected
onto the curved boundary (parents at radius 1, chord midpoint inside the disk,
actual node snapped back onto the circle at radius exactly 1). That is what
"geometry-aware" means, and it keeps every level of the hierarchy faithful to
the CAD model.

See [`docs/src/tutorial.md`](docs/src/tutorial.md) for the full step-by-step
walkthrough — this same example with prose explaining each step, plus
`MeshOptions`, structured diagnostics, and building a `MeshHierarchy`.

## Building geometry

```julia
# CAD files
geom = load_step("model.step")          # also load_brep / load_iges / load_stl
geom = load_geometry("model.brep")      # dispatch on extension (.step/.brep/.iges/.stl)

# 3D CAD modeling via OpenCascade.jl (package "Monge"), then BREP interop:
using Monge, Delone
shape = subtract(box(2, 2, 2), sphere(0.6; center=Point(1, 1, 1)))
mesh  = generate_mesh(shape; maxh=0.3)  # backend-agnostic: pass the Monge.Body directly

# 2D CSG (geom2d): Circle / Rectangle with boolean ops + - *
plate = Rectangle(-1.0,-1.0, 1.0,1.0, "plate", "outer")
hole  = Circle(0.0, 0.0, 0.4, "hole", "inner")
geom  = geometry2d(plate - hole)        # plate with a circular hole
```

## Mesh access and refinement

```julia
mesh = generate_mesh(geom; maxh=0.2, minh=0.01, grading=0.3)

points(mesh)             # dim×np Matrix{Float64}
tetrahedra(mesh)         # 4×ne Matrix{Int32}, 1-based (3D volume meshes)
surface_triangles(mesh)  # 3×nse Matrix{Int32}, 1-based (boundary / 2D meshes)

num_nodes(mesh); num_cells(mesh); mesh_dimension(mesh)
connectivity(mesh)       # (volume, surface) matrices by dimension

save_mesh(mesh, "out.vol")
mesh2 = load_mesh("out.vol")
update_topology!(mesh)   # refresh edge/face tables after mesh changes
check_mesh(mesh)         # (volume_ok=..., boundary_ok=...)
optimize_volume!(mesh; maxh=0.2)

refine!(mesh)                                   # uniform, geometry-aware, in place
mark_for_refinement!(mesh, marked); bisect!(mesh)  # adaptive, element-wise

# Material / boundary labels (Julian helpers)
material_names(mesh)
boundary_names(mesh)
cell_regions(mesh)
```

The **exported API is Julian** (`load_step`, `generate_mesh`, `save_mesh`,
`update_topology!`, `refine!`, …). Strict 1:1 Netgen/NGSolve C++ bindings live in
**`Delone.Netgen`** for advanced/backend use (`Delone.Netgen.GetNP`, …) but
are not re-exported from the top-level module. Most users and LLM agents should
never need `Netgen`.

## Structured reports & diagnostics

Alongside the mesh/geometry API, Delone.jl exposes a **read-only reporting
layer** — structured, serializable results for validation, quality,
meshability, and readiness checks, so a calling tool, solver driver, or LLM
agent can inspect *what happened* and *what to do next* without touching raw
`Delone.Netgen` handles:

```julia
opts = MeshOptions(maxh=2.0, minh=0.1, grading=0.3)
result = generate_mesh(geom; options=opts, result=true)   # MeshGenerationResult

if !result.success
    println(result.diagnostics)
    error("meshing failed")
end

r = mesh_report(generated_mesh(result))   # MeshReport: validation + quality + topology + tags
r.validation.valid
r.quality.min_quality

h = mesh_hierarchy(geom; maxh=0.5, levels=1)
refine!(h; mode=:uniform)
hr = hierarchy_report(h)          # MeshHierarchyReport
hr.nlevels
```

See [Structured reports & introspection](docs/src/examples/introspection.md) for
the full `report`/`validate`/`readiness`/`to_namedtuple` contract (shared with
the rest of the Oodi ecosystem via `OodiCore.jl`), and [`AGENTS.md`](AGENTS.md)
for the design principle behind it.

## Mesh hierarchy

A growable stack of nested meshes sharing one geometry. Grow it during a
simulation — uniformly or by an error indicator — and read the per-level mapping.

```julia
h = mesh_hierarchy(geom; maxh=0.5)      # level 1
refine_uniform!(h)                      # push a uniformly refined level
refine_marked!(h, marked)               # push an adaptively refined level

nlevels(h)                              # number of levels
coarsest(h); finest(h)
prolongation(h, k)                      # 2×np mapping from level k-1 to level k
                                        # (== parent_nodes(h[k]))

# or build all uniform levels up front:
h = uniform_hierarchy(geom; maxh=0.5, levels=4)
```

## Live session + snapshots (consumer integration contract)

Delone.jl exposes the geometry-backed mesh hierarchy as a **live session** — the
authoritative state a solver keeps during a simulation — plus **copied
snapshots** for consumers. The two are distinct on purpose: the live Netgen mesh
handles are authoritative; snapshots are derived copies.

### Live session / handles

Authoritative Netgen state that supports refinement requests *during* a
simulation. Every mutating request (`request_*!`) bumps `generation(session)` and
(for h-refinement) appends a new level while preserving access to all previous
levels.

```julia
s = mesh_session(geom; maxh=0.5)     # level 1; generation 0
nlevels(s)                           # 1
finest(s); coarsest(s)               # live Netgen mesh handles
level_mesh(s, k)                     # live handle for level k (authoritative)
geometry(s); generation(s)

# grow the live hierarchy as the solve/adapt loop proceeds:
request_uniform_refinement!(s)                # append a uniformly refined level
request_marked_refinement!(s, marked)         # append an adaptively bisected level
request_second_order!(s)                       # curve finest IN PLACE (no new level)
```

`request_marked_refinement!` takes `marked` indexed by the **current finest
level's** volume elements.

**Live handles are expert-only for mutation.** `level_mesh(s, k)` (and its
explicitly named alias `unsafe_level_mesh(s, k)`) return the *authoritative live*
Netgen mesh handle. Mutating that handle directly (`refine!`, `bisect!`,
`make_second_order!`, …) changes the session **without** bumping
`generation(session)`, so snapshots can silently go stale. All simulation-time
mutation should go through the `request_*!` functions. If you must mutate a level
directly and keep generation tracking correct, use the callback helper:

```julia
mutate_level_mesh!(s, 2) do m       # bump_generation=true by default
    # in-place mesh mutation via Delone.Netgen if needed
end                                  # -> returns the session; generation bumped
```

### Snapshots

Copied, consumer-agnostic plain arrays. Mutating a snapshot never touches the
live handles.

```julia
ls = level_snapshot(s, k)     # coordinates, volume/boundary connectivity,
                              # cell_regions, boundary_regions, material_names,
                              # boundary_names, element types, level, generation
ts = transfer_snapshot(s, k)  # parent_nodes/elements/surface_elements for k-1 → k
                              # (transfer_snapshot(s, 1) throws ArgumentError)
hs = hierarchy_snapshot(s)    # all levels + all transfers + generation
```

A snapshot records the session `generation` at capture time. When
`snapshot.generation != generation(session)` the snapshot is **stale** — the live
hierarchy changed since it was taken (e.g. by a `request_*!`), and the consumer
should re-snapshot.

**Supported snapshot topology.** `level_snapshot` currently supports only pure
**Tet4/Tri3** 3D meshes (tetrahedral volume, triangular boundary) and pure
**Tri3/Segment** 2D meshes (triangular domain, segment boundary). Curved
(second-order) simplices are accepted — they are still tetrahedra/triangles
topologically (`GetNV == 4`/`3`). Mixed or non-simplex meshes (quads, prisms,
hexes) throw a clear `ArgumentError` rather than being silently reinterpreted.
Use `supported_snapshot_topology(mesh)` to test a mesh before snapshotting.

### Transfer weights

`transfer_snapshot(...).weights === nothing` — exact interpolation weights are not
provided yet. This is **not** "unknown physical value": the accompanying field
`weight_semantics == :topological_bisection_default` states the intended fallback
explicitly — a consumer should use **topological 1/2–1/2 nodal interpolation** on
the bisection parent-node map (each new node is the midpoint of its two parents).
`transfer_weight_semantics(ts)` returns this symbol.

### Stable identity convention

All snapshot ids are **one-based**; `0` means "none". Parent-node columns of
`(0, 0)` mark an **inherited** coarse vertex, and inherited coarse vertices keep
their id on refined levels (so `coords(coarse) ≈ coords(fine)[:, 1:np_coarse]`).
This holds for the current construction path (each level refines a copy of the
previous finest level). The detailed internal audit is kept outside the
repository.

### Second-order curving is a same-level, snapshot-invalidating mutation

`request_second_order!(session; order=2)` curves the **current finest** mesh
**in place** — it is a p-type/topology change to the existing h-level, not a new
level:

- it does **not** append a level (`nlevels` is unchanged) and does **not** create
  an h-refinement transfer;
- it **increases the node count** (edge-midpoint nodes projected onto the true
  geometry) and bumps `generation(session)`;
- therefore any snapshot of that level taken *before* the call is **stale**
  (`snapshot.generation != generation(session)`) — consumers must re-snapshot the
  level afterward;
- `transfer_snapshot` does **not** describe the added high-order nodes; a level
  snapshot taken after curving reports the Tet4/Tri3 corner connectivity, and the
  extra midpoint nodes appear in `coordinates` but are not referenced by
  `volume_connectivity`;
- this is fundamentally different from `request_uniform_refinement!` /
  `request_marked_refinement!`, which append a new level with a parent map.

Only `order == 2` is supported; other orders throw `ArgumentError`.

### Tags, regions, hp-readiness

```julia
volume_tetrahedra(mesh); surface_triangles(mesh)   # 3D
triangles2d(mesh); segments2d(mesh)                # 2D (dimension-checked)
cell_regions(mesh); boundary_regions(mesh)         # Netgen GetIndex region ids
material_names(mesh); boundary_names(mesh)          # region id → name
```

**2D name limitation.** In 3D, `material_names` (via `GetNDomains`/`GetMaterial`)
and `boundary_names` (via face descriptors) are reliable and their keys line up
with `cell_regions` / `boundary_regions`. In **2D**, Netgen reports
`GetNDomains == 0` through the current wrapper path, so `material_names(mesh)` is
**empty**, and `boundary_names` keys (face-descriptor indices) do **not**
correspond to `boundary_regions` values (segment indices). 2D `cell_regions` /
`boundary_regions` (topological region ids) still work. No fake 2D names are
invented; treat 2D material/boundary *names* as unavailable via this path.

Per-element region names (via `Mesh::GetRegionName`):

```julia
region_name_volume(mesh, enr)      # 3D cell material name
region_name_surface(mesh, senr)    # 3D boundary triangle name
region_name_segment(mesh, segnr)   # 2D/3D boundary segment name
material_codim_name(mesh, codim, region_nr)  # Ngx GetMaterialCD<DIM>
```

### FEM geometry (curved maps + parent topology)

Curved element maps (`Ngx_Mesh::ElementTransformation`, second-order meshes):

```julia
volume_element_transformation(mesh, enr, xi)     # 3D tet, xi length 3
surface_element_transformation(mesh, senr, xi)   # 3D boundary tri
domain_element_transformation(mesh, enr, xi)     # 2D tri
segment_element_transformation(mesh, segnr, xi)
volume_element_transformations(mesh, enr, xis)   # batch 3×npts
```

Parent edge/face maps are **off by default**. Enable before refinement:

```julia
enable_topology_table!(mesh, "parentedges")
enable_topology_table!(mesh, "parentfaces")
refine!(mesh)
has_parent_edges(mesh)
parent_edges(mesh, enr); parent_faces(mesh, fnr); face_edges(mesh, fnr)
```

### hp-adaptivity (read + apply)

Delone.jl exposes both **reading** and **applying** hp/p metadata through strict
1:1 `Ngx_Mesh` bindings. Delone.jl does **not** implement an hp-adaptive solve
strategy — consumers own marking policies, error estimators, and solvers.

**Read** (query current state):

```julia
element_orders(mesh); element_order(mesh)
element_orders_xyz(mesh)                             # anisotropic (ox, oy, oz)
surface_element_orders(mesh)                         # 3D boundary
hp_element_levels(mesh)                              # 3×ncells; -1 = no hp table
cluster_rep_vertices(mesh); cluster_rep_elements(mesh)
```

**Apply on a live mesh** (in place):

```julia
set_element_order!(mesh, enr, order)                 # single-cell p set
set_element_orders!(mesh, orders)                  # bulk isotropic orders
set_surface_element_order!(mesh, enr, order)       # 3D boundary

mark_for_ngx_refinement!(mesh, marked)             # mark cells 1:ncells
ngx_refine!(mesh; reftype=NG_REFINE_P)             # marked p-refinement
ngx_refine!(mesh; reftype=NG_REFINE_HP)            # marked hp-refinement
hp_refine!(mesh; levels=1)                         # global hp split (SPLIT_HP)
split_alfeld!(mesh)                                 # Alfeld hp split
```

**Apply through a live session** (bumps `generation`; finest level only unless
noted):

```julia
request_set_element_orders!(s, orders)               # in-place p set
request_marked_p_refinement!(s, marked)            # in-place marked p
request_marked_hp_refinement!(s, marked)             # in-place marked hp
request_hp_refine!(s; levels=1)                      # global hp split
request_split_alfeld!(s)                             # Alfeld split
request_marked_refinement!(s, marked; refine_hp=true)  # append hp-refined level
```

Refinement-type constants: `NG_REFINE_H`, `NG_REFINE_P`, `NG_REFINE_HP`.

In-place hp/p operations **invalidate** snapshots of the finest level (same as
`request_second_order!`) — check `snapshot.generation != generation(session)`.

### Integration contract

```
Delone.jl owns   geometry-backed mesh hierarchy handles, refinement requests,
                 parent maps, stable ids, region/tag + hp-readiness data,
                 and copied snapshots.
Consumer owns    FE spaces, DOF numbering, matrix-free operators, error
                 estimators, preconditioners, GMG assembly, domain
                 decomposition, dynamic load balancing, and migration.
```

### Partitioning responsibility

```
Delone.jl provides   geometry-backed mesh levels, parent maps, stable ids,
                     region/tag data, and optional raw partition hints if
                     available (native_partition_hint(mesh)).
Consumer provides    PartitionGraph, cell/edge weights, METIS/ParMETIS backend
                     selection, PartitionAssignment, distributed ownership,
                     ghost/halo construction, dynamic repartitioning + migration.
```

Delone.jl does **not** call METIS/ParMETIS and does **not** own partition policy.
`native_partition_hint(mesh)` wraps `GetGlobalVertexNum` / `GetDistantProcs`: on
the current serial build, `global_vertex_ids` is the identity `1:np` and each
`distant_procs[i]` is empty; on an MPI-enabled build these become true global
ids and remote ranks.

## Status

Wrapped and tested locally: module load + value types, mesh core + extraction,
OCC file import (STEP/IGES/BREP via nglib), BREP interop with OpenCascade.jl,
2D geom2d/csg2d (circle/rectangle + boolean CSG), geometry-aware uniform **and**
adaptive (marked-bisection) refinement, second-order curving, material/BC labels,
the `Ngx_Mesh` multigrid hierarchy (levels + parent maps), mesh copy, nested
hierarchies, and the structured `report`/`validate`/`readiness` diagnostics
layer. OCCT modeling bindings live in OpenCascade.jl / OpenCascadeCxxWrap_jll.
See `OpenCascadeCxxWrap_jll/README.md` for the split boundary.

## Development

`NetgenCxxWrap_jll` isn't registered yet, so the native library is built locally
and bound via `Artifacts.toml`:

```
julia --project=Delone.jl Delone.jl/gen/build_local.jl
```

This compiles `libnetgen_cxxwrap` against the locally-bound NGSolveNetgen
artifact + OCCT_jll + the CxxWrap/JlCxx prefix (this platform only). Then
`pkg> test Delone`.
