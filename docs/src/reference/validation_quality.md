# Validation, quality & meshability

Structured reports that check whether a mesh is internally consistent
(`MeshValidationReport`), how good its element shapes are
(`MeshQualityReport`), which tags/regions it carries (`MeshTagReport`), and
whether a geometry is likely to mesh successfully before you try
(`MeshabilityReport`). Also includes the underlying mutating quality
operations (`check_mesh`, `improve_mesh!`, `optimize_volume!`).

## Mesh validation & quality reports

```@docs
MeshValidationReport
isvalid
topology_report
MeshQualityReport
quality
mesh_quality
MeshTagReport
tag_report
boundary_tags
region_tags
has_boundary_tag
has_region_tag
MeshReport
mesh_report
```

## Meshability / diagnostics

```@docs
MeshabilityReport
meshability_report
meshing_diagnostics
suggest_mesh_fixes
```

## Mesh quality (operations)

```@docs
check_mesh
improve_mesh!
optimize_volume!
mesh_bounding_box
```
