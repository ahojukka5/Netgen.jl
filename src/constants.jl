# Netgen ELEMENT_TYPE ids (for comparing GetType results).
const NG_TET = 20
const NG_TRIG = 10

# Netgen NG_REFINEMENT_TYPE ids (for Ngx_Mesh-style refinement selection).
const NG_REFINE_H = 0
const NG_REFINE_P = 1
const NG_REFINE_HP = 2

# MESHING3_RESULT enum values (returned as Int by MeshVolume / OptimizeVolume)
const MESHING3_OK                  = 0
const MESHING3_GIVEUP              = 1
const MESHING3_NEGVOL              = 2
const MESHING3_OUTERSTEPSEXCEEDED  = 3
const MESHING3_TERMINATE           = 4
const MESHING3_BADSURFACEMESH      = 5
