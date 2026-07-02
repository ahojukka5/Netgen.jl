# --- spatial node search -----------------------------------------------------
#
# A small `NodeTree` wrapper over `Netgen.Point3dTree`
# (`new_point3dtree`/`Insert`/`GetIntersecting`, already proven in
# test/gprim.jl) for region-based node queries. Pairs naturally with
# `local_sizing.jl`'s `refine_near!`, which currently does an O(n) linear scan
# over all element centroids to find ones within a radius -- a spatial tree
# makes an equivalent point-radius query scale better on large meshes. Wiring
# `refine_near!` itself to use this is a separate, future integration; this
# file only provides the standalone tree.

"""
    NodeTree

Spatial index over a 3D point cloud, wrapping `Netgen.Point3dTree` for
fast axis-aligned-box queries. Node ids returned by [`nodes_near`](@ref) are
1-based column indices into the `points` field (matching
[`points`](@ref)`(mesh)`'s convention when built via [`build_node_tree`](@ref)).

# Fields
- `pmin`, `pmax`: the tree's bounding box (`NTuple{3,Float64}`), padded
  slightly beyond the input point cloud's extent.
- `points`: the indexed points, `3×n` `Matrix{Float64}` (2D input is stored
  with a zero third row).
- `handle`: the underlying `Netgen.Point3dTree` (not part of the public
  data contract -- use [`nodes_near`](@ref) to query it).
"""
struct NodeTree
    pmin::NTuple{3,Float64}
    pmax::NTuple{3,Float64}
    points::Matrix{Float64}
    handle::Any
end

function Base.show(io::IO, t::NodeTree)
    print(io, "NodeTree(", size(t.points, 2), " points, box=", t.pmin, "..", t.pmax, ")")
end

"""
    node_tree(points::AbstractMatrix{<:Real}; margin=nothing) -> NodeTree

Build a [`NodeTree`](@ref) from a `2×n` or `3×n` coordinate matrix, one column
per point (mirrors [`points`](@ref)`(mesh)`'s convention -- 2D input is
embedded at `z = 0`). Node ids used by [`nodes_near`](@ref) are 1-based column
indices into `points`.

`margin` pads the tree's bounding box beyond the point cloud's extent
(absolute units); it defaults to `max(1e-3 * bounding_box_diagonal, 1e-9)` so
points exactly on the cloud's extreme faces are not dropped by
`Netgen.GetIntersecting`'s box test. `points` must have at least one
column.
"""
function node_tree(P::AbstractMatrix{<:Real}; margin::Union{Nothing,Real}=nothing)
    d, n = size(P)
    d in (2, 3) || throw(ArgumentError("node_tree: points must have 2 or 3 rows (got $d)"))
    n > 0 || throw(ArgumentError("node_tree: points must have at least one column"))
    P3 = d == 3 ? Matrix{Float64}(P) :
         vcat(Matrix{Float64}(P), zeros(Float64, 1, n))
    lo = (minimum(view(P3, 1, :)), minimum(view(P3, 2, :)), minimum(view(P3, 3, :)))
    hi = (maximum(view(P3, 1, :)), maximum(view(P3, 2, :)), maximum(view(P3, 3, :)))
    diag = sqrt(sum((hi[i] - lo[i])^2 for i in 1:3))
    pad = margin === nothing ? max(diag * 1e-3, 1e-9) : Float64(margin)
    margin !== nothing && margin < 0 && throw(ArgumentError("node_tree: margin must be >= 0 (got $margin)"))
    pmin = (lo[1] - pad, lo[2] - pad, lo[3] - pad)
    pmax = (hi[1] + pad, hi[2] + pad, hi[3] + pad)
    handle = Netgen.new_point3dtree(_as_point3d(pmin), _as_point3d(pmax))
    for j in 1:n
        Netgen.Insert(handle, _as_point3d((P3[1, j], P3[2, j], P3[3, j])), j)
    end
    return NodeTree(pmin, pmax, P3, handle)
end

"""
    build_node_tree(mesh; margin=nothing) -> NodeTree

Convenience over [`node_tree`](@ref): builds the tree directly from
[`points`](@ref)`(mesh)`, so returned node ids match `mesh`'s 1-based vertex ids.
"""
build_node_tree(m; margin::Union{Nothing,Real}=nothing) = node_tree(points(m); margin=margin)

"""
    nodes_near(tree::NodeTree, point, radius) -> Vector{Int}

1-based node ids within Euclidean `radius` of `point` (length-2 or length-3
real vector/tuple). Queries `Netgen.GetIntersecting` over the axis-aligned
box `point .- radius .. point .+ radius` (`Point3dTree` only supports
box-intersection queries), then filters the box hits down to the exact
Euclidean ball using `tree.points`. `radius` must be `> 0`.
"""
function nodes_near(tree::NodeTree, point, radius::Real)
    radius > 0 || throw(ArgumentError("nodes_near: radius must be > 0 (got $radius)"))
    c = _as_ntuple3(point)
    boxmin = (c[1] - radius, c[2] - radius, c[3] - radius)
    boxmax = (c[1] + radius, c[2] + radius, c[3] + radius)
    hits = Netgen.GetIntersecting(tree.handle, _as_point3d(boxmin), _as_point3d(boxmax))
    r2 = radius^2
    out = Int[]
    for h in hits
        i = Int(h)
        dx = tree.points[1, i] - c[1]
        dy = tree.points[2, i] - c[2]
        dz = tree.points[3, i] - c[3]
        if dx*dx + dy*dy + dz*dz <= r2
            push!(out, i)
        end
    end
    return out
end
