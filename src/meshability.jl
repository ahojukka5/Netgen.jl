# --- pre-meshing diagnostics & suggestions ----------------------------------
#
# Watertightness (open boundary facets): Netgen's `Mesh::FindOpenElements` /
# `Mesh::FindOpenSegments` are the natural native check ("N open boundary
# elements"), but they were investigated and found not to be wireable into a
# count today — they populate internal C++ arrays (`GetNOpenElements()`,
# `GetNOpenSegments()`) that are not exposed through the current `Netgen`
# CxxWrap bindings, and their only Julia-visible side effect is a suppressed
# (verbosity-5) PrintMessage, not a stable value. See `NativeQualityReport`'s
# docstring in quality.jl for the full writeup. Exposing them for real needs
# new bindings (`GetNOpenElements`, `GetNOpenSegments`, and ideally
# `OpenElements()`/`GetOpenSegment(i)` for per-facet indices) added to the
# C++ wrapper layer — out of scope for a Julia-only change.

"""
    MeshabilityReport <: AbstractReadinessReport

Geometry-to-mesh feasibility hints before or after a meshing attempt.
"""
struct MeshabilityReport <: AbstractReadinessReport
    likely_meshable::Union{Bool,Nothing}
    geometry_valid::Union{Bool,Nothing}
    target_h::Float64
    failure_stage::Union{Symbol,Nothing}
    backend_message::Union{String,Nothing}
    suggestions::Vector{DiagnosticMessage}
end

function Base.show(io::IO, r::MeshabilityReport)
    print(io, "MeshabilityReport(likely_meshable=", r.likely_meshable,
          ", target_h=", r.target_h, ")")
    r.failure_stage !== nothing && print(io, "\n  failure_stage: ", r.failure_stage)
    r.backend_message !== nothing && print(io, "\n  backend: ", r.backend_message)
    for s in r.suggestions
        print(io, "\n  suggest: ", s.message)
    end
end

function Base.summary(io::IO, r::MeshabilityReport)
    print(io, "MeshabilityReport(likely_meshable=", r.likely_meshable,
          ", target_h=", r.target_h, ")")
end

function Base.show(io::IO, ::MIME"text/html", r::MeshabilityReport)
    print(io, "<div class=\"delone-report\"><table><caption>MeshabilityReport</caption>",
          "<tr><th>likely_meshable</th><td>", r.likely_meshable, "</td></tr>",
          "<tr><th>geometry_valid</th><td>", r.geometry_valid, "</td></tr>",
          "<tr><th>target_h</th><td>", r.target_h, "</td></tr>",
          "<tr><th>failure_stage</th><td>", r.failure_stage === nothing ? "—" : r.failure_stage, "</td></tr></table>")
    if r.backend_message !== nothing
        print(io, "<p><b>backend:</b> ", _html_escape(r.backend_message), "</p>")
    end
    if !isempty(r.suggestions)
        print(io, "<ul>")
        for s in r.suggestions
            print(io, "<li>", _html_escape(s.message), "</li>")
        end
        print(io, "</ul>")
    end
    print(io, "</div>")
end

"""
    meshability_report(geometry; options::MeshOptions) -> MeshabilityReport

Pre-meshing sanity check: validates options and geometry presence. Does not
guarantee meshing success but surfaces obvious blockers and tuning hints.
"""
function meshability_report(geom; options::MeshOptions)
    suggestions = DiagnosticMessage[]
    validate_options!(options)
    geom === nothing && return MeshabilityReport(
        false, false, options.maxh, :geometry_import, "geometry is nothing",
        [_diagnostic(:suggestion, :provide_geometry, "provide a valid geometry object")])

    if options.maxh <= 0
        _append!(suggestions, :suggestion, :fix_maxh, "set maxh > 0")
    end
    options.minh !== nothing && options.minh > options.maxh &&
        _append!(suggestions, :suggestion, :fix_minh, "ensure minh ≤ maxh")

    _append!(suggestions, :suggestion, :start_coarse,
        "start with a coarser maxh (e.g. $(options.maxh * 2)) then refine locally")
    if options.optimize
        _append!(suggestions, :suggestion, :optimize_later,
            "for debugging failures, try optimize=false first")
    end

    return MeshabilityReport(true, true, options.maxh, nothing, nothing, suggestions)
end

"""
    meshing_diagnostics(geometry, options, result::MeshGenerationResult) -> MeshabilityReport

Post-mortem diagnostics combining options and a generation result.
"""
function meshing_diagnostics(geom, options::MeshOptions, result::MeshGenerationResult)
    sugs = copy(result.diagnostics.suggestions)
    if !result.success
        result.diagnostics.failure_stage == :surface_mesh &&
            _append!(sugs, :suggestion, :heal_cad,
                "heal/repair CAD or remove sliver faces before remeshing")
        result.diagnostics.failure_stage == :volume_mesh &&
            _append!(sugs, :suggestion, :coarsen,
                "increase maxh or simplify small features")
    end
    backend_msg = isempty(result.diagnostics.messages) ? nothing :
        join([m.message for m in result.diagnostics.messages], "; ")
    return MeshabilityReport(
        result.success, result.success, options.maxh,
        result.diagnostics.failure_stage, backend_msg, sugs)
end

"""
    suggest_mesh_fixes(result::MeshGenerationResult) -> Vector{DiagnosticMessage}

Return actionable suggestions from a failed or low-quality generation result.
"""
suggest_mesh_fixes(r::MeshGenerationResult) = r.diagnostics.suggestions

suggest_mesh_fixes(r::MeshGenerationResult, report::MeshReport) = begin
    sugs = copy(r.diagnostics.suggestions)
    report.quality.inverted_element_count > 0 &&
        _append!(sugs, :suggestion, :fix_inverted,
            "inverted elements detected — coarsen mesh or repair geometry")
    report.quality.bad_element_count > 0 &&
        _append!(sugs, :suggestion, :improve_quality,
            "run improve_mesh! or reduce maxh near small features")
    report.tags.untagged_boundary_count > 0 &&
        _append!(sugs, :suggestion, :tag_boundaries,
            "$(report.tags.untagged_boundary_count) untagged boundary facets — check CAD BC names")
    # --- native Netgen diagnostics (see MeshQualityReport's netgen_* fields) --
    !report.quality.netgen_volume_mesh_ok &&
        _append!(sugs, :suggestion, :netgen_orientation_check,
            "Netgen's CheckVolumeMesh flagged one or more elements with wrong " *
            "orientation (see stdout for \"ERROR: Element <i> has wrong " *
            "orientation\" — Netgen prints this directly, it is not currently " *
            "surfaced as a count/list; see NativeQualityReport docstring) — " *
            "try improve_mesh! or coarsen/repair the source geometry")
    !report.quality.netgen_boundary_ok &&
        _append!(sugs, :suggestion, :netgen_boundary_check,
            "Netgen's CheckConsistentBoundary reported an inconsistent " *
            "boundary — check for open/non-manifold surfaces in the CAD input")
    report.quality.netgen_overlapping_boundary &&
        _append!(sugs, :suggestion, :netgen_overlap_check,
            "Netgen's CheckOverlappingBoundary detected overlapping/" *
            "self-intersecting boundary elements — heal the CAD geometry " *
            "before remeshing")
    report.quality.netgen_open_element_count > 0 &&
        _append!(sugs, :suggestion, :netgen_open_boundary,
            "$(report.quality.netgen_open_element_count) boundary facets are " *
            "unpaired (Netgen's FindOpenElements) — the volume mesh's boundary " *
            "is not watertight; check for gaps/non-manifold surfaces in the " *
            "source geometry")
    return sugs
end
