# --- element extraction & region/tag helpers --------------------------------
# Dimension-explicit extraction on top of the 1:1 accessors. Region ids are
# Netgen `GetIndex` values; names come from Netgen material/BC labels. Functions
# fail with `ArgumentError` on an unsupported topology rather than silently
# reinterpreting elements.

"""
    volume_tetrahedra(mesh) -> 4×GetNE Matrix{Int32}

Volume tetrahedra of a **3D** mesh, 1-based node ids. Errors with `ArgumentError`
on a non-3D mesh. (Same data as [`tetrahedra`](@ref) but dimension-checked and
unambiguously named for 3D volume cells.)
"""
function volume_tetrahedra(m)
    d = GetDimension(m)
    d == 3 || throw(ArgumentError("volume_tetrahedra requires a 3D mesh (got dim=$d)"))
    return tetrahedra(m)
end

"""
    triangles2d(mesh) -> 3×GetNSE Matrix{Int32}

Domain triangles of a **2D** mesh, 1-based node ids. In a 2D Netgen mesh the
domain cells are stored as surface elements; this is *those* triangles, not 3D
boundary triangles. Errors with `ArgumentError` on a non-2D mesh. Use
[`surface_triangles`](@ref) for 3D boundary triangles.
"""
function triangles2d(m)
    d = GetDimension(m)
    d == 2 || throw(ArgumentError("triangles2d requires a 2D mesh (got dim=$d); " *
                                  "use surface_triangles for 3D boundary triangles"))
    nse = GetNSE(m)
    T = Matrix{Int32}(undef, 3, nse)
    for i in 1:nse
        e = SurfaceElement(m, i)
        for j in 1:3
            T[j, i] = PNum(e, j)
        end
    end
    return T
end

"""
    segments2d(mesh) -> 2×GetNSeg Matrix{Int32}

Boundary segments of a **2D** mesh, 1-based node ids (first two endpoints). Errors
with `ArgumentError` on a non-2D mesh.
"""
function segments2d(m)
    d = GetDimension(m)
    d == 2 || throw(ArgumentError("segments2d requires a 2D mesh (got dim=$d)"))
    nseg = GetNSeg(m)
    S = Matrix{Int32}(undef, 2, nseg)
    for i in 1:nseg
        s = LineSegment(m, i)
        S[1, i] = PNum(s, 1)
        S[2, i] = PNum(s, 2)
    end
    return S
end

# number of "cells" (top-dimensional elements): tets in 3D, triangles in 2D.
_ncells(m) = GetDimension(m) == 3 ? GetNE(m) : GetNSE(m)

"""
    cell_regions(mesh) -> Vector{Int32}

Per top-dimensional cell, its Netgen region id (`Element::GetIndex`): the
sub-domain index in 3D (indexes [`material_names`](@ref)), or the 2D face/domain
index in 2D. Length is `GetNE` (3D) or `GetNSE` (2D). Errors on other dimensions.
"""
function cell_regions(m)
    d = GetDimension(m)
    if d == 3
        return Int32[GetIndex(VolumeElement(m, i)) for i in 1:GetNE(m)]
    elseif d == 2
        return Int32[GetIndex(SurfaceElement(m, i)) for i in 1:GetNSE(m)]
    else
        throw(ArgumentError("cell_regions: unsupported mesh dimension $d"))
    end
end

"""
    boundary_regions(mesh) -> Vector{Int32}

Per boundary facet, its Netgen region id: the face-descriptor index
(`Element2d::GetIndex`, indexes [`boundary_names`](@ref)) for 3D boundary
triangles, or the segment index (`Segment::GetIndex`) in 2D. Length is `GetNSE`
(3D) or `GetNSeg` (2D). Errors on other dimensions.
"""
function boundary_regions(m)
    d = GetDimension(m)
    if d == 3
        return Int32[GetIndex(SurfaceElement(m, i)) for i in 1:GetNSE(m)]
    elseif d == 2
        return Int32[GetIndex(LineSegment(m, i)) for i in 1:GetNSeg(m)]
    else
        throw(ArgumentError("boundary_regions: unsupported mesh dimension $d"))
    end
end

"""
    material_names(mesh) -> Dict{Int32,String}

Map sub-domain index → material name (`Mesh::GetMaterial`), for
`1:GetNDomains(mesh)`. Keys match the values returned by [`cell_regions`](@ref)
on a 3D mesh.
"""
function material_names(m)
    d = Dict{Int32,String}()
    for i in 1:GetNDomains(m)
        d[Int32(i)] = GetMaterial(m, i)
    end
    return d
end

"""
    boundary_names(mesh) -> Dict{Int32,String}

Map face-descriptor index → boundary-condition name
(`FaceDescriptor::GetBCName`), for `1:GetNFD(mesh)`. Keys match the values
returned by [`boundary_regions`](@ref) on a 3D mesh.
"""
function boundary_names(m)
    d = Dict{Int32,String}()
    for i in 1:GetNFD(m)
        d[Int32(i)] = GetBCName(GetFaceDescriptor(m, i))
    end
    return d
end
