# --- element extraction & region/tag helpers --------------------------------
# Dimension-explicit extraction on top of the 1:1 accessors. Region ids are
# Netgen `GetIndex` values; names come from Netgen material/BC labels. Functions
# fail with `ArgumentError` on an unsupported topology rather than silently
# reinterpreting elements.

"""
    volume_tetrahedra(mesh) -> 4×Internals.GetNE Matrix{Int32}

Volume tetrahedra of a **3D** mesh, 1-based node ids. Errors with `ArgumentError`
on a non-3D mesh. (Same data as [`tetrahedra`](@ref) but dimension-checked and
unambiguously named for 3D volume cells.)
"""
function volume_tetrahedra(m)
    d = Internals.GetDimension(m)
    d == 3 || throw(ArgumentError("volume_tetrahedra requires a 3D mesh (got dim=$d)"))
    return tetrahedra(m)
end

"""
    triangles2d(mesh) -> 3×Internals.GetNSE Matrix{Int32}

Domain triangles of a **2D** mesh, 1-based node ids. In a 2D Netgen mesh the
domain cells are stored as surface elements; this is *those* triangles, not 3D
boundary triangles. Errors with `ArgumentError` on a non-2D mesh. Use
[`surface_triangles`](@ref) for 3D boundary triangles.
"""
function triangles2d(m)
    d = Internals.GetDimension(m)
    d == 2 || throw(ArgumentError("triangles2d requires a 2D mesh (got dim=$d); " *
                                  "use surface_triangles for 3D boundary triangles"))
    nse = Internals.GetNSE(m)
    T = Matrix{Int32}(undef, 3, nse)
    for i in 1:nse
        e = Internals.SurfaceElement(m, i)
        for j in 1:3
            T[j, i] = Internals.PNum(e, j)
        end
    end
    return T
end

"""
    segments2d(mesh) -> 2×Internals.GetNSeg Matrix{Int32}

Boundary segments of a **2D** mesh, 1-based node ids (first two endpoints). Errors
with `ArgumentError` on a non-2D mesh.
"""
function segments2d(m)
    d = Internals.GetDimension(m)
    d == 2 || throw(ArgumentError("segments2d requires a 2D mesh (got dim=$d)"))
    nseg = Internals.GetNSeg(m)
    S = Matrix{Int32}(undef, 2, nseg)
    for i in 1:nseg
        s = Internals.LineSegment(m, i)
        S[1, i] = Internals.PNum(s, 1)
        S[2, i] = Internals.PNum(s, 2)
    end
    return S
end

# number of "cells" (top-dimensional elements): tets in 3D, triangles in 2D.
_ncells(m) = Internals.GetDimension(m) == 3 ? Internals.GetNE(m) : Internals.GetNSE(m)

"""
    cell_regions(mesh) -> Vector{Int32}

Per top-dimensional cell, its Netgen region id (`Element::Internals.GetIndex`): the
sub-domain index in 3D (indexes [`material_names`](@ref)), or the 2D face/domain
index in 2D. Length is `GetNE` (3D) or `GetNSE` (2D). Errors on other dimensions.
"""
function cell_regions(m)
    d = Internals.GetDimension(m)
    if d == 3
        return Int32[Internals.GetIndex(Internals.VolumeElement(m, i)) for i in 1:Internals.GetNE(m)]
    elseif d == 2
        return Int32[Internals.GetIndex(Internals.SurfaceElement(m, i)) for i in 1:Internals.GetNSE(m)]
    else
        throw(ArgumentError("cell_regions: unsupported mesh dimension $d"))
    end
end

"""
    boundary_regions(mesh) -> Vector{Int32}

Per boundary facet, its Netgen region id: the face-descriptor index
(`Element2d::Internals.GetIndex`, indexes [`boundary_names`](@ref)) for 3D boundary
triangles, or the segment index (`Segment::Internals.GetIndex`) in 2D. Length is `GetNSE`
(3D) or `GetNSeg` (2D). Errors on other dimensions.
"""
function boundary_regions(m)
    d = Internals.GetDimension(m)
    if d == 3
        return Int32[Internals.GetIndex(Internals.SurfaceElement(m, i)) for i in 1:Internals.GetNSE(m)]
    elseif d == 2
        return Int32[Internals.GetIndex(Internals.LineSegment(m, i)) for i in 1:Internals.GetNSeg(m)]
    else
        throw(ArgumentError("boundary_regions: unsupported mesh dimension $d"))
    end
end

"""
    material_names(mesh) -> Dict{Int32,String}

Map sub-domain index → material name (`Mesh::Internals.GetMaterial`), for
`1:Internals.GetNDomains(mesh)`. Keys match the values returned by [`cell_regions`](@ref)
on a 3D mesh.

!!! note "2D limitation"
    In 2D, Netgen reports `Internals.GetNDomains == 0` through the current wrapper path, so
    this returns an **empty** dict — 2D material *names* are not available here
    (topological ids via [`cell_regions`](@ref) still work). No fake names are
    invented.
"""
function material_names(m)
    d = Dict{Int32,String}()
    for i in 1:Internals.GetNDomains(m)
        d[Int32(i)] = Internals.GetMaterial(m, i)
    end
    return d
end

"""
    boundary_names(mesh) -> Dict{Int32,String}

Map face-descriptor index → boundary-condition name
(`FaceDescriptor::Internals.GetBCName`), for `1:Internals.GetNFD(mesh)`. Keys match the values
returned by [`boundary_regions`](@ref) on a 3D mesh.

!!! note "2D limitation"
    In 2D the keys here (face-descriptor indices) do **not** correspond to
    [`boundary_regions`](@ref) values (segment indices), so 2D boundary *names*
    cannot be reliably joined to boundary facets through this path. Use the
    topological ids from [`boundary_regions`](@ref) in 2D; do not rely on 2D
    names.
"""
function boundary_names(m)
    d = Dict{Int32,String}()
    for i in 1:Internals.GetNFD(m)
        d[Int32(i)] = Internals.GetBCName(Internals.GetFaceDescriptor(m, i))
    end
    return d
end

"""
    region_name_volume(mesh, enr) -> String

Per volume element material/region name (`Mesh::GetRegionName`, 1-based `enr`).
"""
region_name_volume(m, enr::Integer) = String(Internals.GetRegionNameVolume(m, Int(enr)))

"""
    region_name_surface(mesh, senr) -> String

Per boundary triangle region name (3D, 1-based surface element index).
"""
region_name_surface(m, senr::Integer) = String(Internals.GetRegionNameSurface(m, Int(senr)))

"""
    region_name_segment(mesh, segnr) -> String

Per boundary segment region name (2D/3D, 1-based segment index). Prefer this over
[`boundary_names`](@ref) for joining names to [`boundary_regions`](@ref) in 2D.
"""
region_name_segment(m, segnr::Integer) = String(Internals.GetRegionNameSegment(m, Int(segnr)))
