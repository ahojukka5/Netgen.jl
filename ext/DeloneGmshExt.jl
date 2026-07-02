# --- Delone <-> Gmsh package extension ---------------------------------------
# Loaded automatically (Base.get_extension) when the host session has both
# Delone and Gmsh loaded. See Project.toml [weakdeps]/[extensions].
# Requires Julia >= 1.9.
#
# Gmsh needs no hand-written CxxWrap binding layer the way Netgen does:
# `gmsh_jll` ships a complete, official, auto-generated Julia API
# (`gmsh_jll.gmsh_api`, produced by Gmsh's own build from its language-neutral
# API spec), and the registered `Gmsh` package wraps it safely
# (`include(gmsh_jll.gmsh_api)` + idempotent `initialize`/`finalize`). This
# extension is Julian composition on top of that, following the same pattern
# already used by this ecosystem's `Oodi.jl`/`JuliaFEM.jl` Gmsh extensions.
#
# Session model: per-call `Gmsh.initialize()`/`Gmsh.finalize()`, not a
# persistent session -- v1's scope (one file in, one snapshot out) never has
# two live models needing to coexist. `Gmsh.initialize()` returns `true` only
# if *it* performed initialization (idempotent otherwise), so `finalize()` is
# only called when this function was the one that opened Gmsh -- unlike a
# naive try/finally, this doesn't tear down a Gmsh session the caller's own
# code already had open for something else.
#
# Node/element "tags" from Gmsh are not guaranteed dense/contiguous by the
# API (usually are, for a freshly generated mesh, but that's a convention,
# not a guarantee) -- an explicit tag->index Dict is always built, never
# assumed.
module DeloneGmshExt

using Delone
using Delone: MeshLevelSnapshot
import Gmsh
import Gmsh: gmsh

# Gmsh element type ids (from the Gmsh API docs / gmsh.model.mesh.getElementProperties).
const _GMSH_TET4 = 4
const _GMSH_TRI3 = 2

function Delone.generate_gmsh_mesh(path::AbstractString; maxh::Union{Nothing,Real}=nothing)
    isfile(path) || throw(ArgumentError("generate_gmsh_mesh: file not found: $path"))
    did_init = Gmsh.initialize()
    try
        gmsh.option.setNumber("General.Terminal", 0)
        gmsh.model.add("delone")
        try
            gmsh.model.occ.importShapes(String(path))
        catch e
            e isa ErrorException || rethrow()
            throw(ArgumentError("generate_gmsh_mesh: failed to import $path: $(e.msg)"))
        end
        gmsh.model.occ.synchronize()
        maxh !== nothing && gmsh.option.setNumber("Mesh.MeshSizeMax", Float64(maxh))
        try
            gmsh.model.mesh.generate(3)
        catch e
            e isa ErrorException || rethrow()
            throw(ArgumentError("generate_gmsh_mesh: meshing failed: $(e.msg)"))
        end
        return _extract_snapshot()
    finally
        did_init && Gmsh.finalize()
    end
end

function Delone.gmsh_mesh_from_brep_string(brep::AbstractString; maxh::Union{Nothing,Real}=nothing)
    path = tempname() * ".brep"
    try
        write(path, brep)
        return Delone.generate_gmsh_mesh(path; maxh=maxh)
    finally
        isfile(path) && rm(path; force=true)
    end
end

function _extract_snapshot()
    node_tags, coord, _ = gmsh.model.mesh.getNodes()
    n = length(node_tags)
    n > 0 || throw(ArgumentError("generate_gmsh_mesh: mesh has zero nodes"))
    tag_to_idx = Dict(t => Int32(i) for (i, t) in enumerate(node_tags))
    coords = Matrix{Float64}(undef, 3, n)
    @inbounds for i in 1:n
        coords[:, i] = @view coord[3i-2:3i]
    end

    elem_types, elem_tags, elem_node_tags = gmsh.model.mesh.getElements(3, -1)
    isempty(elem_tags) && throw(ArgumentError("generate_gmsh_mesh: mesh has zero tetrahedra"))
    length(elem_types) == 1 && elem_types[1] == _GMSH_TET4 || throw(ArgumentError(
        "generate_gmsh_mesh: expected a pure Tet4 volume mesh (Gmsh element " *
        "type $_GMSH_TET4), got types $elem_types -- mixed/non-tet meshes are " *
        "not yet supported by MeshLevelSnapshot"))
    ne = length(elem_tags[1])
    vol = reshape(Int32[tag_to_idx[t] for t in elem_node_tags[1]], 4, ne)

    btypes, btags, bnode_tags = gmsh.model.mesh.getElements(2, -1)
    surf = if isempty(btags)
        Matrix{Int32}(undef, 3, 0)
    else
        length(btypes) == 1 && btypes[1] == _GMSH_TRI3 || throw(ArgumentError(
            "generate_gmsh_mesh: expected pure Tri3 boundary facets (Gmsh " *
            "element type $_GMSH_TRI3), got types $btypes"))
        reshape(Int32[tag_to_idx[t] for t in bnode_tags[1]], 3, length(btags[1]))
    end

    return MeshLevelSnapshot{3,Float64,Int32}(
        coords, vol, surf,
        fill(Int32(1), ne), fill(Int32(0), size(surf, 2)),
        Dict{Int32,String}(), Dict{Int32,String}(),
        :tet, :tri, 1, 0)
end

end # module
