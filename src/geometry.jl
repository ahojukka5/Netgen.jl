# --- geometry loading -------------------------------------------------------

"""
    load_step(path) -> NetgenGeometry

Load an OpenCascade STEP file (`.step`/`.stp`) as a meshable Netgen geometry.
"""
load_step(path::AbstractString) = Netgen.LoadOCC_STEP(String(path))

"""
    load_iges(path) -> NetgenGeometry

Load an OpenCascade IGES file (`.iges`/`.igs`) as a meshable Netgen geometry.
"""
load_iges(path::AbstractString) = Netgen.LoadOCC_IGES(String(path))

"""
    load_brep(path) -> NetgenGeometry

Load an OpenCascade BREP file (`.brep`) as a meshable Netgen geometry. For
in-memory BREP strings (e.g. from OpenCascade.jl), use
[`occ_geometry_from_brep_string`](@ref) instead.
"""
load_brep(path::AbstractString) = Netgen.LoadOCC_BREP(String(path))

"""
    load_stl(path) -> NetgenGeometry

Load an STL surface mesh file (`.stl`) as a meshable Netgen geometry.
"""
load_stl(path::AbstractString) = Netgen.LoadSTL(String(path))

"""
    load_splinegeometry2d(path) -> geometry

Load a 2D Netgen spline geometry file as a meshable geometry, for use with
[`generate_mesh`](@ref) / [`mesh_hierarchy`](@ref) in 2D.
"""
load_splinegeometry2d(path::AbstractString) =
    Netgen.LoadSplineGeometry2d(String(path))

"""
    load_geometry(path) -> NetgenGeometry

Load a CAD/mesh geometry file, dispatching on its extension to
[`load_step`](@ref), [`load_brep`](@ref), [`load_iges`](@ref), or
[`load_stl`](@ref) (`.step`/`.stp`, `.brep`, `.iges`/`.igs`, `.stl`). Errors on
an unsupported extension.
"""
function load_geometry(path::AbstractString)
    ext = lowercase(splitext(path)[2])
    ext in (".step", ".stp") && return Netgen.LoadOCC_STEP(String(path))
    ext == ".brep"           && return Netgen.LoadOCC_BREP(String(path))
    ext in (".iges", ".igs") && return Netgen.LoadOCC_IGES(String(path))
    ext == ".stl"            && return Netgen.LoadSTL(String(path))
    throw(ArgumentError("unsupported geometry extension: $ext"))
end

# --- 2D geometry (geom2d / csg2d) -------------------------------------------

"""
    Circle(center, radius)

A circular 2D primitive (Netgen `Solid2d`-compatible), for composing into a
[`CSG2d`](@ref) and building a mesh via [`geometry2d`](@ref).
"""
const Circle = Netgen.Circle

"""
    Rectangle(p1, p2)

An axis-aligned rectangular 2D primitive (Netgen `Solid2d`-compatible), for
composing into a [`CSG2d`](@ref) and building a mesh via [`geometry2d`](@ref).
"""
const Rectangle = Netgen.Rectangle

"""
    CSG2d()

A 2D constructive-solid-geometry container: add primitives (e.g.
[`Circle`](@ref), [`Rectangle`](@ref)) or boolean composites of them, then
convert with [`geometry2d`](@ref).
"""
const CSG2d = Netgen.CSG2d

"""
    geometry2d(solid) -> geometry

Wrap a `Solid2d` (or a boolean composite of them) into a `SplineGeometry2d` that
can be passed to [`generate_mesh`](@ref) / [`mesh_hierarchy`](@ref). Curved
boundaries (e.g. a [`Circle`](@ref)) are followed under refinement.
"""
function geometry2d(solid)
    g = CSG2d()
    Netgen.Add(g, solid)
    return Netgen.GenerateSplineGeometry(g)
end
