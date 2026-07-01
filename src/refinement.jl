# --- refinement -------------------------------------------------------------
"""refine!(mesh) -> mesh, refined uniformly in place (geometry-aware)."""
function refine!(m)
    Internals.Refine(Internals.GetRefinement(Internals.GetGeometry(m)), m)
    return m
end

"""
    mark_for_refinement!(mesh, marked) -> mesh

Set each volume element's refinement flag from `marked` (a `1:ncells`-indexed
boolean vector / predicate). Use before [`bisect!`](@ref).
"""
function mark_for_refinement!(m, marked)
    for i in 1:Internals.GetNE(m)
        Internals.SetRefinementFlag(Internals.VolumeElement(m, i), Bool(marked[i]))
    end
    return m
end

"""
    bisect!(mesh; onlyonce=false, maxlevel=0, refine_p=false, refine_hp=false) -> mesh

Marked-element bisection refinement (geometry-aware). Mark elements first with
[`mark_for_refinement!`](@ref).
"""
function bisect!(m; onlyonce::Bool=false, maxlevel::Integer=0,
                 refine_p::Bool=false, refine_hp::Bool=false)
    opt = Internals.BisectionOptions()
    Internals.usemarkedelements!(opt, 1)
    Internals.onlyonce!(opt, onlyonce)
    maxlevel > 0 && Internals.maxlevel!(opt, Int(maxlevel))
    refine_p && Internals.refine_p!(opt, true)
    refine_hp && Internals.refine_hp!(opt, true)
    Internals.Bisect(Internals.GetRefinement(Internals.GetGeometry(m)), m, opt)
    return m
end

"""make_second_order!(mesh) -> mesh, curve to second order (geometry-aware)."""
function make_second_order!(m)
    Internals.MakeSecondOrder(Internals.GetRefinement(Internals.GetGeometry(m)), m)
    return m
end
