# --- FEM geometry: curved maps, parent topology, periodic pairs -----------
# Julia helpers over strict 1:1 Internals.Ngx_Mesh bindings from netgen_ngx3.cpp.
#
# Indexing: Julia-facing APIs use **1-based** cell/vertex ids where they refer
# to mesh elements or nodes in the rest of Delone.jl. The C++ Ngx entry points
# that expect 0-based indices (ElementTransformation, Internals.GetParentEdges, …) are
# converted here.

_ngx(m) = Internals.Ngx_Mesh(m)

# --- curved element transformations -----------------------------------------

"""Unpack Netgen row-major `dxdxi` buffer into a `space × local` Jacobian matrix."""
function _unpack_jacobian(dxdxi::AbstractVector, nspace::Int, nlocal::Int)
    J = Matrix{Float64}(undef, nspace, nlocal)
    for i in 1:nspace, j in 1:nlocal
        J[i, j] = dxdxi[(i - 1) * nlocal + j]
    end
    return J
end

"""
    volume_element_transformation(mesh, enr, xi) -> (x, J)

Map reference coordinates `xi` (length 3) on volume element `enr` (1-based) to
physical point `x` (length 3) and Jacobian `J` (3×3, row-major from Netgen).
Requires curved-element state (e.g. after [`make_second_order!`](@ref)).
"""
function volume_element_transformation(m, enr::Integer, xi::AbstractVector{<:Real})
    length(xi) == 3 || throw(ArgumentError("xi must have length 3 (got $(length(xi)))"))
    x = zeros(Float64, 3)
    jac = zeros(Float64, 9)
    Internals.ElementTransformation33(_ngx(m), Int(enr) - 1, collect(Float64, xi), x, jac)
    return x, _unpack_jacobian(jac, 3, 3)
end

"""
    surface_element_transformation(mesh, senr, xi) -> (x, J)

Boundary triangle map in 3D: `xi` length 2, `x` length 3, `J` is 3×2.
"""
function surface_element_transformation(m, senr::Integer, xi::AbstractVector{<:Real})
    Internals.GetDimension(m) == 3 || throw(ArgumentError("surface_element_transformation is 3D only"))
    length(xi) == 2 || throw(ArgumentError("xi must have length 2"))
    x = zeros(Float64, 3)
    jac = zeros(Float64, 6)
    Internals.ElementTransformation23(_ngx(m), Int(senr) - 1, collect(Float64, xi), x, jac)
    return x, _unpack_jacobian(jac, 3, 2)
end

"""
    domain_element_transformation(mesh, enr, xi) -> (x, J)

Domain triangle map in 2D: `xi` length 2, `x` length 2, `J` is 2×2.
"""
function domain_element_transformation(m, enr::Integer, xi::AbstractVector{<:Real})
    Internals.GetDimension(m) == 2 || throw(ArgumentError("domain_element_transformation is 2D only"))
    length(xi) == 2 || throw(ArgumentError("xi must have length 2"))
    x = zeros(Float64, 2)
    jac = zeros(Float64, 4)
    Internals.ElementTransformation22(_ngx(m), Int(enr) - 1, collect(Float64, xi), x, jac)
    return x, _unpack_jacobian(jac, 2, 2)
end

"""
    segment_element_transformation(mesh, segnr, xi) -> (x, J)

Boundary segment map: in 3D `x` length 3 and `J` length 3 (column vector); in 2D
`x` length 2 and `J` length 2.
"""
function segment_element_transformation(m, segnr::Integer, xi::AbstractVector{<:Real})
    length(xi) == 1 || throw(ArgumentError("xi must have length 1"))
    d = Int(Internals.GetDimension(m))
    if d == 3
        x = zeros(Float64, 3)
        jac = zeros(Float64, 3)
        Internals.ElementTransformation13(_ngx(m), Int(segnr) - 1, collect(Float64, xi), x, jac)
        return x, jac
    elseif d == 2
        x = zeros(Float64, 2)
        jac = zeros(Float64, 2)
        Internals.ElementTransformation12(_ngx(m), Int(segnr) - 1, collect(Float64, xi), x, jac)
        return x, jac
    else
        throw(ArgumentError("segment_element_transformation: unsupported dimension $d"))
    end
end

"""
    volume_element_transformations(mesh, enr, xis) -> (X, Js)

Batch volume map (`MultiElementTransformation<3,3>`). `xis` is `3×npts` (each
column a reference point). Returns `X` (`3×npts`) and `Js` (`Vector` of 3×3
Jacobian matrices).
"""
function volume_element_transformations(m, enr::Integer, xis::AbstractMatrix{<:Real})
    size(xis, 1) == 3 || throw(ArgumentError("xis must be 3×npts"))
    npts = size(xis, 2)
    xi = vec(collect(Float64, xis))
    x = zeros(Float64, 3 * npts)
    jac = zeros(Float64, 9 * npts)
    Internals.MultiElementTransformation33(_ngx(m), Int(enr) - 1, npts, xi, x, jac)
    X = reshape(x, 3, npts)
    Js = [_unpack_jacobian(jac[(k - 1) * 9 + 1 : k * 9], 3, 3) for k in 1:npts]
    return X, Js
end

# --- topology table toggles (parent edge/face maps) ---------------------------

"""
    enable_topology_table!(mesh, name, set=true)

Enable or disable a `MeshTopology` table on `mesh` (`Internals.EnableTopologyTable`). Use
`"parentedges"` / `"parentfaces"` **before** refinement if you need
[`parent_edges`](@ref) / [`parent_faces`](@ref); parent maps are off by default.
"""
enable_topology_table!(m, name::AbstractString, set::Bool=true) =
    Internals.EnableTopologyTable(m, String(name), set)

# --- parent edge / face maps (after refinement) -----------------------------

"""
    has_parent_edges(mesh) -> Bool

Whether parent-edge maps are configured (`MeshTopology::Internals.HasParentEdges`). This
is `false` on a fresh mesh until you call
[`enable_topology_table!`](@ref)(mesh, "parentedges") and refine.
"""
has_parent_edges(m) = Internals.HasParentEdges(_ngx(m))

"""
    parent_edges(mesh, enr) -> (info, e1, e2, e3)

Parent-edge data for volume element `enr` (1-based). Returns Netgen orientation
`info` and up to three parent edge indices (0-based Netgen edge numbers as
returned by the binding). Requires [`has_parent_edges`](@ref)(mesh).
"""
function parent_edges(m, enr::Integer)
    has_parent_edges(m) || throw(ArgumentError(
        "parent_edges requires parent-edge maps; refine the mesh first"))
    info, e1, e2, e3 = Internals.GetParentEdges(_ngx(m), Int(enr) - 1)
    return Int(info), Int(e1), Int(e2), Int(e3)
end

"""
    parent_faces(mesh, fnr) -> (info, f1, f2, f3, f4)

Parent-face data for face `fnr` (1-based topology face index).
"""
function parent_faces(m, fnr::Integer)
    has_parent_edges(m) || throw(ArgumentError(
        "parent_faces requires parent topology; refine the mesh first"))
    info, f1, f2, f3, f4 = Internals.GetParentFaces(_ngx(m), Int(fnr) - 1)
    return Int(info), Int(f1), Int(f2), Int(f3), Int(f4)
end

"""
    face_edges(mesh, fnr) -> Vector{Int}

Edge indices bounding topology face `fnr` (1-based, `1:GetNFaces(GetTopology(mesh))`).
Uses `Ngx_Mesh::GetFaceEdges`. Call [`Internals.UpdateTopology`](@ref) after mesh
changes if results look stale.
"""
function face_edges(m, fnr::Integer)
    buf = zeros(Cint, 8)
    n = Internals.GetFaceEdges(_ngx(m), Int(fnr) - 1, buf)
    return Int.(buf[1:n])
end

# --- periodic identification --------------------------------------------------

"""
    periodic_vertex_pairs(mesh, idnr=1) -> Vector{Tuple{Int,Int}}

Periodic vertex pairs for identification `idnr` (1-based). Vertex ids in each
pair are **1-based** (converted from Netgen's 0-based Ngx output). Returns an
empty vector when no pairs exist.
"""
function periodic_vertex_pairs(m, idnr::Integer=1)
    n_id = Internals.GetNIdentifications(_ngx(m))
    n_id == 0 && return Tuple{Int,Int}[]
    (1 <= idnr <= n_id) ||
        throw(ArgumentError("identification $idnr out of range (1:$n_id)"))
    buf = zeros(Cint, 2 * max(Internals.GetNP(m), 1))
    n = Internals.GetPeriodicVertices(_ngx(m), idnr - 1, buf)
    n == 0 && return Tuple{Int,Int}[]
    return [(Int(buf[2 * k - 1]) + 1, Int(buf[2 * k]) + 1) for k in 1:n]
end

# --- point location (Ngx FindElementOfPoint) --------------------------------

"""
    find_element(mesh, x; build_searchtree=false, hint=nothing, tol=1e-4)
        -> Union{Nothing, Tuple{Int, Vector{Float64}}}

Locate the mesh cell containing physical point `x` and return `(cell_nr, λ)` where
`cell_nr` is **1-based** and `λ` are the reference/barycentric coordinates from
`Ngx_Mesh::FindElementOfPoint` (length 1 for segments, 2 for surface/domain
triangles, 4 for volume tets in 3D). Returns `nothing` when no cell contains the
point.

`hint` is an optional **1-based** cell index to accelerate the search.
`build_searchtree=true` builds Netgen's search tree first (amortize over many
queries).
"""
function find_element(m, x::AbstractVector{<:Real};
                      build_searchtree::Bool=false,
                      hint::Union{Nothing,Integer}=nothing,
                      tol::Real=1e-4)
    d = Int(Internals.GetDimension(m))
    nm = _ngx(m)
    p = collect(Float64, x)
    hints = hint === nothing ? Cint[] : Cint[Int(hint) - 1]
    if d == 3
        length(p) >= 3 || throw(ArgumentError("x must have length ≥ 3 for a 3D mesh"))
        elnr, l1, l2, l3, l4 = Internals.FindElementOfPoint3(nm, p, build_searchtree, hints, Float64(tol))
        elnr < 0 && return nothing
        return Int(elnr) + 1, Float64[l1, l2, l3, l4]
    elseif d == 2
        length(p) >= 2 || throw(ArgumentError("x must have length ≥ 2 for a 2D mesh"))
        elnr, l1, l2 = Internals.FindElementOfPoint2(nm, p, build_searchtree, hints, Float64(tol))
        elnr < 0 && return nothing
        return Int(elnr) + 1, Float64[l1, l2]
    elseif d == 1
        length(p) >= 1 || throw(ArgumentError("x must have length ≥ 1"))
        elnr, l1 = Internals.FindElementOfPoint1(nm, p, build_searchtree, hints, Float64(tol))
        elnr < 0 && return nothing
        return Int(elnr) + 1, Float64[l1]
    else
        throw(ArgumentError("find_element: unsupported mesh dimension $d"))
    end
end

# --- local mesh size at an existing node ------------------------------------

"""
    mesh_h_at_point(mesh, pi) -> Float64

Local mesh size `h` at mesh node `pi` (1-based), via `Mesh::GetH(PointIndex)`.
"""
mesh_h_at_point(m, pi::Integer) = Internals.GetHPointIndex(m, Int(pi))


"""
    material_codim_name(mesh, codim, region_nr) -> String

Region/material name for codimension `codim` and region index `region_nr`
(1-based). Dispatches to `Ngx_Mesh::GetMaterialCD<DIM>`:

| mesh dim | codim | meaning |
|----------|-------|---------|
| 3D | 0 | volume material (`GetMaterial`) |
| 3D | 1 | boundary condition name |
| 3D | 2 | edge name (`GetCD2Name`) |
| 3D | 3 | vertex name |
| 2D | 2 | domain material |
| 2D | 1 | boundary segment name |
"""
function material_codim_name(m, codim::Integer, region_nr::Integer)
    nm = _ngx(m)
    r0 = Int(region_nr) - 1
    name = if codim == 0
        Internals.GetMaterialCD0(nm, r0)
    elseif codim == 1
        Internals.GetMaterialCD1(nm, r0)
    elseif codim == 2
        Internals.GetMaterialCD2(nm, r0)
    elseif codim == 3
        Internals.GetMaterialCD3(nm, r0)
    else
        throw(ArgumentError("codim must be 0–3 (got $codim)"))
    end
    return String(name)
end
