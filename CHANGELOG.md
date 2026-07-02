# Changelog

All notable changes to Delone.jl are documented in this file.

## [Unreleased]

### Added — Gmsh backend selector and BREP-string bridge
- **`generate_mesh(geom; backend=:gmsh, maxh=...)`**: a familiar-verb
  alternative to calling `generate_gmsh_mesh` directly. Additive kwarg
  (default `:netgen`, zero behavior change for existing callers); rejects
  `options=`/`result=true` with a clear `ArgumentError` under `backend=:gmsh`
  rather than silently ignoring Netgen-specific settings Gmsh has no
  equivalent for yet.
- **`gmsh_mesh_from_brep_string(brep; maxh=nothing)`**: the Gmsh-backend
  analogue of `occ_geometry_from_brep_string`'s in-memory BREP-string
  bridge for Netgen. Gmsh's own API has no in-memory-string import, so this
  writes `brep` to a temporary file internally and delegates to
  `generate_gmsh_mesh` — same safety profile as the Netgen path. Considered
  and rejected Gmsh's `importShapesNativePointer` (a raw-pointer,
  zero-copy alternative): Gmsh's own docs call it unsafe/undefined-behavior
  on a bad pointer, and it would rely on Monge's and Gmsh's independently-
  built OCCT libraries staying ABI-identical indefinitely, which isn't
  guaranteed.
- Both additions keep `Gmsh` a weakdep (not a hard dependency) — considered
  and rejected making it hard: `gmsh_jll` pulls in Cairo/FLTK/X11/its own
  OCCT, real install weight a Netgen-only user shouldn't pay by default.

### Added — Gmsh as a second, optional meshing backend
- **`generate_gmsh_mesh(path; maxh=nothing) -> MeshLevelSnapshot`**
  (`ext/DeloneGmshExt.jl`, active once the registered `Gmsh` package is
  loaded): meshes a STEP/IGES/BREP file via Gmsh's OpenCASCADE-based CAD
  kernel and volume mesher, as an alternative to the default Netgen backend.
  Unlike Netgen, Gmsh needed no hand-written CxxWrap binding layer —
  `gmsh_jll` ships a complete, official, auto-generated Julia API, safely
  wrapped by the registered `Gmsh` package (per-call `initialize`/`finalize`,
  only finalizing if this call was the one that initialized, avoiding a
  latent robustness gap present in this ecosystem's other Gmsh extensions).
  Returns a plain `MeshLevelSnapshot`, so `export_vtk`/`export_vtu`/
  `GeometryBasics.Mesh`/Makie plotting all work on Gmsh output for free.
  Verified: Netgen and Gmsh coexist safely in one process in both call
  orders; bounding boxes of the same STEP file match exactly between the
  two independently-triangulating backends.
- Chose Gmsh over Neper for this round after comparing both Yggdrasil build
  recipes directly: `neper_jll` ships only a bare CLI executable (no
  library/API — a fundamentally different, heavier integration shape),
  while `gmsh_jll` ships a real library plus a ready-made Julia API. See
  ROADMAP.md's Workstream F2 for the full reasoning; Neper remains open for
  a future, differently-shaped effort.

### Changed — renamed `Delone.Internals` to `Delone.Netgen`
- **Breaking**: the raw CxxWrap bindings submodule is now `Delone.Netgen`
  (was `Delone.Internals`); `src/internals.jl` is now `src/netgen.jl`. No
  compatibility alias — this is a pre-registration (v0.1.0) package with no
  external consumers besides the sibling Oodi ecosystem, checked clean
  before the rename. First step toward supporting multiple meshing
  backends (Gmsh, Neper, …) as sibling submodules alongside `Netgen`,
  rather than a single generic `Internals` module that only ever wrapped
  one backend. Every `Internals.*` call site across `src/`/`test/`, plus
  doc pages built around the concept (`internals_escape_hatch.md` →
  `netgen_escape_hatch.md`), were updated accordingly.

### Added — periodic boundary conditions (RVE / microstructure unit cells)
- **`identify_periodic!`/`identify_periodic_box!`** (`src/periodic.jl`): set
  up pre-mesh periodic identification between OCC faces, so `generate_mesh`
  produces exact node correspondence across periodic boundaries (Netgen
  copies one face's mesh through the given translation to build the
  other's) — the standard mechanism for computational-homogenization
  periodic BCs. `identify_periodic_box!` is a convenience for axis-aligned
  box/hex unit cells (auto-detects the min/max face pair along an axis via
  the new `faces_on_plane`/`occ_face_bbox`/`occ_nr_faces`). New
  `NetgenCxxWrap_jll` bindings (`OCC_NrFaces`, `OCC_FaceBoundingBox`,
  `OCC_IdentifyFaces`, `OCC_RebuildGeometry`) wrap Netgen's OCC-level
  `netgen::Identify`. New constants `NG_ID_PERIODIC`, `NG_ID_CLOSESURFACES`,
  `NG_ID_CLOSEEDGES`.
- Found and fixed a real propagation bug along the way: `Identify()` calls
  made on an already-constructed `OCCGeometry` register correctly in
  Netgen's global side table, but that geometry's own snapshot (taken once,
  at construction time via `BuildFMap()`) goes stale, so `generate_mesh`
  would silently produce zero identifications. Fixed via
  `OCC_RebuildGeometry`, which reconstructs a fresh `OCCGeometry` from the
  same underlying shape — `identify_periodic!`/`identify_periodic_box!`
  return this new handle automatically.
- Scoped to axis-aligned box/hex unit cells for now; arbitrary curved-face
  pairing and multi-fragment face pairing (from boolean-cut microstructure)
  are follow-ups, not yet supported.

### Changed (roadmap Phase 5.4 — naming consolidation)
- **`set_element_orders!`'s 5-arg single-cell anisotropic overload renamed
  to `set_element_orders_xyz!`**, pairing with the reader
  `element_orders_xyz` and disambiguating it from the bulk-vector
  `set_element_orders!(mesh, orders)` overload and from singular
  `set_element_order!`. Old call shape `Base.@deprecate`d.
- The deprecated aliases `try_generate_mesh`, `coarse_hierarchy`,
  `mesh_quality`, `mesh`, and `unsafe_level_mesh` were moved out of their
  topic-grouped export lines in `src/Delone.jl` into one dedicated,
  commented "deprecated aliases" export block, so tab-completion no longer
  surfaces them at equal visibility to their replacements. No functional
  change.

### Added (roadmap Phase 5.4)
- `tetrahedra`/`surface_triangles` docstrings gained "See also" cross-links
  to their dimension-checked siblings (`volume_tetrahedra`/`triangles2d`/
  `segments2d`).
- `docs/src/mesh_options.md` gained a "Which constructor do I want?"
  comparison table for `MeshOptions`/`mesh_options`/`meshing_parameters`/
  `to_meshing_parameters`.

### Changed (roadmap Phase 5.3 — breaking API fixes)
- **`optimize_volume!` now returns the mesh, not a status code**, matching
  AGENTS.md's "mutating `!` functions return the mesh" convention that every
  other `!` function already followed. `throw_on_error=true` (default):
  unchanged throwing behavior, now returns `mesh` on success.
  `throw_on_error=false`: returns `(mesh=, status=)` instead of a bare `Int`,
  so the Netgen status is still recoverable via `.status`. **Breaking**: code
  calling `optimize_volume!(...; throw_on_error=false)` and treating the
  result as an `Int` status must switch to `.status`.
- **`mesh(result::MeshGenerationResult)` renamed to `generated_mesh`** to
  stop colliding with the near-universal local variable name `mesh` (as in
  `mesh = generate_mesh(...)`, which then shadowed the exported accessor).
  `mesh(result)` is now `Base.@deprecate`d to `generated_mesh(result)`.
- **`unsafe_level_mesh` deprecated** — it was a bare alias for `level_mesh`
  (`unsafe_level_mesh(s, k) === level_mesh(s, k)`), so the `unsafe_` naming
  provided no actual type-level protection against mutating the returned
  handle directly. `level_mesh`'s own docstring now carries the same
  warning; use `mutate_level_mesh!` for generation-tracked mutation.

### Fixed (roadmap Phase 5.2 — AGENTS.md-convention bugfixes)
- `load_geometry` threw a bare `ErrorException` on an unsupported file
  extension instead of `ArgumentError`, violating AGENTS.md's explicit
  convention (every other loader/validator already followed it).
- `refine!`/`refine_session!` (on failure, `result=false`) threw
  `ArgumentError(string(res))`, stringifying an entire `RefinementResult`
  struct into the error message; now builds a clean message from
  `res.diagnostics`.

### Added (roadmap Phase 5.2)
- `MeshLevelSnapshot` gained a `Base.show` method (dimension, level,
  generation, node/cell/facet counts) — printing one at the REPL previously
  dumped every field, including full coordinate/connectivity matrices.

### Changed (roadmap Phase 5.2)
- `parent_edges`, `parent_faces`, `volume_element_transformation`, and
  `find_element` now return `NamedTuple`s (`(info=, e1=, e2=, e3=)`,
  `(info=, f1=, f2=, f3=, f4=)`, `(x=, J=)`, `(cell=, lambda=)`) instead of
  plain tuples, continuing the `mesh_bounding_box`/`connectivity`/
  `element_orders_xyz` precedent — positional destructuring at existing call
  sites keeps working unchanged. `find_element` still returns `nothing` on a
  miss.
- `set_global_h!`, `set_minimal_h!`, `restrict_h_at!` docstrings now state
  the same "does not retroactively affect already-generated elements"
  caveat that `restrict_h!` already documented.

### Fixed (roadmap Phase 5.1 — documentation corrections)
- `docs/src/mesh_options.md` still claimed 2D `local_size` "only achieves
  uniform refinement... not spatial localization" and that a warning was
  emitted — both stale since the 2D local-sizing fix (`1cbc05a`); corrected
  to match `docs/src/reference/local_sizing.md`/`limitations.md`.
- `docs/src/development.md` claimed "this package does not ship a CI
  workflow yet" (false — `.github/workflows/test.yml`/`docs.yml` exist,
  referenced by README badges) and listed "Julia ≥ 1.6" as a prerequisite
  (actual `[compat] julia = "1.9"`, required for package extensions).
- Fixed 3 broken `@ref`/relative-link targets that `docs/make.jl`'s
  `warnonly = [:cross_references, ...]` was silently hiding (removed
  `:cross_references` from `warnonly` so future breakage fails the build):
  `examples/meshing.md`'s `Delone.Internals` ref, `interop.jl`'s
  `to_brep_string` ref (a different package), `fem.jl`'s
  `Internals.UpdateTopology` ref, `validation.jl`'s `../OodiCore.jl` relative
  link, and two ambiguous `[Refinement](@ref "Refinement")` links (the nav
  title "Refinement" resolves to two different pages —
  `examples/refinement.md` and `reference/refinement.md` — now disambiguated
  with explicit relative paths).
- The three package extensions (`DeloneMakieExt`, `DeloneWriteVTKExt`,
  `DeloneGeometryBasicsExt`) were only discoverable via
  `docs/src/reference/export.md`; now also surfaced in `docs/src/index.md`'s
  capability table, `docs/src/capabilities.md`'s export-formats table, and
  `docs/src/examples/introspection.md`.
- `docs/src/examples/geometry.md` had a placeholder OpenCascade.jl link
  (`https://github.com/`); now points at the real repo.
- `docs/src/limitations.md` "2D-vs-3D effectiveness difference" reworded to
  "2D-vs-3D mechanism difference" — 2D and 3D are equally effective
  post-fix; only the underlying Netgen refinement call differs.

### Added
- **`DeloneWriteVTKExt`** (`ext/DeloneWriteVTKExt.jl`, weakdep on `WriteVTK`):
  `export_vtu`, real binary/compressed VTU export with cell data (`region`,
  `boundary_region`, `is_boundary`), accepting either a `MeshLevelSnapshot`
  or a live mesh handle. `export_vtk` (ASCII, dependency-free) is unchanged
  and remains the always-available fallback.
- **`DeloneGeometryBasicsExt`** (`ext/DeloneGeometryBasicsExt.jl`, weakdep on
  `GeometryBasics`): `GeometryBasics.Mesh(::MeshLevelSnapshot)`/
  `GeometryBasics.Mesh(::MeshHierarchySnapshot)`, bridging into the wider
  Julia visualization/geometry ecosystem — composes with `DeloneMakieExt`
  (`Makie.mesh(GeometryBasics.Mesh(snapshot))` works once both are loaded).
  Found and worked around a real bug in `GeometryBasics.connect`: it silently
  byte-reinterprets mismatched integer element types rather than converting,
  which would have corrupted `Int32` connectivity data if used directly.
- `connectivity`, `mesh_bounding_box`, and `element_orders_xyz` now return
  `NamedTuple`s (`(volume=, surface=)`, `(min=, max=)`, `(ox=, oy=, oz=)`)
  instead of plain tuples — positional destructuring at existing call sites
  keeps working unchanged. The Int32-vs-Int question for connectivity/index
  arrays is now a permanent, documented decision (`AGENTS.md`): keep Int32.
- Real content verification for `export_vtk`/`export_obj`/`export_svg_2d`
  tests (parses written files and checks point/cell counts against the
  source mesh, not just "file exists" + a keyword string) — `export_obj` had
  zero test coverage before this. Expanded `@test_throws ArgumentError`
  coverage across `fem.jl`, `hp_apply.jl`, `llm_feedback.jl`, and
  `mesh_surgery.jl` (not an exhaustive sweep — `generation_result.jl`/
  `snapshots.jl`/`tags.jl` remain thinner, noted for a future round).
- CI (tests + docs) and license badges added to `README.md`.

### Fixed
- `export_vtk`'s 2D `include_volume` path wrote 4-node cells (a bogus padded
  4th index) while still labeling them `VTK_TRIANGLE` (which requires
  exactly 3) — would have produced a file real VTK readers (e.g. ParaView)
  reject or misread. Found while adding real content-verification tests for
  export functions; fixed by removing the erroneous padding.
- `refine_near!`/`MeshOptions.local_size` now genuinely localizes in 2D, not
  just 3D. Previously, 2D used `mark_for_refinement!`/`bisect!`, which
  refines 2D meshes uniformly regardless of marking; it now uses
  `mark_for_ngx_refinement!`/`ngx_refine!(reftype=NG_REFINE_H)` instead,
  verified to genuinely localize (an unmarked control pass leaves the mesh
  unchanged; a marked pass grows element count only near the marked
  elements) while preserving geometry-aware boundary projection.

### Added (C++ binding improvements — NetgenCxxWrap_jll)
Three of the Julian-layer gaps found during Phase 2/4 were genuinely fixable
by extending the CxxWrap binding layer (not just documenting a limitation);
two others were investigated and confirmed to need a fix further upstream
than the binding layer reaches. `NetgenCxxWrap_jll` commits `9e4860e`,
`b551a88`, `03402fd`.

- **`Element`/`Element2d` construction** (`9e4860e`): these C++ types were
  registered with no constructor and only a `PNum` *getter*, so
  `AddVolumeElement`/`AddSurfaceElement`/`SetVolumeElement`/
  `SetSurfaceElement` were reachable but structurally unusable. Added
  `Element(anp)`/`Element2d(anp)` constructors and `SetPNum`/`SetIndex`
  (exploiting `PNum(i)`'s non-const reference return). New Julian API:
  `add_volume_element!`/`add_surface_element!` (`src/mesh_construction.jl`)
  — incremental, one-element-at-a-time mesh editing, complementing
  `mesh_from_arrays`'s whole-mesh-at-once construction.
  **Safety finding**: `add_surface_element!` with a `region` that has no
  corresponding face descriptor **segfaults the Netgen backend** rather than
  throwing — `add_surface_element!` bounds-checks `region` against
  `GetNFD(mesh)` before calling into C++ specifically to prevent this; see
  its docstring and the regression test in `test/mesh_construction.jl`.
- **Real open-element/open-segment counts** (`b551a88`): wrapped
  `Mesh::GetNOpenElements`/`OpenElement`/`GetNOpenSegments`/`GetOpenSegment`.
  `NativeQualityReport`/`MeshQualityReport` gained `open_element_count`/
  `netgen_open_element_count` (well-verified: `0` on a normal mesh, exactly
  `4` on a hand-built tet with no surface elements) and the same for
  segments (exposed, but its exact semantics were **not** pinned down — see
  the caveat in `NativeQualityReport`'s docstring, it read nonzero on an
  otherwise fully-consistent mesh). `suggest_mesh_fixes` now surfaces a
  `:netgen_open_boundary` suggestion when `open_element_count > 0`.
- **Investigated, confirmed out of `NetgenCxxWrap_jll`'s reach** (`03402fd`):
  `STLMeshingDummy` (the free function that would let `STLParameters` reach
  STL meshing) compiles but fails to **link** — the symbol has no
  `DLL_HEADER` export macro in Netgen's own header, so it isn't exported
  from the prebuilt `NGSolveNetgen_jll` binary even though its implementing
  `.cpp` file is compiled into Netgen's own build. Needs an upstream Netgen
  header fix + an `NGSolveNetgen_jll` rebuild, confirmed via this session's
  Yggdrasil-registration-status research to already be tracked as future work.
- **Investigated, root cause is Netgen's own core, not a binding**: `parent_faces`'s
  uninitialized-memory issue (`docs/src/limitations.md`) traced to
  `parent_faces` being stored as a raw `std::array<int,4>` (not
  zero-initialized in C++) in Netgen's own `topology.hpp` — whatever
  populates it doesn't always fill all 4 slots. `merge_mesh_file!`'s
  boundary/segment gap: `Mesh::Merge`'s C++ source was read in full and
  looks correct (it does read and append `surfaceelements`), so the
  discrepancy is more likely a version skew between the reviewed Netgen
  source checkout and the actually-linked `NGSolveNetgen_jll` binary than a
  reproducible bug — not re-confirmed further.

### Added (roadmap Phase 4 — interop, surgery, lifetime audit)
- **`mesh_from_arrays`** (`src/mesh_construction.jl`) — the other half of the
  interop story: build a mesh from plain point/tet/surface arrays (e.g. from
  Gmsh, Triangle, a solver's own remesher). Direct `Internals.Element`/
  `Element2d` construction is confirmed structurally blocked (registered as
  C++ types but with no constructor and no `PNum` setter — `AddVolumeElement`/
  `AddSurfaceElement`/`SetVolumeElement`/`SetSurfaceElement` are therefore all
  unreachable despite being wrapped). Implemented instead by hand-writing a
  Netgen `.vol` ASCII mesh file (grammar reverse-engineered from Netgen's own
  `Mesh::Save`/`Load` C++ source) and loading it via the same path
  `load_mesh` already uses. Verified with an **exact, full-array** round-trip
  (not sampled) on a real 131k-tet mesh: points, connectivity, cell/boundary
  regions, and `GetNDomains`/`GetNFD` all matched precisely, including
  `material_names` after `rename_materials!`. 3D only; 2D is a documented
  follow-up.
- **Mesh surgery** (`src/mesh_surgery.jl`): `split_to_tets!`,
  `split_into_parts!`, `merge_mesh_file!`, `get_sub_mesh`, `pure_tet_mesh`,
  `pure_trig_mesh`, `surface_mesh_orientation!`. Each docstring records what
  was empirically verified, including two real surprises: `split_into_parts!`
  is destructive to existing boundary/material names (collapsed 375→2 face
  descriptors on the STEP fixture, all reset to `"default"`) and is
  documented with a prominent warning; `get_sub_mesh`'s `domains`/`faces`
  arguments are `std::regex` patterns matched against material/boundary
  **names**, not `"1-3,5"`-style index ranges (confirmed empirically and via
  the Netgen source) — no numeric-range convenience was invented since none
  was confirmed to exist. `merge_mesh_file!`'s boundary/segment-data gap is
  tracked in `docs/src/limitations.md` rather than silently assumed to work.
- **Spatial search** (`src/spatial_search.jl`): `NodeTree`/`node_tree`/
  `build_node_tree`/`nodes_near`, a small wrapper over `Internals.Point3dTree`
  for radius-based node queries. Cross-checked against a brute-force linear
  scan on a real 29k-node mesh — exact match. Pairs naturally with
  `local_sizing.jl`'s `refine_near!` (currently an O(n) linear scan);
  wiring them together is a documented future integration, not done here.
- **Handle-lifetime/GC audit** (`docs/src/handles_gc.md` extended, no code
  changed — investigation found nothing to fix): empirically confirmed that
  dropping a geometry's Julia reference while a mesh built from it is still
  alive is safe (boundary-node radius exactly preserved after forced `GC.gc`,
  in both 2D and 3D, and via `refine!`/`make_second_order!` which are the
  operations most likely to touch geometry data after the fact) — because
  `refine!`/`bisect!`/`make_second_order!` fetch geometry via
  `Internals.GetGeometry(m)` from the C++ mesh object itself, never from a
  Julia-held reference, so the C++ layer's own ownership is structurally
  independent of Julia's GC. Same result confirmed for `MeshHierarchySession`/
  `MeshHierarchy` when only `finest(...)` is retained and the session/
  hierarchy struct itself is dropped. Also documented: no thread-safety
  mechanism exists anywhere in the codebase — assume live handles are not
  thread-safe.
- Registration-track update (`ROADMAP.md`'s D4): confirmed
  `NGSolveNetgen_jll`, `NetgenCxxWrap_jll`, and `OpenCascadeCxxWrap_jll` all
  already have working `BinaryBuilder.jl` `build_tarballs.jl` scripts and
  their own GitHub repos — the remaining work is a Yggdrasil PR + cross-
  platform build verification, not building these from scratch. Concrete
  sequenced checklist added (`Monge.jl` needs a LICENSE file; dependency
  order for registry submission spelled out).

### Added (roadmap Phase 3 — polish & ecosystem)
- **Getting-started tutorial** (`docs/src/tutorial.md`) and five new concept
  pages: `mesh_options.md`, `sessions_snapshots.md`, `introspection_contract.md`,
  `internals_escape_hatch.md`, `handles_gc.md` — including an empirical GC
  finding (a `level_mesh` handle extracted from a session survives the
  session going out of scope and `GC.gc()`, since Julia's GC tracks the
  handle's own reachability, not the session's — observed, not an upstream
  guarantee). `README.md`'s worked example trimmed to a teaser pointing at
  the tutorial.
- **Doctests**: all ~48 code blocks across the 6 example pages and
  `index.md` converted to real `@example`/`jldoctest` blocks (`doctest = true`
  in `docs/make.jl`); a few left as illustrative fences where execution
  wasn't practical (undeclared doc dependency, a live-mutation pattern).
  Verifying them surfaced and fixed 6 real doc-accuracy bugs (stale
  constructor signatures, a vacuous 2D test comparing the wrong element
  count, an incorrect claim that a bare `MeshOptions(...)` validates its
  input). Also surfaced a likely native-binding bug: `parent_faces`'s
  2nd–4th return fields appear to read uninitialized memory when a face has
  no parent (documented in `docs/src/limitations.md`, not fixed here) —
  and a **known fix path for 2D local sizing**: `mark_for_ngx_refinement!`/
  `ngx_refine!` was verified to achieve real localized 2D refinement, unlike
  the `bisect!`-based mechanism `refine_near!` currently uses (noted in
  `src/local_sizing.jl` as a follow-up, not yet integrated).
- **`deploydocs()`** wired in `docs/make.jl` (targets `github.com/ahojukka5/
  Delone.jl.git`) and `.github/workflows/docs.yml` updated to pass through
  `DOCUMENTER_KEY`/`GITHUB_TOKEN` — publishing still requires a human to add
  the `DOCUMENTER_KEY` repo secret; safe no-op locally and on PRs until then.
- **`Base.summary`/`MIME"text/html"` show methods** across all structured
  report types (`MeshReport`, `MeshQualityReport`, `NativeQualityReport`,
  `MeshValidationReport`, `MeshGenerationResult`/`Diagnostics`,
  `RefinementResult`'s siblings, `MeshabilityReport`, `OodiSnapshotReadiness`,
  `MeshTagReport`, `MeshHierarchyReport`/`MeshLevelReport`/`TransferReport`),
  plus the `MeshHierarchySnapshot` collection interface
  (`length`/`getindex`/`iterate`, mirroring `MeshHierarchy`). No new exports
  — all additive methods on existing public types. A shared `_html_escape`
  helper (`src/diagnostics.jl`) is applied to every user/backend-controlled
  string field rendered as HTML.
- **`DeloneMakieExt`** package extension (`ext/DeloneMakieExt.jl`,
  Julia ≥1.9 required — `[compat] julia` bumped from `"1.6"` to `"1.9"` for
  the `Base.get_extension` mechanism): `Makie.mesh`/`Makie.mesh!`/`Makie.plot`
  recipes for `MeshLevelSnapshot`/`MeshHierarchySnapshot` (plain-array
  snapshot data only — live mesh handles are deliberately not supported,
  since they're raw unexported `Internals` C++ types).
  `DeloneWriteVTKExt`/`DeloneGeometryBasicsExt` remain open for a future round.

### Added (roadmap Phase 2 — functionality gaps)
- **Local mesh sizing** (`src/local_sizing.jl`): `LocalSizeField`,
  `local_size_field`, `restrict_h!`, `restrict_h_at!`, `mesh_h_at`,
  `set_global_h!`, `set_minimal_h!`, `refine_near!`, and a `local_size` option
  on `MeshOptions`. Netgen's `RestrictLocalH`/`SetLocalH` were investigated
  and found not to feed back into `generate_mesh` in this build, so local
  sizing is implemented as coarse generation followed by geometric
  mark-and-bisect refinement near the requested points — verified to work in
  3D; in 2D `bisect!` refines uniformly regardless of marking, so
  `local_size` only achieves uniform refinement there (documented, warned).
- **Native Netgen quality diagnostics**: `NativeQualityReport`,
  `native_quality`, and new `netgen_*`-prefixed fields on `MeshQualityReport`
  (`CalcTotalBad`/`ElementError`-based, distinct scale from the existing
  Julia-side proxy metrics — see the docstring). `suggest_mesh_fixes` now
  surfaces orientation/boundary/overlap issues Netgen's own kernel detects.
  `FindOpenElements`/`FindOpenSegments` were investigated and found not
  exposable as a count with the current C++ bindings (documented as an open
  item needing new bindings, not faked).
- **Pre-meshing boundary/material naming**: `set_material_name!`,
  `set_boundary_name!`, `rename_materials!`, `rename_boundaries!` in
  `src/tags.jl` — the write side of the existing `material_names`/
  `boundary_names` queries.
- New API reference page `docs/src/reference/local_sizing.md`, and additions
  to `reference/validation_quality.md` / `reference/tags.md`.

### Investigated, not shipped
- `STLParameters` (STL feature-angle meshing controls): confirmed
  unreachable from the wrapped `STLGeometry::GenerateMesh` — it copies a
  global C++ singleton rather than accepting a caller-supplied object, and
  the lower-level free function that would (`STLMeshingDummy`) isn't exposed
  by `NetgenCxxWrap_jll`. No `STLOptions` API was added; needs a new C++
  binding upstream first.

### Fixed (roadmap Phase 2 follow-up)
- `generate_mesh`/`generate_mesh_result` was broken end-to-end for STL
  geometry: `Internals.SetGeometry` has no overload accepting `STLGeometry`
  (only `NetgenGeometry`), so it threw `MethodError` before meshing started.
  `generate_mesh_result` now checks `hasmethod` before calling `SetGeometry`
  and skips straight to `Internals.GenerateMesh` when unsupported — see the
  new end-to-end STL volume-meshing test in `test/stl.jl`.

### Added
- Full Documenter.jl API reference (`docs/src/reference/*.md`, 13 pages,
  `@docs` blocks grouped by topic to match `src/Delone.jl`'s export sections)
  wired into `docs/make.jl`'s page tree.
- `checkdocs = :exported` in `docs/make.jl`, so an exported name with no
  docstring now fails/warns the docs build instead of going unnoticed.
- `LICENSE` (MIT) and this `CHANGELOG.md`.
- CI workflows: `.github/workflows/test.yml` and `.github/workflows/docs.yml`
  (best-effort first pass — not yet validated on a real GitHub Actions
  runner; see caveats in each file, notably that `gen/build_local.jl` expects
  a sibling `NetgenCxxWrap_jll` checkout CI does not fetch).
- `Aqua.jl` static-quality testset in `test/runtests.jl` (ambiguities,
  stale-deps, and piracy checks disabled with documented reasons — CxxWrap
  method tables, this repo's monorepo-style dependency convention, and the
  intentional OodiCore introspection-contract extension pattern,
  respectively; unbound-args and undefined-exports checks pass and stay on).
- Missing docstrings for several exported names (`src/constants.jl`,
  `src/geometry.jl`'s `load_*` family, `src/hierarchy.jl`'s
  `level_nvertices`/`coarsest`/`finest`/`geometry`/`uniform_hierarchy`/
  `refine_uniform!`/`refine_marked!`/`prolongation`).

### Changed
- Consolidated redundant naming (deprecated via `Base.@deprecate`, old names
  still callable with a warning): `try_generate_mesh` → `generate_mesh_result`,
  `coarse_hierarchy` → `mesh_hierarchy(geom; maxh=maxh)`, `mesh_quality` →
  `quality`. The legacy `secondorder` keyword to `mesh_options` now emits a
  deprecation warning pointing at `second_order` instead of being silently
  accepted.
- `Manifest.toml` is no longer tracked in git (library convention).
- Renamed the package from `Netgen.jl` to `Delone.jl`; `Delone.Internals` is
  the raw `NetgenCxxWrap_jll` escape hatch (Netgen/NGSolve remains the backend
  engine name throughout). See `audit/DELONE_REBRAND_AND_LLM_MESHING_VISION_2026-07-02.md`.
- Split the former monolithic `src/Netgen.jl` into focused modules
  (`geometry.jl`, `mesh.jl`, `options.jl`, `validation.jl`, `quality.jl`,
  `refinement.jl`, `hierarchy.jl`, `session.jl`, `snapshots.jl`, `hp.jl`,
  `fem.jl`, `export_mesh.jl`, `introspection.jl`, and structured report types).

## [0.1.0]

Initial development version. Julian, LLM-friendly meshing, refinement,
mesh-diagnostics, and mesh-hierarchy API built on Netgen/NGSolve
(`Delone.Internals` — raw `NetgenCxxWrap_jll` bindings). See `README.md` and
`AGENTS.md` for the introspection contract and architecture.
