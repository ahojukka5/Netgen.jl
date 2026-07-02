# --- Gmsh backend stub (real implementation in ext/DeloneGmshExt.jl) --------
# Gmsh needs no hand-written CxxWrap binding layer the way Netgen does:
# `gmsh_jll` ships a complete, official, auto-generated Julia API
# (`gmsh_jll.gmsh_api`), wrapped safely by the registered `Gmsh` package
# (`include(gmsh_jll.gmsh_api)` + idempotent `initialize`/`finalize`). This
# stub exists only because Julia package extensions can add *methods* to an
# existing function binding, not introduce a new top-level name from scratch
# (same reason `export_vtu` has a stub in `src/export_mesh.jl`).

"""
    generate_gmsh_mesh(path; maxh=nothing) -> MeshLevelSnapshot{3,Float64,Int32}

Mesh a STEP/IGES/BREP file via Gmsh's OpenCASCADE-based CAD kernel and volume
mesher. Defined by the `DeloneGmshExt` package extension and only becomes
usable once `Gmsh` is loaded (`using Gmsh`) — see [`generate_mesh`](@ref) for
the always-available Netgen backend.
"""
function generate_gmsh_mesh(args...; kwargs...)
    throw(ArgumentError(
        "generate_gmsh_mesh requires Gmsh to be loaded (`using Gmsh`) to activate " *
        "the DeloneGmshExt package extension; see generate_mesh for the " *
        "always-available Netgen backend"))
end

"""
    gmsh_mesh_from_brep_string(brep::AbstractString; maxh=nothing) -> MeshLevelSnapshot{3,Float64,Int32}

Mesh an in-memory BREP string (e.g. from `Monge.to_brep_string`) via Gmsh —
the Gmsh-backend analogue of [`occ_geometry_from_brep_string`](@ref)'s
BREP-string bridge for Netgen.

Gmsh's own API has no in-memory-string import (unlike Netgen's), so this
writes `brep` to a temporary `.brep` file internally and delegates to
[`generate_gmsh_mesh`](@ref) — equivalent to, but safer than, passing a raw
in-memory shape pointer across two independently-built OCCT libraries.
Defined by the `DeloneGmshExt` package extension and only becomes usable
once `Gmsh` is loaded (`using Gmsh`).
"""
function gmsh_mesh_from_brep_string(args...; kwargs...)
    throw(ArgumentError(
        "gmsh_mesh_from_brep_string requires Gmsh to be loaded (`using Gmsh`) to " *
        "activate the DeloneGmshExt package extension; see " *
        "occ_geometry_from_brep_string for the always-available Netgen backend"))
end
