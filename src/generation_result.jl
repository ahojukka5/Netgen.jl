# --- mesh generation result -------------------------------------------------

"""
    MeshGenerationDiagnostics

Structured diagnostics from a mesh-generation attempt.
"""
mutable struct MeshGenerationDiagnostics
    failure_stage::Union{Symbol,Nothing}
    backend_status::Union{Int,Nothing}
    messages::Vector{DiagnosticMessage}
    suggestions::Vector{DiagnosticMessage}
end

MeshGenerationDiagnostics() = MeshGenerationDiagnostics(nothing, nothing, DiagnosticMessage[], DiagnosticMessage[])

function Base.show(io::IO, d::MeshGenerationDiagnostics)
    print(io, "MeshGenerationDiagnostics(")
    d.failure_stage !== nothing && print(io, "stage=", d.failure_stage, ", ")
    print(io, "messages=", length(d.messages), ", suggestions=", length(d.suggestions), ")")
    for m in d.messages
        print(io, "\n  ", m.severity, " [", m.code, "]: ", m.message)
    end
    for s in d.suggestions
        print(io, "\n  suggest: ", s.message)
    end
end

"""
    MeshGenerationResult <: AbstractOodiReport

Structured result from [`generate_mesh`](@ref) when `result=true`.
"""
struct MeshGenerationResult <: AbstractOodiReport
    success::Bool
    mesh::Union{Nothing,Any}
    options::MeshOptions
    diagnostics::MeshGenerationDiagnostics
    elapsed_seconds::Float64
    warnings::Vector{DiagnosticMessage}
end

"""Extract the mesh from a successful result; throw if generation failed."""
function mesh(r::MeshGenerationResult)
    r.success || throw(ArgumentError("mesh generation failed: $(r.diagnostics)"))
    return r.mesh
end

function Base.show(io::IO, r::MeshGenerationResult)
    print(io, "MeshGenerationResult(success=", r.success,
          ", elapsed=", round(r.elapsed_seconds; digits=3), "s)")
    if r.success && r.mesh !== nothing
        print(io, ", nodes=", num_nodes(r.mesh), ", cells=", num_cells(r.mesh))
    end
    !isempty(r.warnings) && print(io, ", warnings=", length(r.warnings))
    print(io, "\n  ", r.diagnostics)
end

const _MESHING3_STAGE = Dict(
    MESHING3_OK => nothing,
    MESHING3_GIVEUP => :optimization,
    MESHING3_NEGVOL => :volume_mesh,
    MESHING3_OUTERSTEPSEXCEEDED => :optimization,
    MESHING3_TERMINATE => :volume_mesh,
    MESHING3_BADSURFACEMESH => :surface_mesh,
)

function _status_message(code::Int)
    if code == MESHING3_OK
        return "meshing completed successfully"
    elseif code == MESHING3_NEGVOL
        return "negative volume elements detected during volume meshing"
    elseif code == MESHING3_BADSURFACEMESH
        return "surface mesh quality insufficient for volume fill"
    elseif code == MESHING3_GIVEUP
        return "optimizer gave up before reaching target quality"
    elseif code == MESHING3_OUTERSTEPSEXCEEDED
        return "optimizer exceeded outer step limit"
    elseif code == MESHING3_TERMINATE
        return "volume meshing terminated early"
    else
        return "backend returned status code $code"
    end
end

function _suggest_for_status(code::Int, opts::MeshOptions)
    sugs = DiagnosticMessage[]
    if code == MESHING3_BADSURFACEMESH
        _append!(sugs, :suggestion, :coarsen_or_heal,
            "try increasing maxh ($(opts.maxh)) or healing/repairing CAD geometry")
        _append!(sugs, :suggestion, :check_tags,
            "verify boundary tags and that the solid is watertight")
    elseif code == MESHING3_NEGVOL
        _append!(sugs, :suggestion, :reduce_grading,
            "try reducing grading or increasing minh to avoid sliver elements")
    elseif code in (MESHING3_GIVEUP, MESHING3_OUTERSTEPSEXCEEDED)
        _append!(sugs, :suggestion, :disable_optimize,
            "try generate_mesh with optimize=false, then improve_mesh! separately")
    end
    return sugs
end

function _classify_exception(e, diag::MeshGenerationDiagnostics)
    msg = sprint(showerror, e)
    if occursin("unsupported geometry", lowercase(msg))
        diag.failure_stage = :geometry_import
        _append!(diag.messages, :error, :unsupported_geometry, msg)
    elseif occursin("GenerateMesh", msg) || occursin("mesh", lowercase(msg))
        diag.failure_stage = :volume_mesh
        _append!(diag.messages, :error, :meshing_exception, msg)
    else
        diag.failure_stage = :unknown
        _append!(diag.messages, :error, :exception, msg)
    end
    _append!(diag.suggestions, :suggestion, :revise_options,
        "revise MeshOptions (maxh, minh, grading) or repair input geometry")
    return diag
end

"""
    generate_mesh_result(geometry, options::MeshOptions) -> MeshGenerationResult

Generate a mesh and return a structured result (never throws on meshing failure).
"""
function generate_mesh_result(geom, opts::MeshOptions)
    validate_options!(opts)
    t0 = time()
    warnings = DiagnosticMessage[]
    diag = MeshGenerationDiagnostics()

    if geom === nothing
        diag.failure_stage = :geometry_import
        _append!(diag.messages, :error, :null_geometry, "geometry input is nothing")
        return MeshGenerationResult(false, nothing, opts, diag, time() - t0, warnings)
    end

    local m
    try
        m = Internals.new_mesh()
        Internals.SetGeometry(m, geom)
        mp = to_meshing_parameters(opts)
        Internals.GenerateMesh(geom, m, mp)
    catch e
        _classify_exception(e, diag)
        return MeshGenerationResult(false, nothing, opts, diag, time() - t0, warnings)
    end

    if opts.dimension !== nothing && mesh_dimension(m) != opts.dimension
        diag.failure_stage = :volume_mesh
        _append!(diag.messages, :error, :dimension_mismatch,
            "expected dimension $(opts.dimension), got $(mesh_dimension(m))")
        return MeshGenerationResult(false, nothing, opts, diag, time() - t0, warnings)
    end

    if num_cells(m) == 0
        diag.failure_stage = :volume_mesh
        _append!(diag.messages, :error, :empty_mesh, "meshing produced zero cells")
        _append!(diag.suggestions, :suggestion, :increase_maxh,
            "try increasing maxh (currently $(opts.maxh))")
        return MeshGenerationResult(false, m, opts, diag, time() - t0, warnings)
    end

    if opts.optimize && mesh_dimension(m) == 3
        mp = to_meshing_parameters(opts)
        status = Internals.MeshVolume(mp, m)
        if status != MESHING3_OK
            diag.failure_stage = get(_MESHING3_STAGE, status, :optimization)
            diag.backend_status = status
            _append!(diag.messages, :error, :mesh_volume_failed, _status_message(status))
            append!(diag.suggestions, _suggest_for_status(status, opts))
            return MeshGenerationResult(false, m, opts, diag, time() - t0, warnings)
        end
        status = Internals.OptimizeVolume(mp, m)
        if status != MESHING3_OK
            diag.failure_stage = get(_MESHING3_STAGE, status, :optimization)
            diag.backend_status = status
            _append!(diag.messages, :error, :optimize_failed, _status_message(status))
            append!(diag.suggestions, _suggest_for_status(status, opts))
            return MeshGenerationResult(false, m, opts, diag, time() - t0, warnings)
        end
    end

    vr = validate(m)
    for w in vr.warnings
        push!(warnings, w)
    end
    if !vr.valid
        diag.failure_stage = :post_validation
        append!(diag.messages, vr.errors)
        return MeshGenerationResult(false, m, opts, diag, time() - t0, warnings)
    end

    return MeshGenerationResult(true, m, opts, diag, time() - t0, warnings)
end

Base.@deprecate try_generate_mesh(geom, opts::MeshOptions) generate_mesh_result(geom, opts)

"""
    generate_mesh(geometry; options=nothing, maxh=nothing, result=false, kwargs...) -> mesh | MeshGenerationResult

Mesh `geometry` using [`MeshOptions`](@ref) or legacy `maxh` keywords.

- `result=false` (default): return the mesh handle; throw on failure.
- `result=true`: return [`MeshGenerationResult`](@ref) with diagnostics.
"""
function generate_mesh(geom; options=nothing, maxh=nothing, result::Bool=false, kwargs...)
    if options === nothing
        maxh === nothing &&
            throw(ArgumentError("provide maxh or options=MeshOptions(...)"))
        options = mesh_options(; maxh=maxh, kwargs...)
    end
    res = generate_mesh_result(geom, options)
    return result ? res : mesh(res)
end
