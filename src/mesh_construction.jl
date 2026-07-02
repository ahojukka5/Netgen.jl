# --- building a mesh from plain point/connectivity arrays -------------------
# Mesh data flows *out* of Delone (points, tetrahedra, snapshots, VTK export)
# via the extraction helpers in extraction.jl/tags.jl, but there is otherwise
# no way to hand Delone a mesh built by an external tool (Gmsh, Triangle, a
# solver's own remesher) as plain arrays. `mesh_from_arrays` closes that gap.
#
# Historical note: `mesh_from_arrays` was originally built via a `.vol` file
# round-trip (see below) because at the time `Netgen.Element`/`Element2d`
# had no registered constructor and no `PNum` setter — `AddVolumeElement`/
# `AddSurfaceElement`/`SetVolumeElement`/`SetSurfaceElement` were reachable
# but structurally unusable. `NetgenCxxWrap_jll` commit `9e4860e` fixed this
# (`Element(anp)`/`Element2d(anp)` constructors + `SetPNum`/`SetIndex`), so
# direct per-element construction is now also possible — see
# `add_volume_element!`/`add_surface_element!` below for the incremental,
# one-element-at-a-time counterpart to this file's whole-mesh
# `mesh_from_arrays`. The `.vol` round-trip approach is kept for
# `mesh_from_arrays` itself (it's verified, fast, and simpler for building an
# entire mesh from arrays at once) rather than rewritten to loop over the new
# per-element calls.
#
# `Mesh::Save`/`Mesh::Load`, by contrast, are wrapped taking plain file paths
# (see `save_mesh`/`load_mesh` in mesh.jl) and round-trip through Netgen's
# native `.vol` ASCII mesh format. That format is not gated behind the missing
# Element constructor, so this module hand-writes a minimal `.vol` file from
# the input arrays and loads it back via the same `Netgen.new_mesh()` +
# `Netgen.Load` path `load_mesh` already uses.
#
# The `.vol` grammar below was reverse-engineered by reading the real
# `Mesh::Save`/`Mesh::Load` implementation in a sibling Netgen source checkout
# (`libsrc/meshing/meshclass.cpp`), not guessed from partial docs:
#
#   mesh3d
#   dimension
#   <3>
#   geomtype
#   <0>
#
#   surfaceelements
#   <nse>
#   <surfnr> <bcnr> <domin> <domout> <np=3> <p1> <p2> <p3>   (one line per facet)
#   ...
#
#   volumeelements
#   <ne>
#   <matnr> <np=4> <p1> <p2> <p3> <p4>                        (one line per cell)
#   ...
#
#   points
#   <np>
#   <x> <y> <z>                                               (one line per node)
#   ...
#
#   endmesh
#
# Key details confirmed by reading the parser (`Mesh::Load(istream&)`):
#   - Sections are read as a flat token stream (`while (infile.good() &&
#     !endmesh) { infile >> str; ... }`), so section order is not load-bearing
#     and blank lines/comments between sections are harmless; `endmesh` (or
#     EOF) just stops the scan.
#   - `volumeelements`' leading integer directly becomes the element's region
#     id (`Element::GetIndex`), i.e. exactly what `cell_regions` reads back.
#   - `surfaceelements`' `(surfnr, bcnr, domin, domout)` 4-tuple is looked up
#     in the face-descriptor table; the first row with a new combination
#     allocates a new `FaceDescriptor` (`AddFaceDescriptor` appends and returns
#     `facedecoding.Size()`, i.e. strict 1-based row order), and that
#     allocation-order index is exactly what `boundary_regions` reads back via
#     `Element2d::GetIndex`. To reproduce the *exact* original region ids (not
#     just their grouping), we emit an explicit `facedescriptors` section
#     up front, one row per region id `1:maximum(boundary_regions)` in order,
#     so `AddFaceDescriptor` allocates them at exactly those indices before any
#     `surfaceelements` row is scanned.
#   - `Mesh::GetNDomains()` (used by `material_names`/`set_material_name!`) is
#     derived from face descriptors' `domin`/`domout` fields, **not** from the
#     volume elements' region ids — so `domin` must be populated for
#     `material_names`/`set_material_name!` to see any domains at all. We
#     derive `domin` for each supplied boundary triangle by finding the
#     tetrahedron in `tets` that owns that face (matching Netgen's own
#     convention of "domain in = the region touching the face"); `domout` is
#     always written as `0` (exterior).
#
# Verified round-trip: a hand-written single-tetrahedron `.vol` file (4
# points, 1 volume element, its 4 boundary triangles) loaded via
# `Netgen.new_mesh()` + `Netgen.Load` reported the expected
# `GetNP`/`GetNE`/`GetNSE`/`GetNDomains`/`GetNFD`, and `points`/`tetrahedra`/
# `surface_triangles`/`cell_regions`/`boundary_regions` extracted the exact
# input data back out before this general writer was implemented.

"""
    mesh_from_arrays(points, tets; surface=nothing, cell_regions=nothing,
                      boundary_regions=nothing, material_names=nothing,
                      boundary_names=nothing) -> mesh

Build a 3D Netgen mesh from plain point/connectivity arrays — e.g. a mesh
produced by an external tool (Gmsh, Triangle, a solver's own remesher) — the
inverse of [`points`](@ref)/[`tetrahedra`](@ref)/[`surface_triangles`](@ref)/
[`cell_regions`](@ref)/[`boundary_regions`](@ref).

Arguments:
- `points`: `3×np` node coordinates.
- `tets`: `4×ne` 1-based node ids (matching [`tetrahedra`](@ref)'s convention).
- `surface`: optional `3×nse` 1-based boundary-triangle connectivity. If
  omitted, no boundary triangles are written at all
  (`num_boundary_facets(mesh) == 0`) — a real limitation, since some
  downstream Netgen operations (e.g. `check_mesh`'s
  `CheckConsistentBoundary`) expect boundary data.
- `cell_regions`: optional per-tet 1-based region id (length `size(tets, 2)`);
  defaults to `1` for every cell.
- `boundary_regions`: optional per-surface-triangle 1-based region id (length
  `size(surface, 2)`); defaults to `1` for every triangle. Requires `surface`.
- `material_names`, `boundary_names`: optional `Dict{<:Integer,<:AbstractString}`
  applied *after* loading via [`rename_materials!`](@ref)/
  [`rename_boundaries!`](@ref) (which wrap [`set_material_name!`](@ref)/
  [`set_boundary_name!`](@ref)).

Implementation: hand-writes a temporary Netgen `.vol` ASCII mesh file (see the
grammar documented at the top of `src/mesh_construction.jl`) and loads it via
the same `Netgen.new_mesh()` + `Netgen.Load` path [`load_mesh`](@ref)
uses; the temp file is removed afterward (even on error). This sidesteps a
real gap in `Delone.Netgen`: `Netgen.Element`/`Netgen.Element2d` have
no registered constructor, so `Netgen.AddVolumeElement`/
`Netgen.AddSurfaceElement` are unreachable in practice — see the module
docstring comment above `mesh_from_arrays` in the source for details.

Throws `ArgumentError` on inconsistent shapes, out-of-range/non-1-based node
ids, or mismatched region-vector lengths, before writing anything to disk.

!!! note "2D not yet supported"
    Only 3D (`points` is `3×np`, `tets` is `4×ne`) is implemented. 2D (`2×np`
    points plus domain-triangle connectivity) is a documented follow-up, not
    implemented here.
"""
function mesh_from_arrays(points::AbstractMatrix, tets::AbstractMatrix;
        surface::Union{Nothing,AbstractMatrix}=nothing,
        cell_regions::Union{Nothing,AbstractVector{<:Integer}}=nothing,
        boundary_regions::Union{Nothing,AbstractVector{<:Integer}}=nothing,
        material_names::Union{Nothing,AbstractDict}=nothing,
        boundary_names::Union{Nothing,AbstractDict}=nothing)

    size(points, 1) == 3 || throw(ArgumentError(
        "mesh_from_arrays: points must be 3×np (got $(size(points))); 2D is not yet supported"))
    size(tets, 1) == 4 || throw(ArgumentError(
        "mesh_from_arrays: tets must be 4×ne (got $(size(tets)))"))

    np = size(points, 2)
    ne = size(tets, 2)
    np > 0 || throw(ArgumentError("mesh_from_arrays: points has zero columns"))
    ne > 0 || throw(ArgumentError("mesh_from_arrays: tets has zero columns"))

    _check_node_ids(tets, np, "tets")

    cregions = cell_regions === nothing ? fill(1, ne) : collect(Int, cell_regions)
    length(cregions) == ne || throw(ArgumentError(
        "mesh_from_arrays: cell_regions has length $(length(cregions)), expected $ne (size(tets,2))"))
    all(>=(1), cregions) || throw(ArgumentError(
        "mesh_from_arrays: cell_regions must be 1-based (all entries >= 1)"))

    if surface === nothing
        boundary_regions === nothing || throw(ArgumentError(
            "mesh_from_arrays: boundary_regions given without surface"))
        nse = 0
        bregions = Int[]
    else
        size(surface, 1) == 3 || throw(ArgumentError(
            "mesh_from_arrays: surface must be 3×nse (got $(size(surface)))"))
        nse = size(surface, 2)
        _check_node_ids(surface, np, "surface")
        bregions = boundary_regions === nothing ? fill(1, nse) : collect(Int, boundary_regions)
        length(bregions) == nse || throw(ArgumentError(
            "mesh_from_arrays: boundary_regions has length $(length(bregions)), expected $nse (size(surface,2))"))
        all(>=(1), bregions) || throw(ArgumentError(
            "mesh_from_arrays: boundary_regions must be 1-based (all entries >= 1)"))
    end

    path = tempname() * ".vol"
    try
        _write_vol_file(path, points, tets, surface, cregions, bregions)
        m = Netgen.new_mesh()
        Netgen.Load(m, path)

        material_names !== nothing && rename_materials!(m, material_names)
        boundary_names !== nothing && rename_boundaries!(m, boundary_names)

        return m
    finally
        rm(path; force=true)
    end
end

# Every entry of `ids` must be a valid 1-based index into `1:np`.
function _check_node_ids(ids::AbstractMatrix, np::Integer, label::AbstractString)
    lo, hi = extrema(ids)
    lo >= 1 || throw(ArgumentError(
        "mesh_from_arrays: $label contains non-1-based index $lo (must be >= 1)"))
    hi <= np || throw(ArgumentError(
        "mesh_from_arrays: $label references node index $hi, but points only has $np columns"))
    return nothing
end

# Sort 3 node ids into a canonical (order-independent) face key.
function _sorted3(a::Integer, b::Integer, c::Integer)
    a, b, c = Int(a), Int(b), Int(c)
    a, b = a < b ? (a, b) : (b, a)
    b, c = b < c ? (b, c) : (c, b)
    a, b = a < b ? (a, b) : (b, a)
    return (a, b, c)
end

# Map each tetrahedron face (as a sorted 3-tuple of node ids) to the region id
# of the (unique, for boundary faces) tet that owns it. Mirrors Netgen's own
# "domain in = the region touching the face" convention for face descriptors.
function _face_owner_regions(tets::AbstractMatrix, cregions::Vector{Int})
    ne = size(tets, 2)
    owner = Dict{NTuple{3,Int},Int}()
    sizehint!(owner, 4 * ne)
    for i in 1:ne
        p1, p2, p3, p4 = Int(tets[1, i]), Int(tets[2, i]), Int(tets[3, i]), Int(tets[4, i])
        owner[_sorted3(p1, p2, p3)] = cregions[i]
        owner[_sorted3(p1, p2, p4)] = cregions[i]
        owner[_sorted3(p1, p3, p4)] = cregions[i]
        owner[_sorted3(p2, p3, p4)] = cregions[i]
    end
    return owner
end

# Hand-write a minimal Netgen `.vol` ASCII mesh file. See the grammar notes at
# the top of this file for the reverse-engineered format.
function _write_vol_file(path::AbstractString, points::AbstractMatrix, tets::AbstractMatrix,
        surface::Union{Nothing,AbstractMatrix}, cregions::Vector{Int}, bregions::Vector{Int})
    ne = size(tets, 2)
    np = size(points, 2)
    open(path, "w") do io
        println(io, "mesh3d")
        println(io, "dimension")
        println(io, 3)
        println(io, "geomtype")
        println(io, 0)
        println(io)

        if surface !== nothing
            nse = size(surface, 2)
            owner = _face_owner_regions(tets, cregions)

            # domIn per boundary region (1:nfd), from the first triangle seen
            # in that region -- FaceDescriptor's DomainIn is per-region
            # metadata, not per-triangle, so this assumes (as real Netgen
            # meshes do) that every triangle sharing a boundary_regions id
            # borders the same domain.
            nfd = isempty(bregions) ? 0 : maximum(bregions)
            domin_of_region = zeros(Int, nfd)
            seen = falses(nfd)
            for j in 1:nse
                r = bregions[j]
                seen[r] && continue
                p1, p2, p3 = Int(surface[1, j]), Int(surface[2, j]), Int(surface[3, j])
                domin_of_region[r] = get(owner, _sorted3(p1, p2, p3), 0)
                seen[r] = true
            end

            # Explicit facedescriptors block, one row per region id in order,
            # so AddFaceDescriptor allocates index r for region r exactly (see
            # grammar notes above) -- this is what makes boundary_regions
            # round-trip byte-for-byte instead of just preserving groupings.
            println(io, "facedescriptors")
            println(io, nfd)
            for r in 1:nfd
                println(io, "$r $(domin_of_region[r]) 0 0 $r")
            end
            println(io)

            println(io, "surfaceelements")
            println(io, nse)
            for j in 1:nse
                p1, p2, p3 = Int(surface[1, j]), Int(surface[2, j]), Int(surface[3, j])
                r = bregions[j]
                # NOTE: the surfaceelements reader does `infile >> surfnr; ...;
                # surfnr--;` before comparing against FaceDescriptor::SurfNr(),
                # but the explicit facedescriptors reader stores SurfNr()
                # verbatim (no decrement) -- so the surfnr field written here
                # must be one more than the facedescriptors row's surfnr field
                # for the two to resolve to the same FaceDescriptor (verified
                # empirically: without the +1, every row silently allocates a
                # *new* FaceDescriptor instead of matching the pre-registered
                # one, doubling GetNFD()).
                println(io, " $(r + 1) $r $(domin_of_region[r]) 0 3 $p1 $p2 $p3")
            end
            println(io)
        end

        println(io, "volumeelements")
        println(io, ne)
        for i in 1:ne
            p1, p2, p3, p4 = Int(tets[1, i]), Int(tets[2, i]), Int(tets[3, i]), Int(tets[4, i])
            println(io, "$(cregions[i]) 4 $p1 $p2 $p3 $p4")
        end
        println(io)

        println(io, "points")
        println(io, np)
        for i in 1:np
            x, y, z = Float64(points[1, i]), Float64(points[2, i]), Float64(points[3, i])
            println(io, "$x $y $z")
        end
        println(io)

        println(io, "endmesh")
    end
    return nothing
end

# --- incremental, one-element-at-a-time construction -------------------------
# The counterpart to mesh_from_arrays above: add a single volume/surface
# element to an *existing* mesh, for incremental editing (as opposed to
# building a whole mesh from arrays at once). See the module note near the
# top of this file for why this was previously unreachable.

"""
    add_volume_element!(mesh, point_ids; region=1) -> mesh

Add one tetrahedron to `mesh` (`Netgen.Element` + `Netgen.AddVolumeElement`).
`point_ids` is a length-4 vector/tuple of 1-based node indices into `mesh`
(matching [`tetrahedra`](@ref)'s convention); `region` is the 1-based
domain/material index the new element belongs to (matching
[`cell_regions`](@ref)).

Throws `ArgumentError` if `point_ids` does not have exactly 4 entries, if any
entry is not a valid 1-based index into `mesh`'s existing points, or if
`region < 1`.
"""
function add_volume_element!(m, point_ids; region::Integer=1)
    length(point_ids) == 4 || throw(ArgumentError(
        "add_volume_element!: point_ids must have exactly 4 entries (got $(length(point_ids)))"))
    region >= 1 || throw(ArgumentError("add_volume_element!: region must be >= 1 (got $region)"))
    np = Netgen.GetNP(m)
    for pid in point_ids
        1 <= pid <= np || throw(ArgumentError(
            "add_volume_element!: point id $pid out of range 1:$np"))
    end
    el = Netgen.Element(4)
    for (i, pid) in enumerate(point_ids)
        Netgen.SetPNum(el, i, Int(pid))
    end
    Netgen.SetIndex(el, Int(region))
    Netgen.AddVolumeElement(m, el)
    return m
end

"""
    add_surface_element!(mesh, point_ids; region=1) -> mesh

Add one boundary triangle to `mesh` (`Netgen.Element2d` +
`Netgen.AddSurfaceElement`). `point_ids` is a length-3 vector/tuple of
1-based node indices into `mesh` (matching [`surface_triangles`](@ref)'s
convention); `region` is the 1-based face-descriptor index the new element
belongs to (matching [`boundary_regions`](@ref)) — it must already exist
(e.g. from a prior `generate_mesh`/`mesh_from_arrays` call); this function
does not allocate new face descriptors.

Throws `ArgumentError` if `point_ids` does not have exactly 3 entries, if any
entry is not a valid 1-based index into `mesh`'s existing points, or if
`region` is not a valid 1-based index into `mesh`'s existing face
descriptors (`1:GetNFD(mesh)`).

!!! warning "Do not skip the `region` check"
    Unlike an out-of-range point id, calling `Netgen.AddSurfaceElement`
    with a face-descriptor index that doesn't exist **segfaults the whole
    Julia process** rather than throwing a catchable exception (confirmed
    empirically — Netgen's own `has no facedecoding` internal check runs
    after the point in the C++ call where it's safe to recover). This
    function bounds-checks `region` against `GetNFD(mesh)` up front
    specifically to prevent that crash; do not remove this check when
    editing this function.
"""
function add_surface_element!(m, point_ids; region::Integer=1)
    length(point_ids) == 3 || throw(ArgumentError(
        "add_surface_element!: point_ids must have exactly 3 entries (got $(length(point_ids)))"))
    nfd = Netgen.GetNFD(m)
    1 <= region <= nfd || throw(ArgumentError(
        "add_surface_element!: region $region is not a valid face-descriptor index " *
        "(mesh has $nfd; add_surface_element! does not allocate new ones — " *
        "passing an invalid index would segfault the Netgen backend rather " *
        "than throw, so this is checked explicitly)"))
    np = Netgen.GetNP(m)
    for pid in point_ids
        1 <= pid <= np || throw(ArgumentError(
            "add_surface_element!: point id $pid out of range 1:$np"))
    end
    el = Netgen.Element2d(3)
    for (i, pid) in enumerate(point_ids)
        Netgen.SetPNum(el, i, Int(pid))
    end
    Netgen.SetIndex(el, Int(region))
    Netgen.AddSurfaceElement(m, el)
    return m
end
