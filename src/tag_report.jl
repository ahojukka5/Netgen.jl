# --- boundary / region tag reporting ----------------------------------------

"""
    MeshTagReport

Structured boundary and region tag summary for downstream FEM setup.
"""
struct MeshTagReport
    boundary_tags::Dict{String,Int}
    region_tags::Dict{String,Int}
    untagged_boundary_count::Int
    untagged_region_count::Int
    warnings::Vector{DiagnosticMessage}
end

function Base.show(io::IO, r::MeshTagReport)
    println(io, "MeshTagReport")
    println(io, "  boundary tags:")
    if isempty(r.boundary_tags)
        println(io, "    (none)")
    else
        for (name, cnt) in sort(collect(r.boundary_tags); by=x -> x[1])
            println(io, "    ", name, ": ", cnt, " boundary facets")
        end
    end
    println(io, "  region tags:")
    if isempty(r.region_tags)
        println(io, "    (none)")
    else
        for (name, cnt) in sort(collect(r.region_tags); by=x -> x[1])
            println(io, "    ", name, ": ", cnt, " cells")
        end
    end
    r.untagged_boundary_count > 0 &&
        println(io, "  untagged boundary facets: ", r.untagged_boundary_count)
    r.untagged_region_count > 0 &&
        println(io, "  untagged cells: ", r.untagged_region_count)
    for w in r.warnings
        println(io, "  warning: ", w.message)
    end
end

function _count_tags(regs::Vector{Int32}, names::Dict{Int32,String})
    counts = Dict{String,Int}()
    untagged = 0
    for r in regs
        if haskey(names, r) && !isempty(strip(names[r]))
            n = names[r]
            counts[n] = get(counts, n, 0) + 1
        else
            untagged += 1
        end
    end
    return counts, untagged
end

"""
    boundary_tags(mesh) -> Dict{String,Int}

Boundary tag name → facet count (3D triangles or 2D segments).
"""
function boundary_tags(m)
    d = mesh_dimension(m)
    regs = boundary_regions(m)
    if d == 3
        return _count_tags(regs, boundary_names(m))[1]
    else
        # 2D: join via per-segment region names
        counts = Dict{String,Int}()
        for i in 1:length(regs)
            name = region_name_segment(m, i)
            if !isempty(strip(name))
                counts[name] = get(counts, name, 0) + 1
            end
        end
        return counts
    end
end

"""
    region_tags(mesh) -> Dict{String,Int}

Region/material tag name → cell count.
"""
function region_tags(m)
    d = mesh_dimension(m)
    regs = cell_regions(m)
    if d == 3
        return _count_tags(regs, material_names(m))[1]
    else
        counts = Dict{String,Int}()
        for i in 1:length(regs)
            name = region_name_surface(m, i)
            if !isempty(strip(name))
                counts[name] = get(counts, name, 0) + 1
            end
        end
        return counts
    end
end

"""
    has_boundary_tag(mesh, name) -> Bool

`true` if any boundary facet carries tag `name` (string or symbol).
"""
function has_boundary_tag(m, name)
    tag = String(name)
    return get(boundary_tags(m), tag, 0) > 0
end

"""
    has_region_tag(mesh, name) -> Bool

`true` if any top-dimensional cell carries region tag `name`.
"""
function has_region_tag(m, name)
    tag = String(name)
    return get(region_tags(m), tag, 0) > 0
end

"""
    tag_report(mesh) -> MeshTagReport

Full boundary/region tag report with untagged counts and warnings.
"""
function tag_report(m)
    warnings = DiagnosticMessage[]
    d = mesh_dimension(m)
    btags = boundary_tags(m)
    rtags = region_tags(m)
    untagged_b = num_boundary_facets(m) - sum(values(btags); init=0)
    untagged_r = num_cells(m) - sum(values(rtags); init=0)
    d == 2 && isempty(material_names(m)) &&
        _append!(warnings, :warning, :two_d_material_names_unreliable,
            "2D material name dictionaries may be empty; use region_name_surface per cell")
    return MeshTagReport(btags, rtags, max(0, untagged_b), max(0, untagged_r), warnings)
end
