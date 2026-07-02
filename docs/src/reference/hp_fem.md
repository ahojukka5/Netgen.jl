# hp-adaptivity & FEM geometry

Per-element polynomial order queries/mutation, hp-refinement marking, hp
cluster metadata (for hp-refinement history), and the finite-element
geometry primitives (reference-to-physical transformations, Jacobians) used
to build local FEM data on top of a Delone.jl mesh.

## hp-adaptivity

```@docs
element_order
element_orders
element_orders_xyz
surface_element_order
surface_element_orders
hp_element_levels
set_element_order!
set_element_orders!
set_element_orders_xyz!
set_surface_element_order!
set_surface_element_orders!
mark_for_ngx_refinement!
ngx_refine!
hp_refine!
split_alfeld!
hp_clusters_available
cluster_rep_vertex
cluster_rep_edge
cluster_rep_face
cluster_rep_element
cluster_rep_vertices
cluster_rep_elements
```

## FEM geometry

```@docs
volume_element_transformation
surface_element_transformation
domain_element_transformation
segment_element_transformation
volume_element_transformations
```
