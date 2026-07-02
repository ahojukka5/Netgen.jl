# Not yet wrapped

Delone.jl is built on Netgen's **exported mesh/geometry API** and a
**narrow OCCT modeling kernel** (via `Delone.Internals`), not every symbol in
the upstream trees.

## Netgen — missing or partial

### Entire subsystems not wrapped

| Area | Why |
|------|-----|
| `CurvedElements` direct API | Used indirectly via `BuildCurvedElements`; full API needs NGSolve FEM context. |
| `Identifications` (periodic mesh glue) | ~~Complex; partial access via `GetPeriodicVertices` / `periodic_vertex_pairs`.~~ **Read+write for the axis-aligned box/hex case**: [`identify_periodic!`](@ref)/[`identify_periodic_box!`](@ref) set up periodic identification pre-mesh (see [Building geometry](@ref "Building geometry")); still not wrapped: arbitrary curved-face pairing (needs full `TopoDS_Shape` navigation, not just bounding-box face selection) and multi-fragment face pairing (a boolean cut can split one periodic face into several pieces touching the same plane). |
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

### `parent_faces` — uninitialized memory on faces with no parent (Netgen core bug)

`parent_faces(mesh, fnr)` (`src/fem.jl`, wraps `Internals.GetParentFaces`)
returns a `(info=, f1=, f2=, f3=, f4=)` `NamedTuple`. When a face has no
parent, fields `f2`–`f4`
were observed to vary non-deterministically between runs on identical input
— consistent with reading uninitialized memory rather than a documented "no
parent" sentinel. Only `info` (the first field, orientation) is currently
reliable. **Root cause confirmed**: Netgen's own `MeshTopology::parent_faces`
(`libsrc/meshing/topology.hpp`) is declared as
`Array<std::tuple<int, std::array<int,4>>>` — a raw `std::array<int,4>` is
not zero-initialized in C++, and whatever populates this array in Netgen's
own topology code does not always fill all 4 slots. This is a bug in
**Netgen's own core** (`topology.cpp`'s population logic), not in
`NetgenCxxWrap_jll`'s wrapper (which faithfully passes through whatever
`GetParentFaces` returns) — fixing it means patching Netgen's own mesh
topology code and rebuilding `NGSolveNetgen_jll`, out of reach from the
CxxWrap binding layer alone. Discovered while writing
`docs/src/examples/tags_hp_fem.md`'s doctest.

### `merge_mesh_file!` — boundary/segment data does not appear to merge

`merge_mesh_file!(mesh, path)` (`src/mesh_surgery.jl`, wraps `Internals.Merge`)
was verified to exactly double node and volume-element counts when merging a
mesh into a copy of itself, as expected. But `GetNSE` (boundary triangles) and
`GetNSeg` (edge segments) did **not** change, even though the saved `.vol`
file being merged contains non-empty `surfaceelements`/`edgesegmentsgi3`
sections and the reviewed Netgen source (`Mesh::Merge`) reads and appends
them. This looks like a discrepancy between the reviewed upstream C++ source
and this build's actually-linked runtime, not a Julia-layer bug — rely on
`merge_mesh_file!` for volume topology (points + tets) only; verify
`num_boundary_facets` yourself before depending on it merging surface data
too. Discovered while building `src/mesh_surgery.jl`.

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

## Julian-layer gaps found during the local-sizing/quality audit

These are wrapped-in-C++-but-not-usable-as-hoped findings from building
[Local mesh sizing](@ref) and native quality diagnostics, kept here so they
aren't rediscovered from scratch:

- **`RestrictLocalH`/`SetLocalH`/`LoadLocalMeshSize` do not influence
  `generate_mesh`.** They update a mesh's local-h field immediately (visible
  to `mesh_h_at`), but `GenerateMesh` recomputes its own local-h field during
  surface meshing and discards any pre-set restriction. `MeshOptions.local_size`
  works around this via post-generation mark-and-refine refinement instead
  (`refine_near!`) — see [Local mesh sizing](@ref) for the full writeup,
  including a 2D-vs-3D mechanism difference (2D and 3D are equally effective;
  only the underlying Netgen refinement call differs).
- ~~**`FindOpenElements`/`FindOpenSegments` cannot report a count.**~~
  **Fixed** (`NetgenCxxWrap_jll` commit `b551a88`): `GetNOpenElements`/
  `OpenElement`/`GetNOpenSegments`/`GetOpenSegment` are now wrapped.
  `native_quality`/`quality` expose `open_element_count`/
  `netgen_open_element_count`, well-verified as a real watertightness
  signal. `open_segment_count` is also exposed but its exact semantics were
  **not** pinned down (read nonzero on an otherwise fully-consistent mesh) —
  see `NativeQualityReport`'s docstring.
- **`STLParameters` still cannot be threaded into STL meshing** — confirmed
  at a deeper level than originally found. The wrapped
  `STLGeometry::GenerateMesh` override copies a global C++ singleton
  (`extern STLParameters stlparam`) rather than accepting a caller-supplied
  object. The lower-level free function upstream Netgen's own Python
  bindings use instead (`STLMeshingDummy`) was attempted here and **compiles
  but fails to link**: it has no `DLL_HEADER` export macro in Netgen's own
  header (unlike virtually everything else in this codebase), so it isn't
  exported from the prebuilt `NGSolveNetgen_jll` shared library even though
  its implementation is compiled into Netgen's own build. This needs an
  upstream Netgen header fix (`DLL_HEADER` on `STLMeshingDummy`'s
  declaration) plus an `NGSolveNetgen_jll` rebuild — genuinely out of reach
  from `NetgenCxxWrap_jll` alone. No Julian `STLOptions` API exists.
- ~~**`generate_mesh`/`generate_mesh_result` was broken for STL geometry**~~
  **Fixed.** `Internals.SetGeometry` has no overload accepting `STLGeometry`
  (only `NetgenGeometry`), so it used to throw `MethodError` before meshing
  started. `generate_mesh_result` now checks `hasmethod` before calling
  `SetGeometry` and skips straight to `Internals.GenerateMesh` when the
  geometry type doesn't support it — see `test/stl.jl`'s end-to-end STL
  volume-meshing test.

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
