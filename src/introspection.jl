# --- LLM-native introspection contract --------------------------------------
# Generic, read-only entry points for the Oodi pipeline (see AGENTS.md):
#   report(x)             -> "what is this object?"
#   validate(x)           -> "is this object internally valid?"
#   readiness(x, target)  -> "can this object move to the requested next stage?"
# These generics, `to_namedtuple`, and the base marker/report types
# (AbstractPipelineTarget, PipelineTarget, ValidationReport, ReadinessReport,
# DiagnosticMessage, ...) are owned by OodiCore (`using OodiCore` in
# Delone.jl) so that this package and any sibling Oodi package can extend the
# same generics without name collisions. This file only adds methods and
# concrete target/report subtypes.
# Read-only; mutation stays in `!`-suffixed functions.

# --- pipeline target markers ------------------------------------------------

"""
    MeshingTarget(; options=nothing)

Readiness target: "can this geometry be meshed?". Carries the [`MeshOptions`](@ref)
that meshing would use (required to assess sizing-dependent meshability).
"""
struct MeshingTarget <: AbstractPipelineTarget
    options::Union{Nothing,MeshOptions}
end
MeshingTarget(; options::Union{Nothing,MeshOptions}=nothing) = MeshingTarget(options)

"""
    OodiImportTarget()

Readiness target: "can this mesh/hierarchy be exported to Oodi.jl?" (snapshot
contract). Delegates to [`oodi_snapshot_readiness`](@ref).
"""
struct OodiImportTarget <: AbstractPipelineTarget end

"""
    GeometricMultigridTarget()

Readiness target: "is this hierarchy usable for geometric multigrid?" (≥2 levels
with valid coarse→fine transfers).
"""
struct GeometricMultigridTarget <: AbstractPipelineTarget end

# --- report(x) --------------------------------------------------------------

"""
    report(x) -> structured report

Main read-only introspection entry point. Returns the canonical structured
report for `x` (all have readable `show` methods and serialize via
[`to_namedtuple`](@ref)):

- mesh handle → [`mesh_report`](@ref) (`MeshReport`)
- [`MeshHierarchy`](@ref) / [`MeshHierarchySession`](@ref) → [`hierarchy_report`](@ref)
- [`MeshGenerationResult`](@ref) / `RefinementResult` → the result object itself
"""
report(m) = mesh_report(m)
report(x::MeshGenerationResult) = x
report(x::RefinementResult) = x
report(h::MeshHierarchy) = hierarchy_report(h)
report(s::MeshHierarchySession) = hierarchy_report(s)

# --- validate(x) extensions -------------------------------------------------
# validate(mesh) already lives in validation.jl. Extend to options here.

"""
    validate(options::MeshOptions) -> ValidationReport

Non-throwing option consistency check (mirrors the throwing
[`validate_options!`](@ref)).
"""
function validate(opts::MeshOptions)
    diagnostics = DiagnosticMessage[]
    opts.maxh > 0 || push!(diagnostics, error_diagnostic(:invalid_maxh, "maxh must be > 0 (got $(opts.maxh))"))
    if opts.minh !== nothing
        opts.minh > 0 || push!(diagnostics, error_diagnostic(:invalid_minh, "minh must be > 0 (got $(opts.minh))"))
        opts.minh !== nothing && opts.minh > opts.maxh &&
            push!(diagnostics, error_diagnostic(:minh_gt_maxh, "minh ($(opts.minh)) must be ≤ maxh ($(opts.maxh))"))
    end
    opts.grading !== nothing && opts.grading < 0 &&
        push!(diagnostics, error_diagnostic(:invalid_grading, "grading must be ≥ 0"))
    opts.dimension !== nothing && opts.dimension ∉ (2, 3) &&
        push!(diagnostics, error_diagnostic(:invalid_dimension, "dimension must be 2 or 3"))
    opts.second_order &&
        push!(diagnostics, warning(:second_order_export,
            "second-order elements are curved but export connectivity stays linear"))
    valid = !any(d -> d.severity == :error, diagnostics)
    return ValidationReport(:mesh_options, valid, diagnostics, (;))
end

# --- readiness(x, target) ---------------------------------------------------

"""
    readiness(x, target::AbstractPipelineTarget) -> readiness report

Fitness of `x` for a specific next pipeline stage. Supported targets:

- [`MeshingTarget`](@ref) on a geometry → [`meshability_report`](@ref)
- [`OodiImportTarget`](@ref) on a mesh/hierarchy → [`oodi_snapshot_readiness`](@ref)
- [`GeometricMultigridTarget`](@ref) on a hierarchy/session → [`ReadinessReport`](@ref)
"""
function readiness(geom, t::MeshingTarget)
    t.options === nothing && throw(ArgumentError(
        "MeshingTarget requires options=MeshOptions(...) to assess meshability"))
    return meshability_report(geom; options=t.options)
end

readiness(x, ::OodiImportTarget) = oodi_snapshot_readiness(x)

function readiness(h::Union{MeshHierarchy,MeshHierarchySession}, ::GeometricMultigridTarget)
    diagnostics = DiagnosticMessage[]
    hr = hierarchy_report(h)
    ready = true
    if hr.nlevels < 2
        ready = false
        push!(diagnostics, error_diagnostic(:too_few_levels,
            "geometric multigrid needs ≥ 2 levels (got $(hr.nlevels))"))
    end
    if !hr.valid
        ready = false
        push!(diagnostics, error_diagnostic(:invalid_hierarchy, "hierarchy_report flagged inconsistencies"))
    end
    if !all(tr -> tr.valid, hr.transfers)
        ready = false
        push!(diagnostics, error_diagnostic(:invalid_transfers, "one or more coarse→fine transfers are invalid"))
    end
    ready && push!(diagnostics, info(:ok,
        "$(hr.nlevels) levels with valid parent-node transfers (topological 1/2–1/2)"))
    return ReadinessReport(:geometric_multigrid, PipelineTarget(:geometric_multigrid), ready, diagnostics, (;))
end

# Clear error for unsupported (object, target) combinations.
function readiness(x, t::AbstractPipelineTarget)
    throw(ArgumentError(
        "readiness not implemented for target $(typeof(t)) on object of type $(typeof(x))"))
end

# --- to_namedtuple(x) -------------------------------------------------------
# Recursive, serialization-friendly conversion of local report structs. Never
# emits raw Internals handles (see the MeshGenerationResult specialization).
# OodiCore already provides to_namedtuple for DiagnosticMessage, PipelineTarget,
# ValidationReport, ReadinessReport, ObjectReport, and ArtifactRef.

const _NT_REPORTS = Union{
    MeshOptions,
    MeshValidationReport, MeshQualityReport, MeshTagReport, MeshReport,
    MeshGenerationDiagnostics, MeshLevelReport, TransferReport,
    MeshHierarchyReport, RefinementResult, OodiSnapshotReadiness,
    MeshabilityReport,
}

_nt_value(v) = v
_nt_value(v::DiagnosticMessage) = to_namedtuple(v)
_nt_value(v::_NT_REPORTS) = to_namedtuple(v)
_nt_value(v::AbstractVector) = [_nt_value(e) for e in v]
_nt_value(v::Tuple) = map(_nt_value, v)
_nt_value(v::NamedTuple) = map(_nt_value, v)
_nt_value(v::AbstractDict) = Dict(k => _nt_value(val) for (k, val) in v)

"""
    to_namedtuple(report) -> NamedTuple

Recursively convert a structured report into a `NamedTuple` of plain values
(numbers, strings, symbols, vectors, dicts) for JSON-like serialization and
future MCP/tool-server exposure. Raw Netgen handles are never emitted.
"""
function to_namedtuple(x::_NT_REPORTS)
    fns = fieldnames(typeof(x))
    return NamedTuple{fns}(map(f -> _nt_value(getfield(x, f)), fns))
end

# MeshGenerationResult holds a live mesh handle; summarize instead of serializing it.
function to_namedtuple(r::MeshGenerationResult)
    return (
        success=r.success,
        has_mesh=r.mesh !== nothing,
        node_count=r.mesh === nothing ? 0 : num_nodes(r.mesh),
        cell_count=r.mesh === nothing ? 0 : num_cells(r.mesh),
        options=to_namedtuple(r.options),
        diagnostics=to_namedtuple(r.diagnostics),
        elapsed_seconds=r.elapsed_seconds,
        warnings=[_nt_value(w) for w in r.warnings],
    )
end
