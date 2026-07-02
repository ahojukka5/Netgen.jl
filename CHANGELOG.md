# Changelog

All notable changes to Delone.jl are documented in this file.

## [Unreleased]

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
