# --- BREP interop (OpenCascade.jl → Delone.jl) -------------------------------
# Primary boundary: in-memory BREP strings. TopoDS_Shape stays in OpenCascade;
# Netgen imports geometry via OCCGeometry_from_brep_string only.

"""
    occ_geometry_from_brep_string(brep) -> NetgenGeometry

Build a meshable Netgen `OCCGeometry` from an in-memory BREP string (from
`to_brep_string` in OpenCascade.jl — a different package, not part of
Delone.jl's own API). This is the stable interop path between CAD modeling
and Netgen meshing.
"""
occ_geometry_from_brep_string(brep::AbstractString) =
    Netgen.OCCGeometry_from_brep_string(String(brep))

"""
    generate_mesh(body::Monge.Body; options=nothing, maxh=nothing,
                  result=false, backend=:netgen, kwargs...)

Mesh an in-memory CAD body built with OpenCascade.jl (`Monge.Body`) directly
— the backend-agnostic counterpart of converting to a BREP string and
calling [`occ_geometry_from_brep_string`](@ref)/[`gmsh_mesh_from_brep_string`](@ref)
by hand. Converts `body` once (`Monge.to_brep_string`) and dispatches on
`backend` exactly like [`generate_mesh`](@ref)'s other methods:
`backend=:netgen` (default) returns a mesh handle (or
[`MeshGenerationResult`](@ref) under `result=true`); `backend=:gmsh` returns
a `MeshLevelSnapshot` (`options=`/`result=true` throw `ArgumentError`, same
restriction as the file-path method — requires `using Gmsh`), forwarding
all other keywords (`maxh`, `regions`, `boundary_names`, `refine_near`,
`periodic`, `periodic_box`, ...) to [`gmsh_mesh_from_brep_string`](@ref)
verbatim.
"""
function generate_mesh(body::Body; options=nothing, maxh=nothing,
                        result::Bool=false, backend::Symbol=:netgen,
                        kwargs...)
    brep = to_brep_string(body)
    if backend === :gmsh
        (options === nothing && !result) || throw(ArgumentError(
            "generate_mesh: backend=:gmsh does not support options=MeshOptions(...) " *
            "or result=true (Netgen-specific structured diagnostics; call " *
            "gmsh_mesh_from_brep_string(...; result=true) directly for GmshMeshGenerationResult)"))
        return gmsh_mesh_from_brep_string(brep; maxh=maxh, kwargs...)
    elseif backend !== :netgen
        throw(ArgumentError("generate_mesh: unknown backend $backend (expected :netgen or :gmsh)"))
    end
    geom = occ_geometry_from_brep_string(brep)
    return generate_mesh(geom; options=options, maxh=maxh, result=result, kwargs...)
end
