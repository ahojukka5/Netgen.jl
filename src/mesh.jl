# --- mesh workflow (Julian helpers over Netgen) --------------------------
# I/O, meshing parameters, introspection, topology refresh, and quality checks.

"""
    meshing_parameters(; maxh, minh=nothing, grading=nothing, secondorder=false,
                       optsteps2d=nothing, optsteps3d=nothing)

Build a `MeshingParameters` object for [`generate_mesh`](@ref),
[`improve_mesh!`](@ref), or [`optimize_volume!`](@ref).
"""
function meshing_parameters(;
        maxh::Real,
        minh::Union{Nothing,Real}=nothing,
        grading::Union{Nothing,Real}=nothing,
        secondorder::Bool=false,
        optsteps2d::Union{Nothing,Integer}=nothing,
        optsteps3d::Union{Nothing,Integer}=nothing)
    mp = Netgen.MeshingParameters()
    Netgen.maxh!(mp, Float64(maxh))
    minh !== nothing && Netgen.minh!(mp, Float64(minh))
    grading !== nothing && Netgen.grading!(mp, Float64(grading))
    Netgen.secondorder!(mp, secondorder)
    optsteps2d !== nothing && Netgen.optsteps2d!(mp, Int(optsteps2d))
    optsteps3d !== nothing && Netgen.optsteps3d!(mp, Int(optsteps3d))
    return mp
end

"""
    save_mesh(mesh, path) -> mesh

Write `mesh` to Netgen volume format (`Mesh::Save`).
"""
function save_mesh(m, path::AbstractString)
    Netgen.Save(m, String(path))
    return m
end

"""
    load_mesh(path) -> mesh

Read a mesh from Netgen volume format (`Mesh::Load`).
"""
function load_mesh(path::AbstractString)
    m = Netgen.new_mesh()
    Netgen.Load(m, String(path))
    return m
end

"""num_nodes(mesh) -> number of mesh nodes."""
num_nodes(m) = Netgen.GetNP(m)

"""num_cells(mesh) -> number of top-dimensional cells (tets in 3D, triangles in 2D)."""
num_cells(m) = _ncells(m)

"""num_boundary_facets(mesh) -> boundary triangles in 3D, segments in 2D."""
function num_boundary_facets(m)
    d = Netgen.GetDimension(m)
    return d == 3 ? Netgen.GetNSE(m) : Netgen.GetNSeg(m)
end

"""mesh_dimension(mesh) -> topological dimension (2 or 3)."""
mesh_dimension(m) = Int(Netgen.GetDimension(m))

"""
    connectivity(mesh) -> (volume=..., surface=...)

Top-dimensional and boundary connectivity as 1-based integer matrices, returned
as a `NamedTuple` (`volume`, `surface`; also destructures positionally as
`(volume, surface)`). Dispatches on mesh dimension via
[`volume_tetrahedra`](@ref)/[`triangles2d`](@ref) and
[`surface_triangles`](@ref)/[`segments2d`](@ref).
"""
function connectivity(m)
    d = mesh_dimension(m)
    if d == 3
        return (volume=volume_tetrahedra(m), surface=surface_triangles(m))
    elseif d == 2
        return (volume=triangles2d(m), surface=segments2d(m))
    else
        throw(ArgumentError("connectivity: unsupported mesh dimension $d"))
    end
end

"""update_topology!(mesh) -> mesh, refresh edge/face topology tables."""
function update_topology!(m)
    Netgen.UpdateTopology(m)
    return m
end

"""
    check_mesh(mesh) -> NamedTuple

Run basic mesh checks. Returns `(volume_ok=..., boundary_ok=...)` where each
field is `true` when the corresponding `CheckVolumeMesh` / `CheckConsistentBoundary`
call returns `0`.
"""
function check_mesh(m)
    vol = Netgen.CheckVolumeMesh(m) == 0
    bnd = Netgen.CheckConsistentBoundary(m) == 0
    return (volume_ok=vol, boundary_ok=bnd)
end

"""
    improve_mesh!(mesh; maxh, kwargs...) -> mesh

Improve mesh quality in place (`Mesh::ImproveMesh`) using [`meshing_parameters`](@ref).
"""
function improve_mesh!(m; maxh::Real, kwargs...)
    mp = meshing_parameters(; maxh=maxh, kwargs...)
    Netgen.ImproveMesh(m, mp)
    return m
end

"""
    optimize_volume!(mesh; maxh, throw_on_error=true, kwargs...) -> mesh
    optimize_volume!(mesh; maxh, throw_on_error=false, kwargs...) -> (mesh=mesh, status=status)

Fill and optimize a volume mesh (`MeshVolume` then `OptimizeVolume`).

With `throw_on_error=true` (default), throws `ErrorException` when the
Netgen status is not `MESHING3_OK` and otherwise returns `mesh` — matching
every other mutating `!` function in this package. With
`throw_on_error=false`, never throws and instead returns `(mesh=mesh,
status=status)` so the Netgen status code (see [`MESHING3_OK`](@ref) and
related constants) is still recoverable via `.status`.
"""
function optimize_volume!(m; maxh::Real, throw_on_error::Bool=true, kwargs...)
    mp = meshing_parameters(; maxh=maxh, kwargs...)
    status = Netgen.MeshVolume(mp, m)
    if status != MESHING3_OK
        throw_on_error && throw(ErrorException("MeshVolume failed with status $status"))
        return (mesh=m, status=status)
    end
    status = Netgen.OptimizeVolume(mp, m)
    if status != MESHING3_OK
        throw_on_error && throw(ErrorException("OptimizeVolume failed with status $status"))
        return (mesh=m, status=status)
    end
    return throw_on_error ? m : (mesh=m, status=status)
end

"""
    mesh_bounding_box(mesh) -> (min=(xmin, ymin, zmin), max=(xmax, ymax, zmax))

Axis-aligned bounding box from `Mesh::GetBox`, returned as a `NamedTuple`
(`min`, `max`; also destructures positionally as `(lo, hi)`). Each field is a
plain 3-tuple of coordinates.
"""
function mesh_bounding_box(m)
    b = Netgen.GetBox(m)
    return (min=(Netgen.MinX(b), Netgen.MinY(b), Netgen.MinZ(b)),
            max=(Netgen.MaxX(b), Netgen.MaxY(b), Netgen.MaxZ(b)))
end

"""compress!(mesh) -> mesh, remove unused mesh points in place."""
function compress!(m)
    Netgen.Compress(m)
    return m
end
