# Meshing

## Basic mesh generation

Every mesh starts from a geometry object and a characteristic mesh size `maxh`
(smaller → finer mesh):

```@example meshing
using Delone

disk = Circle(0.0, 0.0, 1.0, "disk", "boundary")
mesh = generate_mesh(geometry2d(disk); maxh=0.4)
Int(num_cells(mesh))
```

3D example from a STEP file:

```@example meshing
step_path = joinpath(@__DIR__, "..", "..", "..", "test", "fixtures", "frame.step")
step_geom = load_step(step_path)
step_mesh = generate_mesh(step_geom; maxh=40.0)
Int(num_cells(step_mesh))
```

Optional meshing parameters are passed as keyword arguments to
[`generate_mesh`](@ref) (via [`meshing_parameters`](@ref)):

```@example meshing
mesh_params = generate_mesh(geometry2d(disk);
    maxh=0.4,
    minh=0.05,          # optional lower bound
    grading=0.3,        # mesh grading between coarse and fine regions
    second_order=false,
    optsteps2d=3,
    optsteps3d=3,
)
Int(num_cells(mesh_params))
```

## Reading mesh data

Julian helpers loop over 1-based Netgen indices. The rest of this page continues
with a 3D volume mesh loaded from the `cylinder.brep` fixture (unit cylinder,
radius 1, height 2) — smaller and faster to iterate on than the STEP frame above:

```@example meshing
cylinder_path = joinpath(@__DIR__, "..", "..", "..", "test", "fixtures", "cylinder.brep")
geom = load_brep(cylinder_path)
mesh3d = generate_mesh(geom; maxh=0.5)

X = points(mesh3d)                  # 3×np (z=0 for 2D meshes)

# 3D volume mesh
T = tetrahedra(mesh3d)              # 4×ne, 1-based node indices
F = surface_triangles(mesh3d)       # 3×nse boundary triangles

# 2D domain mesh
Tr = triangles2d(mesh)              # domain triangles
S  = segments2d(mesh)               # boundary segments

# counts and combined connectivity
println("X: ", size(X), ", T: ", size(T), ", F: ", size(F))
println("Tr: ", size(Tr), ", S: ", size(S))
println("num_nodes: ", num_nodes(mesh3d), ", num_cells: ", num_cells(mesh3d),
        ", mesh_dimension: ", mesh_dimension(mesh3d))
vol, surf = connectivity(mesh3d)
(vol == T, surf == F)
```

For low-level access, use `Delone.Internals` (`GetNP`, `Point(mesh, i)`,
`VolumeElement(mesh, i)`, …) — see [Internals escape hatch](../internals_escape_hatch.md)
for when and how to drop down to it.

## Mesh I/O

Save and reload Netgen volume format without touching Internals:

```@example meshing
out_path = tempname() * ".vol"
save_mesh(mesh3d, out_path)
mesh2 = load_mesh(out_path)
Int(num_cells(mesh2))
```

## Mesh parameters

For reuse across generate / improve / optimize steps, build parameters explicitly:

```@example meshing
mp = meshing_parameters(maxh=0.2, minh=0.01, grading=0.3)
typeof(mp)
```

Set `second_order=true` before generation if you want second-order elements from
the mesher (alternative: [`make_second_order!`](@ref) after the fact — see
[Refinement](refinement.md)).

## Topology

After mesh changes, refresh topology tables:

```@example meshing
update_topology!(mesh3d)
topo = Delone.Internals.GetTopology(mesh3d)
println("edges: ", Delone.Internals.GetNEdges(topo))
println("faces: ", Delone.Internals.GetNFaces(topo))
```

Enable optional parent-edge tables before refinement (see
[Tags, hp-adaptivity & FEM data](@ref "Tags, hp-adaptivity & FEM data")):

```@example meshing
enable_topology_table!(mesh3d, "parentedges")
enable_topology_table!(mesh3d, "parentfaces")
```

## Quality checks

```@example meshing
check_mesh(mesh3d)                    # (volume_ok=..., boundary_ok=...)
```

```@example meshing
optimize_volume!(mesh3d; maxh=0.5)   # returns MESHING3_OK (see exported constants)
```

```@example meshing
improve_mesh!(mesh3d; maxh=0.5)
(lo, hi) = mesh_bounding_box(mesh3d)
compress!(mesh3d)
Int(num_cells(mesh3d))
```

## Copying meshes

[`copy_mesh`](@ref) (C++ `Mesh.assign`) duplicates a mesh so you can refine one level
without destroying another:

```@example meshing
coarse = generate_mesh(geom; maxh=0.5)
fine   = copy_mesh(coarse)
refine!(fine)
(Int(num_cells(coarse)), Int(num_cells(fine)))
```

This pattern underlies multigrid hierarchies — see
[Mesh hierarchies & sessions](@ref "Mesh hierarchies & sessions").

## STL surfaces

```@example meshing
stl_path = joinpath(@__DIR__, "..", "..", "..", "test", "fixtures", "tet.stl")
stl = load_stl(stl_path)           # or load_geometry(stl_path)
stl_mesh = generate_mesh(stl; maxh=10.0)   # surface triangle mesh
Int(num_cells(stl_mesh))
```

STL geometry is triangle-based; volume meshing typically starts from a closed
BREP/STEP solid instead.

Next: [Refinement](refinement.md).
