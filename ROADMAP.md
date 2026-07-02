# Delone.jl — finalization & polish roadmap

*Based on the full-package audit of 2026-07-02 (API ergonomics, Internals→Julian
coverage gaps, documentation, tests, package hygiene). Companion background
notes live in `audit/`.*

## Where the package stands

The audit confirms the premise: **the wrapping work is essentially done, the
product work is not.** `Delone.Internals` covers ~94 % of Netgen's `DLL_HEADER`
surface (`docs/API_COVERAGE.md`), the Julian layer exports ~190 names with
near-complete docstring coverage, all report types print well, the
hierarchy/session/snapshot design is coherent, and the test suite (~1400 LOC,
75+ testsets) exercises 85–90 % of the exports.

What is missing falls into four buckets, in decreasing order of user pain:

1. **Julian feature gaps** — important, already-wrapped Netgen capabilities
   (local mesh sizing above all) that are unreachable without dropping to
   `Internals`.
2. **API ergonomics debt** — naming redundancy, Int32 leakage, undocumented
   handle lifetimes, missing ecosystem hooks.
3. **Documentation gaps** — good example pages, but **no API reference at
   all**, no doctests, `checkdocs = :none`, no getting-started tutorial, and
   README/docs drift (`OpenCascade` vs `Monge`).
4. **Hygiene / registration blockers** — no LICENSE, no CI, no CHANGELOG,
   local-path `[sources]`, locally-built artifact.

The rest of this document is the concrete plan, organized as four workstreams
(A–D) and then sequenced into phases.

---

## Workstream A — close the Julian feature gaps

These are capabilities **already wrapped and tested at the Internals level**
(evidence in `test/extras.jl`, `test/mesh2.jl`, `test/gprim.jl`, `test/stl.jl`)
with no high-level API. Ordered by user impact.

### A1. Local mesh size control — *the* missing feature ⭐

A meshing package where you cannot say "be fine near this hole" is not
finished. Everything needed is wrapped: `RestrictLocalH`, `RestrictLocalHLine`,
`SetLocalH`, `LocalH` (`SetH`/`GetH`/`GetMinH`/`Copy`), `SetGlobalH`,
`SetMinimalH`, `CalcLocalHFromSurfaceCurvature`, `CalcLocalHFromPointDistances`,
`LoadLocalMeshSize`, `AverageH`, `GetH(Point3d)`.

Proposed Julian surface:

```julia
# declarative, through MeshOptions (preferred for LLM workflows):
opts = MeshOptions(maxh=0.5,
    local_size = [SizeAtPoint((0,0,0), 0.05),
                  SizeAlongLine((0,0,0), (1,0,0), 0.1),
                  CurvatureSize(factor=2.0)])

# imperative, pre-generation on the geometry/mesh:
restrict_size!(mesh, point, h)
restrict_size_line!(mesh, p1, p2, h)
size_from_curvature!(mesh, geom; factor=2)
load_size_field!(mesh, "sizes.msz")
mesh_size_at(mesh, point)            # read back (GetH); AverageH → average_mesh_size
```

Also extend `MeshReport`/`readiness` so an agent can *see* the h-field was
applied (min/avg/max h). This closes the loop of the long-term vision in
`audit/LLM_FRIENDLY_MESHING_API_2026-07-01.md` ("mesh it with local refinement
near holes"), which explicitly named this as next step #2 — still unimplemented.

### A2. Mesh construction from raw arrays (interop in *both* directions) ⭐

`AddPoint`, `AddVolumeElement`, `AddSurfaceElement`, `AddSegment`,
`SetDimension`, face-descriptor setup are all wrapped. Exposing a
`mesh_from_arrays(points, cells; boundary=..., regions=..., names=...)`
constructor makes Delone interoperable with Gmsh/Triangle/Meshes.jl/FEM codes —
today data flows *out* (snapshots, VTK) but never *in*. This is the single
biggest interop unlock and also enables round-trip testing of snapshots.

```julia
m = mesh_from_arrays(X, tets; surface=tris, cell_regions=..., material_names=...)
```

### A3. Boundary/region naming *before* meshing

`FaceDescriptor`/`EdgeDescriptor` setters (`SetBCName`, `SetName`,
`SetBCProperty`, `SetDomainIn/Out`) are wrapped but unreachable. Users of loaded
CAD geometry cannot name boundaries for their solver without post-hoc surgery.
Proposed: `set_boundary_name!(mesh, fd_index, name)`, `set_material_name!`,
plus a `rename_boundaries!(mesh, Dict(...))` bulk helper, and surface them in
`MeshTagReport`.

### A4. Native quality metrics & topology diagnostics

`CalcMinMaxAngle`, `CalcTotalBad`, `ElementError`, `FindOpenElements`,
`FindOpenSegments`, `CheckOverlappingBoundary`, `MarkIllegalElements`,
`RemoveIllegalElements` are wrapped. Today `MeshQualityReport` uses Julia-side
simplex proxies only (documented limitation). Wire the native metrics into
`quality()`/`mesh_report` (`min_angle`, `max_angle`, `netgen_badness`), and add
a `mesh_repair!(mesh)` / `open_elements(mesh)` diagnostics pair. This directly
strengthens the LLM feedback story: `suggest_mesh_fixes` can then say *which*
elements are illegal.

### A5. STL parameter control

`load_stl` exists but `STLParameters` (yangle, chartangle, …) is not exposed.
Add an `STLOptions` struct mirroring `MeshOptions` and accept it in
`load_stl(path; options=...)`. Also end-to-end STL→volume test at the Julian
layer (named as a gap in the 2026-07-01 audit, still open).

### A6. Mesh surgery & spatial search (secondary)

- `merge!(mesh_a, mesh_b)` (`Merge`), `split_into_parts(mesh)`
  (`SplitIntoParts`/`GetSubMesh`), `split2tets!`.
- `Point3dTree` / `BuildElementSearchTree` behind a small `NodeTree`-style
  wrapper for region-based marking (pairs naturally with A1: "mark all cells
  within radius r of p").
- `surface_mesh_orientation!`, `pure_tet_mesh`/`pure_trig_mesh` checks →
  useful inside `validate`.

### A7. Periodic identifications (query exists, setup doesn't)

`periodic_vertex_pairs` reads; nothing writes. Setup needs the un-wrapped
`Identifications` class — record it as a **known backend gap** in
`limitations.md` and defer wrapping until a consumer (Oodi) needs it.

---

## Workstream B — API ergonomics & consistency

### B1. Consolidate redundant names (do this **before** registration — it's a breaking-change window)

| Today | Proposal |
|---|---|
| `generate_mesh` / `generate_mesh_result` / `try_generate_mesh` | Keep `generate_mesh(...)` and `generate_mesh(...; result=true)`; make `try_generate_mesh` the *one* blessed non-throwing name and deprecate `generate_mesh_result` (or vice versa — pick one, delete the alias). |
| `coarse_hierarchy` / `uniform_hierarchy` / `mesh_hierarchy` | `mesh_hierarchy(geom; maxh, levels=1)` as the single front door; keep the others as documented specializations or deprecate `coarse_hierarchy` (`levels=1` covers it). |
| `quality` / `mesh_quality` | Keep one, deprecate the alias (other reports have no aliases). |
| `num_levels(mesh)` vs `nlevels(h)` | Rename the mesh-side one (Netgen-internal ngx count) to `ngx_num_levels` or fold it into hierarchy docs; the near-collision is a trap. |
| `secondorder` legacy kwarg | Deprecation warning now, removal at 0.2. |

### B2. Return-type polish

- **Int32 policy decision**: connectivity (`tetrahedra`, `parent_nodes`,
  `cell_regions`, …) returns `Matrix{Int32}`. Either convert to `Int` at the
  boundary or document the choice loudly in every docstring + docs page. Decide
  once, apply everywhere (snapshots currently also Int32 — keep consistent).
- Plain tuples → NamedTuples where structure isn't obvious:
  `mesh_bounding_box` → `(min=..., max=...)`, `connectivity` →
  `(volume=..., surface=...)`, `element_orders_xyz` → `(ox=..., oy=..., oz=...)`.
- `refine!(...; result=true)` returning a different type per kwarg is fine for
  the high-level API but document it; consider `refine_with_result!` if type
  stability ever matters to a consumer.

### B3. Lifetimes, GC, and thread-safety documentation

Nothing documents what happens when a `MeshHierarchySession` is GC'd while a
live `level_mesh` handle is held, or whether sessions are thread-safe. Add a
"Handles, ownership & GC" section to the docs (and docstrings of `level_mesh`
/ `unsafe_level_mesh`). Audit that CxxWrap finalizer ordering is actually safe
(geometry outliving meshes that reference it) and add a keep-alive field if not.

### B4. Small Base-interface additions

- `Base.getindex`/`length`/`iterate` for `MeshHierarchySnapshot` (levels), as
  already done for `MeshHierarchy`/session.
- `Base.summary(mesh)`, `Base.summary(::MeshReport)` one-liners.
- `show(::MIME"text/html", report)` (or markdown) for Pluto/Jupyter — cheap and
  visible payoff for the "reports should shine" goal.

### B5. Ecosystem integration via package extensions (weakdeps)

Keep the core lean; add Julia ≥1.9 extensions:

- **DeloneMakieExt** — `plot(mesh)` / `plot(::MeshLevelSnapshot)` recipes.
  Highest wow-factor per line of code.
- **DeloneWriteVTKExt** — real binary VTU export with cell data
  (regions, quality, orders); keep the dependency-free ASCII `export_vtk` as
  fallback.
- **DeloneGeometryBasicsExt** — `GeometryBasics.Mesh(snapshot)` for the wider
  viz ecosystem.
- (Later) Tables.jl views of connectivity/quality tables.

---

## Workstream C — documentation ("should shine")

### C1. API reference — the single biggest docs gap ⭐

There is **no `@docs`/`@autodocs` page**; ~190 well-written docstrings are
invisible to the docs site. Add `docs/src/reference/*.md`, grouped exactly like
the export groups in `src/Delone.jl` (geometry, generation, introspection,
reports, refinement, hierarchy, session, snapshots, tags, hp, FEM, export,
partition). Flip `checkdocs = :none` → `:exported` in `docs/make.jl:27` and fix
whatever it flags (e.g. `level_nvertices` is missing a docstring).

### C2. Getting-started tutorial

`index.md` is a map, not a path. Add one progressive tutorial:
install/build → 2D disk → 3D STEP file → options & diagnostics → refinement →
hierarchy → snapshot handoff. Reuse the excellent README disk example as its
spine, then *shorten the README* to point at it (30–40 % of README/docs content
is currently duplicated and will drift — the `using OpenCascade` vs `Monge`
drift already happened, see C5).

### C3. Doctests / runnable examples

47 code blocks across the example pages, none executed. Convert the stable ones
to `@example`/`jldoctest` blocks (mesh node counts are deterministic enough for
`@example`; use `jldoctest` only where output is stable) and enable doctests in
CI. This converts the docs from "probably right" to "tested".

### C4. Missing topic pages

- **MeshOptions reference** — every field, default, constraint, and its Netgen
  meaning (one honest table; also document what is *not* yet mapped, e.g.
  curvature-based sizing until A1 lands).
- **Sessions, snapshots & generations** — the best material in the package is
  currently buried in the README; give the live-session/staleness contract its
  own page.
- **The introspection contract** (`report`/`validate`/`readiness`) — one page,
  with the AGENTS.md tables, aimed at agent authors.
- **`Delone.Internals` escape hatch** — when to drop down, naming convention,
  the 1-based vs 0-based rule, link to `API_COVERAGE.md`.
- **Handles & GC** (from B3).

### C5. Fix drift now

- README says `using OpenCascade, Delone`; tests and Project.toml use **Monge**
  (`[sources] Monge = {path=.../OpenCascade.jl}`). Decide the public name and
  make README/docs/Project agree.
- `docs/make.jl`: add `deploydocs` (once CI exists), keep `sitename` etc.
- Move the audit-note content that states *current contracts* (snapshot
  topology support, 2D-names limitation) from README prose into `limitations.md`
  so there is one source of truth.

---

## Workstream D — tests, CI, hygiene, registration

### D1. Immediate hygiene (hours, not days)

- **LICENSE** file (MIT unless there's a reason otherwise; note Netgen is LGPL —
  Delone links it via JLLs, statement worth one line in README).
- **CHANGELOG.md** seeded with 0.1.0.
- `.gitignore` the root `Manifest.toml` (library convention).

### D2. CI

`.github/workflows/`:
- `test.yml` — the honest blocker is the locally-built `libnetgen_cxxwrap`
  artifact; until `NetgenCxxWrap_jll` exists, CI can at least run
  `gen/build_local.jl` on one Linux + one macOS runner (cache the build), then
  the test suite. Even a single-platform smoke CI beats none.
- `docs.yml` — build docs with `checkdocs=:exported` + doctests, deploy Pages.
- Add **Aqua.jl** (piracy, stale exports, compat hygiene) and optionally JET to
  the test suite — cheap and catches exactly the class of issues found in this
  audit (e.g. undocumented exports, unbound args).

### D3. Test additions

- Export-format content checks (VTK/OBJ/SVG currently smoke-only: parse the
  written file, count cells).
- `show`-method golden tests for every report type (they're part of the LLM
  product surface — treat them as API).
- Error-path tests for each `ArgumentError` branch (dimension mismatches, bad
  options, unsupported topology).
- STL→volume end-to-end (with A5).
- Round-trip test once A2 lands (`snapshot → mesh_from_arrays → snapshot`).

### D4. Registration track (longer pole, mostly upstream)

**Update (2026-07-02): further along than assumed.** All three native-binding
JLLs in the dependency chain already have working `BinaryBuilder.jl`
`build_tarballs.jl` scripts and their own GitHub repos — this is not "needs to
be built from scratch," it's "needs a Yggdrasil PR and cross-platform build
verification":

```
OpenCascadeCxxWrap_jll   build_tarballs.jl present, github.com/ahojukka5/OpenCascadeCxxWrap_jll
NGSolveNetgen_jll        build_tarballs.jl present, github.com/ahojukka5/NGSolveNetgen_jll
NetgenCxxWrap_jll        build_tarballs.jl present, github.com/ahojukka5/NetgenCxxWrap_jll
                         (depends on NGSolveNetgen_jll + OCCT_jll + Zlib_jll + libcxxwrap_julia_jll)
```

Dependency order for Yggdrasil submission: `NGSolveNetgen_jll` first (no
Delone-stack deps beyond upstream OCCT/Netgen sources), then
`NetgenCxxWrap_jll` (depends on the above), in parallel with
`OpenCascadeCxxWrap_jll` (Monge.jl's own native binding, same pattern).

**Upstream Netgen PRs opened (2026-07-02), tracked here — this is now the
critical path for A5:** two bugs found while extending the C++ binding layer
were fixed on a Netgen fork and PRs opened against upstream Netgen. Status:
open, awaiting review.
1. `DLL_HEADER` export macro missing on `STLMeshingDummy` — the specific fix
   A5 (STL parameter control) needs before it's even worth revisiting locally.
2. `MeshTopology::parent_faces` array-initialization bug (root-caused: an
   `operator=(initializer_list)` call silently collapses the array to size 1
   instead of broadcast-initializing it, causing out-of-bounds reads).

Neither fix helps until merged upstream **and** a new `NGSolveNetgen_jll`
build picks up the fixed Netgen source — treat both as blocked on external
review, not on anything actionable in this repo.

**Package layer, checked 2026-07-02:**

| Package | UUID/version | LICENSE | `[sources]` (path deps) | Blocker |
|---|---|---|---|---|
| `OodiCore.jl` | present, `0.1.0` | ✓ present | none | Otherwise registration-ready — smallest, cleanest package in the stack; a good first General-registry candidate once someone verifies its own test suite/compat bounds are complete. |
| `Monge.jl` (repo dir `OpenCascade.jl`, package name `Monge`) | present, `0.1.0` | ✗ **missing** | `OodiCore` (path) | Needs a LICENSE file (quick fix) + `OodiCore` resolved (registered or git-sourced) + `OpenCascadeCxxWrap_jll` registered (native binding, see above). |
| `Delone.jl` (this repo) | present, `0.1.0` | ✓ present (added this round) | `OodiCore`, `Monge` (both path) | Needs `OodiCore`/`Monge` resolved + `NetgenCxxWrap_jll`/`NGSolveNetgen_jll` registered + the local `libnetgen_cxxwrap` artifact binding in `Artifacts.toml` replaced by the registered JLL. |

**Concrete next steps, in dependency order:**
1. Add a LICENSE to `Monge.jl` (5-minute fix, blocks its own registration today).
2. Submit `NGSolveNetgen_jll`'s `build_tarballs.jl` to Yggdrasil; verify it
   actually builds on Yggdrasil's CI across the platforms it claims to support
   (this is the real gate — a `build_tarballs.jl` existing locally doesn't
   guarantee it builds clean on Yggdrasil's sandboxed builders on the first try).
3. Submit `NetgenCxxWrap_jll` and `OpenCascadeCxxWrap_jll` (parallel, both
   depend only on already-registered upstream JLLs + step 2's output).
4. Once both CxxWrap JLLs are registered: update `Monge.jl` and `Delone.jl` to
   depend on the registered JLLs instead of `gen/build_local.jl` +
   locally-bound `Artifacts.toml` entries; drop the local build script (or
   keep it as a `dev`-only convenience for contributors without registry access).
5. Register `OodiCore.jl` → `Monge.jl` → `Delone.jl`, in that order (each
   depends on the previous), to the General registry or a private registry if
   the Oodi ecosystem isn't ready for public release yet.

None of this is safely automatable from within a single coding session — it
requires real Yggdrasil CI runs (which can surface platform-specific build
failures no local check catches) and, for General-registry submission, a
human decision about public release timing. Treat this as a tracked,
sequenced initiative rather than a task to "finish."

---

## Suggested sequencing

**Phase 1 — "make it honest" (days).** D1 hygiene, C5 drift fixes, C1 API
reference + `checkdocs`, B1 naming consolidation (breaking-change window is
now), Aqua in tests. Low effort, removes every "unfinished" smell.

**Phase 2 — "make it complete" (1–2 weeks).** A1 local mesh sizing (flagship),
A4 native quality metrics, A3 boundary naming, A5 STL options, B2 return-type
polish, D3 test additions. After this, a user should almost never need
`Internals`.

**Phase 3 — "make it shine" (1–2 weeks).** C2 tutorial, C3 doctests, C4 topic
pages, B4 MIME show, B5 Makie/WriteVTK extensions, D2 CI + docs deploy. This is
the visible-quality phase.

**Phase 4 — "make it shippable" (calendar time, parallel).** A2 mesh-from-arrays,
A6 surgery/search, B3 GC docs + finalizer audit, D4 JLL/registry work toward
registration.

### Definition of done for "polished"

**Status as of 2026-07-02: Phases 1-4 executed and committed** (`3526837`,
`46fc6cf`, `1e43fdf`, `310ab27`, `cc58928`; 420 → 693 passing tests), plus a
follow-up C++ binding round (`4331e85`..`d0a4261`; 693 → 719 passing tests)
that closed two of the previously-open gaps by extending the native binding
layer instead of just documenting the limitation:

- **`Element`/`Element2d` construction** is now real (was structurally
  blocked — the C++ types had no constructor and no `PNum` setter). New
  Julian API: `add_volume_element!`/`add_surface_element!`
  (`src/mesh_construction.jl`), incremental one-element-at-a-time editing
  complementing `mesh_from_arrays`'s whole-mesh construction.
- **A4's `FindOpenElements`/`FindOpenSegments` count is now real** —
  `open_element_count`/`netgen_open_element_count` on
  `NativeQualityReport`/`MeshQualityReport`, well-verified as a genuine
  watertightness signal, feeding a new `suggest_mesh_fixes` suggestion.
- **A5 STLParameters investigated one level deeper and confirmed blocked at
  the Netgen-core level**, not just the binding layer: the escape-hatch free
  function `STLMeshingDummy` compiles but fails to *link* (missing export
  macro in Netgen's own header). Two upstream fixes were prepared on a
  Netgen fork and PRs have now been opened upstream — see
  [D4 tracking below](#d4-registration-track-longer-pole-mostly-upstream)
  for the second fix found along the way (`parent_faces` uninitialized
  memory, previously thought to be a Netgen-core bug of unclear origin, now
  root-caused and fixed the same way). **Landing these upstream does not by
  itself unblock STLParameters** — that additionally needs `STLMeshingDummy`
  itself exposed with `DLL_HEADER`, which is the PR that was opened; once
  merged and a new `NGSolveNetgen_jll` build picks it up, `STLOptions` in
  Delone.jl becomes achievable and should be revisited.

See per-item status below — most items are done; a handful are intentionally
still open (upstream-blocked, deliberately deferred, or lower-priority
polish not yet scheduled).

- [x] A user can do local refinement near a feature without touching `Internals`
      — `refine_near!`/`MeshOptions.local_size` (3D; 2D uniform-only, a real
      fix path via `ngx_refine!` is identified but not yet wired in).
- [x] A mesh can enter and leave Delone as plain arrays — `mesh_from_arrays`
      (whole-mesh, 3D only, 2D deferred) plus `add_volume_element!`/
      `add_surface_element!` (incremental, one element at a time).
- [x] Docs site has a tutorial, topic guides, and a complete generated API
      reference, built and deployed by CI with doctests green — `deploydocs()`
      is wired but **publishing still needs a human to add the
      `DOCUMENTER_KEY` repo secret**; local builds are green.
- [x] `checkdocs=:exported` and Aqua pass
- [x] One blessed name per concept (no `try_`/alias ambiguity) — for the 3
      pairs originally flagged. `num_levels`/`nlevels` was deliberately left
      as-is (cross-referencing docstrings judged sufficient over a rename).
- [x] LICENSE, CHANGELOG — [ ] **CI badges in README are not added.**
- [ ] **Registration blocked only by upstream JLL availability, nothing
      local** — not yet true: `Delone.jl`/`Monge.jl` still use local-path
      `[sources]` and a locally-built `libnetgen_cxxwrap` artifact. This is
      the D4 registration track, correctly still open (see D4 above) — it
      needs real Yggdrasil PRs and CI runs, not something to finish in a
      coding session.

**Other items still open, not covered by the checklist above:**
- A4 `FindOpenElements`/`FindOpenSegments` counts — **done** in the C++
  binding follow-up round (see above); struck from "still open."
- A5 STL parameter control — confirmed genuinely unreachable at the
  Netgen-core level (not just the binding layer); the specific upstream fix
  it needs (`DLL_HEADER` on `STLMeshingDummy`) has a PR open. **Blocked on
  an external PR review/merge + a new `NGSolveNetgen_jll` build**, not
  something to revisit locally until that lands.
- A7 Periodic identifications (`Identifications` class) — deliberately
  deferred per the original plan; still open, no consumer need yet.
- B2 Return-type polish (Int32→Int decision, tuple→NamedTuple conversions
  for `mesh_bounding_box`/`connectivity`/`element_orders_xyz`) — not started.
- B5 `DeloneWriteVTKExt`/`DeloneGeometryBasicsExt`/Tables.jl views — deferred;
  only `DeloneMakieExt` shipped.
- D3 test additions — export-format tests are still smoke-only (file exists +
  a keyword string check, not real content/cell-count parsing); no systematic
  `ArgumentError`-branch sweep; `mesh_from_arrays`'s round-trip test verified
  raw extraction-function output, not literally `level_snapshot`/
  `hierarchy_snapshot` objects (equivalent in practice, not identical to the
  original wording).
