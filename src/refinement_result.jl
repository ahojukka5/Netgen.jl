# --- structured refinement results ------------------------------------------

"""
    RefinementResult <: AbstractOodiReport

Structured outcome of a hierarchy refinement operation.
"""
struct RefinementResult <: AbstractOodiReport
    success::Bool
    old_level_count::Int
    new_level_count::Int
    old_element_count::Int
    new_element_count::Int
    created_nodes::Int
    created_elements::Int
    transfer_available::Bool
    diagnostics::Vector{DiagnosticMessage}
end

function Base.show(io::IO, r::RefinementResult)
    print(io, "RefinementResult(success=", r.success,
          ", levels ", r.old_level_count, "→", r.new_level_count,
          ", cells ", r.old_element_count, "→", r.new_element_count, ")")
end

function _refinement_result!(h, old_levels, old_ne, old_np; transfer_available=true)
    new_levels = nlevels(h)
    m_new = finest(h)
    new_ne = num_cells(m_new)
    new_np = num_nodes(m_new)
    diags = DiagnosticMessage[]
    success = new_levels > old_levels && new_ne > old_ne
    !success && _append!(diags, :error, :refinement_failed,
        "refinement did not increase level count or element count")
    return RefinementResult(
        success, old_levels, new_levels,
        old_ne, new_ne,
        new_np - old_np, new_ne - old_ne,
        transfer_available, diags)
end

"""
    refine!(hierarchy; mode=:uniform, marked_elements=nothing, result=false)

Refine a [`MeshHierarchy`](@ref). With `result=true`, return a [`RefinementResult`](@ref).

Modes: `:uniform` (default) or `:marked` (requires `marked_elements`).
"""
function refine!(h::MeshHierarchy; mode::Symbol=:uniform,
                 marked_elements=nothing, result::Bool=false)
    old_levels = nlevels(h)
    m = finest(h)
    old_ne = num_cells(m)
    old_np = num_nodes(m)
    if mode == :uniform
        refine_uniform!(h)
    elseif mode == :marked
        marked_elements === nothing &&
            throw(ArgumentError("marked_elements required for mode=:marked"))
        refine_marked!(h, marked_elements)
    else
        throw(ArgumentError("unsupported refinement mode: $mode"))
    end
    res = _refinement_result!(h, old_levels, old_ne, old_np)
    return result ? res : (res.success ? h : throw(ArgumentError(string(res))))
end

"""
    refine_session!(session; mode=:uniform, marked_elements=nothing, result=false)

Refine a [`MeshHierarchySession`](@ref) via `request_*!` and optionally return
[`RefinementResult`](@ref).
"""
function refine_session!(s::MeshHierarchySession; mode::Symbol=:uniform,
                         marked_elements=nothing, result::Bool=false)
    old_levels = nlevels(s)
    old_ne = num_cells(finest(s))
    old_np = num_nodes(finest(s))
    if mode == :uniform
        request_uniform_refinement!(s)
    elseif mode == :marked
        marked_elements === nothing &&
            throw(ArgumentError("marked_elements required for mode=:marked"))
        request_marked_refinement!(s, marked_elements)
    else
        throw(ArgumentError("unsupported refinement mode: $mode"))
    end
    res = _refinement_result!(s, old_levels, old_ne, old_np)
    return result ? res : (res.success ? s : throw(ArgumentError(string(res))))
end
