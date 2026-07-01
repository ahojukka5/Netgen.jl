# Live session

`MeshHierarchySession` is a live, mutable multigrid hierarchy: it tracks a
generation counter and exposes `request_*!` mutators for uniform/marked
h-refinement, second-order curving, and p-/hp-adaptivity, so a session can be
driven incrementally (e.g. from an LLM agent loop) without rebuilding the
whole hierarchy each step.

```@docs
MeshHierarchySession
mesh_session
level_mesh
unsafe_level_mesh
mutate_level_mesh!
generation
request_uniform_refinement!
request_marked_refinement!
request_second_order!
request_set_element_orders!
request_set_element_order!
request_marked_p_refinement!
request_marked_hp_refinement!
request_hp_refine!
request_split_alfeld!
```
