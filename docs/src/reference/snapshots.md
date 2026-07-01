# Snapshots & Oodi readiness

Immutable, serialization-friendly snapshots of a mesh hierarchy session
(per-level data and coarse→fine transfer weights), and the readiness check
that determines whether a mesh/hierarchy can be handed off to Oodi.jl.

## Snapshots

```@docs
MeshLevelSnapshot
HierarchyTransferSnapshot
MeshHierarchySnapshot
level_snapshot
transfer_snapshot
hierarchy_snapshot
supported_snapshot_topology
transfer_weight_semantics
```

## Oodi readiness

```@docs
OodiSnapshotReadiness
oodi_snapshot_readiness
```
