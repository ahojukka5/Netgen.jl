# Structured reports & introspection

Alongside the mesh/geometry API, Delone.jl exposes a **read-only reporting
layer**: structured, serializable results for validation, quality, meshability,
and readiness checks. It exists so a calling tool, solver driver, or LLM agent
can inspect *what happened* and *what to do next* without touching raw
`Delone.Internals` handles. The generic entry points (`report`, `validate`,
`readiness`, `to_namedtuple`) are owned by **OodiCore**, a small shared
contract package — Delone.jl only adds methods and concrete report types.
`test/llm_feedback.jl` exercises this whole layer end to end and is the most
current reference if this page and the code ever drift.

## MeshOptions: construction and validation

```julia
using Delone

opts = MeshOptions(maxh=2.0, minh=0.1, grading=0.3)
validate_options!(opts)          # throws ArgumentError on bad combinations, returns opts

MeshOptions(maxh=-1.0)           # ArgumentError: maxh must be > 0
MeshOptions(maxh=1.0, minh=2.0)  # ArgumentError: minh must be ≤ maxh
```

`validate(opts)` is the non-throwing counterpart, returning an OodiCore
`ValidationReport`:

```julia
vr = validate(MeshOptions(maxh=1.0, minh=2.0))
isvalid(vr)                                    # false
any(d -> d.severity == :error, vr.diagnostics) # true
```

## Structured mesh generation

`generate_mesh` normally returns a bare mesh and throws on failure. Pass
`result=true` for a [`MeshGenerationResult`](@ref) instead — meshing failures
become data, not exceptions:

```julia
result = generate_mesh(geom; options=opts, result=true)
result.success           # Bool
result.mesh              # mesh handle, or `nothing` on failure
result.options           # the MeshOptions actually used
result.elapsed_seconds
result.diagnostics       # MeshGenerationDiagnostics: failure_stage, messages, suggestions

mesh(result)              # extract the mesh; throws if result.success == false
```

A failed attempt (e.g. `nothing` geometry, an empty mesh, or a backend
`MESHING3_*` failure code) sets `diagnostics.failure_stage` (one of
`:geometry_import`, `:surface_mesh`, `:volume_mesh`, `:optimization`,
`:post_validation`, `:unknown`) and fills `diagnostics.suggestions` with
actionable `DiagnosticMessage`s (e.g. "try increasing maxh" or "heal/repair CAD
geometry"). `try_generate_mesh` is an alias of `generate_mesh_result` for the
same non-throwing path.

## Mesh reports: validation, quality, tags

```julia
m = generate_mesh(geom; maxh=40.0)

r = mesh_report(m)        # MeshReport: validation + quality + topology + tags
r.validation.valid
r.validation.node_count
r.validation.element_count
isvalid(m)                 # shortcut: r.validation.valid

q = quality(m)             # MeshQualityReport (mesh_quality is an alias)
q.min_quality; q.mean_quality
q.min_edge_length; q.max_edge_length

tr = tag_report(m)         # MeshTagReport: boundary/region tag inventory
```

All report types have readable `show` methods (`string(r)`), and none of them
expose `Delone.Internals` handles — `r.validation isa Delone.Internals.Mesh`
is always `false`.

## Meshability: checking before you commit

`meshability_report` is a pre-meshing sanity check (options + geometry
presence, sizing hints) — it doesn't guarantee success but flags obvious
blockers:

```julia
mr = meshability_report(geom; options=opts)
mr.likely_meshable   # Bool or nothing
mr.suggestions       # Vector{DiagnosticMessage}
```

`meshing_diagnostics(geom, opts, result)` does the post-mortem version,
combining a `MeshGenerationResult` with option context; `suggest_mesh_fixes`
pulls actionable fixes out of a result (optionally cross-referenced against a
`MeshReport` for quality-driven suggestions like inverted elements or
untagged boundaries).

## Hierarchy & session reports

```julia
h = mesh_hierarchy(geom; maxh=0.5, levels=1)
refine!(h; mode=:uniform, result=true)   # RefinementResult when result=true

hr = hierarchy_report(h)                 # MeshHierarchyReport
hr.nlevels
hr.levels[k].element_count
hr.transfers[k].inherited_node_count
```

The same pattern works on a live `MeshHierarchySession` via
`hierarchy_report(session)` and `refine_session!(session; mode=:uniform,
result=true)`. A [`RefinementResult`](@ref) reports `success`,
`old_level_count` → `new_level_count`, and `old_element_count` →
`new_element_count`, so a caller can tell *whether refinement actually grew
the mesh* without re-deriving it from before/after handles.

## The `report` / `validate` / `readiness` contract

Three generic entry points, dispatched by argument type, cover "what is this?",
"is this internally consistent?", and "is this ready for the next stage?":

| Call | Returns |
|------|---------|
| `report(mesh)` | [`MeshReport`](@ref) (same as `mesh_report(mesh)`) |
| `report(hierarchy_or_session)` | [`MeshHierarchyReport`](@ref) |
| `report(generation_or_refinement_result)` | the result itself (idempotent) |
| `validate(mesh)` | `MeshValidationReport` |
| `validate(::MeshOptions)` | OodiCore `ValidationReport` |
| `readiness(geom, MeshingTarget(options=...))` | [`MeshabilityReport`](@ref) |
| `readiness(mesh_or_hierarchy, OodiImportTarget())` | [`OodiSnapshotReadiness`](@ref) |
| `readiness(hierarchy_or_session, GeometricMultigridTarget())` | OodiCore `ReadinessReport` |

```julia
readiness(geom, MeshingTarget())                       # ArgumentError: needs options=
readiness(geom, MeshingTarget(options=opts)).likely_meshable

gmg = readiness(h, GeometricMultigridTarget())
gmg.subject       # :geometric_multigrid
isready(gmg)       # needs ≥2 levels + valid coarse→fine transfers
```

`oodi_snapshot_readiness(x)` (the concrete function behind `OodiImportTarget`)
reports `dimension`, `hierarchy_levels`, and `parent_node_transfers` — the
minimum a downstream Oodi-ecosystem consumer needs before importing a
snapshot.

## Serialization: `to_namedtuple`

Every report type above converts recursively to a plain `NamedTuple` — numbers,
strings, symbols, vectors, dicts, nested named tuples — safe for JSON logging
or an LLM tool response. Raw mesh handles are never emitted; a
`MeshGenerationResult` is summarized (`has_mesh`, `node_count`, `cell_count`)
instead of embedding `r.mesh`:

```julia
nt = to_namedtuple(mesh_report(m))
nt.validation.valid
nt.quality.min_quality

ntr = to_namedtuple(generate_mesh(geom; maxh=40.0, result=true))
ntr.success; ntr.has_mesh; ntr.node_count
haskey(ntr, :mesh)   # false — raw handle never serialized
```

## Export & preview formats

Lightweight, dependency-free export for human or LLM feedback loops (no full
viewer):

```julia
export_vtk(m, "mesh.vtk")           # ASCII VTK unstructured grid (volume + boundary)
export_obj(m, "mesh.obj")           # Wavefront OBJ (boundary/domain triangles)
export_svg_2d(m2d, "mesh.svg")      # 2D-only SVG preview
export_mesh_preview(m, path; format=:vtk)  # dispatches to :vtk or :obj

mesh_preview(m; format=:vtk)                    # writes to a fresh tempfile, returns its path
mesh_previews(m; formats=[:vtk, :obj])          # one tempfile per format
```

Next: [Tags, hp-adaptivity & FEM data](@ref "Tags, hp-adaptivity & FEM data").
