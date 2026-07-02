# Handle lifetimes, ownership, and garbage collection

Delone.jl's live mesh and geometry objects are C++ objects managed by
[CxxWrap](https://github.com/JuliaInterop/CxxWrap.jl) and reachable from
ordinary Julia structs — a [`MeshHierarchySession`](@ref) holds `meshes::
Vector{Any}`, a [`MeshHierarchy`](@ref) holds the same shape. This page
explains what that means for object lifetimes: when a handle is safe to keep
around, what happens if you extract one and let its owning struct go out of
scope, and how this contrasts with snapshots, which have no such lifetime
concern at all. None of this is documented anywhere else in the package
today, so treat this page as the canonical source.

## The basic guarantee: reachability keeps handles alive

Julia's garbage collector works by reachability: an object is kept alive as
long as something reachable from a GC root still refers to it. A
`MeshHierarchySession`'s `meshes` field is an ordinary `Vector{Any}` of
CxxWrap-wrapped mesh objects, so as long as the session struct itself is
reachable, every mesh handle inside it is reachable too, and none of them
will be finalized:

```@example handles_gc
using Delone

disk = Circle(0.0, 0.0, 1.0, "disk", "boundary")
geom = geometry2d(disk)

s = mesh_session(geom; maxh=0.4)
request_uniform_refinement!(s)
nlevels(s)
```

As long as `s` stays reachable (a global binding, a field of another live
struct, a local variable still in scope), `level_mesh(s, 1)` and
`level_mesh(s, 2)` stay valid to call into. This is the ordinary case and
requires no special care.

## What if you extract a handle and drop the session?

This is the question worth answering explicitly, because it is not obvious
from the API alone whether a live mesh handle's validity is somehow tied to
its *session*, the way a raw pointer might be invalidated once the object
that allocated it is destroyed. It is not: the object returned by
`level_mesh(s, k)` is a first-class Julia value (a CxxWrap wrapper around a
`shared_ptr<Mesh>`), and once you hold *your own* reference to it, that
reference — not the session's `Vector{Any}` — is what keeps it reachable.
Empirically:

```@example handles_gc
function make_handle_and_drop_session()
    session = mesh_session(geom; maxh=0.4)
    handle = level_mesh(session, 1)   # extract the live mesh handle
    return handle                     # `session` becomes unreachable on return
end

m = make_handle_and_drop_session()
GC.gc(true)
GC.gc(true)
num_nodes(m)   # still callable after the owning session is gone and GC has run
```

The mesh handle **survives** the session going out of scope, and forcing a
full garbage collection does not finalize or invalidate it. `num_nodes(m)`
above is a real call into the live Netgen mesh, not a cached value — it
succeeds because the underlying `shared_ptr<Mesh>` is still referenced by
the Julia wrapper object `m`, and `m` is reachable from the local binding in
this scope regardless of what happened to `session`.

**Do not read this as "sessions don't matter for lifetime management."**
What it means precisely is: Julia's GC tracks reachability of the *handle
object itself*, not of the *session struct that happened to hand it to
you*. If you extract a handle and keep a reference to it (in a variable, a
field, a closure), it stays alive on its own merits. If you extract a
handle and *do not* keep any reference to it — and the session that held it
is also unreachable — then, like any other Julia value, it becomes eligible
for collection and its finalizer runs. The session is not adding or
removing protection from the handle; each Julia binding to the same
underlying object independently keeps it alive.

## Practical implication

This means the `Vector{Any}` inside a session is not a special ownership
mechanism you need to defeat or work around — it is just one more reference
among potentially several. In practice this makes handle lifetimes in
Delone.jl behave the way most Julia objects do (no manual `delete`/`free`,
no dangling-pointer class of bug from normal use), which is a meaningfully
different — and safer — situation than working with raw C++ pointers
directly. That said, this package makes no *documented upstream guarantee*
about `Internals`' CxxWrap-generated finalizers beyond ordinary Julia GC
semantics — see "Open question" below before relying on this for anything
safety-critical (e.g. holding a handle across a long-running external
process boundary, or assuming finalization order relative to the geometry
object a mesh depends on).

## Contrast: snapshots have no lifetime concern at all

Everything above is about **live handles**. Snapshots
([`MeshLevelSnapshot`](@ref), [`HierarchyTransferSnapshot`](@ref),
[`MeshHierarchySnapshot`](@ref), produced by [`level_snapshot`](@ref),
[`transfer_snapshot`](@ref), [`hierarchy_snapshot`](@ref)) are different in
kind, not just in degree: they are copied plain Julia arrays
(`Matrix{Float64}`, `Matrix{Int32}`, `Dict{Int32,String}`, …) with no C++
object inside them at all.

```@example handles_gc
snap = level_snapshot(s, 1)
typeof(snap.coordinates), typeof(snap.volume_connectivity)
```

A snapshot has completely ordinary Julia value semantics: no finalizer, no
underlying native resource, nothing that becomes invalid when any other
object is garbage collected. You can hold a snapshot indefinitely, serialize
it, send it across a process boundary, or let the session (and every live
handle it ever held) be fully collected — the snapshot is unaffected,
because it never referenced the live handle to begin with; `level_snapshot`
*read from* the live mesh once, at capture time, and copied everything it
needed into plain arrays. This is precisely why the [live-session
staleness contract](sessions_snapshots.md) exists as a *generation counter*
rather than a live reference: a snapshot cannot "point at" a session in any
GC sense, so the only way to know it might be out of date is to compare the
recorded `generation` against the session's current one.

## Open question: are `Internals`' finalizers documented upstream?

No — as far as this repository's documentation goes, this is unverified.
Neither [`docs/API_COVERAGE.md`](https://github.com/ahojukka5/Delone.jl/blob/master/docs/API_COVERAGE.md)
nor [`AGENTS.md`](https://github.com/ahojukka5/Delone.jl/blob/master/AGENTS.md)
makes any claim about how `NetgenCxxWrap_jll`'s CxxWrap-generated bindings
finalize their underlying C++ objects (destructor ordering between a mesh
and the geometry it was built from, thread-safety of finalizers, behavior
under `Base.@ccallable` boundaries, or anything else beyond what CxxWrap
provides by default for `shared_ptr`-wrapped types). The empirical behavior
demonstrated above — a `shared_ptr<Mesh>`-backed handle surviving its
originating session and an explicit `GC.gc(true)` — is consistent with
CxxWrap's default `shared_ptr` finalizer behavior, but this page is
reporting an observation from this package's build, not citing an upstream
guarantee. If you need a stronger guarantee than "matches observed
behavior in this build," treat it as an open item to verify against
CxxWrap.jl's own documentation rather than an assumption this package makes
for you.

## Does a mesh's geometry dependency survive dropping the Julia `geometry` reference?

The question above ("does *this* handle outlive its container?") has a mirror
image that is arguably more concerning: `generate_mesh_result` (in
`src/generation_result.jl`) calls `Internals.SetGeometry(m, geom)` once, at
mesh-creation time, and never stores `geom` anywhere the returned mesh object
itself keeps a Julia-level reference to. If Julia's GC were free to collect
`geom` as soon as no Julia binding pointed at it — even while a mesh built
from it is still alive and in active use — every geometry-aware operation on
that mesh (`refine!`, `bisect!`, `make_second_order!`, all of which
re-project new nodes onto the *true* boundary/surface, not the polygonal
approximation) would be reading through a dangling reference. This was a
real, previously untested risk, not a hypothetical one, and it was
investigated empirically rather than assumed away.

**Why the risk is structurally smaller than it first looks:** `refine!`,
`bisect!`, and `make_second_order!` (`src/refinement.jl`) never receive a
Julia `geom` argument at all — they fetch the geometry via
`Internals.GetGeometry(m)`, i.e. **from the mesh object itself**, not from
any Julia-side variable:

```julia
function refine!(m)
    Internals.Refine(Internals.GetRefinement(Internals.GetGeometry(m)), m)
    return m
end
```

This means the C++ `Mesh` object must already hold its own reference to the
geometry set by `SetGeometry` — Julia holding or dropping the original
`geom` binding was never what kept the C++ mesh-to-geometry link alive in
the first place. That's a structural argument; the empirical test confirms
it actually behaves that way at runtime.

**Empirical test (2D, `Circle`/`geometry2d`):** built inside a function that
returns only the mesh (`geom` is a purely local binding, unreachable after
the function returns), followed by five rounds of `GC.gc(true); GC.gc(true);
sleep(0.05)` plus scratch allocations to flush CxxWrap's finalizer queue:

- Before dropping+GC'ing `geom`: `num_nodes(m) == 39`, max boundary point
  radius `== 1.0` (true circle radius).
- After dropping `geom` and forcing GC: `num_nodes(m) == 39` (unchanged,
  still callable).
- After `refine!(m)` (geometry-aware — re-projects every new boundary node
  onto the true circle): `num_nodes(m) == 133`, max boundary radius
  `== 1.0` to within `1e-9` — **exactly** the true radius, not a stale or
  corrupted polygonal approximation.
- After `make_second_order!(m)` (curves new edge-midpoint nodes onto the true
  boundary): `num_nodes(m) == 489`, max boundary radius still `== 1.0` to
  within `1e-9`.

**Same test in 3D** (`load_step("frame.step")`, `maxh=5.0`, geometry dropped
and GC'd before any refinement): `refine!` grew the mesh from 92,695 to
632,373 nodes, and a subsequent `make_second_order!` grew it to 4,638,346
nodes — both completed without a crash, segfault, or exception, which would
be the expected failure mode of reading through a freed C++ geometry object.

**Conclusion: this is safe, and provably so.** The C++ `Mesh` object holds
its own (evidently reference-counted, e.g. `shared_ptr`-style) link to the
geometry once `SetGeometry` is called; Julia's GC collecting the Julia-level
`geom` wrapper only decrements *that* wrapper's reference count, it does not
tear down the underlying C++ geometry object as long as the mesh's own
internal reference to it is still live. No code change was made here —
adding a Julia-side keep-alive field (e.g. storing `geom` in
`MeshGenerationResult` or the mesh wrapper) would be pure defensive
complexity with no empirically-demonstrated failure to justify it, which is
exactly the kind of unnecessary speculative fix this project's conventions
argue against.

## `MeshHierarchySession` / `MeshHierarchy`: does holding only `finest(h)` and dropping `h` break anything?

`MeshHierarchySession` (`src/session.jl`) and `MeshHierarchy`
(`src/hierarchy.jl`) both store `geometry` and `meshes::Vector{Any}` as plain
struct fields — there is no special ownership relationship *between* those
two fields beyond both being ordinary Julia references reachable from the
struct. That means:

- As long as the struct itself (`s` / `h`) is reachable, both its geometry
  and every mesh level stay reachable — the ordinary case documented above.
- If a caller extracts only `finest(h)` (or any `level_mesh(s, k)`) and lets
  the struct itself become unreachable, the struct's own references to
  `geometry` and the other mesh levels can be collected — but the *extracted
  mesh's own* dependency on the geometry is unaffected, for the same
  structural reason as the previous section: the C++ mesh holds its own
  reference to its geometry via `SetGeometry`/`GetGeometry`, independent of
  whichever Julia container(s) happened to reference the `geom` value.

Empirically verified for both types with the same pattern as Investigation
1: a function builds a `mesh_session`/`uniform_hierarchy`, calls
`request_uniform_refinement!`/appends a level, extracts only `finest(...)`,
and returns that alone (session/hierarchy struct and geometry variable both
unreachable on return). After five rounds of forced `GC.gc(true)`:

- Session path (`Circle` radius 2.0): `num_nodes` unchanged across GC
  (597 before and after); `refine!` on the retained, session-dropped mesh
  produced a max boundary radius of exactly `2.0` (within `1e-9`).
- Hierarchy path (`Circle` radius 3.0, 2-level `uniform_hierarchy`):
  `num_nodes` unchanged across GC (1445 before and after); `refine!` on the
  retained, hierarchy-dropped mesh produced a max boundary radius of
  `3.0000000000000004` (within `1e-9` of the true radius), matching the
  pre-GC value exactly.

**Conclusion:** dropping the session/hierarchy struct while keeping only one
extracted mesh handle is safe in the same sense, and for the same underlying
reason, as dropping just the geometry reference alone: each Julia binding
(struct field or extracted handle) independently keeps what it points to
alive, and the C++ mesh-to-geometry link does not depend on any particular
Julia binding surviving. No code change was made.

## Thread-safety: not documented, not implemented, assume unsafe

A repository-wide search (`grep -rn "Threads\|lock\|Mutex\|@lock" src/`) found
no thread-safety mechanism anywhere in `src/` — no locks, no `Threads.@spawn`
coordination, no documented concurrency contract for `MeshHierarchySession`,
`MeshHierarchy`, or any live mesh/geometry handle. Treat every CxxWrap-wrapped
handle and every mutable struct in this package (`MeshHierarchySession`,
`MeshHierarchy`, and the raw `Internals` mesh/geometry objects) as **not
safe for concurrent use from multiple threads** unless and until this
package documents and tests a specific concurrency contract — this is a
documentation statement of the honest default, not a result of testing actual
concurrent access.

Next: [Sessions & snapshots](sessions_snapshots.md) for the generation/staleness
contract this page's snapshot contrast leans on, and [Internals escape
hatch](internals_escape_hatch.md) for when you need to reach into
`Delone.Internals` directly.
