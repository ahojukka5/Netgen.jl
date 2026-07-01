# Upstream documentation

Delone.jl is a high-level meshing, refinement, and mesh-hierarchy package built
on Netgen/NGSolve. For meshing theory, GUI usage, and the full Netgen/NGSolve
C++ API, use the upstream projects directly; for raw backend bindings inside
this package, see `Delone.Internals`.

## Netgen & NGSolve

| Resource | URL | Notes |
|----------|-----|-------|
| NGSolve home | [https://ngsolve.org/](https://ngsolve.org/) | Project overview, downloads, community. |
| NGSolve documentation | [https://docu.ngsolve.org/](https://docu.ngsolve.org/) | Tutorials, iTutorial, FEM + meshing context. |
| Netgen source (this repo's upstream) | [https://github.com/NGSolve/netgen](https://github.com/NGSolve/netgen) | C++ headers and implementation; authoritative for symbol names. |
| `nginterface_v2` | `netgen/libsrc/include/nginterface_v2.hpp` in the upstream tree | NGSolve-facing mesh interface (`Ngx_Mesh`) wrapped by this package. |

When a Julia binding name matches a C++ name (e.g. `Refine`, `GetParentNodes`),
the upstream header or NGSolve docs are the reference for semantics and indexing.

## OpenCASCADE (OCCT)

**OpenCascade.jl** wraps a **modeling kernel** subset of OCCT — enough to build
primitives, booleans, fillets, and import/export BREP/STEP/IGES. It does **not**
wrap the full OCCT documentation surface (~6800 headers).

| Resource | URL |
|----------|-----|
| Open CASCADE Technology | [https://dev.opencascade.org/](https://dev.opencascade.org/) |
| OCCT documentation | [https://dev.opencascade.org/doc/overview/html/index.html](https://dev.opencascade.org/doc/overview/html/index.html) |
| OCCT reference (classes) | [https://dev.opencascade.org/doc/refman/html/index.html](https://dev.opencascade.org/doc/refman/html/index.html) |

Look up `gp_Pnt`, `TopoDS_Shape`, `BRepPrimAPI_MakeBox`, etc. in the OCCT refman
when using OpenCascade.jl. Mesh via `occ_geometry_from_brep_string(to_brep_string(shape))`.

## This repository

| Path | Content |
|------|---------|
| `Delone.jl/README.md` | Package overview and integration contract (live session vs snapshots). |
| `Delone.jl/docs/API_COVERAGE.md` | Quantitative wrap coverage (Netgen ~94 % of `DLL_HEADER` mesh API; OCC &lt; 1 % of all OCCT). |
| `NetgenCxxWrap_jll/docs/WRAPPING_PLAN.md` | Design: strict 1:1 binding policy and planned OCCT classes. |

## Indexing reminders

Different entry points use different conventions:

| API | Typical indexing |
|-----|------------------|
| Julia helpers (`tetrahedra`, `cell_regions`, `mesh_session`) | **1-based** |
| Raw `GetElementOrder`, `SetElementOrder` | **1-based** element numbers |
| `Ngx_Mesh` parent maps, `ElementTransformation`, `GetParentEdges` in C++ | often **0-based** internally; Julia helpers in `fem.jl` convert at the boundary |
| `Point(mesh, i)`, `GetNP` | **1-based** mesh point indices |

When in doubt, check the docstring of the Julian helper or the upstream C++
comment for that function.
