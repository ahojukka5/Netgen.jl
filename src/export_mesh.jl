# --- mesh export / preview --------------------------------------------------
# Lightweight export for LLM/human feedback. No full viewer.

"""
    export_vtk(mesh, path; include_volume=true, include_surface=true)

Write an ASCII VTK unstructured grid (`path`) with volume and/or boundary cells.
"""
function export_vtk(m, path::AbstractString;
                    include_volume::Bool=true, include_surface::Bool=true)
    P = points(m)
    d = mesh_dimension(m)
    np = size(P, 2)

    cells = Vector{Vector{Int}}()
    types = Vector{Int}()
    if include_volume
        if d == 3
            T = tetrahedra(m)
            for e in axes(T, 2)
                push!(cells, collect(T[:, e] .- 1))  # VTK 0-based
                push!(types, 10)  # VTK_TETRA
            end
        elseif d == 2
            Tr = triangles2d(m)
            for e in axes(Tr, 2)
                push!(cells, vcat(collect(Tr[:, e] .- 1), [0]))  # pad to 3 nodes
                push!(types, 5)  # VTK_TRIANGLE
            end
        end
    end
    if include_surface
        if d == 3
            S = surface_triangles(m)
            for e in axes(S, 2)
                push!(cells, collect(S[:, e] .- 1))
                push!(types, 5)
            end
        elseif d == 2
            Seg = segments2d(m)
            for e in axes(Seg, 2)
                push!(cells, collect(Seg[:, e] .- 1))
                push!(types, 3)  # VTK_LINE
            end
        end
    end

    open(path, "w") do io
        println(io, "# vtk DataFile Version 3.0")
        println(io, "Delone.jl export")
        println(io, "ASCII")
        println(io, "DATASET UNSTRUCTURED_GRID")
        println(io, "POINTS ", np, " double")
        for i in 1:np
            println(io, P[1, i], " ", P[2, i], " ", P[3, i])
        end
        ncells = length(cells)
        total = sum(length(c) for c in cells) + ncells
        println(io, "CELLS ", ncells, " ", total)
        for c in cells
            print(io, length(c))
            for v in c
                print(io, " ", v)
            end
            println(io)
        end
        println(io, "CELL_TYPES ", ncells)
        for t in types
            println(io, t)
        end
    end
    return path
end

"""
    export_obj(mesh, path)

Write boundary surface triangles (3D) or domain triangles (2D) as Wavefront OBJ.
"""
function export_obj(m, path::AbstractString)
    P = points(m)
    d = mesh_dimension(m)
    open(path, "w") do io
        for i in 1:size(P, 2)
            println(io, "v ", P[1, i], " ", P[2, i], " ", P[3, i])
        end
        if d == 3
            S = surface_triangles(m)
            for e in axes(S, 2)
                println(io, "f ", join(S[:, e], " "))
            end
        elseif d == 2
            Tr = triangles2d(m)
            for e in axes(Tr, 2)
                println(io, "f ", join(Tr[:, e], " "))
            end
        end
    end
    return path
end

"""
    export_mesh_preview(mesh, path; format=:vtk)

Export a preview artifact. Supported: `:vtk`, `:obj`.
"""
function export_mesh_preview(m, path::AbstractString; format::Symbol=:vtk)
    format == :vtk && return export_vtk(m, path)
    format == :obj && return export_obj(m, path)
    throw(ArgumentError("unsupported preview format: $format (use :vtk or :obj)"))
end

"""
    export_svg_2d(mesh, path)

Simple 2D SVG preview of domain triangles (2D meshes only).
"""
function export_svg_2d(m, path::AbstractString)
    mesh_dimension(m) == 2 ||
        throw(ArgumentError("export_svg_2d requires a 2D mesh"))
    P = points(m)
    Tr = triangles2d(m)
    (lo, hi) = mesh_bounding_box(m)
    w = hi[1] - lo[1]
    h = hi[2] - lo[2]
    pad = 0.05 * max(w, h, 1e-12)
    view_w = w + 2pad
    view_h = h + 2pad
    tx(x) = (x - lo[1] + pad) / view_w
    ty(y) = 1 - (y - lo[2] + pad) / view_h

    open(path, "w") do io
        println(io, """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 400 400">""")
        println(io, """<rect width="100%" height="100%" fill="#f8f8f8"/>""")
        for e in axes(Tr, 2)
            pts = [(P[1, Tr[j, e]], P[2, Tr[j, e]]) for j in 1:3]
            coords = join(["$(400 * tx(x)),$(400 * ty(y))" for (x, y) in pts], " ")
            println(io, """<polygon points="$coords" fill="#4a90d9" fill-opacity="0.35" stroke="#333"/>""")
        end
        println(io, "</svg>")
    end
    return path
end

"""
    mesh_preview(mesh; format=:vtk) -> String

Write a mesh preview to a fresh temporary file (via [`export_mesh_preview`](@ref))
and return its path. Convenience wrapper for quick inspection (e.g. a REPL or an
LLM tool loop) without choosing a path yourself.
"""
mesh_preview(m; format::Symbol=:vtk) = export_mesh_preview(m, tempname() * "." * String(format))

"""
    mesh_previews(mesh; formats=[:vtk]) -> Vector{String}

[`mesh_preview`](@ref) for multiple formats at once.
"""
mesh_previews(m; formats=[:vtk]) = [mesh_preview(m; format=f) for f in formats]
