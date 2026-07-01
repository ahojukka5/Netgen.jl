# Netgen ELEMENT_TYPE ids (for comparing GetType results).

"""Netgen `ELEMENT_TYPE` id for a tetrahedron, as returned by `GetType`."""
const NG_TET = 20

"""Netgen `ELEMENT_TYPE` id for a triangle, as returned by `GetType`."""
const NG_TRIG = 10

# Netgen NG_REFINEMENT_TYPE ids (for Ngx_Mesh-style refinement selection).

"""Netgen `NG_REFINEMENT_TYPE` id selecting pure h-refinement."""
const NG_REFINE_H = 0

"""Netgen `NG_REFINEMENT_TYPE` id selecting pure p-refinement."""
const NG_REFINE_P = 1

"""Netgen `NG_REFINEMENT_TYPE` id selecting combined hp-refinement."""
const NG_REFINE_HP = 2

# MESHING3_RESULT enum values (returned as Int by MeshVolume / OptimizeVolume)

"""`MESHING3_RESULT` code: volume meshing completed successfully."""
const MESHING3_OK                  = 0

"""`MESHING3_RESULT` code: volume mesher gave up (exhausted retries)."""
const MESHING3_GIVEUP              = 1

"""`MESHING3_RESULT` code: volume mesher produced a negative-volume element."""
const MESHING3_NEGVOL              = 2

"""`MESHING3_RESULT` code: outer meshing loop exceeded its step limit."""
const MESHING3_OUTERSTEPSEXCEEDED  = 3

"""`MESHING3_RESULT` code: volume meshing was terminated (e.g. by the caller)."""
const MESHING3_TERMINATE           = 4

"""`MESHING3_RESULT` code: the input surface mesh is not suitable for volume meshing."""
const MESHING3_BADSURFACEMESH      = 5
