# Not yet wrapped

Delone.jl is built on Netgen's **exported mesh/geometry API** and a
**narrow OCCT modeling kernel** (via `Delone.Internals`), not every symbol in
the upstream trees.

## Netgen — missing or partial

### Entire subsystems not wrapped

| Area | Why |
|------|-----|
| `CurvedElements` direct API | Used indirectly via `BuildCurvedElements`; full API needs NGSolve FEM context. |
| `Identifications` (periodic mesh glue) | Complex; partial access via `GetPeriodicVertices` / `periodic_vertex_pairs`. |
| `ZRefinement` / structured z-refinement | Specialized path for layered meshes. |
| `Mesh::Distribute`, `ParallelMetis` | MPI domain decomposition inside Netgen (consumers own partition policy). |
| `GeometryRegister` plugin system | Internal geometry registration. |
| STL topology inspection | `GetTriangle`, `InvertTrig`, etc. on `STLTopology` — only `LoadSTL` + `GenerateMesh` wrapped. |

### Methods missing on otherwise wrapped classes

| Class | Gap |
|-------|-----|
| `Mesh` | Point-to-element tables; bulk `SetNBCNames` / CD2/CD3 name tables (individual `GetCD2/3Name` etc. are wrapped). |
| `Mesh` | Point-curve visualization (`InitPointCurve`, …). |
| `SplineGeometry2d` | Per-spline access (`GetSpline(int)`). |
| `Point3dTree` | `DeleteElement` (not exported from upstream DLL). |

### hp / cluster caveats

Several `Ngx_Mesh` hp methods are bound but require **hp internal state**:

- `GetClusterRep*` crashes on plain h-refined meshes → use `hp_clusters_available` first.
- Cluster reps and some order queries assume hp refinement or second-order curving has run.

### 2D tag/name limitation (Julia layer, not missing C++)

In 2D, `material_names` is empty (`GetNDomains == 0` on the current path), and
`boundary_names` keys do not align with `boundary_regions`. Use topological
`cell_regions` / `boundary_regions` and `region_name_segment` for segment names.

### Serial partition hints

`native_partition_hint` wraps MPI partition APIs. On the current **serial**
artifact, `global_vertex_ids` is the identity `1:np` and `distant_procs` is
empty. True parallel ghost data requires an MPI-enabled Netgen build.

## OpenCASCADE — out of scope

OCCT ships thousands of headers. **Not wrapped** (by design):

| Package families | Examples |
|------------------|----------|
| STEP/IGES schema | `StepBasic_*`, `IGESGeom_*`, … |
| Visualization | `AIS_*`, `V3d_*`, `Graphic3d_*` |
| Full `Geom_*` ecosystem | Most Handle-based curves/surfaces beyond the small `Geom_Curve`/`Geom_Surface` bridge |
| Meshing internals | `BRepMesh_*` beyond `IncrementalMesh` |
| XCAF / assemblies | colors, names, structure trees |
| GLTF/OBJ/VRML exporters | |

### OCCT — plausible next additions

Documented in `NetgenCxxWrap_jll/docs/WRAPPING_PLAN.md`:

- More `gp_*` conics and transforms
- `BRep_Tool::Curve` / `Surface` (Handle-based geometry access)
- `Geom2d_*` / `GC_Make*` curve builders
- Additional offset/pipe APIs

Each follows the same strict 1:1 pattern as existing `BRepPrimAPI_*` wrappers.

## What Delone.jl does not do

Even when upstream APIs exist, this package **does not**:

- Assemble FE spaces, DOF maps, or multigrid transfer **matrices**
- Run error estimators or hp marking strategies
- Call METIS / ParMETIS or assign MPI ownership
- Provide a GUI or interactive meshing session

Those belong in a downstream solver or application layer.

## Reporting gaps

If you need a specific `DLL_HEADER` Netgen symbol or OCCT modeling-class that
is missing, check `docs/API_COVERAGE.md` and open an issue with the upstream C++
signature. New bindings belong in `NetgenCxxWrap_jll`; Julian composition belongs
in `Delone.jl`.
