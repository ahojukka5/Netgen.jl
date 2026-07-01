# --- hierarchy reports ------------------------------------------------------

"""
    MeshLevelReport

Per-level summary inside a mesh hierarchy or session.
"""
struct MeshLevelReport
    level::Int
    node_count::Int
    element_count::Int
    boundary_element_count::Int
    quality::MeshQualityReport
    valid::Bool
end

function Base.show(io::IO, r::MeshLevelReport)
    print(io, "MeshLevelReport(level=", r.level,
          ", nodes=", r.node_count,
          ", cells=", r.element_count,
          ", valid=", r.valid, ")")
end

"""
    TransferReport

Coarse→fine transfer metadata summary between two hierarchy levels.
"""
struct TransferReport
    coarse_level::Int
    fine_level::Int
    valid::Bool
    inherited_node_count::Int
    created_node_count::Int
    parent_map_kind::Symbol
    interpolation_rule_summary::String
    warnings::Vector{DiagnosticMessage}
end

function Base.show(io::IO, r::TransferReport)
    print(io, "TransferReport(", r.coarse_level, "→", r.fine_level,
          ", inherited_nodes=", r.inherited_node_count,
          ", created_nodes=", r.created_node_count,
          ", valid=", r.valid, ")")
end

"""
    MeshHierarchyReport <: AbstractOodiReport

Structured report for [`MeshHierarchy`](@ref) or [`MeshHierarchySession`](@ref).
"""
struct MeshHierarchyReport <: AbstractOodiReport
    valid::Bool
    nlevels::Int
    generation::Union{Int,Nothing}
    levels::Vector{MeshLevelReport}
    transfers::Vector{TransferReport}
    refinement_history::Vector{Symbol}
    warnings::Vector{DiagnosticMessage}
end

function Base.show(io::IO, r::MeshHierarchyReport)
    println(io, "MeshHierarchyReport(valid=", r.valid, ", nlevels=", r.nlevels, ")")
    r.generation !== nothing && println(io, "  generation: ", r.generation)
    for lv in r.levels
        println(io, "  ", lv)
    end
    for tr in r.transfers
        println(io, "  ", tr)
    end
    for w in r.warnings
        println(io, "  warning: ", w.message)
    end
end

function _level_report(m, level::Int)
    vr = validate(m)
    return MeshLevelReport(
        level, num_nodes(m), num_cells(m), num_boundary_facets(m),
        quality(m), vr.valid)
end

function _transfer_report(m_fine, coarse_level::Int, fine_level::Int)
    warnings = DiagnosticMessage[]
    P = parent_nodes(m_fine)
    inherited = count(i -> P[1, i] == 0 && P[2, i] == 0, axes(P, 2))
    created = size(P, 2) - inherited
    valid = true
    inherited == 0 && fine_level > 1 &&
        _append!(warnings, :warning, :no_inherited_nodes,
            "no inherited nodes on level $fine_level (unexpected for bisection refine)")
    return TransferReport(
        coarse_level, fine_level, valid,
        inherited, created,
        :parent_nodes_2stencil,
        "topological bisection: new nodes interpolate 1/2–1/2 between two coarse parents",
        warnings)
end

"""Collect live mesh handles from a hierarchy-like object."""
function _hierarchy_meshes(h)
    if h isa MeshHierarchy
        return h.meshes, nothing
    elseif h isa MeshHierarchySession
        return h.meshes, h.generation
    else
        throw(ArgumentError("expected MeshHierarchy or MeshHierarchySession, got $(typeof(h))"))
    end
end

"""
    level_report(hierarchy, level) -> MeshLevelReport

Report for one level of a [`MeshHierarchy`](@ref) or [`MeshHierarchySession`](@ref).
"""
function level_report(h, level::Integer)
    meshes, _ = _hierarchy_meshes(h)
    1 <= level <= length(meshes) ||
        throw(ArgumentError("level $level out of range 1:$(length(meshes))"))
    return _level_report(meshes[level], Int(level))
end

"""
    transfer_report(hierarchy, coarse_level, fine_level) -> TransferReport

Transfer metadata between adjacent levels (`fine_level == coarse_level + 1`).
"""
function transfer_report(h, coarse_level::Integer, fine_level::Integer)
    fine_level == coarse_level + 1 ||
        throw(ArgumentError("fine_level must equal coarse_level + 1"))
    meshes, _ = _hierarchy_meshes(h)
    fine_level <= length(meshes) ||
        throw(ArgumentError("fine_level $fine_level out of range"))
    return _transfer_report(meshes[fine_level], Int(coarse_level), Int(fine_level))
end

"""
    hierarchy_report(hierarchy) -> MeshHierarchyReport

Full hierarchy consistency report for LLM / Oodi GMG verification.
"""
function hierarchy_report(h)
    meshes, gen = _hierarchy_meshes(h)
    warnings = DiagnosticMessage[]
    levels = MeshLevelReport[_level_report(meshes[k], k) for k in 1:length(meshes)]
    transfers = TransferReport[
        _transfer_report(meshes[k], k - 1, k) for k in 2:length(meshes)]
    valid = all(l -> l.valid, levels)

    for k in 2:length(levels)
        if levels[k].element_count <= levels[k - 1].element_count
            _append!(warnings, :warning, :refinement_did_not_grow,
                "level $k has no more cells than level $(k - 1)")
            valid = false
        end
        if levels[k].node_count <= levels[k - 1].node_count
            _append!(warnings, :warning, :nodes_did_not_grow,
                "level $k has no more nodes than level $(k - 1)")
        end
    end

    history = Symbol[:initial]
    for _ in 2:length(meshes)
        push!(history, :refined)
    end

    return MeshHierarchyReport(
        valid, length(meshes), gen, levels, transfers, history, warnings)
end

"""
    mesh_hierarchy(geometry; maxh, levels=1, kwargs...) -> MeshHierarchy

Build a [`MeshHierarchy`](@ref) with `levels` uniform levels (alias for
[`uniform_hierarchy`](@ref)).
"""
mesh_hierarchy(geom; maxh::Real, levels::Integer=1, kwargs...) =
    uniform_hierarchy(geom; maxh=maxh, levels=levels)
