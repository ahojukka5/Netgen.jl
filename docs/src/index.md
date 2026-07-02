# Delone.jl

**Delone.jl** is a high-level, LLM-friendly meshing, refinement,
mesh-diagnostics, and mesh-hierarchy package for numerical simulation
workflows. It is built on top of **Netgen/NGSolve**, a mature and powerful
open-source meshing technology, loaded through
[CxxWrap](https://github.com/JuliaInterop/CxxWrap.jl) (`libnetgen_cxxwrap`
from `NetgenCxxWrap_jll`) — Delone.jl does not replace Netgen; it provides a
Julian, simulation-oriented, agent-friendly layer above it, covering
geometry-backed meshing, refinement, and multigrid-style hierarchies.

Netgen itself is the mesh generator behind [NGSolve](https://ngsolve.org/). This
package does **not** implement finite-element solvers, partitioners, or transfer-
operator assembly — it exposes meshes, refinement, parent maps, region/tag data,
and optional snapshots so a downstream solver can build its own FE spaces and
preconditioners.

## Stack

```
NGSolveNetgen_jll   upstream Netgen + OpenCASCADE binaries
NetgenCxxWrap_jll   strict 1:1 CxxWrap bindings for meshing (+ BREP bridge)
OpenCascadeCxxWrap_jll / OpenCascade.jl   OCCT modeling (separate package)
Delone.jl           Julian helpers + live hierarchy / snapshot contract
```

## What you can do today

| Area | Summary |
|------|---------|
| **Geometry** | Load STEP/IGES/BREP/STL; build 2D CSG (`Circle`, `Rectangle`); import 3D shapes from OpenCascade.jl via BREP strings. |
| **Meshing** | `generate_mesh(geom; maxh=…)`; extract points and connectivity; topology queries. |
| **Refinement** | Uniform and marked bisection; geometry-aware boundary projection; second-order curving. |
| **Hierarchy** | `Ngx_Mesh` parent maps; `MeshHierarchySession` with refinement requests; copied snapshots for consumers. |
| **hp / FEM metadata** | Read and apply element orders; hp refinement hooks; curved element maps; parent edge/face topology. |
| **Tags** | Volume/surface/segment region ids and names (with documented 2D name limitations). |
| **Introspection** | Structured, serializable reports (`mesh_report`, `hierarchy_report`, `meshability_report`) via the `report`/`validate`/`readiness`/`to_namedtuple` contract. |

## Quick start

```@example quickstart
using Delone

# 2D unit disk
disk = Circle(0.0, 0.0, 1.0, "disk", "boundary")
mesh = generate_mesh(geometry2d(disk); maxh=0.4)

println("points: ", size(points(mesh)))            # 3×np coordinate matrix
println("triangles2d: ", size(triangles2d(mesh)))   # 3×nse connectivity (1-based)

refine!(mesh)         # geometry-aware h-refinement in place
Int(num_cells(mesh))
```

For 3D CAD import or programmatic OCC modeling, see [Building geometry](@ref "Building geometry").

## Documentation map

- [Upstream documentation](@ref) — where to read about Netgen/NGSolve/OCCT itself.
- [Wrapped capabilities](@ref) — what this package exposes (Netgen + OCC surface).
- [Not yet wrapped](@ref) — known gaps and out-of-scope areas.
- Example pages: [Building geometry](@ref "Building geometry"), [Meshing](@ref "Meshing"),
  [Refinement](examples/refinement.md), [Mesh hierarchies & sessions](@ref "Mesh hierarchies & sessions"),
  [Structured reports & introspection](@ref "Structured reports & introspection"),
  [Tags, hp-adaptivity & FEM data](@ref "Tags, hp-adaptivity & FEM data").
- [Development](@ref) — building the native library and this documentation locally.

## Naming convention

Wrapped C++ symbols keep their **original names** (`GetNP`, `Refine`, …).
Julian helpers use snake_case (`generate_mesh`, `parent_nodes`, `mesh_session`).
Use `using Delone` for meshing; use **OpenCascade.jl** for CAD modeling.
