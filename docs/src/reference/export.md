# Export & preview

Writing meshes to common interchange/visualization formats and generating
quick raster/vector previews.

```@docs
export_vtk
export_vtu
export_obj
export_mesh_preview
export_svg_2d
mesh_preview
mesh_previews
```

## Package extensions

Two optional, weakdep-gated extensions add real ecosystem integration beyond
the dependency-free formats above — see `Project.toml`'s `[weakdeps]`/
`[extensions]`:

- **`DeloneMakieExt`** (`ext/DeloneMakieExt.jl`, active once `Makie` is
  loaded) — `Makie.mesh`/`Makie.mesh!`/`Makie.plot` recipes for
  `MeshLevelSnapshot`/`MeshHierarchySnapshot`.
- **`DeloneWriteVTKExt`** (`ext/DeloneWriteVTKExt.jl`, active once `WriteVTK`
  is loaded) — [`export_vtu`](@ref), real binary/compressed VTU export with
  cell data.
- **`DeloneGeometryBasicsExt`** (`ext/DeloneGeometryBasicsExt.jl`, active
  once `GeometryBasics` is loaded) — `GeometryBasics.Mesh(::MeshLevelSnapshot)`/
  `GeometryBasics.Mesh(::MeshHierarchySnapshot)`, bridging into the wider
  Julia visualization/geometry ecosystem (composes with `DeloneMakieExt`:
  `Makie.mesh(GeometryBasics.Mesh(snapshot))` works once both are loaded).
