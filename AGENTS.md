# AGENTS.md

Guidance for AI agents working in **Delone.jl** — a high-level, LLM-friendly
meshing, refinement, mesh-diagnostics, and mesh-hierarchy package for numerical
simulation workflows, built on top of **Netgen/NGSolve**, a mature and powerful
open-source meshing technology. Delone.jl does not replace Netgen or reimplement
a meshing kernel; raw Netgen/NGSolve C++ bindings live under `Delone.Internals`
(strict 1:1 names from `NetgenCxxWrap_jll`) for advanced/backend use, while the
top-level `Delone` module is the Julian, agent-friendly public API.

Delone.jl is the meshing stage of the **Monge → Delone → Oodi** pipeline:
Monge.jl handles semantic CAD / constructive geometry, Delone.jl discretizes
that geometry into simulation-ready meshes and hierarchies, and Oodi.jl builds,
solves, and diagnoses the numerical model. Within a single solve, this is the
**meshing / mesh-hierarchy** stage of the Oodi numerical pipeline:

```
intent → geometry → validation → mesh → quality diagnostics → discretization
→ operator/problem construction → solve → verification → report → revision
```

## LLM-native design principle

This project is designed to be **LLM-native**. This is a core architecture
principle, not a cosmetic feature. Major public objects should be **inspectable,
validatable, and pipeline-aware** so that both humans and language-model agents
can understand what was built, whether it is valid, and whether it is ready for
the next pipeline stage. Avoid opaque black boxes as the primary user-facing
design: a function that only returns a raw handle or throws an unstructured
error is not enough.

### Minimal introspection contract

Every major public object that participates in the pipeline should gradually
support these three read-only, first-class functions:

```julia
report(x)              # "What is this object?"
validate(x)            # "Is this object internally valid?"
readiness(x, target)   # "Can this object move to the requested next stage?"
```

- **`report(x)`** — main structured introspection entry point. Returns a
  human- and machine-readable overview: key metadata, dimensions/counts/options,
  warnings, diagnostics, and references to artifacts when available.
- **`validate(x)`** — internal consistency only. Catches missing data,
  inconsistent topology, invalid options, unresolved tags, unsupported element
  types, and similar well-formedness problems.
- **`readiness(x, target)`** — fitness for a specific next stage. Validity is
  necessary but not sufficient; a valid object can still be unfit for a target.

Keep the distinction sharp:

```
validate(x)            → "Is this object internally valid?"
readiness(x, target)   → "Can this object be used for this next stage?"
report(x)              → "What is this object and what should an agent know?"
```

Example (meshing): `validate(mesh).valid == true` can hold while
`readiness(mesh, OodiImportTarget())` still fails because the element type is
unsupported by the snapshot contract.

### What the contract covers in this repository

The pipeline objects here are: geometry input, `MeshOptions`,
`MeshGenerationResult`, meshes, boundary/region tags, quality reports,
`RefinementResult`, `MeshHierarchy` / `MeshHierarchySession`, level snapshots,
transfer/prolongation metadata, and Oodi snapshot-readiness reports.

Reports/readiness should let an agent answer:

- Did mesh generation succeed? If not, at what stage and why?
- How many nodes/elements exist? Are elements inverted or low quality?
- Are boundary and region tags preserved (or which are untagged)?
- Is the mesh suitable for export to Oodi (element type, order, topology)?
- Does the hierarchy have valid transfers for geometric multigrid?

### Current state (do not over-claim)

The generic `report` / `validate` / `readiness` / `to_namedtuple` verbs, the
`DiagnosticMessage` type, and the base marker/report types
(`AbstractPipelineTarget`, `PipelineTarget`, `ValidationReport`,
`ReadinessReport`, `ObjectReport`, `ArtifactRef`) are **owned by
[`OodiCore.jl`](../OodiCore.jl)**, the shared introspection contract for the
whole Oodi ecosystem (`using OodiCore` in `src/Delone.jl`). This package must
never redefine those names locally — it only adds methods/subtypes in
`src/introspection.jl` and the stage-specific report files. Coverage is still
growing (e.g. `validate` does not yet cover raw geometry handles). Current
wiring:

| Contract role | Generic verb | Delegates to / notes |
|---------------|--------------|----------------------|
| `report(x)` | `report(mesh)`, `report(::MeshHierarchy/Session)`, `report(::MeshGenerationResult/RefinementResult)` | wraps `mesh_report` / `hierarchy_report`; results return themselves |
| `validate(x)` | `validate(mesh)` → `MeshValidationReport`; `validate(::MeshOptions)` → `OodiCore.ValidationReport` | `isvalid(mesh)` shortcut; geometry `validate` still TODO |
| `readiness(x, target)` | `MeshingTarget`, `OodiImportTarget`, `GeometricMultigridTarget` | delegate to `meshability_report` / `oodi_snapshot_readiness` / `OodiCore.ReadinessReport` |
| serialization | `to_namedtuple(report)` | recursive, JSON-friendly; never emits raw handles |
| structured results | `MeshGenerationResult`, `RefinementResult`, `MeshQualityReport`, `MeshTagReport`, `OodiSnapshotReadiness`, `MeshabilityReport`, `DiagnosticMessage` (from OodiCore), `suggest_mesh_fixes` | printable structs with fields |

Target marker types live in `src/introspection.jl` (`MeshingTarget`,
`OodiImportTarget`, `GeometricMultigridTarget`, all `<: OodiCore.AbstractPipelineTarget`).
`readiness(x, target)` throws a clear `ArgumentError` for unsupported
`(object, target)` combinations rather than guessing. Domain-specific report
types (`MeshValidationReport`, `MeshReport`, `MeshHierarchyReport`,
`MeshabilityReport`, `OodiSnapshotReadiness`, `MeshGenerationResult`,
`RefinementResult`) subtype `OodiCore.AbstractValidationReport` /
`AbstractReadinessReport` / `AbstractOodiReport` as appropriate, per
[`OodiCore.jl`'s AGENTS.md](../OodiCore.jl/AGENTS.md).

### How future agents should extend it

1. When adding a new major object, also add or plan its `report` / `validate` /
   `readiness` behavior. Prefer extending these over ad-hoc print/debug helpers.
2. Reports are **structured Julia objects**, not just strings, and keep a
   readable `show` method for humans.
3. Expose enough fields that a report can be serialized to a NamedTuple/JSON-like
   structure later.
4. Include warnings and suggestions in reports when useful (reuse
   `DiagnosticMessage`).
5. Do **not** silently ignore missing tags, unsupported element types, failed
   refinement, or empty meshes — surface them in the report/readiness result.
6. If the code falls back to a simplified/approximate path (e.g. topological
   `1/2–1/2` transfer weights instead of exact weights), **report it explicitly**.
7. If something is not implemented, say so in the report or readiness result
   rather than pretending it works.
8. When introducing generic `report`/`readiness`, define target marker types
   (e.g. `OodiImportTarget`, `MeshingTarget`) so `readiness(x, target)` dispatches
   cleanly, and keep the existing stage-specific functions working.

### Read-only vs mutating

The introspection contract is **read-only**: `report`, `validate`, and
`readiness` must not mutate major computational state. Mutation must be explicit
via a trailing `!` or a clear verb: `repair!`, `refine!`, `solve!`, `optimize!`,
`write_*`, `delete_*`. This matters because read-only introspection may later be
exposed as freely-callable agent tools, while mutating operations need dry-runs,
sandboxing, or user confirmation.

### MCP / tool-server direction

Design the contract so it can later be exposed through an MCP server or similar
tool interface (e.g. `oodi.report`, `oodi.validate`, `oodi.readiness`). Practical
implications: inputs should be schema-friendly, outputs structured and
serializable, artifacts referenced explicitly (paths, not raw handles), and
read-only introspection kept separate from mutating operations.

### Future expansion (not required now)

The contract may later grow to include `summary`, `diagnose`, `explain`,
`suggest_fixes`, `artifacts`, `provenance`, `to_namedtuple`, `schema`. These are
directions, not current requirements. First priority stays `report` / `validate`
/ `readiness`.

## Architecture

```
Delone                     exported Julian API (src/*.jl) — public, LLM-friendly
  └── Delone.Internals     strict 1:1 CxxWrap bindings from NetgenCxxWrap_jll
                            (raw Netgen/NGSolve backend; advanced/backend use)
```

- `src/internals.jl` defines `module Internals`, loads `libnetgen_cxxwrap`, and
  runs `@initcxx` inside its own `__init__`. **Never** move `@initcxx` to the
  parent module.
- All C++ calls in high-level code go through `Internals.*`. `Internals` is
  **not exported** — advanced callers use the fully qualified `Delone.Internals`.
  Most users and LLM agents should never need it; it exists for advanced users
  and backend development, not as the recommended default layer.
- OCCT/CAD modeling lives in the sibling **OpenCascade.jl**; Delone only bridges
  in-memory BREP via `occ_geometry_from_brep_string`.

## Source layout (`src/`, included in order by `Delone.jl`)

| File | Responsibility |
|------|----------------|
| `internals.jl` | raw CxxWrap submodule (escape hatch) |
| `constants.jl` | `NG_*`, `MESHING3_*` enums |
| `diagnostics.jl` | `DiagnosticMessage` for reports |
| `geometry.jl` | `load_*`, `load_geometry`, 2D CSG (`Circle`, `geometry2d`) |
| `extraction.jl` | `points`, `tetrahedra`, `surface_triangles` |
| `tags.jl` | dimension-checked connectivity, region/name helpers |
| `mesh.jl` | `generate_mesh`, `meshing_parameters`, I/O, quality ops |
| `options.jl` | `MeshOptions`, `mesh_options`, validation |
| `validation.jl`, `quality.jl`, `tag_report.jl`, `mesh_report.jl` | structured reports |
| `generation_result.jl` | `MeshGenerationResult`, structured `generate_mesh` |
| `refinement.jl`, `hierarchy.jl` | h-refinement, `MeshHierarchy`, parent maps |
| `hierarchy_report.jl`, `refinement_result.jl` | hierarchy/refinement reports |
| `meshability.jl`, `oodi_readiness.jl`, `export_mesh.jl` | diagnostics, Oodi readiness, VTK/OBJ/SVG export |
| `session.jl`, `snapshots.jl` | live `MeshHierarchySession` + copied snapshots |
| `hp.jl`, `fem.jl`, `partition.jl`, `interop.jl` | hp-adaptivity, curved maps, partition hints, BREP bridge |

## Conventions (match existing code)

- **Do not put implementation directly in `src/Delone.jl`** — add a focused file
  and `include` it. `Delone.jl` is only the module shell, includes, and exports.
- **Exports are grouped by topic** with section comments (one `export` per group),
  not a single monolithic `export` line.
- Julian helpers live in `Delone`, call `Internals.*` internally, use **1-based
  ids**, and **return `m`** (or the session/hierarchy) from mutating `!` functions.
- Docstrings reference **Julian names**; mention C++ names in backticks for
  upstream lookup only.
- Fail with `ArgumentError` on unsupported topology/dimension rather than
  silently reinterpreting elements. **Never invent 2D material/boundary names**
  (see the documented 2D limitation).
- Reports are structured Julia types with readable `show` methods — never leak
  raw `Internals` handles into public report fields.
- No FEM/solver logic here; this package owns mesh + hierarchy + metadata only.

## Build & test

Native library is built locally (not registered yet) and bound via `Artifacts.toml`:

```bash
julia --project=. gen/build_local.jl        # (re)build libnetgen_cxxwrap
```

Run the full suite (takes ~5–6 minutes; loads the native lib + OpenCascade.jl):

```bash
julia --project=. test/runtests.jl
```

- Tests reference raw bindings via `const I = Delone.Internals` (set in
  `test/runtests.jl`). New test files must be added to the `@testset` include list.
- Fixtures live in `test/fixtures/` (`frame.step`, `cylinder.brep`, `tet.stl`).

## Docs

- `README.md` — integration contract, session/snapshot semantics.
- `docs/src/` — Documenter sources; `docs/API_COVERAGE.md` — wrapped C++ inventory.
- `audit/` — design/audit notes (e.g. the LLM-friendly meshing API note, and the
  Delone rebrand & LLM-meshing vision note).

When adding public API, update the topic-grouped exports, the relevant
`docs/src/examples/*.md`, and `docs/src/capabilities.md`.

## TODO: converge on the introspection contract

Done: generic `report` / `validate(::MeshOptions)` / `readiness(x, target)` /
`to_namedtuple` in `src/introspection.jl` (tested in `test/llm_feedback.jl`),
now sourced from `OodiCore.jl` instead of locally-defined duplicates (fixes
name collisions with other Oodi packages extending the same generics).

Remaining targets:

- Extend `validate` to raw geometry handles (needs a stable dispatch type for the
  Netgen geometry pointer, or a small wrapper type around loaded geometry).
- Add `readiness(mesh, DiscretizationTarget)` once the discretization stage
  (Oodi.jl) defines its own requirements.
- Serialize hierarchy transfer *weights* explicitly once exact weights exist
  (today `to_namedtuple` reports the `:topological_bisection_default` semantics).
- Consider `to_json(report)` on top of `to_namedtuple` when a JSON dep is added.
- Expose `report` / `validate` / `readiness` through an MCP tool server
  (`oodi.report`, `oodi.validate`, `oodi.readiness`) with schema-friendly inputs.
