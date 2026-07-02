# --- local mesh-size control -------------------------------------------------
#
# Julian front door over Netgen's local-h machinery (`Netgen.LocalH`,
# `Mesh::GetH/SetGlobalH/SetMinimalH`). See the module docstring below for
# what is and is not verified to influence `generate_mesh` in this build.
#
# VERIFIED (via standalone probing, see test/local_sizing.jl):
#   - `Netgen.new_localh(pmin, pmax, globalh)` / `SetH` / `GetH` / `GetMinH`
#     on a standalone `LocalH` field: fully works, independent of any mesh.
#   - `Netgen.GetH(mesh, point)`, `SetGlobalH(mesh, h)`, `SetMinimalH(mesh, h)`
#     on an existing mesh: fully works (already exercised in test/mesh2.jl).
#   - `Netgen.RestrictLocalH(mesh, point, h)` and
#     `Netgen.SetLocalH(mesh, localh)`: the call succeeds and immediately
#     updates `GetH(mesh, point)` to reflect the requested size — but this
#     package's `GenerateMesh(geometry, mesh, meshingparameters)` entry point
#     (the only OCC-geometry meshing path wrapped here) recomputes its own
#     local-h field internally during surface meshing and DISCARDS any
#     restriction applied beforehand. The identical behavior was confirmed for
#     `Netgen.LoadLocalMeshSize` (a `.msz` file loader — internally calls
#     `RestrictLocalH`). None of these three actually make `generate_mesh`
#     produce smaller elements near a point in this build.
#   - `Netgen.OptimizeVolume` (a post-generation quality pass) does read the
#     mesh's local-h field, but it only removes/flips elements to improve
#     quality — it cannot ADD elements to reach a finer local target, so it is
#     not a usable substitute for real local refinement either.
#
# NOT USABLE for pre-generation local sizing (documented, not silently
# dropped): `RestrictLocalH`, `RestrictLocalHLine`, `SetLocalH`,
# `LoadLocalMeshSize` as *inputs to `generate_mesh`*. They remain useful for
# introspecting/annotating an existing size field (hence still wrapped below
# for `LocalSizeField` and for post-hoc `mesh_h_at`/`set_global_h!`/
# `set_minimal_h!`), and for future work if a lower-level
# surface-mesh-then-volume-mesh entry point is ever wrapped.
#
# WORKING mechanism for "mesh finer near a point" end-to-end: generate a
# coarse mesh, then geometrically mark elements near the target point(s) and
# run the existing, already-proven `mark_for_refinement!` / `bisect!` pipeline
# (see refinement.jl). `MeshOptions.local_size` below is wired to exactly this
# path in `to_meshing_parameters`/a post-generation hook, not to
# `RestrictLocalH`.
#
# 2D vs 3D use different marked-refinement backends (verified empirically,
# see test/local_sizing.jl):
#   - In 3D, `mark_for_refinement!` + `bisect!` has a real, measurable
#     localizing effect: an apples-to-apples comparison (identical base mesh,
#     marked vs. unmarked, same query location) showed meaningfully shorter
#     edges and several times more elements near the marked region.
#   - In 2D, that same pipeline does NOT localize — `bisect!` on a 2D mesh
#     refines fully uniformly regardless of `mark_for_refinement!` in this
#     build (an apples-to-apples comparison showed zero difference between
#     marking a subset of triangles and marking nothing at all). The
#     `mark_for_ngx_refinement!`/`ngx_refine!` pair (see hp.jl), by contrast,
#     DOES localize correctly in 2D: verified with an unmarked control pass
#     (zero elements marked -> mesh unchanged, 56 -> 56 cells on a disk
#     fixture) and a marked pass (3 elements marked near a boundary point ->
#     56 -> 76 cells, with the extra density entirely concentrated near the
#     marked point and zero extra elements near an unmarked point on the
#     opposite side) — plus geometry-aware boundary projection intact (new
#     boundary nodes still land exactly on the true circle). `refine_near!`
#     therefore dispatches on dimension: 3D uses `mark_for_refinement!`/
#     `bisect!`, 2D uses `mark_for_ngx_refinement!`/`ngx_refine!`.

# --- standalone size field ---------------------------------------------------

"""
    LocalSizeField

A standalone spatial mesh-size field, independent of any mesh. Wraps
`Netgen.new_localh` (a bounding box + a default/global size) plus any
number of point-wise overrides applied via `Netgen.SetH`.

Useful for building a size specification before a mesh exists, or for
querying/visualizing a target sizing independent of the mesher.

# Fields
- `pmin`, `pmax`: the bounding box, `NTuple{3,Float64}`
- `global_h`: the default/background mesh size
- `refine_at`: the `(point, h)` overrides applied, in application order
- `handle`: the underlying `Netgen.LocalH` object (not part of the public
  data contract — use [`field_h`](@ref)/[`field_min_h`](@ref) to query it)
"""
struct LocalSizeField
    pmin::NTuple{3,Float64}
    pmax::NTuple{3,Float64}
    global_h::Float64
    refine_at::Vector{Tuple{NTuple{3,Float64},Float64}}
    handle::Any
end

function Base.show(io::IO, f::LocalSizeField)
    print(io, "LocalSizeField(global_h=", f.global_h,
          ", box=", f.pmin, "..", f.pmax,
          ", refine_at=", length(f.refine_at), " points)")
end

_as_point3d(p::NTuple{3,<:Real}) = Netgen.Point3d(Float64(p[1]), Float64(p[2]), Float64(p[3]))
_as_point3d(p::AbstractVector{<:Real}) =
    length(p) == 3 ? Netgen.Point3d(Float64(p[1]), Float64(p[2]), Float64(p[3])) :
    length(p) == 2 ? Netgen.Point3d(Float64(p[1]), Float64(p[2]), 0.0) :
    throw(ArgumentError("point must have length 2 or 3 (got $(length(p)))"))
_as_point3d(p::Tuple{<:Real,<:Real}) = Netgen.Point3d(Float64(p[1]), Float64(p[2]), 0.0)
_as_ntuple3(p) = length(p) == 3 ? (Float64(p[1]), Float64(p[2]), Float64(p[3])) :
                 length(p) == 2 ? (Float64(p[1]), Float64(p[2]), 0.0) :
                 throw(ArgumentError("point must have length 2 or 3 (got $(length(p)))"))

"""
    local_size_field(pmin, pmax, global_h; refine_at=[]) -> LocalSizeField

Build a standalone [`LocalSizeField`](@ref) over the box `pmin..pmax` with
background size `global_h`, applying `refine_at` as a list of `(point, h)`
overrides (each `point` a length-2 or length-3 real vector/tuple; `h > 0`).

`global_h` must be `> 0`. Overrides are applied in order via `Netgen.SetH`;
later overrides at the same location win.
"""
function local_size_field(pmin, pmax, global_h::Real; refine_at=Tuple{Any,Float64}[])
    global_h > 0 || throw(ArgumentError("local_size_field: global_h must be > 0 (got $global_h)"))
    handle = Netgen.new_localh(_as_point3d(pmin), _as_point3d(pmax), Float64(global_h))
    applied = Tuple{NTuple{3,Float64},Float64}[]
    for (pt, h) in refine_at
        h > 0 || throw(ArgumentError("local_size_field: refine_at size must be > 0 (got $h at $pt)"))
        Netgen.SetH(handle, _as_point3d(pt), Float64(h))
        push!(applied, (_as_ntuple3(pt), Float64(h)))
    end
    return LocalSizeField(_as_ntuple3(pmin), _as_ntuple3(pmax), Float64(global_h), applied, handle)
end

"""
    restrict_h!(field::LocalSizeField, point, h) -> field

Override the mesh size at `point` to `h` (`Netgen.SetH`). `h` must be `> 0`.
"""
function restrict_h!(f::LocalSizeField, point, h::Real)
    h > 0 || throw(ArgumentError("restrict_h!: h must be > 0 (got $h)"))
    Netgen.SetH(f.handle, _as_point3d(point), Float64(h))
    push!(f.refine_at, (_as_ntuple3(point), Float64(h)))
    return f
end

"""
    field_h(field::LocalSizeField, point) -> Float64

Query the current size at `point` (`Netgen.GetH`).
"""
field_h(f::LocalSizeField, point) = Netgen.GetH(f.handle, _as_point3d(point))

"""
    field_min_h(field::LocalSizeField, pmin, pmax) -> Float64

Minimum size over the box `pmin..pmax` (`Netgen.GetMinH`).
"""
field_min_h(f::LocalSizeField, pmin, pmax) =
    Netgen.GetMinH(f.handle, _as_point3d(pmin), _as_point3d(pmax))

# --- mesh-level h-field operations -------------------------------------------

"""
    restrict_h!(mesh, point, h) -> mesh

Best-effort local size annotation on an existing `mesh` (`Netgen.RestrictLocalH`).
Immediately visible to [`mesh_h_at`](@ref) queries and to post-generation passes
that consult the mesh's local-h field (e.g. `optimize_volume!`), but — in this
build — does **not** retroactively change element sizes produced by
[`generate_mesh`](@ref), since `GenerateMesh` recomputes its own local-h field
during surface meshing. To actually get finer elements near a point, use
`MeshOptions(local_size=...)` (mark-and-bisect refinement) or call
[`refine_near!`](@ref) after generation.
"""
function restrict_h!(m, point, h::Real)
    h > 0 || throw(ArgumentError("restrict_h!: h must be > 0 (got $h)"))
    Netgen.RestrictLocalH(m, _as_point3d(point), Float64(h))
    return m
end

"""
    restrict_h_at!(mesh, points::AbstractMatrix, hs::AbstractVector) -> mesh

Bulk convenience over [`restrict_h!`](@ref): `points` is `2×n` or `3×n` (one
column per point), `hs` is length `n`. Throws `ArgumentError` on shape mismatch.

Same caveat as [`restrict_h!`](@ref): in this build, does **not**
retroactively change element sizes produced by [`generate_mesh`](@ref) — use
`MeshOptions(local_size=...)` or [`refine_near!`](@ref) after generation for
that.
"""
function restrict_h_at!(m, points::AbstractMatrix{<:Real}, hs::AbstractVector{<:Real})
    d, n = size(points)
    d in (2, 3) || throw(ArgumentError("restrict_h_at!: points must have 2 or 3 rows (got $d)"))
    length(hs) == n ||
        throw(ArgumentError("restrict_h_at!: hs length ($(length(hs))) must match number of points ($n)"))
    for j in 1:n
        restrict_h!(m, view(points, :, j), hs[j])
    end
    return m
end

"""
    mesh_h_at(mesh, point) -> Float64

Current local-h field value at `point` (`Netgen.GetH`). For a specific
existing mesh vertex by 1-based index, see [`mesh_h_at_point`](@ref).
"""
mesh_h_at(m, point) = Netgen.GetH(m, _as_point3d(point))

"""
    set_global_h!(mesh, h) -> mesh

Set the mesh's global/background target size (`Netgen.SetGlobalH`). `h` must
be `> 0`. Same caveat as [`restrict_h!`](@ref): in this build, does **not**
retroactively change element sizes produced by [`generate_mesh`](@ref) — pass
`maxh` to `generate_mesh`/`MeshOptions` for that instead.
"""
function set_global_h!(m, h::Real)
    h > 0 || throw(ArgumentError("set_global_h!: h must be > 0 (got $h)"))
    Netgen.SetGlobalH(m, Float64(h))
    return m
end

"""
    set_minimal_h!(mesh, h) -> mesh

Set the mesh's minimum allowed size (`Netgen.SetMinimalH`). `h` must be `> 0`.
Same caveat as [`restrict_h!`](@ref): in this build, does **not** retroactively
change element sizes produced by [`generate_mesh`](@ref) — pass `minh` to
`generate_mesh`/`MeshOptions` for that instead.
"""
function set_minimal_h!(m, h::Real)
    h > 0 || throw(ArgumentError("set_minimal_h!: h must be > 0 (got $h)"))
    Netgen.SetMinimalH(m, Float64(h))
    return m
end

# --- the mechanism that actually works: mark + refine near a point ---------

# Mark-and-refine, dispatching on dimension to the backend that actually
# localizes in that dimension (see the module notes above).
function _mark_and_refine!(m, d::Integer, marked)
    if d == 3
        mark_for_refinement!(m, marked)
        bisect!(m)
    else
        mark_for_ngx_refinement!(m, marked)
        ngx_refine!(m; reftype=NG_REFINE_H)
    end
    return m
end

"""
    refine_near!(mesh, point; radius, levels=1) -> mesh

Locally refine `mesh` near `point` by marking every element whose centroid
lies within `radius` of `point` and running a marked-refinement pass,
repeated `levels` times (each pass roughly halves local element size). This
is the mechanism [`MeshOptions`](@ref)'s `local_size` option is built on,
since Netgen's `RestrictLocalH`/`SetLocalH` do not feed back into this
package's `generate_mesh` entry point (see the module notes in
`local_sizing.jl`).

`radius` must be `> 0`; `levels` must be `>= 1`. Each additional level roughly
doubles element count *within* `radius`, so `levels >= 3` can blow up total
element count quickly on a large mesh; `levels=2` was observed (on curved/thin
geometry) to occasionally produce a handful of inverted elements that Netgen's
`CheckVolumeMesh` flags as warnings without failing — check `validate(mesh)`
after aggressive local refinement.

# Backend (dimension-dependent, verified empirically — see `local_sizing.jl`'s
module notes for the numbers)

- **3D**: [`mark_for_refinement!`](@ref) + [`bisect!`](@ref) — has a real,
  measurable localizing effect on top of `bisect!`'s mostly-uniform base
  refinement.
- **2D**: [`mark_for_ngx_refinement!`](@ref) + [`ngx_refine!`](@ref) (not
  `bisect!`, which refines 2D meshes uniformly regardless of marking in this
  build) — genuinely localizes: an unmarked control pass leaves the mesh
  unchanged, and a marked pass grows element count only near the marked
  elements, with geometry-aware boundary projection intact.
"""
function refine_near!(m, point; radius::Real, levels::Integer=1)
    radius > 0 || throw(ArgumentError("refine_near!: radius must be > 0 (got $radius)"))
    levels >= 1 || throw(ArgumentError("refine_near!: levels must be >= 1 (got $levels)"))
    center = collect(_as_ntuple3(point))
    d = mesh_dimension(m)
    for _ in 1:levels
        X = points(m)
        T = d == 3 ? tetrahedra(m) : triangles2d(m)
        ne = size(T, 2)
        marked = falses(ne)
        nv = size(T, 1)
        for e in 1:ne
            c = sum(X[:, T[i, e]] for i in 1:nv) ./ nv
            marked[e] = sqrt(sum((c .- center) .^ 2)) <= radius
        end
        _mark_and_refine!(m, d, marked)
    end
    return m
end

"""
    refine_near!(mesh, points::AbstractVector; radius, levels=1) -> mesh

Refine near each of several points in a single pass per level (elements within
`radius` of *any* listed point are marked together, rather than iterating
[`refine_near!`](@ref) point-by-point). See the single-point [`refine_near!`](@ref)
docstring for the dimension-dependent backend.
"""
function refine_near!(m, pts::AbstractVector; radius::Real, levels::Integer=1)
    radius > 0 || throw(ArgumentError("refine_near!: radius must be > 0 (got $radius)"))
    levels >= 1 || throw(ArgumentError("refine_near!: levels must be >= 1 (got $levels)"))
    centers = [collect(_as_ntuple3(p)) for p in pts]
    d = mesh_dimension(m)
    for _ in 1:levels
        X = points(m)
        T = d == 3 ? tetrahedra(m) : triangles2d(m)
        ne = size(T, 2)
        nv = size(T, 1)
        marked = falses(ne)
        for e in 1:ne
            c = sum(X[:, T[i, e]] for i in 1:nv) ./ nv
            marked[e] = any(center -> sqrt(sum((c .- center) .^ 2)) <= radius, centers)
        end
        _mark_and_refine!(m, d, marked)
    end
    return m
end
