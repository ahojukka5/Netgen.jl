# Mesh surgery & spatial search

Topology splitting/merging/sub-meshing operations, and a spatial index for
radius-based node queries.

```@docs
split_to_tets!
split_into_parts!
merge_mesh_file!
get_sub_mesh
pure_tet_mesh
pure_trig_mesh
surface_mesh_orientation!
```

## Spatial search

```@docs
NodeTree
node_tree
build_node_tree
nodes_near
```
