# --- combined mesh report ---------------------------------------------------

"""
    MeshReport <: AbstractOodiReport

Combined validation, quality, topology, and tag report for one mesh.
"""
struct MeshReport <: AbstractOodiReport
    validation::MeshValidationReport
    quality::MeshQualityReport
    topology::NamedTuple
    tags::MeshTagReport
end

function Base.show(io::IO, r::MeshReport)
    println(io, "MeshReport")
    println(io, "  ", r.validation)
    println(io, "  ", r.quality)
    println(io, "  topology: dim=", r.topology.dimension,
          ", nodes=", r.topology.node_count,
          ", cells=", r.topology.element_count)
    print(io, r.tags)
end

"""
    mesh_report(mesh) -> MeshReport

One-call structured mesh summary for LLM feedback loops.
"""
function mesh_report(m)
    return MeshReport(
        validate(m),
        quality(m),
        topology_report(m),
        tag_report(m))
end
