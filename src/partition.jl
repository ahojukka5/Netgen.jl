# --- partitioning / load-balancing data contract ----------------------------
# Delone.jl does NOT own domain decomposition. It exposes optional native
# partition hints so a consumer can build PartitionGraph / METIS / ParMETIS input.

"""
    native_partition_hint(mesh) -> NamedTuple

Optional native partition hints from Netgen's MPI interface:

- `global_vertex_ids::Vector{Int}` — per local vertex (1-based index into
  [`points`](@ref)), the global vertex id (`Ngx_Mesh::GetGlobalVertexNum`). On
  a serial build this equals the local 1-based id.
- `distant_procs::Vector{Vector{Int}}` — per local vertex, MPI ranks that own
  ghost copies (`Ngx_Mesh::GetDistantProcs`, nodetype `0`). Empty inner vectors
  on a serial build.

This is **optional input** to a consumer partitioner, not a partitioning policy.
Delone.jl does not call METIS/ParMETIS or assign ownership.
"""
function native_partition_hint(m)
    nm = Internals.Ngx_Mesh(m)
    np = Internals.GetNP(m)
    np == 0 && return (global_vertex_ids=Int[], distant_procs=Vector{Int}[])
    return (
        global_vertex_ids = [Int(Internals.GetGlobalVertexNum(nm, i - 1)) + 1 for i in 1:np],
        distant_procs = [collect(Int, Internals.GetDistantProcs(nm, 0, i - 1)) for i in 1:np],
    )
end
