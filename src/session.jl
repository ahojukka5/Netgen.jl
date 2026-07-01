# --- live mesh-hierarchy session --------------------------------------------
# A MeshHierarchySession is the *authoritative*, mutable, geometry-backed live
# handle a consumer keeps during a simulation. It owns the Netgen geometry and a
# stack of live Netgen mesh handles (one per level), a generation counter that is
# bumped on every mutating request, and a free-form metadata dictionary. Copied
# snapshots (see snapshots.jl) are derived views for consumers; the live handles
# here remain authoritative.

"""
    MeshHierarchySession

Live, geometry-backed mesh hierarchy — the authoritative state a consumer keeps
during a simulation.

Fields:
- `geometry` — the shared Netgen/OCC geometry backing every level.
- `meshes::Vector{Any}` — live Netgen mesh handles, one per level, coarsest
  first. `meshes[end]` is the current finest level.
- `generation::Int` — bumped by **every** mutating request. Lets a consumer
  detect that the live hierarchy changed since a snapshot was taken.
- `metadata::Dict{Symbol,Any}` — free-form (e.g. `:maxh`, `:curved_order`).

Semantics:
- it stores **live** Netgen geometry and mesh handles (not copies);
- it can grow during a simulation via the `request_*!` functions;
- it preserves access to every previous level;
- it can hand out copied snapshots on demand ([`level_snapshot`](@ref),
  [`transfer_snapshot`](@ref), [`hierarchy_snapshot`](@ref));
- snapshots are **not** authoritative — the live mesh handles are.

Construct with [`mesh_session`](@ref).
"""
mutable struct MeshHierarchySession
    geometry::Any
    meshes::Vector{Any}
    generation::Int
    metadata::Dict{Symbol,Any}
end

Base.length(s::MeshHierarchySession) = length(s.meshes)
Base.getindex(s::MeshHierarchySession, k::Integer) = s.meshes[k]
Base.lastindex(s::MeshHierarchySession) = length(s.meshes)
Base.iterate(s::MeshHierarchySession, i=1) =
    i > length(s.meshes) ? nothing : (s.meshes[i], i + 1)

"""
    mesh_session(geometry; maxh, kwargs...) -> MeshHierarchySession

Start a live hierarchy with a single coarse mesh of `geometry` (level 1) meshed
at `maxh`. Any extra `kwargs` are stored verbatim in `metadata`. The session's
`generation` starts at `0`. Grow it during the simulation with
[`request_uniform_refinement!`](@ref) / [`request_marked_refinement!`](@ref).
"""
function mesh_session(geometry; options=nothing, maxh::Union{Nothing,Real}=nothing, kwargs...)
    if options === nothing
        maxh === nothing &&
            throw(ArgumentError("mesh_session requires maxh or options=MeshOptions(...)"))
        options = mesh_options(; maxh=maxh, kwargs...)
    end
    res = generate_mesh_result(geometry, options)
    res.success || throw(ErrorException("mesh_session: initial meshing failed: $(res.diagnostics)"))
    m = res.mesh
    meta = Dict{Symbol,Any}(:maxh => options.maxh, :options => options)
    for (k, v) in kwargs
        meta[k] = v
    end
    return MeshHierarchySession(geometry, Any[m], 0, meta)
end

"""
    nlevels(session) -> Int

Number of live mesh levels currently in the session. Distinct from
[`num_levels`](@ref), which reads the raw ngx multigrid level count off a
single mesh object.
"""
nlevels(s::MeshHierarchySession) = length(s.meshes)

"""coarsest(session) / finest(session) -> the coarsest / finest live mesh handle."""
coarsest(s::MeshHierarchySession) = s.meshes[1]
finest(s::MeshHierarchySession) = s.meshes[end]

"""
    level_mesh(session, k) -> live Netgen mesh handle for level `k` (1-based).

Returns the **authoritative live** mesh handle, not a copy. `k` must be in
`1:nlevels(session)`.

!!! warning "Expert-only mutation"
    This is the live handle. Mutating it directly (`refine!`, `bisect!`,
    `make_second_order!`, `Compress`, …) changes the session **without** bumping
    `generation(session)`, so any snapshots taken beforehand silently go stale.
    Prefer the `request_*!` functions for all simulation-time mutation, or
    [`mutate_level_mesh!`](@ref) when you must mutate a level in place but keep
    generation tracking correct. [`unsafe_level_mesh`](@ref) is an explicitly
    named alias of this function.
"""
function level_mesh(s::MeshHierarchySession, k::Integer)
    1 <= k <= nlevels(s) ||
        throw(ArgumentError("level $k out of range 1:$(nlevels(s))"))
    return s.meshes[k]
end

"""
    unsafe_level_mesh(session, k) -> live Netgen mesh handle for level `k`.

Explicitly named alias of [`level_mesh`](@ref). The `unsafe_` prefix flags that
mutating the returned handle bypasses automatic `generation` tracking; reads are
fine. Use [`mutate_level_mesh!`](@ref) or the `request_*!` functions for
generation-safe mutation.
"""
unsafe_level_mesh(s::MeshHierarchySession, k::Integer) = level_mesh(s, k)

"""
    mutate_level_mesh!(f, session, k; bump_generation=true) -> session

Generation-safe in-place mutation of level `k`. Calls `f(level_mesh(session, k))`
for its side effects, then increments `generation(session)` when
`bump_generation` is `true` (the default). Returns the **session** (not `f`'s
result) so it composes with the other `!` functions; capture what you need inside
`f`.

This is the sanctioned way to apply an in-place mesh operation that is not one of
the `request_*!` refinements while keeping snapshot staleness detection correct.
Pass `bump_generation=false` only for a mutation that genuinely does not change
what a snapshot would observe.
"""
function mutate_level_mesh!(f, s::MeshHierarchySession, k::Integer;
                            bump_generation::Bool=true)
    f(level_mesh(s, k))
    bump_generation && (s.generation += 1)
    return s
end

"""geometry(session) -> the shared geometry backing every level."""
geometry(s::MeshHierarchySession) = s.geometry

"""generation(session) -> the mutation counter (bumped by every `request_*!`)."""
generation(s::MeshHierarchySession) = s.generation

# --- refinement requests (mutating; each bumps generation) ------------------

"""
    request_uniform_refinement!(session) -> session

Append a new finest level: a uniformly, geometry-aware refined copy of the
current finest mesh (`Refinement::Refine`). Previous levels are preserved.
Increments `generation(session)`.
"""
function request_uniform_refinement!(s::MeshHierarchySession)
    m = copy_mesh(finest(s))
    refine!(m)
    push!(s.meshes, m)
    s.generation += 1
    return s
end

"""
    request_marked_refinement!(session, marked; onlyonce=false, maxlevel=0) -> session

Append a new finest level by element-wise, geometry-aware **bisection** of a copy
of the current finest mesh. `marked` is indexed by the **current finest level's
volume elements** (`1:Internals.GetNE(finest(session))` for 3D; a `Bool` vector /
predicate from an error indicator). Netgen adds conforming closure refinement as
needed. Previous levels are preserved. Increments `generation(session)`.

`onlyonce`/`maxlevel`/`refine_p`/`refine_hp` are forwarded to `bisect!` /
`BisectionOptions`. Set `refine_hp=true` for marked hp-refinement that appends a
new h-level (Netgen bisection with hp flag); set `refine_p=true` for marked
p-refinement on a new level copy.
"""
function request_marked_refinement!(s::MeshHierarchySession, marked;
                                    onlyonce::Bool=false, maxlevel::Integer=0,
                                    refine_p::Bool=false, refine_hp::Bool=false)
    m = copy_mesh(finest(s))
    Internals.UpdateTopology(m)
    mark_for_refinement!(m, marked)
    bisect!(m; onlyonce=onlyonce, maxlevel=maxlevel,
            refine_p=refine_p, refine_hp=refine_hp)
    push!(s.meshes, m)
    s.generation += 1
    return s
end

"""
    request_second_order!(session; order=2) -> session

**Same-level, snapshot-invalidating in-place curving** (documented choice): curves
the current finest mesh in place — it does **NOT** append a new level. Second-order
curving is a p-type/topology change to the existing h-level (edge-midpoint nodes
projected onto the true geometry), not an h-refinement.

Semantics:

- `nlevels(session)` is unchanged (no new level, no h-refinement transfer);
- the finest level's **node count increases** and `generation(session)` is bumped;
- any snapshot of the finest level taken *before* this call becomes **stale**
  (`snapshot.generation != generation(session)`) — re-snapshot afterward;
- [`transfer_snapshot`](@ref) does **not** describe the added high-order nodes; a
  [`level_snapshot`](@ref) taken afterward reports the Tet4/Tri3 corner
  connectivity, and the extra midpoint nodes appear in `coordinates` but are not
  referenced by `volume_connectivity`;
- this differs from [`request_uniform_refinement!`](@ref) /
  [`request_marked_refinement!`](@ref), which append a new level with a parent map.

Records `metadata[:curved_order]`. Only `order == 2` is supported (via
`Refinement::MakeSecondOrder`); higher-order curving through
`Mesh::BuildCurvedElements` / `Ngx_Mesh::Curve` is deferred, and a call with
`order != 2` throws `ArgumentError`.
"""
function request_second_order!(s::MeshHierarchySession; order::Integer=2)
    order == 2 || throw(ArgumentError(
        "request_second_order! currently supports order=2 only (got $order); " *
        "higher-order curving via BuildCurvedElements/Curve is deferred"))
    make_second_order!(finest(s))
    s.metadata[:curved_order] = Int(order)
    s.generation += 1
    return s
end

# --- hp / p apply on the finest level (in-place; invalidates snapshots) -----

"""
    request_set_element_orders!(session, orders) -> session

Set isotropic polynomial orders on every cell of the **current finest** mesh in
place (`set_element_orders!`). Does not change topology. Bumps
`generation(session)`; re-snapshot afterward.
"""
function request_set_element_orders!(s::MeshHierarchySession,
                                     orders::AbstractVector{<:Integer})
    set_element_orders!(finest(s), orders)
    s.generation += 1
    return s
end

"""
    request_set_element_order!(session, enr, order) -> session

Set order of a single cell on the finest mesh in place. Bumps `generation(session)`.
"""
function request_set_element_order!(s::MeshHierarchySession, enr::Integer,
                                    order::Integer)
    set_element_order!(finest(s), enr, order)
    s.generation += 1
    return s
end

"""
    request_marked_p_refinement!(session, marked; onlyonce=false) -> session

**In-place** marked p-refinement on the finest level via `Ngx_Mesh::Refine`
(`NG_REFINE_P`). Does **not** append a level. `marked` indexes finest-level cells.
Invalidates snapshots of the finest level. Bumps `generation(session)`.
"""
function request_marked_p_refinement!(s::MeshHierarchySession, marked;
                                      onlyonce::Bool=false)
    m = finest(s)
    Internals.UpdateTopology(m)
    mark_for_ngx_refinement!(m, marked)
    ngx_refine!(m; reftype=NG_REFINE_P, onlyonce=onlyonce)
    s.generation += 1
    return s
end

"""
    request_marked_hp_refinement!(session, marked; onlyonce=false) -> session

**In-place** marked hp-refinement on the finest level via `Ngx_Mesh::Refine`
(`NG_REFINE_HP`). Does **not** append a level. Invalidates finest-level snapshots.
"""
function request_marked_hp_refinement!(s::MeshHierarchySession, marked;
                                        onlyonce::Bool=false)
    m = finest(s)
    Internals.UpdateTopology(m)
    mark_for_ngx_refinement!(m, marked)
    ngx_refine!(m; reftype=NG_REFINE_HP, onlyonce=onlyonce)
    s.generation += 1
    return s
end

"""
    request_hp_refine!(session; levels=1, parameter=0.125,
                       setorders=true, ref_level=false) -> session

Global hp split on the finest mesh in place (`Ngx_Mesh::HPRefinement`). Does not
append a level. Bumps `generation(session)`.
"""
function request_hp_refine!(s::MeshHierarchySession;
                            levels::Integer=1, parameter::Real=0.125,
                            setorders::Bool=true, ref_level::Bool=false)
    hp_refine!(finest(s); levels=levels, parameter=parameter,
               setorders=setorders, ref_level=ref_level)
    s.generation += 1
    return s
end

"""
    request_split_alfeld!(session) -> session

Alfeld hp split on the finest mesh in place (`Ngx_Mesh::SplitAlfeld`). Bumps
`generation(session)`.
"""
function request_split_alfeld!(s::MeshHierarchySession)
    split_alfeld!(finest(s))
    s.generation += 1
    return s
end
