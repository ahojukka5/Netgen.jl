# Wrapped capabilities

Raw bindings live in `NetgenCxxWrap_jll` (`libnetgen_cxxwrap`) and are loaded
by `Delone.jl` under `Delone.Internals`; C++ names are preserved 1:1 there.
The sections below group Delone.jl's high-level capabilities by workflow,
noting the underlying Netgen/NGSolve entry points where useful. For per-class
method lists see `docs/API_COVERAGE.md` in the package tree.

## Geometry input

| Capability | Julia / C++ entry points |
|------------|--------------------------|
| STEP / IGES / BREP / STL import | `load_step`, `load_iges`, `load_brep`, `load_stl`, `load_geometry` → `LoadOCC_*` / `LoadSTL` |
| 2D spline geometry file | `load_splinegeometry2d` |
| 2D CSG | `Circle`, `Rectangle`, `CSG2d`, `geometry2d`, boolean `+` / `*` / `-` |
| OCC programmatic 3D | OpenCascade.jl → `occ_geometry_from_brep_string(to_brep_string(shape))` |
| OCC I/O (modeling) | OpenCascade.jl: `BRepTools_*`, `STEPControl_*`, `IGESControl_*` |

## Mesh generation & core `Mesh` API

| Capability | Julian entry points | Internals (1:1) |
|------------|---------------------|-----------------|
| Generate from geometry | `generate_mesh`, `meshing_parameters` | `MeshingParameters`, `maxh!`, `GenerateMesh` |
| Mesh I/O | `save_mesh`, `load_mesh` | `Save`, `Load` |
| Counts / dimension | `num_nodes`, `num_cells`, `num_boundary_facets`, `mesh_dimension` | `GetNP`, `GetNE`, `GetNSE`, `GetDimension` |
| Connectivity | `connectivity`, `points`, `tetrahedra`, `surface_triangles` | `Point`, `VolumeElement`, `SurfaceElement` |
| Topology refresh | `update_topology!` | `UpdateTopology`, `GetTopology`, `GetNEdges`, `GetNFaces` |
| Build / modify mesh | `copy_mesh`, `compress!` | `assign`, `AddPoint`, `AddVolumeElement`, … |
| Quality / h-field | `check_mesh`, `improve_mesh!`, `optimize_volume!`, `mesh_bounding_box` | `CheckVolumeMesh`, `ImproveMesh`, `MeshVolume`, `OptimizeVolume`, `GetBox`, … |
| Sub-mesh extraction | — | `GetSubMesh` |

## Refinement (geometry-aware)

| Capability | Entry points |
|------------|--------------|
| Uniform refine | `refine!` → `Refinement.Refine` |
| Marked bisection | `mark_for_refinement!`, `bisect!` → `BisectionOptions`, `Refinement.Bisect` |
| Second-order curving | `make_second_order!` → `Refinement.MakeSecondOrder` |
| Volume meshing driver | `optimize_volume!`, `improve_mesh!` (`MeshVolume`, `OptimizeVolume`, …) |

## `Ngx_Mesh` hierarchy & parent maps

| Capability | Entry points |
|------------|--------------|
| Multigrid levels | `num_levels`, `level_nvertices`, `Ngx_Mesh.GetNLevels`, `GetNVLevel` |
| Prolongation stencil | `parent_nodes`, `parent_elements`, `parent_surface_elements`, `GetParentNodes`, … |
| Curved geometry on mesh | `Curve`, `GetCurveOrder`, `BuildCurvedElements` |
| Copy / nested hierarchy helpers | `copy_mesh`, `MeshHierarchy`, `mesh_hierarchy`, `uniform_hierarchy`, `refine_uniform!` |

## Live session & snapshots (Julia layer)

| Capability | Description |
|------------|-------------|
| `MeshHierarchySession`, `mesh_session` | Authoritative live handles per level + `generation` counter |
| `request_uniform_refinement!`, `request_marked_refinement!`, `request_second_order!` | Append levels or in-place curving |
| `MeshLevelSnapshot`, `HierarchyTransferSnapshot`, `MeshHierarchySnapshot` | **Copied** mesh data for downstream consumers |
| `supported_snapshot_topology`, `transfer_weight_semantics` | Documented snapshot contract |

## hp-adaptivity (read + apply)

| Capability | Entry points |
|------------|--------------|
| Read orders / hp levels | `element_order(s)`, `element_orders_xyz`, `surface_element_orders`, `hp_element_levels` |
| Cluster representatives | `cluster_rep_*` (requires `hp_clusters_available`) |
| Apply p / hp | `set_element_order!`, `set_element_orders!`, `ngx_refine!`, `hp_refine!`, `split_alfeld!` |
| Session requests | `request_set_element_orders!`, `request_marked_p_refinement!`, `request_hp_refine!`, … |
| Constants | `NG_REFINE_H`, `NG_REFINE_P`, `NG_REFINE_HP` |

## Structured reports & introspection (Julia layer)

Read-only, serializable feedback for solver drivers and LLM-driven workflows —
see [Structured reports & introspection](@ref "Structured reports & introspection")
for a full walkthrough.

| Capability | Entry points |
|------------|--------------|
| Options validation | `MeshOptions`, `validate_options!` (throwing), `validate(::MeshOptions)` (non-throwing) |
| Structured generation | `generate_mesh(...; result=true)` → `MeshGenerationResult`, `MeshGenerationDiagnostics` |
| Mesh reports | `mesh_report` → `MeshReport` (`MeshValidationReport` + `MeshQualityReport` + `MeshTagReport` + topology); `isvalid`, `quality`, `tag_report` |
| Pre/post-meshing diagnostics | `meshability_report`, `meshing_diagnostics`, `suggest_mesh_fixes` |
| Hierarchy/session reports | `hierarchy_report` → `MeshHierarchyReport` (`MeshLevelReport`, `TransferReport`); `refine!`/`refine_session!(...; result=true)` → `RefinementResult` |
| Generic contract (OodiCore) | `report(x)`, `validate(x)`, `readiness(x, target)`, `to_namedtuple(x)` |
| Readiness targets | `MeshingTarget`, `OodiImportTarget` → `oodi_snapshot_readiness`, `GeometricMultigridTarget` |

## Export & preview formats

| Capability | Entry points |
|------------|--------------|
| VTK / OBJ / SVG export | `export_vtk`, `export_obj`, `export_svg_2d`, `export_mesh_preview` |
| Tempfile previews | `mesh_preview`, `mesh_previews` |

## Tags, regions & names

| Capability | Entry points |
|------------|--------------|
| Bulk extraction | `volume_tetrahedra`, `surface_triangles`, `triangles2d`, `segments2d` |
| Region ids per cell/facet | `cell_regions`, `boundary_regions` |
| Name dictionaries | `material_names`, `boundary_names` (3D reliable; 2D limitations documented) |
| Per-element names | `region_name_volume`, `region_name_surface`, `region_name_segment` |
| Codimension names | `material_codim_name`, `GetMaterialCD0`–`3` |

## FEM geometry & partition hints

| Capability | Entry points |
|------------|--------------|
| Curved element maps | `volume_element_transformation`, `surface_element_transformation`, `domain_element_transformation`, `MultiElementTransformation*` |
| Parent edge/face maps | `enable_topology_table!`, `has_parent_edges`, `parent_edges`, `parent_faces`, `face_edges` |
| Periodic pairs | `periodic_vertex_pairs`, `GetPeriodicVertices` |
| Partition hints | `native_partition_hint` → `GetGlobalVertexNum`, `GetDistantProcs` |
| Point location | `find_element`, `FindElementOfPoint1/2/3` |
| Mesh size at node | `mesh_h_at_point`, `GetHPointIndex` |

## Julian extraction helpers

| Function | Returns |
|----------|---------|
| `points` | `3×GetNP` coordinates |
| `tetrahedra` | `4×GetNE` volume connectivity (3D) |
| `surface_triangles` | boundary triangles (3D) or domain triangles (2D) |
| `prolongation` | sparse-style parent data between hierarchy levels |

## OpenCASCADE interop

CAD modeling lives in **OpenCascade.jl** (`OpenCascadeCxxWrap_jll`), not Delone.
Delone.jl imports meshable geometry via **`occ_geometry_from_brep_string`**
(in-memory BREP from `to_brep_string`). File import remains
**`load_step` / `load_iges` / `load_brep`** (nglib). See OpenCascade.jl docs
for the full OCCT surface.

## Test coverage

The package test suite (`test/runtests.jl`) exercises mesh core, BREP interop with
OpenCascade.jl, 2D CSG, refinement, hierarchy, session/snapshots, hp apply, FEM
helpers, and tags/partition contracts against local fixtures (`test/fixtures/`).
OCCT modeling tests live in OpenCascade.jl.
