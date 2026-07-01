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
end

function Base.show(io::IO, opts::MeshOptions)
    print(io, "MeshOptions(maxh=", opts.maxh)
    opts.minh !== nothing && print(io, ", minh=", opts.minh)
    opts.grading !== nothing && print(io, ", grading=", opts.grading)
    opts.second_order && print(io, ", second_order=true")
    opts.optimize && print(io, ", optimize=true")
    opts.dimension !== nothing && print(io, ", dimension=", opts.dimension)
    print(io, ")")
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
    return opts
end

"""Convert [`MeshOptions`](@ref) to a Netgen `MeshingParameters` object (via Internals)."""
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

"""Build and validate `MeshOptions` from keyword arguments (legacy `secondorder` alias supported)."""
function mesh_options(;
        maxh::Real,
        minh::Union{Nothing,Real}=nothing,
        grading::Union{Nothing,Real}=nothing,
        secondorder::Bool=false,
        second_order::Bool=secondorder,
        optimize::Bool=false,
        dimension::Union{Nothing,Integer}=nothing,
        preserve_tags::Bool=true,
        optsteps2d::Union{Nothing,Integer}=nothing,
        optsteps3d::Union{Nothing,Integer}=nothing,
        kwargs...)
    isempty(kwargs) || @warn "ignored keyword arguments" kwargs=keys(kwargs)
    return validate_options!(MeshOptions(;
        maxh=Float64(maxh),
        minh=minh === nothing ? nothing : Float64(minh),
        grading=grading === nothing ? nothing : Float64(grading),
        second_order=second_order,
        optimize=optimize,
        dimension=dimension === nothing ? nothing : Int(dimension),
        preserve_tags=preserve_tags,
        optsteps2d=optsteps2d === nothing ? nothing : Int(optsteps2d),
        optsteps3d=optsteps3d === nothing ? nothing : Int(optsteps3d)))
end
