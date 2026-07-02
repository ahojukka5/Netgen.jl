# --- Delone <-> GeometryBasics package extension -----------------------------
# Loaded automatically (Base.get_extension) when the host session has both
# Delone and GeometryBasics loaded. See Project.toml [weakdeps]/[extensions].
# Requires Julia >= 1.9.
#
# Only Delone's dependency-free, plain-array snapshot types
# (`MeshLevelSnapshot`, `MeshHierarchySnapshot` from src/snapshots.jl) are
# supported here, for the same reason DeloneMakieExt only supports them: live
# mesh handles returned by `generate_mesh`/`mesh_session` are
# `CxxWrap.StdLib.SharedPtrAllocated{Delone.Internals.Mesh}` — a raw,
# unexported `Internals` C++ handle type, not a stable Delone-owned type to
# dispatch a public bridge on (and AGENTS.md explicitly says public code must
# never leak raw `Internals` handles). Take a snapshot first
# (`level_snapshot`/`hierarchy_snapshot`) and convert that instead.
#
# This is the bridge DeloneMakieExt's header comment deliberately deferred:
# "No GeometryBasics types are constructed here (that bridge is deferred to a
# future DeloneGeometryBasicsExt)". Makie's own `mesh` recipe accepts plain
# coordinate/face matrices directly, so it never needed this; other
# GeometryBasics-consuming tooling (mesh export/interchange, other plotting
# backends, geometry processing packages) wants an actual `GeometryBasics.Mesh`
# instead.
module DeloneGeometryBasicsExt

using Delone
using Delone: MeshLevelSnapshot, MeshHierarchySnapshot
using GeometryBasics

# --- shared helpers -----------------------------------------------------------

# GeometryBasics.Mesh wants a `Vector{Point{Dim,T}}` and a `Vector{<:AbstractFace}`
# (e.g. `Vector{TriangleFace{Int32}}`), NOT raw matrices — unlike Makie's `mesh`
# recipe, which accepts plain coordinate/face matrices directly (see
# DeloneMakieExt's `_mesh_verts_faces`). Delone stores `Dim x Npoints`
# coordinates and `nv x Ncells` connectivity (one-based); build points/faces by
# iterating columns rather than via `GeometryBasics.connect`, which
# byte-reinterprets when the input integer eltype doesn't already match the
# target face's index eltype (e.g. reinterpreting `Vector{Int32}` as
# `TriangleFace{Int}` silently corrupts indices) — column construction avoids
# that pitfall and keeps Delone's native `Int32` connectivity eltype end to end.

"""
    _points(coords::AbstractMatrix{T}) where {T} -> Vector{Point{Dim,T}}

Convert a `Dim x Npoints` coordinate matrix (Delone's native layout) into a
`GeometryBasics`-native `Vector{Point{Dim,T}}`.
"""
function _points(coords::AbstractMatrix{T}) where {T}
    dim = size(coords, 1)
    return [Point{dim,T}(c) for c in eachcol(coords)]
end

"""
    _triangle_faces(conn::AbstractMatrix{I}) where {I<:Integer} -> Vector{TriangleFace{I}}

Convert a `3 x Ncells` one-based triangle connectivity matrix (Delone's native
layout for both `MeshLevelSnapshot{3}.surface_connectivity` and
`MeshLevelSnapshot{2}.volume_connectivity`) into a
`Vector{TriangleFace{I}}`, preserving the input integer eltype.
"""
function _triangle_faces(conn::AbstractMatrix{I}) where {I<:Integer}
    size(conn, 1) == 3 || throw(ArgumentError(
        "expected a 3 x Ncells triangle connectivity matrix, got size $(size(conn))"))
    return [TriangleFace{I}(f) for f in eachcol(conn)]
end

"""
    GeometryBasics.Mesh(m::MeshLevelSnapshot{3}) -> GeometryBasics.Mesh

Boundary surface triangulation of a 3D snapshot: points come from
`m.coordinates` and faces from `m.surface_connectivity` (already one-based
triangles). Tetrahedra themselves are not a `GeometryBasics.Mesh` face type
this bridge targets — the boundary facets are what downstream consumers
(rendering, export, geometry processing) actually want, matching
`DeloneMakieExt`'s boundary-triangulation convention.
"""
function GeometryBasics.Mesh(m::MeshLevelSnapshot{3})
    return GeometryBasics.Mesh(_points(m.coordinates), _triangle_faces(m.surface_connectivity))
end

"""
    GeometryBasics.Mesh(m::MeshLevelSnapshot{2}) -> GeometryBasics.Mesh

Flat domain triangulation of a 2D snapshot: points come from `m.coordinates`
(native 2D `Point2`, not lifted to `z = 0`) and faces from
`m.volume_connectivity` (already one-based triangles).
"""
function GeometryBasics.Mesh(m::MeshLevelSnapshot{2})
    return GeometryBasics.Mesh(_points(m.coordinates), _triangle_faces(m.volume_connectivity))
end

function GeometryBasics.Mesh(m::MeshLevelSnapshot{Dim}) where {Dim}
    throw(ArgumentError(
        "GeometryBasics.Mesh(::MeshLevelSnapshot) only supports Dim in (2, 3); got Dim=$Dim"))
end

"""
    GeometryBasics.Mesh(h::MeshHierarchySnapshot; level::Integer=length(h.levels))

Convert a single level of a mesh hierarchy snapshot (default: the finest
level). Delegates to [`GeometryBasics.Mesh(::MeshLevelSnapshot)`](@ref).
"""
function GeometryBasics.Mesh(h::MeshHierarchySnapshot; level::Integer=length(h.levels))
    1 <= level <= length(h.levels) || throw(ArgumentError(
        "level $level out of range 1:$(length(h.levels))"))
    return GeometryBasics.Mesh(h.levels[level])
end

end # module DeloneGeometryBasicsExt
