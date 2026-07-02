# MeshOptions

[`MeshOptions`](@ref) is the structured, inspectable way to configure
[`generate_mesh`](@ref) instead of passing an open-ended list of keyword
arguments. This page is a narrative walkthrough of every field, its default,
its validation rule, and what it does (or does not) map to on the Netgen
side. For the terse auto-generated signature list, see [Mesh generation &
I/O](reference/meshing.md); this page is the reading-order companion to it.

## Constructing options

`maxh` is the only required field. Everything else has an explicit default:

```@example mesh_options
using Delone

opts = MeshOptions(maxh=0.5)
opts
```

A more fully specified example:

```@example mesh_options
opts = MeshOptions(maxh=0.5, minh=0.05, grading=0.3, second_order=false, optimize=true)
opts
```

`mesh_options(; maxh=..., kwargs...)` is the keyword-argument constructor used
internally by `generate_mesh`; it also validates its result and accepts the
deprecated `secondorder` spelling (warns and forwards to `second_order`).

## Field-by-field reference

| Field | Default | Constraint (`validate_options!`) | Netgen mapping |
|-------|---------|-----------------------------------|----------------|
| `maxh` | *(required)* | `> 0` | `MeshingParameters.maxh` — target characteristic element size |
| `minh` | `nothing` | if set: `> 0` and `≤ maxh` | `MeshingParameters.minh` — lower bound on local mesh size |
| `grading` | `nothing` | if set: `≥ 0` | `MeshingParameters.grading` — how quickly element size can change between neighboring regions |
| `second_order` | `false` | — | `MeshingParameters.secondorder` — request curved second-order elements from the mesher itself (equivalent to a post-hoc [`make_second_order!`](@ref)) |
| `optimize` | `false` | — | drives whether `generate_mesh` calls `optimize_volume!` after generation (3D only) |
| `dimension` | `nothing` | if set: `2` or `3` | not a Netgen parameter — checked *after* meshing against `mesh_dimension(mesh)` as a caller-side sanity assertion |
| `preserve_tags` | `true` | — | informational only; CAD tags are preserved whenever the geometry backend provides them, this flag does not disable that |
| `optsteps2d` | `nothing` | — | `MeshingParameters.optsteps2d` — optimizer passes for 2D meshes |
| `optsteps3d` | `nothing` | — | `MeshingParameters.optsteps3d` — optimizer passes for 3D volume meshes |
| `local_size` | `Vector{Any}()` | each entry normalized by [`local_size_requests`](@ref) (see below) | **not** a Netgen field — applied by this package *after* generation via [`refine_near!`](@ref) |

`to_meshing_parameters(opts)` converts the Netgen-mapped fields above into a
raw `MeshingParameters` object (via `Internals.meshing_parameters`) and is
what `generate_mesh` calls internally after validating.

## `local_size`: the one field that is not a direct Netgen passthrough

Every other field above maps onto a real `MeshingParameters` field that
Netgen's `GenerateMesh` reads directly. `local_size` is different: it is a
**post-processing step implemented in this package**, not a Netgen sizing
field. Each entry requests locally finer elements near a point:

```@example mesh_options
opts_local = MeshOptions(
    maxh=0.5,
    local_size=[(point=(0.0, 0.0), h=0.1, radius=0.2, levels=1)],
)
local_size_requests(opts_local)
```

Entries may be `(point, h)` tuples or `(point=..., h=..., radius=nothing,
levels=1)` named tuples; `radius` defaults to `h`, `levels` is the number of
bisection passes. [`local_size_requests`](@ref) normalizes and validates
every entry (throwing `ArgumentError` on malformed input) without needing a
mesh.

### Why `local_size` is not a graded local-h field

Netgen exposes real local-h machinery (`RestrictLocalH`, `SetLocalH`,
`LoadLocalMeshSize`), but in this build `GenerateMesh` recomputes its own
local-h field during surface meshing and **discards** any restriction applied
beforehand — so those calls cannot steer element sizes during initial
generation (see the "Julian-layer gaps" entry in [Not yet wrapped](limitations.md)
for the full empirical writeup). `MeshOptions.local_size` therefore works
around this with coarse generation followed by geometric mark-and-refine
near each requested point — verified to genuinely localize in **both 2D and
3D**: 3D uses `mark_for_refinement!`/`bisect!`; 2D uses
`mark_for_ngx_refinement!`/`ngx_refine!` instead, since plain `bisect!`
refines 2D meshes uniformly regardless of marking. See
[Local mesh sizing](reference/local_sizing.md) for `refine_near!` and the
rest of the standalone size-field API this mechanism is built from — that
page, not a `MeshOptions` field, is the current mechanism for genuinely
spatial/curvature-aware refinement.

## Validating options: throwing vs. non-throwing

[`validate_options!`](@ref) is the throwing form used internally before every
mesh generation call; it returns `opts` unchanged on success:

```@example mesh_options
opts_ok = MeshOptions(maxh=1.0, minh=0.2)
validate_options!(opts_ok) === opts_ok
```

```@example mesh_options
try
    validate_options!(MeshOptions(maxh=1.0, minh=2.0))   # minh > maxh
catch err
    err
end
```

[`validate`](@ref)`(::MeshOptions)` is the non-throwing counterpart
from the generic [`report`/`validate`/`readiness` contract](introspection_contract.md) —
useful when a caller (especially an LLM agent) wants to inspect *why*
something is invalid instead of catching an exception:

```@example mesh_options
vr = validate(MeshOptions(maxh=1.0, minh=2.0))
isvalid(vr)
```

```@example mesh_options
[d.message for d in vr.diagnostics if d.severity == :error]
```

`mesh_options(; maxh=1.0, minh=2.0)` runs the same validation as
`validate_options!` and throws the same `ArgumentError`; use it when you want
keyword-argument construction with immediate validation instead of building
`MeshOptions` and validating separately.

## What is not covered by `MeshOptions` at all

`MeshOptions` only reaches the meshing-generation parameters listed above.
Several related but distinct concerns are **not** `MeshOptions` fields:

- **Curvature-based or graded spatial sizing** — not a field; see
  [Local mesh sizing](reference/local_sizing.md) (`LocalSizeField`,
  `refine_near!`, `restrict_h!`) for the current, more explicit mechanism.
- **Refinement after generation** (uniform or marked bisection) — a separate
  step via [`refine!`](@ref)/[`bisect!`](@ref), not a meshing option; see
  [Refinement](examples/refinement.md).
- **Second-order curving *after* the fact** (rather than requesting it at
  generation time) — [`make_second_order!`](@ref), independent of
  `second_order`.
- **Live-session refinement policy** (`request_*!` functions) — orthogonal to
  `MeshOptions`, see [Sessions & snapshots](sessions_snapshots.md).

Next: [Sessions & snapshots](sessions_snapshots.md) for the live-hierarchy
contract that consumes meshes built from these options.
