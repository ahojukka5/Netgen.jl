# Tags, hp-adaptivity & FEM data

## Region ids and names

```julia
using Delone

mesh = generate_mesh(load_step("part.step"); maxh=0.5)

cr = cell_regions(mesh)           # per volume element (3D)
br = boundary_regions(mesh)       # per boundary triangle

mats = material_names(mesh)       # Dict region_id => name (3D)
bnames = boundary_names(mesh)

region_name_volume(mesh, 1)       # per-element material name
region_name_surface(mesh, 1)      # per boundary triangle
```

**2D caveat:** `material_names` is empty and `boundary_names` keys do not match
`boundary_regions`. Use `region_name_segment(mesh, segnr)` for segment names in 2D.

Codimension dispatch:

```julia
material_codim_name(mesh, 0, region_nr)   # volume material (3D)
material_codim_name(mesh, 1, region_nr)   # boundary condition name
```

## hp-adaptivity — reading state

```julia
element_orders(mesh)              # vector length = ncells
element_order(mesh)               # maximum order
hp_element_levels(mesh)           # 3×ncells; -1 = no hp table

surface_element_orders(mesh)      # 3D boundaries only
```

Cluster representatives (only after hp refinement):

```julia
hp_clusters_available(mesh) || error("no hp clusters")
cluster_rep_vertices(mesh)
cluster_rep_elements(mesh)
```

## hp-adaptivity — applying changes

On a live mesh:

```julia
set_element_order!(mesh, 1, 3)           # raise order on cell 1
set_element_orders!(mesh, orders)        # bulk vector

mark_for_ngx_refinement!(mesh, marked)
ngx_refine!(mesh; reftype=NG_REFINE_P)   # marked p-refinement
ngx_refine!(mesh; reftype=NG_REFINE_HP)  # marked hp-refinement

hp_refine!(mesh; levels=1)               # global hp split
split_alfeld!(mesh)
```

Through a session:

```julia
s = mesh_session(geom; maxh=0.5)
request_set_element_orders!(s, orders)
request_marked_p_refinement!(s, marked)
request_hp_refine!(s; levels=1)
```

In-place hp/p operations invalidate finest-level snapshots (same as second-order
curving).

## FEM geometry — curved maps

After `make_second_order!(mesh)`, query reference-to-physical maps:

```julia
make_second_order!(mesh)

xi = [0.0, 0.0, 0.0]
x, J = volume_element_transformation(mesh, 1, xi)   # 3D volume cell 1
# x: physical point, J: 3×3 Jacobian

x, J = surface_element_transformation(mesh, 1, [0.0, 0.0])  # 3D boundary
x, J = domain_element_transformation(mesh, 1, [0.0, 0.0])   # 2D domain
```

Batch evaluation:

```julia
xis = [0.0 0.5; 0.0 0.0; 0.0 0.0]    # 3×npts
X, Js = volume_element_transformations(mesh, 1, xis)
```

## Parent edge / face topology

Off by default. Enable **before** refining:

```julia
enable_topology_table!(mesh, "parentedges")
enable_topology_table!(mesh, "parentfaces")
refine!(mesh)
Delone.Internals.UpdateTopology(mesh)

has_parent_edges(mesh)
parent_edges(mesh, enr)           # orientation + parent edge indices
parent_faces(mesh, fnr)
face_edges(mesh, fnr)             # needs up-to-date topology
```

## Periodic identifications

```julia
periodic_vertex_pairs(mesh)       # [] if mesh has no identifications
periodic_vertex_pairs(mesh, idnr) # 1-based identification index
```

## Point location & local mesh size

```julia
find_element(mesh, x)             # (cell_nr, λ) or nothing
mesh_h_at_point(mesh, pi)         # h at mesh node pi (1-based)
```

## Partition hints

Optional input for an external partitioner (METIS/ParMETIS, etc.):

```julia
hint = native_partition_hint(mesh)
hint.global_vertex_ids    # per local vertex, global id (identity on serial build)
hint.distant_procs        # per vertex, remote MPI ranks (empty on serial build)
```

Delone.jl does not call a partitioner or assign ownership.
