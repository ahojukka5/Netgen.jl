# Changelog

All notable changes to Delone.jl are documented in this file.

## [Unreleased]

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
