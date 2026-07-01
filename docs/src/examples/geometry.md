# Building geometry

Netgen.jl accepts geometry from files, 2D constructive solid geometry (CSG), or
shapes built in [OpenCascade.jl](https://github.com/) and passed via BREP strings.

## Import CAD files

```julia
using Netgen

geom = load_step("model.step")       # also load_iges, load_brep
geom = load_geometry("part.brep")    # extension dispatch

# STL → surface mesh pipeline (3D triangle soup)
stl_geom = load_stl("surface.stl")
```

`load_*` functions return a Netgen geometry object (`NetgenGeometry` /
`STLGeometry`) that you pass to `generate_mesh` (see [Meshing](@ref "Meshing")).

## 2D CSG — disks, rectangles, booleans

2D domains use `geom2d` / `csg2d`. Primitives carry a material label and a
boundary label:

```julia
using Netgen

# Unit disk (radius 1), curved boundary
disk = Circle(0.0, 0.0, 1.0, "disk", "outer")
geom = geometry2d(disk)

# Plate with a rectangular notch (difference)
outer = Circle(0.0, 0.0, 1.0, "plate", "circle")
notch = Rectangle(-0.2, -1.5, 0.2, 0.0, "notch", "rect")
geom = geometry2d(outer - notch)

# Union / intersection: use + and * ; difference: -
```

Boolean operators match Netgen's CSG conventions (`+` union, `*` intersection,
`-` difference).

## 3D modeling with OpenCascade.jl

CAD modeling lives in **OpenCascade.jl** (not Netgen). Build a shape there, then
import via the in-memory BREP boundary:

```julia
using OpenCascade, Netgen

shape = cylinder(1.0, 2.0)
geom  = occ_geometry_from_brep_string(to_brep_string(shape))
mesh  = generate_mesh(geom; maxh=0.3)
```

### Booleans

```julia
big   = box(2, 2, 2)
small = sphere(0.6; center=gp_Pnt(1, 1, 1))
cut   = cut(big, small)
geom  = occ_geometry_from_brep_string(to_brep_string(cut))
```

### File export / Netgen file import

```julia
write_brep(shape, "part.brep")
geom = load_brep("part.brep")
```

## Choosing a workflow

| Goal | Suggested path |
|------|----------------|
| Existing CAD part | `load_step` / `load_brep` |
| Parametric 2D domain | `Circle` / `Rectangle` CSG |
| Custom 3D solid | OpenCascade.jl → `occ_geometry_from_brep_string` |
| Surface scan | `load_stl` |

Next: [Meshing](@ref "Meshing") turns any of these geometries into a simplicial mesh.
