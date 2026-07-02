# --- mesh validation --------------------------------------------------------

"""
    MeshValidationReport <: AbstractValidationReport

Structured validation summary for a mesh. Produced by [`validate`](@ref).
"""
struct MeshValidationReport <: AbstractValidationReport
    valid::Bool
    dimension::Int
    element_types::Dict{Symbol,Int}
    node_count::Int
    element_count::Int
    boundary_element_count::Int
    errors::Vector{DiagnosticMessage}
    warnings::Vector{DiagnosticMessage}
end

function Base.show(io::IO, r::MeshValidationReport)
    print(io, "MeshValidationReport(valid=", r.valid,
          ", dim=", r.dimension,
          ", nodes=", r.node_count,
          ", cells=", r.element_count,
          ", boundary=", r.boundary_element_count, ")")
    if !isempty(r.errors)
        print(io, "\n  errors:")
        for e in r.errors
            print(io, "\n    ", e.severity, " [", e.code, "]: ", e.message)
        end
    end
    if !isempty(r.warnings)
        print(io, "\n  warnings:")
        for w in r.warnings
            print(io, "\n    ", w.severity, " [", w.code, "]: ", w.message)
        end
    end
end

function Base.summary(io::IO, r::MeshValidationReport)
    print(io, "MeshValidationReport(valid=", r.valid, ", dim=", r.dimension, ")")
end

function Base.show(io::IO, ::MIME"text/html", r::MeshValidationReport)
    print(io, "<div class=\"delone-report\"><table><caption>MeshValidationReport</caption>",
          "<tr><th>valid</th><td>", r.valid, "</td></tr>",
          "<tr><th>dimension</th><td>", r.dimension, "</td></tr>",
          "<tr><th>nodes</th><td>", r.node_count, "</td></tr>",
          "<tr><th>cells</th><td>", r.element_count, "</td></tr>",
          "<tr><th>boundary</th><td>", r.boundary_element_count, "</td></tr></table>")
    if !isempty(r.errors)
        print(io, "<b>errors</b><ul>")
        for e in r.errors
            print(io, "<li>[", e.code, "] ", _html_escape(e.message), "</li>")
        end
        print(io, "</ul>")
    end
    if !isempty(r.warnings)
        print(io, "<b>warnings</b><ul>")
        for w in r.warnings
            print(io, "<li>[", w.code, "] ", _html_escape(w.message), "</li>")
        end
        print(io, "</ul>")
    end
    print(io, "</div>")
end

"""
    isvalid(report::MeshValidationReport) -> Bool

Return whether `report` describes a valid mesh (extends `Base.isvalid`, same
convention OodiCore uses for its own `ValidationReport`).
"""
Base.isvalid(r::MeshValidationReport) = r.valid

"""Return element-type counts keyed by symbolic names (`:tet`, `:tri`, `:segment`, …)."""
function _element_type_counts(m)
    d = mesh_dimension(m)
    counts = Dict{Symbol,Int}()
    if d == 3
        counts[:tet] = Netgen.GetNE(m)
        counts[:tri] = Netgen.GetNSE(m)
    elseif d == 2
        counts[:tri] = Netgen.GetNSE(m)
        counts[:segment] = Netgen.GetNSeg(m)
    end
    return counts
end

"""
    isvalid(mesh) -> Bool

Quick validity check: nonzero cells, Netgen volume/boundary checks pass, no fatal
report errors from [`validate`](@ref).

Explicitly qualified as `Base.isvalid` (not a bare `function isvalid(...)`) so
this extends the same generic function `using Delone` brings into scope,
rather than shadowing it with a new module-local `isvalid` — that shadowing
is exactly the kind of name collision this package is meant to avoid (see
`OodiCore.jl`'s own `Base.isvalid(::ValidationReport)`, a different package
from Delone.jl's own API).
"""
Base.isvalid(m) = validate(m).valid

"""
    validate(mesh) -> MeshValidationReport

Run structured mesh validation suitable for LLM feedback loops.
"""
function validate(m)
    errors = DiagnosticMessage[]
    warnings = DiagnosticMessage[]
    d = mesh_dimension(m)
    nc = num_cells(m)
    nn = num_nodes(m)
    nb = num_boundary_facets(m)
    etypes = _element_type_counts(m)

    nn == 0 && _append!(errors, :error, :empty_mesh, "mesh has zero nodes")
    nc == 0 && _append!(errors, :error, :empty_mesh, "mesh has zero top-dimensional elements")
    d ∉ (2, 3) && _append!(errors, :error, :unsupported_dimension, "unsupported mesh dimension $d")

    chk = check_mesh(m)
    !chk.volume_ok && _append!(errors, :error, :volume_check_failed,
        "Netgen CheckVolumeMesh failed")
    !chk.boundary_ok && _append!(errors, :error, :boundary_check_failed,
        "Netgen CheckConsistentBoundary failed")

    nc > 0 && !supported_snapshot_topology(m) &&
        _append!(warnings, :warning, :non_simplex_topology,
            "mesh is not pure simplex (Tet4/Tri3); snapshot export may be limited")

    valid = isempty(errors)
    return MeshValidationReport(valid, d, etypes, nn, nc, nb, errors, warnings)
end

"""
    topology_report(mesh) -> NamedTuple

Lightweight topology summary: counts and element types.
"""
function topology_report(m)
    v = validate(m)
    return (
        dimension=v.dimension,
        node_count=v.node_count,
        element_count=v.element_count,
        boundary_element_count=v.boundary_element_count,
        element_types=v.element_types,
    )
end
