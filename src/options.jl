# --- mesh generation options ------------------------------------------------

"""
    MeshOptions

Structured, inspectable mesh-generation options for [`generate_mesh`](@ref).

All fields have explicit defaults except `maxh`, which is required.

# Fields
- `maxh`: characteristic mesh size (required, must be > 0)
- `minh`: optional lower bound on local mesh size
- `grading`: optional grading between coarse and fine regions
- `second_order`: request second-order elements from the mesher
- `optimize`: run volume optimization after generation (3D only)
- `dimension`: expected mesh dimension (`2` or `3`); validated after meshing if set
- `preserve_tags`: informational flag (CAD tags are preserved when geometry provides them)
- `optsteps2d`, `optsteps3d`: optimizer step counts forwarded to Netgen
- `local_size`: optional local refinement requests, applied *after* generation
  via [`refine_near!`](@ref) (see below — Netgen's `RestrictLocalH`/`SetLocalH`
  do not influence this package's `generate_mesh` entry point). Each entry is
  `(point, h)` or `(point=..., h=..., radius=nothing, levels=1)`; `radius`
  defaults to `h` (elements within one target-size of `point` are refined) and
  `levels` controls how many marked-refinement passes are applied.

# Local mesh sizing caveat

Netgen exposes real local-h machinery (`RestrictLocalH`, `SetLocalH`,
`LoadLocalMeshSize`) but, in this build, `GenerateMesh` recomputes its own
local-h field during surface meshing and discards any restriction applied
beforehand — so those calls cannot steer element sizes during initial
generation. `local_size` is therefore implemented as coarse generation followed
by geometric mark-and-refine near each requested point (a mechanism verified
to genuinely localize in both 2D and 3D; see `src/local_sizing.jl` — 3D uses
`mark_for_refinement!`/`bisect!`, 2D uses `mark_for_ngx_refinement!`/
`ngx_refine!`, since plain `bisect!` refines 2D meshes uniformly regardless of
marking). This gives locally finer elements near the requested points but is
a distinct mechanism from a true graded local-h field: refinement proceeds by
discrete levels rather than a continuously graded size function.
"""
Base.@kwdef struct MeshOptions
    maxh::Float64
    minh::Union{Nothing,Float64} = nothing
    grading::Union{Nothing,Float64} = nothing
    second_order::Bool = false
    optimize::Bool = false
    dimension::Union{Nothing,Int} = nothing
    preserve_tags::Bool = true
    optsteps2d::Union{Nothing,Int} = nothing
    optsteps3d::Union{Nothing,Int} = nothing
    local_size::Vector{Any} = Any[]
end

function Base.show(io::IO, opts::MeshOptions)
    print(io, "MeshOptions(maxh=", opts.maxh)
    opts.minh !== nothing && print(io, ", minh=", opts.minh)
    opts.grading !== nothing && print(io, ", grading=", opts.grading)
    opts.second_order && print(io, ", second_order=true")
    opts.optimize && print(io, ", optimize=true")
    opts.dimension !== nothing && print(io, ", dimension=", opts.dimension)
    !isempty(opts.local_size) && print(io, ", local_size=", length(opts.local_size), " points")
    print(io, ")")
end

"""Normalize one `local_size` entry to `(point, h, radius, levels)`; throw `ArgumentError` on malformed input."""
function _normalize_local_size_entry(entry)
    point = nothing
    h = nothing
    radius = nothing
    levels = 1
    if entry isa NamedTuple
        point = get(entry, :point, nothing)
        h = get(entry, :h, nothing)
        radius = get(entry, :radius, nothing)
        levels = get(entry, :levels, 1)
    elseif entry isa Tuple && length(entry) >= 2
        point, h = entry[1], entry[2]
        length(entry) >= 3 && (radius = entry[3])
        length(entry) >= 4 && (levels = entry[4])
    else
        throw(ArgumentError("MeshOptions.local_size entries must be `(point, h)` tuples or `(point=..., h=...)` named tuples (got $(typeof(entry)))"))
    end
    point === nothing && throw(ArgumentError("MeshOptions.local_size entry is missing `point`"))
    h === nothing && throw(ArgumentError("MeshOptions.local_size entry is missing `h`"))
    (length(point) == 2 || length(point) == 3) ||
        throw(ArgumentError("MeshOptions.local_size point must have length 2 or 3 (got $(length(point)))"))
    h > 0 || throw(ArgumentError("MeshOptions.local_size h must be > 0 (got $h)"))
    radius = radius === nothing ? Float64(h) : Float64(radius)
    radius > 0 || throw(ArgumentError("MeshOptions.local_size radius must be > 0 (got $radius)"))
    Int(levels) >= 1 || throw(ArgumentError("MeshOptions.local_size levels must be >= 1 (got $levels)"))
    return (point=point, h=Float64(h), radius=radius, levels=Int(levels))
end

"""Validate option combinations; throw `ArgumentError` on invalid input."""
function validate_options!(opts::MeshOptions)
    opts.maxh > 0 || throw(ArgumentError("MeshOptions.maxh must be > 0 (got $(opts.maxh))"))
    if opts.minh !== nothing
        opts.minh > 0 || throw(ArgumentError("MeshOptions.minh must be > 0 (got $(opts.minh))"))
        opts.minh <= opts.maxh ||
            throw(ArgumentError("MeshOptions.minh ($(opts.minh)) must be ≤ maxh ($(opts.maxh))"))
    end
    if opts.grading !== nothing
        opts.grading >= 0 || throw(ArgumentError("MeshOptions.grading must be ≥ 0"))
    end
    if opts.dimension !== nothing
        opts.dimension in (2, 3) ||
            throw(ArgumentError("MeshOptions.dimension must be 2 or 3 (got $(opts.dimension))"))
    end
    foreach(_normalize_local_size_entry, opts.local_size)
    return opts
end

"""Normalized `(point, h, radius, levels)` tuples for `opts.local_size`."""
local_size_requests(opts::MeshOptions) = [_normalize_local_size_entry(e) for e in opts.local_size]

"""Convert [`MeshOptions`](@ref) to a Netgen `MeshingParameters` object (via Netgen)."""
function to_meshing_parameters(opts::MeshOptions)
    validate_options!(opts)
    return meshing_parameters(;
        maxh=opts.maxh,
        minh=opts.minh,
        grading=opts.grading,
        secondorder=opts.second_order,
        optsteps2d=opts.optsteps2d,
        optsteps3d=opts.optsteps3d)
end

"""Build and validate `MeshOptions` from keyword arguments (legacy `secondorder` keyword deprecated in favor of `second_order`)."""
function mesh_options(;
        maxh::Real,
        minh::Union{Nothing,Real}=nothing,
        grading::Union{Nothing,Real}=nothing,
        secondorder::Union{Nothing,Bool}=nothing,
        second_order::Bool=false,
        optimize::Bool=false,
        dimension::Union{Nothing,Integer}=nothing,
        preserve_tags::Bool=true,
        optsteps2d::Union{Nothing,Integer}=nothing,
        optsteps3d::Union{Nothing,Integer}=nothing,
        local_size=Any[],
        kwargs...)
    isempty(kwargs) || @warn "ignored keyword arguments" kwargs=keys(kwargs)
    if secondorder !== nothing
        Base.depwarn(
            "keyword `secondorder` is deprecated, use `second_order`",
            :mesh_options)
        second_order = secondorder
    end
    return validate_options!(MeshOptions(;
        maxh=Float64(maxh),
        minh=minh === nothing ? nothing : Float64(minh),
        grading=grading === nothing ? nothing : Float64(grading),
        second_order=second_order,
        optimize=optimize,
        dimension=dimension === nothing ? nothing : Int(dimension),
        preserve_tags=preserve_tags,
        optsteps2d=optsteps2d === nothing ? nothing : Int(optsteps2d),
        optsteps3d=optsteps3d === nothing ? nothing : Int(optsteps3d),
        local_size=Any[e for e in local_size]))
end
