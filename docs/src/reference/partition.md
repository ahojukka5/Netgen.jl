# Topology tables & partition/search

Optional derived topology tables (parent edges/faces, periodic vertex
pairs) and geometric search / partitioning-hint helpers used to locate
elements at a point or feed an external domain-decomposition tool.

## Topology tables

```@docs
enable_topology_table!
has_parent_edges
parent_edges
parent_faces
face_edges
periodic_vertex_pairs
```

## Partition & search

```@docs
find_element
mesh_h_at_point
native_partition_hint
```
