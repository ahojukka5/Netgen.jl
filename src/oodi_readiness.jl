# --- Oodi snapshot readiness ------------------------------------------------

"""
    OodiSnapshotReadiness <: AbstractReadinessReport

Report whether a mesh or hierarchy can be exported via the Oodi snapshot contract
for downstream Oodi.jl consumption.
"""
struct OodiSnapshotReadiness <: AbstractReadinessReport
    ready::Bool
    dimension::Union{Int,Nothing}
    element_type::Union{Symbol,Nothing}
    hierarchy_levels::Union{Int,Nothing}
    parent_node_transfers::Symbol   # :available, :missing, :partial
    parent_element_transfers::Symbol
    boundary_tags::Symbol           # :available, :missing, :partial
    region_tags::Symbol
    order::Symbol                   # :linear, :second_order, :mixed, :unknown
    warnings::Vector{DiagnosticMessage}
end

function Base.show(io::IO, r::OodiSnapshotReadiness)
    println(io, "OodiSnapshotReadiness")
    println(io, "  ready: ", r.ready)
    r.dimension !== nothing && println(io, "  dimension: ", r.dimension)
    r.element_type !== nothing && println(io, "  element_type: ", r.element_type)
    r.hierarchy_levels !== nothing && println(io, "  hierarchy_levels: ", r.hierarchy_levels)
    println(io, "  parent_node_transfers: ", r.parent_node_transfers)
    println(io, "  parent_element_transfers: ", r.parent_element_transfers)
    println(io, "  boundary_tags: ", r.boundary_tags)
    println(io, "  region_tags: ", r.region_tags)
    println(io, "  order: ", r.order)
    for w in r.warnings
        println(io, "  warning: ", w.message)
    end
end

function _detect_order(m)
    try
        orders = element_orders(m)
        all(o -> o == 1, orders) && return :linear
        all(o -> o == 2, orders) && return :second_order
        return :mixed
    catch
        return :unknown
    end
end

function _tag_availability(m)
    bt = boundary_tags(m)
    rt = region_tags(m)
    bstatus = isempty(bt) ? :missing : (tag_report(m).untagged_boundary_count > 0 ? :partial : :available)
    rstatus = isempty(rt) ? :missing : (tag_report(m).untagged_region_count > 0 ? :partial : :available)
    return bstatus, rstatus
end

"""
    oodi_snapshot_readiness(mesh) -> OodiSnapshotReadiness

Check whether a single mesh is ready for [`level_snapshot`](@ref)-style export.
"""
function oodi_snapshot_readiness(m)
    warnings = DiagnosticMessage[]
    d = mesh_dimension(m)
    snap_ok = supported_snapshot_topology(m)
    !snap_ok && _append!(warnings, :warning, :unsupported_topology,
        "mesh is not pure simplex Tet4/Tri3 topology supported by snapshots")
    etype = d == 3 ? :Tet4 : (d == 2 ? :Tri3 : nothing)
    btags, rtags = _tag_availability(m)
    order = _detect_order(m)
    order == :second_order &&
        _append!(warnings, :warning, :high_order_export,
            "second-order nodes may appear in coordinates but volume connectivity stays linear")
    ready = snap_ok && validate(m).valid && num_cells(m) > 0
    return OodiSnapshotReadiness(
        ready, d, etype, 1,
        :missing, :missing,
        btags, rtags, order, warnings)
end

"""
    oodi_snapshot_readiness(session_or_hierarchy) -> OodiSnapshotReadiness

Check hierarchy/session readiness including transfer metadata.
"""
function oodi_snapshot_readiness(h::Union{MeshHierarchy,MeshHierarchySession})
    warnings = DiagnosticMessage[]
    m = finest(h)
    base = oodi_snapshot_readiness(m)
    append!(warnings, base.warnings)
    nl = nlevels(h)
    hr = hierarchy_report(h)
    !hr.valid && _append!(warnings, :warning, :hierarchy_invalid,
        "hierarchy_report flagged consistency issues")

    parent_nodes_ok = all(tr -> tr.valid, hr.transfers)
    parent_elems_ok = nl >= 2  # parent_elements available on refined levels

    nl >= 2 && !parent_nodes_ok &&
        _append!(warnings, :warning, :transfer_incomplete,
            "parent-node transfer maps may be incomplete")

    ready = base.ready && hr.valid && parent_nodes_ok
    return OodiSnapshotReadiness(
        ready, base.dimension, base.element_type, nl,
        parent_nodes_ok ? :available : :missing,
        parent_elems_ok ? :available : :missing,
        base.boundary_tags, base.region_tags, base.order, warnings)
end
