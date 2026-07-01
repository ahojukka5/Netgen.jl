# --- multigrid hierarchy ----------------------------------------------------
"""
    num_levels(mesh) -> Int

Raw ngx accessor: how many multigrid levels Netgen's C++ `Ngx_Mesh` already
knows about for this single mesh object (e.g. from prior in-place `refine!`
calls). This is **not** the same as [`nlevels`](@ref), which counts the
logical levels of a [`MeshHierarchy`](@ref) or `MeshHierarchySession` built by
this package.
"""
num_levels(m) = Internals.GetNLevels(Internals.Ngx_Mesh(m))

"""
    level_nvertices(mesh, level) -> Int

Number of vertices Netgen's C++ `Ngx_Mesh` reports for the given 0-based ngx
`level` of this single mesh object (raw ngx accessor, see [`num_levels`](@ref)).
"""
level_nvertices(m, level::Integer) =
    Internals.GetNVLevel(Internals.Ngx_Mesh(m), Int(level))

_ngx_to_1based(v::Integer) = Int32(v) + Int32(1)

"""
    parent_nodes(mesh) -> 2×nnodes Matrix{Int32}

For each 1-based vertex, its two coarse-level parent vertices. `(0, 0)` marks an
inherited coarse vertex.
"""
function parent_nodes(m)
    nm = Internals.Ngx_Mesh(m)
    np = Internals.GetNP(m)
    P = Matrix{Int32}(undef, 2, np)
    buf = zeros(Cint, 2)
    for i in 1:np
        Internals.GetParentNodes(nm, i - 1, buf)
        P[1, i] = _ngx_to_1based(buf[1]); P[2, i] = _ngx_to_1based(buf[2])
    end
    return P
end

"""parent_elements(mesh) -> Vector{Int32}, 1-based parent per volume cell (`0` = none)."""
function parent_elements(m)
    nm = Internals.Ngx_Mesh(m)
    ne = Internals.GetNE(m)
    return Int32[_ngx_to_1based(Internals.GetParentElement(nm, i - 1)) for i in 1:ne]
end

"""parent_surface_elements(mesh) -> Vector{Int32}, 1-based parent per surface facet."""
function parent_surface_elements(m)
    nm = Internals.Ngx_Mesh(m)
    nse = Internals.GetNSE(m)
    return Int32[_ngx_to_1based(Internals.GetParentSElement(nm, i - 1)) for i in 1:nse]
end

"""copy_mesh(mesh) -> deep copy with no refinement history."""
function copy_mesh(src)
    m = Internals.new_mesh()
    Internals.assign(m, src)
    return m
end

"""
    MeshHierarchy

A growable stack of nested meshes sharing one geometry. Each level is a distinct
mesh obtained by refining a copy of the previous finest level.
"""
struct MeshHierarchy
    geometry::Any
    meshes::Vector{Any}
end

Base.length(h::MeshHierarchy) = length(h.meshes)
Base.getindex(h::MeshHierarchy, k::Integer) = h.meshes[k]
Base.lastindex(h::MeshHierarchy) = length(h.meshes)
Base.iterate(h::MeshHierarchy, s=1) =
    s > length(h.meshes) ? nothing : (h.meshes[s], s + 1)

"""
    nlevels(h::MeshHierarchy) -> Int

Number of levels tracked by this `MeshHierarchy` (the `MeshHierarchySession`
method lives in `session.jl`). Distinct from [`num_levels`](@ref), which reads
the raw ngx multigrid level count off a single mesh object.
"""
nlevels(h::MeshHierarchy) = length(h.meshes)

"""coarsest(h::MeshHierarchy) -> mesh handle at level 1."""
coarsest(h::MeshHierarchy) = h.meshes[1]

"""finest(h::MeshHierarchy) -> mesh handle at the current last level."""
finest(h::MeshHierarchy) = h.meshes[end]

"""geometry(h::MeshHierarchy) -> the geometry shared by every level of `h`."""
geometry(h::MeshHierarchy) = h.geometry

Base.@deprecate coarse_hierarchy(geom; maxh::Real) mesh_hierarchy(geom; maxh=maxh)

"""refine_uniform!(h::MeshHierarchy) -> h with a new uniformly-refined level appended."""
function refine_uniform!(h::MeshHierarchy)
    m = copy_mesh(finest(h))
    refine!(m)
    push!(h.meshes, m)
    return h
end

"""refine_marked!(h::MeshHierarchy, marked) -> h with a new adaptively-bisected level appended."""
function refine_marked!(h::MeshHierarchy, marked)
    m = copy_mesh(finest(h))
    update_topology!(m)
    mark_for_refinement!(m, marked)
    bisect!(m)
    push!(h.meshes, m)
    return h
end

"""
    uniform_hierarchy(geometry; maxh, levels) -> MeshHierarchy

Build all `levels` uniformly-refined levels up front, starting from a coarse
mesh at `maxh`. See also [`mesh_hierarchy`](@ref).
"""
function uniform_hierarchy(geom; maxh::Real, levels::Integer)
    levels >= 1 || throw(ArgumentError("levels must be ≥ 1 (got $levels)"))
    h = MeshHierarchy(geom, Any[generate_mesh(geom; maxh=maxh)])
    for _ in 2:levels
        refine_uniform!(h)
    end
    return h
end

"""
    prolongation(h::MeshHierarchy, k) -> 2×np Matrix{Int32}

Coarse→fine parent-node mapping from level `k - 1` to level `k` (`k ≥ 2`),
i.e. [`parent_nodes`](@ref)`(h[k])`.
"""
function prolongation(h::MeshHierarchy, k::Integer)
    k >= 2 || throw(ArgumentError("prolongation is defined for levels k ≥ 2 (got $k)"))
    return parent_nodes(h.meshes[k])
end
