# --- geometry loading -------------------------------------------------------
load_step(path::AbstractString) = Internals.LoadOCC_STEP(String(path))
load_iges(path::AbstractString) = Internals.LoadOCC_IGES(String(path))
load_brep(path::AbstractString) = Internals.LoadOCC_BREP(String(path))
load_stl(path::AbstractString) = Internals.LoadSTL(String(path))
load_splinegeometry2d(path::AbstractString) =
    Internals.LoadSplineGeometry2d(String(path))

function load_geometry(path::AbstractString)
    ext = lowercase(splitext(path)[2])
    ext in (".step", ".stp") && return Internals.LoadOCC_STEP(String(path))
    ext == ".brep"           && return Internals.LoadOCC_BREP(String(path))
    ext in (".iges", ".igs") && return Internals.LoadOCC_IGES(String(path))
    ext == ".stl"            && return Internals.LoadSTL(String(path))
    error("unsupported geometry extension: $ext")
end

# --- 2D geometry (geom2d / csg2d) -------------------------------------------
const Circle = Internals.Circle
const Rectangle = Internals.Rectangle
const CSG2d = Internals.CSG2d

"""
    geometry2d(solid) -> geometry

Wrap a `Solid2d` (or a boolean composite of them) into a `SplineGeometry2d` that
can be passed to [`generate_mesh`](@ref) / [`coarse_hierarchy`](@ref). Curved
boundaries (e.g. a [`Circle`](@ref)) are followed under refinement.
"""
function geometry2d(solid)
    g = CSG2d()
    Internals.Add(g, solid)
    return Internals.GenerateSplineGeometry(g)
end
