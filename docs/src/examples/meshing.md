# Meshing

## Basic mesh generation

Every mesh starts from a geometry object and a characteristic mesh size `maxh`
(smaller → finer mesh):

```julia
using Delone

disk = Circle(0.0, 0.0, 1.0, "disk", "boundary")
mesh = generate_mesh(geometry2d(disk); maxh=0.4)
```

3D example from a STEP file:

```julia
geom = load_step("frame.step")
mesh = generate_mesh(geom; maxh=0.5)
```

Optional meshing parameters are passed as keyword arguments to
[`generate_mesh`](@ref) (via [`meshing_parameters`](@ref)):

```julia
mesh = generate_mesh(geom;
    maxh=0.5,
    minh=0.01,          # optional lower bound
    grading=0.3,        # mesh grading between coarse and fine regions
    secondorder=false,
    optsteps2d=3,
    optsteps3d=3,
)
```

## Reading mesh data

Julian helpers loop over 1-based Netgen indices:

```julia
X = points(mesh)                  # 3×np (z=0 for 2D meshes)

# 3D volume mesh
T = tetrahedra(mesh)              # 4×ne, 1-based node indices
F = surface_triangles(mesh)       # 3×nse boundary triangles

# 2D domain mesh
Tr = triangles2d(mesh)            # domain triangles
S  = segments2d(mesh)             # boundary segments

# counts and combined connectivity
num_nodes(mesh); num_cells(mesh); mesh_dimension(mesh)
vol, surf = connectivity(mesh)
```

For low-level access, use [`Delone.Internals`](@ref) (`GetNP`, `Point(mesh, i)`,
`VolumeElement(mesh, i)`, …).

## Mesh I/O

Save and reload Netgen volume format without touching Internals:

```julia
save_mesh(mesh, "out.vol")
mesh2 = load_mesh("out.vol")
```

## Mesh parameters

For reuse across generate / improve / optimize steps, build parameters explicitly:

```julia
mp = meshing_parameters(maxh=0.2, minh=0.01, grading=0.3)
```

Set `secondorder=true` before generation if you want second-order elements from
the mesher (alternative: [`make_second_order!`](@ref) after the fact — see
[Refinement](@ref "Refinement")).

## Topology

After mesh changes, refresh topology tables:

```julia
update_topology!(mesh)
topo = Delone.Internals.GetTopology(mesh)
Delone.Internals.GetNEdges(topo)
Delone.Internals.GetNFaces(topo)
```

Enable optional parent-edge tables before refinement (see
[Tags, hp-adaptivity & FEM data](@ref "Tags, hp-adaptivity & FEM data")):

```julia
enable_topology_table!(mesh, "parentedges")
enable_topology_table!(mesh, "parentfaces")
```

## Quality checks

```julia
check_mesh(mesh)                    # (volume_ok=..., boundary_ok=...)
optimize_volume!(mesh; maxh=0.5)   # returns MESHING3_OK (see exported constants)
improve_mesh!(mesh; maxh=0.5)
(lo, hi) = mesh_bounding_box(mesh)
compress!(mesh)
```

## Copying meshes

[`copy_mesh`](@ref) (C++ `Mesh.assign`) duplicates a mesh so you can refine one level
without destroying another:

```julia
coarse = generate_mesh(geom; maxh=0.5)
fine   = copy_mesh(coarse)
refine!(fine)
```

This pattern underlies multigrid hierarchies — see
[Mesh hierarchies & sessions](@ref "Mesh hierarchies & sessions").

## STL surfaces

```julia
stl = load_stl("scan.stl")           # or load_geometry("scan.stl")
mesh = generate_mesh(stl; maxh=1.0)   # surface triangle mesh
```

STL geometry is triangle-based; volume meshing typically starts from a closed
BREP/STEP solid instead.

Next: [Refinement](@ref "Refinement").
