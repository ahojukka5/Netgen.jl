# --- hp-adaptivity: read + apply --------------------------------------------
# Julia helpers over the wrapped Ngx_Mesh hp/order/refinement accessors.
#
# Indexing conventions (netgen/libsrc/interface/nginterface_v2.cpp):
#   Get/SetElementOrder(s), Get/SetSurfaceElementOrder(s): enr is 1-based.
#   Internals.GetHPElementLevel(ei, dir): ei is 0-based internally (ei++ in C++).
#   Internals.SetRefinementFlag2/3(elnr, flag): elnr is 0-based.
#
# Delone.jl exposes apply-side hp/p helpers but does **not** implement an
# hp-adaptive solve strategy — consumers own marking policies and solvers.

_ngx_mesh(m) = Internals.Ngx_Mesh(m)

# --- order readers ----------------------------------------------------------

"""
    element_orders(mesh) -> Vector{Int}

Per top-dimensional cell polynomial order (`Ngx_Mesh::GetElementOrder`, 1-based
enr; volume elements in 3D, triangles in 2D). Length is `GetNE` (3D) or
`GetNSE` (2D). A freshly generated linear mesh returns all `1`.
"""
function element_orders(m)
    nm = _ngx_mesh(m)
    return Int[Internals.GetElementOrder(nm, i) for i in 1:_ncells(m)]
end

"""element_order(mesh) -> maximum(element_orders(mesh)) (`1` if empty)."""
function element_order(m)
    os = element_orders(m)
    return isempty(os) ? 1 : maximum(os)
end

"""
    surface_element_orders(mesh) -> Vector{Int}

Per boundary triangle order (`Ngx_Mesh::GetSurfaceElementOrder`). **3D only**.
"""
function surface_element_orders(m)
    d = Internals.GetDimension(m)
    d == 3 || throw(ArgumentError(
        "surface_element_orders requires a 3D mesh (got dim=$d)"))
    nm = _ngx_mesh(m)
    return Int[Internals.GetSurfaceElementOrder(nm, i) for i in 1:Internals.GetNSE(m)]
end

"""surface_element_order(mesh) -> maximum(surface_element_orders(mesh)). 3D only."""
function surface_element_order(m)
    os = surface_element_orders(m)
    return isempty(os) ? 1 : maximum(os)
end

"""
    hp_element_levels(mesh) -> 3×ncells Matrix{Int}

Per cell hp-refinement level in each direction (`GetHPElementLevel`). `-1` when
no hp-element table exists (mesh not hp-refined through Netgen's hp path).
"""
function hp_element_levels(m)
    nm = _ngx_mesh(m)
    nc = _ncells(m)
    L = Matrix{Int}(undef, 3, nc)
    for i in 1:nc
        for dir in 1:3
            L[dir, i] = Internals.GetHPElementLevel(nm, i - 1, dir)
        end
    end
    return L
end

"""
    element_orders_xyz(mesh) -> (ox, oy, oz) vectors

Per cell anisotropic orders (`GetElementOrders`). In 2D, `oz` is filled but
ignored by Netgen for surface elements.
"""
function element_orders_xyz(m)
    nm = _ngx_mesh(m)
    nc = _ncells(m)
    ox = Vector{Int}(undef, nc)
    oy = Vector{Int}(undef, nc)
    oz = Vector{Int}(undef, nc)
    buf = zeros(Cint, 3)
    for i in 1:nc
        Internals.GetElementOrders(nm, i, buf)
        ox[i] = buf[1]; oy[i] = buf[2]; oz[i] = buf[3]
    end
    return ox, oy, oz
end

# --- order setters (p-refinement apply) -------------------------------------

"""
    set_element_order!(mesh, enr, order) -> mesh

Set the isotropic polynomial order of top-dimensional cell `enr` (1-based) via
`Ngx_Mesh::SetElementOrder`. Does not refine the mesh topology.
"""
function set_element_order!(m, enr::Integer, order::Integer)
    Internals.SetElementOrder(_ngx_mesh(m), Int(enr), Int(order))
    return m
end

"""
    set_element_orders!(mesh, enr, ox, oy, oz) -> mesh

Set anisotropic orders of cell `enr` (1-based) via `Ngx_Mesh::SetElementOrders`.
In 2D only `ox`, `oy` are used by Netgen.
"""
function set_element_orders!(m, enr::Integer, ox::Integer, oy::Integer, oz::Integer)
    Internals.SetElementOrders(_ngx_mesh(m), Int(enr), Int(ox), Int(oy), Int(oz))
    return m
end

"""
    set_element_orders!(mesh, orders) -> mesh

Bulk isotropic p-refinement: set order of every top-dimensional cell from
`orders` (length `GetNE` in 3D / `GetNSE` in 2D, 1-based indexing).
"""
function set_element_orders!(m, orders::AbstractVector{<:Integer})
    nc = _ncells(m)
    length(orders) == nc ||
        throw(ArgumentError("orders length must be $nc (got $(length(orders)))"))
    nm = _ngx_mesh(m)
    for i in 1:nc
        Internals.SetElementOrder(nm, i, Int(orders[i]))
    end
    return m
end

"""
    set_surface_element_order!(mesh, enr, order) -> mesh

Set boundary triangle order (1-based `enr`, 3D only).
"""
function set_surface_element_order!(m, enr::Integer, order::Integer)
    Internals.GetDimension(m) == 3 || throw(ArgumentError("set_surface_element_order! is 3D only"))
    Internals.SetSurfaceElementOrder(_ngx_mesh(m), Int(enr), Int(order))
    return m
end

"""
    set_surface_element_orders!(mesh, enr, ox, oy) -> mesh

Set anisotropic boundary triangle orders (3D only).
"""
function set_surface_element_orders!(m, enr::Integer, ox::Integer, oy::Integer)
    Internals.GetDimension(m) == 3 || throw(ArgumentError("set_surface_element_orders! is 3D only"))
    Internals.SetSurfaceElementOrders(_ngx_mesh(m), Int(enr), Int(ox), Int(oy))
    return m
end

"""
    set_surface_element_orders!(mesh, orders) -> mesh

Bulk-set boundary triangle orders from `orders` (length `GetNSE`, 3D only).
"""
function set_surface_element_orders!(m, orders::AbstractVector{<:Integer})
    Internals.GetDimension(m) == 3 || throw(ArgumentError("set_surface_element_orders! is 3D only"))
    nse = Internals.GetNSE(m)
    length(orders) == nse ||
        throw(ArgumentError("orders length must be $nse (got $(length(orders)))"))
    nm = _ngx_mesh(m)
    for i in 1:nse
        Internals.SetSurfaceElementOrder(nm, i, Int(orders[i]))
    end
    return m
end

# --- marked h/p/hp refinement (Ngx_Mesh path) ------------------------------

"""
    mark_for_ngx_refinement!(mesh, marked) -> mesh

Set refinement flags on top-dimensional cells for the `Ngx_Mesh::Refine` /
`Internals.NgxRefine` path (`Internals.SetRefinementFlag2/3`, 0-based internally). `marked` is
indexed `1:ncells(mesh)`. Equivalent to [`mark_for_refinement!`](@ref) for
volume elements in 3D but uses the Ngx entry point required before
[`ngx_refine!`](@ref).
"""
function mark_for_ngx_refinement!(m, marked)
    nc = _ncells(m)
    length(marked) == nc ||
        throw(ArgumentError("marked length must be $nc (got $(length(marked)))"))
    nm = _ngx_mesh(m)
    d = Int(Internals.GetDimension(m))
    if d == 3
        for i in 1:nc
            Internals.SetRefinementFlag3(nm, i - 1, Bool(marked[i]))
        end
    elseif d == 2
        for i in 1:nc
            Internals.SetRefinementFlag2(nm, i - 1, Bool(marked[i]))
        end
    else
        throw(ArgumentError("mark_for_ngx_refinement!: unsupported dimension $d"))
    end
    return m
end

"""
    ngx_refine!(mesh; reftype=NG_REFINE_H, onlyonce=false) -> mesh

Marked-element refinement via `Ngx_Mesh::Refine` (`Internals.NgxRefine` binding). Mark
cells first with [`mark_for_ngx_refinement!`](@ref) or [`mark_for_refinement!`](@ref).

`reftype` is one of [`NG_REFINE_H`](@ref), [`NG_REFINE_P`](@ref),
[`NG_REFINE_HP`](@ref). Operates **in place** on `mesh` (does not copy). Updates
topology and rebuilds curved elements when the mesh is high-order.
"""
function ngx_refine!(m; reftype::Integer=NG_REFINE_H, onlyonce::Bool=false)
    reftype in (NG_REFINE_H, NG_REFINE_P, NG_REFINE_HP) ||
        throw(ArgumentError("reftype must be NG_REFINE_H/P/HP (got $reftype)"))
    Internals.NgxRefine(_ngx_mesh(m), Int(reftype), onlyonce)
    return m
end

"""
    hp_refine!(mesh; levels=1, parameter=0.125, setorders=true, ref_level=false) -> mesh

Global hp split via `Ngx_Mesh::HPRefinement` (`SPLIT_HP`). Refines the whole mesh
according to Netgen's hp-refinement driver — not element-wise marking. Useful to
bootstrap an hp mesh or apply a uniform hp pattern.
"""
function hp_refine!(m; levels::Integer=1, parameter::Real=0.125,
                    setorders::Bool=true, ref_level::Bool=false)
    Internals.HPRefinement(_ngx_mesh(m), Int(levels), Float64(parameter),
                 setorders, ref_level)
    return m
end

"""
    split_alfeld!(mesh) -> mesh

Alfeld-type hp split via `Ngx_Mesh::SplitAlfeld` (`SPLIT_ALFELD`). In-place.
"""
split_alfeld!(m) = (Internals.SplitAlfeld(_ngx_mesh(m)); m)

# --- cluster representatives (hp hanging-node metadata) ---------------------
# Requires hp-internal cluster state — only valid after hp_refinement paths
# (`hp_refine!`, `split_alfeld!`, marked hp via `ngx_refine!`, etc.).

"""Return `true` when the mesh carries hp cluster metadata (`hp_element_levels` not all `-1`)."""
hp_clusters_available(m) = any(!=(-1), hp_element_levels(m))

function _require_hp_clusters(m, what::String)
    hp_clusters_available(m) || throw(ArgumentError(
        "$what requires hp cluster metadata on the mesh; hp_element_levels are all -1. " *
        "Run hp_refine!, split_alfeld!, or marked hp refinement first."))
end

"""cluster_rep_vertex(mesh, vi) -> cluster representative vertex id (1-based Netgen index)."""
cluster_rep_vertex(m, vi::Integer) = (
    _require_hp_clusters(m, "cluster_rep_vertex");
    Internals.GetClusterRepVertex(_ngx_mesh(m), Int(vi)))

"""cluster_rep_edge(mesh, edi) -> cluster representative edge id."""
cluster_rep_edge(m, edi::Integer) = (
    _require_hp_clusters(m, "cluster_rep_edge");
    Internals.GetClusterRepEdge(_ngx_mesh(m), Int(edi)))

"""cluster_rep_face(mesh, fai) -> cluster representative face id."""
cluster_rep_face(m, fai::Integer) = (
    _require_hp_clusters(m, "cluster_rep_face");
    Internals.GetClusterRepFace(_ngx_mesh(m), Int(fai)))

"""cluster_rep_element(mesh, eli) -> cluster representative element id."""
cluster_rep_element(m, eli::Integer) = (
    _require_hp_clusters(m, "cluster_rep_element");
    Internals.GetClusterRepElement(_ngx_mesh(m), Int(eli)))

"""
    cluster_rep_vertices(mesh) -> Vector{Int}

Per vertex (`1:GetNP`), its hp cluster representative. Requires
[`hp_clusters_available`](@ref)(mesh).
"""
function cluster_rep_vertices(m)
    _require_hp_clusters(m, "cluster_rep_vertices")
    np = Internals.GetNP(m)
    nm = _ngx_mesh(m)
    return Int[Internals.GetClusterRepVertex(nm, i) for i in 1:np]
end

"""
    cluster_rep_elements(mesh) -> Vector{Int}

Per top-dimensional cell, its hp cluster representative. Requires
[`hp_clusters_available`](@ref)(mesh).
"""
function cluster_rep_elements(m)
    _require_hp_clusters(m, "cluster_rep_elements")
    nc = _ncells(m)
    nm = _ngx_mesh(m)
    return Int[Internals.GetClusterRepElement(nm, i) for i in 1:nc]
end
