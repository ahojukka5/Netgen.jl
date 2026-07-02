# --- element extraction & region/tag helpers --------------------------------
# Dimension-explicit extraction on top of the 1:1 accessors. Region ids are
# Netgen `GetIndex` values; names come from Netgen material/BC labels. Functions
# fail with `ArgumentError` on an unsupported topology rather than silently
# reinterpreting elements.

"""
    volume_tetrahedra(mesh) -> 4×Netgen.GetNE Matrix{Int32}

Volume tetrahedra of a **3D** mesh, 1-based node ids. Errors with `ArgumentError`
on a non-3D mesh. (Same data as [`tetrahedra`](@ref) but dimension-checked and
unambiguously named for 3D volume cells.)
"""
function volume_tetrahedra(m)
    d = Netgen.GetDimension(m)
    d == 3 || throw(ArgumentError("volume_tetrahedra requires a 3D mesh (got dim=$d)"))
    return tetrahedra(m)
end

"""
    triangles2d(mesh) -> 3×Netgen.GetNSE Matrix{Int32}

Domain triangles of a **2D** mesh, 1-based node ids. In a 2D Netgen mesh the
domain cells are stored as surface elements; this is *those* triangles, not 3D
boundary triangles. Errors with `ArgumentError` on a non-2D mesh. Use
[`surface_triangles`](@ref) for 3D boundary triangles.
"""
function triangles2d(m)
    d = Netgen.GetDimension(m)
    d == 2 || throw(ArgumentError("triangles2d requires a 2D mesh (got dim=$d); " *
                                  "use surface_triangles for 3D boundary triangles"))
    nse = Netgen.GetNSE(m)
    T = Matrix{Int32}(undef, 3, nse)
    for i in 1:nse
        e = Netgen.SurfaceElement(m, i)
        for j in 1:3
            T[j, i] = Netgen.PNum(e, j)
        end
    end
    return T
end

"""
    segments2d(mesh) -> 2×Netgen.GetNSeg Matrix{Int32}

Boundary segments of a **2D** mesh, 1-based node ids (first two endpoints). Errors
with `ArgumentError` on a non-2D mesh.
"""
function segments2d(m)
    d = Netgen.GetDimension(m)
    d == 2 || throw(ArgumentError("segments2d requires a 2D mesh (got dim=$d)"))
    nseg = Netgen.GetNSeg(m)
    S = Matrix{Int32}(undef, 2, nseg)
    for i in 1:nseg
        s = Netgen.LineSegment(m, i)
        S[1, i] = Netgen.PNum(s, 1)
        S[2, i] = Netgen.PNum(s, 2)
    end
    return S
end

# number of "cells" (top-dimensional elements): tets in 3D, triangles in 2D.
_ncells(m) = Netgen.GetDimension(m) == 3 ? Netgen.GetNE(m) : Netgen.GetNSE(m)

"""
    cell_regions(mesh) -> Vector{Int32}

Per top-dimensional cell, its Netgen region id (`Element::Netgen.GetIndex`): the
sub-domain index in 3D (indexes [`material_names`](@ref)), or the 2D face/domain
index in 2D. Length is `GetNE` (3D) or `GetNSE` (2D). Errors on other dimensions.
"""
function cell_regions(m)
    d = Netgen.GetDimension(m)
    if d == 3
        return Int32[Netgen.GetIndex(Netgen.VolumeElement(m, i)) for i in 1:Netgen.GetNE(m)]
    elseif d == 2
        return Int32[Netgen.GetIndex(Netgen.SurfaceElement(m, i)) for i in 1:Netgen.GetNSE(m)]
    else
        throw(ArgumentError("cell_regions: unsupported mesh dimension $d"))
    end
end

"""
    boundary_regions(mesh) -> Vector{Int32}

Per boundary facet, its Netgen region id: the face-descriptor index
(`Element2d::Netgen.GetIndex`, indexes [`boundary_names`](@ref)) for 3D boundary
triangles, or the segment index (`Segment::Netgen.GetIndex`) in 2D. Length is `GetNSE`
(3D) or `GetNSeg` (2D). Errors on other dimensions.
"""
function boundary_regions(m)
    d = Netgen.GetDimension(m)
    if d == 3
        return Int32[Netgen.GetIndex(Netgen.SurfaceElement(m, i)) for i in 1:Netgen.GetNSE(m)]
    elseif d == 2
        return Int32[Netgen.GetIndex(Netgen.LineSegment(m, i)) for i in 1:Netgen.GetNSeg(m)]
    else
        throw(ArgumentError("boundary_regions: unsupported mesh dimension $d"))
    end
end

"""
    material_names(mesh) -> Dict{Int32,String}

Map sub-domain index → material name (`Mesh::Netgen.GetMaterial`), for
`1:Netgen.GetNDomains(mesh)`. Keys match the values returned by [`cell_regions`](@ref)
on a 3D mesh.

!!! note "2D limitation"
    In 2D, Netgen reports `Netgen.GetNDomains == 0` through the current wrapper path, so
    this returns an **empty** dict — 2D material *names* are not available here
    (topological ids via [`cell_regions`](@ref) still work). No fake names are
    invented.
"""
function material_names(m)
    d = Dict{Int32,String}()
    for i in 1:Netgen.GetNDomains(m)
        d[Int32(i)] = Netgen.GetMaterial(m, i)
    end
    return d
end

"""
    boundary_names(mesh) -> Dict{Int32,String}

Map face-descriptor index → boundary-condition name
(`FaceDescriptor::Netgen.GetBCName`), for `1:Netgen.GetNFD(mesh)`. Keys match the values
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
    for i in 1:Netgen.GetNFD(m)
        d[Int32(i)] = Netgen.GetBCName(Netgen.GetFaceDescriptor(m, i))
    end
    return d
end

"""
    region_name_volume(mesh, enr) -> String

Per volume element material/region name (`Mesh::GetRegionName`, 1-based `enr`).
"""
region_name_volume(m, enr::Integer) = String(Netgen.GetRegionNameVolume(m, Int(enr)))

"""
    region_name_surface(mesh, senr) -> String

Per boundary triangle region name (3D, 1-based surface element index).
"""
region_name_surface(m, senr::Integer) = String(Netgen.GetRegionNameSurface(m, Int(senr)))

"""
    region_name_segment(mesh, segnr) -> String

Per boundary segment region name (2D/3D, 1-based segment index). Prefer this over
[`boundary_names`](@ref) for joining names to [`boundary_regions`](@ref) in 2D.
"""
region_name_segment(m, segnr::Integer) = String(Netgen.GetRegionNameSegment(m, Int(segnr)))

# --- naming setters (write side of material_names / boundary_names) --------
# Mirrors the getter pattern above. `Netgen.GetFaceDescriptor` returns a
# *const* reference (cannot be mutated in place); `Netgen.GetFaceDescriptorMut`
# returns the mutable reference required for `Netgen.SetBCName` to persist
# back into the mesh — verified empirically (see test/boundary_naming_stl.jl).

"""
    set_material_name!(mesh, i::Integer, name::AbstractString) -> mesh

Set the material name of sub-domain index `i` (`1:Netgen.GetNDomains(mesh)`,
`Mesh::SetMaterial`). Symmetric with [`material_names`](@ref). Errors with
`ArgumentError` if `i` is out of range.
"""
function set_material_name!(m, i::Integer, name::AbstractString)
    nd = Netgen.GetNDomains(m)
    1 <= i <= nd || throw(ArgumentError(
        "set_material_name!: index $i out of range 1:$nd"))
    Netgen.SetMaterial(m, Int(i), String(name))
    return m
end

"""
    set_boundary_name!(mesh, i::Integer, name::AbstractString) -> mesh

Set the boundary-condition name of face-descriptor index `i`
(`1:Netgen.GetNFD(mesh)`), via `Netgen.GetFaceDescriptorMut` +
`Netgen.SetBCName`. Symmetric with [`boundary_names`](@ref). Errors with
`ArgumentError` if `i` is out of range.

!!! note
    Use [`set_boundary_name!`](@ref), not `Netgen.GetFaceDescriptor` +
    `Netgen.SetBCName` directly — `GetFaceDescriptor` returns a `const`
    reference, so `Netgen.SetBCName` on it throws a loud `MethodError`
    (verified empirically) rather than persisting; only the
    `GetFaceDescriptorMut` path mutates the live mesh.
"""
function set_boundary_name!(m, i::Integer, name::AbstractString)
    nfd = Netgen.GetNFD(m)
    1 <= i <= nfd || throw(ArgumentError(
        "set_boundary_name!: index $i out of range 1:$nfd"))
    fd = Netgen.GetFaceDescriptorMut(m, Int(i))
    Netgen.SetBCName(fd, String(name))
    return m
end

"""
    rename_materials!(mesh, names::AbstractDict{<:Integer,<:AbstractString}) -> mesh

Bulk-apply [`set_material_name!`](@ref) for each `index => name` pair.
"""
function rename_materials!(m, names::AbstractDict{<:Integer,<:AbstractString})
    for (i, name) in names
        set_material_name!(m, i, name)
    end
    return m
end

"""
    rename_boundaries!(mesh, names::AbstractDict{<:Integer,<:AbstractString}) -> mesh

Bulk-apply [`set_boundary_name!`](@ref) for each `index => name` pair.
"""
function rename_boundaries!(m, names::AbstractDict{<:Integer,<:AbstractString})
    for (i, name) in names
        set_boundary_name!(m, i, name)
    end
    return m
end
