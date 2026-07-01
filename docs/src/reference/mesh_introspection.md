# Mesh introspection & the LLM-native introspection contract

Low-level introspection of a live mesh handle (counts, connectivity, raw
arrays), together with the generic `report`/`validate`/`readiness` contract
(from OodiCore, re-exported here) that gives any Delone.jl object a
structured, LLM-friendly way to describe itself.

## Mesh introspection

```@docs
num_nodes
num_cells
num_boundary_facets
mesh_dimension
connectivity
points
tetrahedra
surface_triangles
volume_tetrahedra
triangles2d
segments2d
```

## LLM-native introspection contract

```@docs
report
validate
readiness
to_namedtuple
AbstractOodiReport
AbstractValidationReport
AbstractReadinessReport
AbstractPipelineTarget
PipelineTarget
ValidationReport
ReadinessReport
ObjectReport
ArtifactRef
DiagnosticMessage
info
warning
error_diagnostic
MeshingTarget
OodiImportTarget
GeometricMultigridTarget
```
