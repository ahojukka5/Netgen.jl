# Multigrid hierarchy

Coarse-to-fine mesh hierarchies for geometric multigrid: building a
[`MeshHierarchy`](@ref), refining every level, structured hierarchy/transfer
reports, and the low-level ngx parent maps that describe how fine-level
entities relate to their coarse-level parents.

## Multigrid hierarchy

```@docs
copy_mesh
MeshHierarchy
coarse_hierarchy
uniform_hierarchy
mesh_hierarchy
refine_uniform!
refine_marked!
nlevels
coarsest
finest
geometry
prolongation
```

## Hierarchy reports

```@docs
MeshLevelReport
TransferReport
MeshHierarchyReport
level_report
transfer_report
hierarchy_report
```

## ngx parent maps

```@docs
num_levels
level_nvertices
parent_nodes
parent_elements
parent_surface_elements
```
