# --- BREP interop (OpenCascade.jl → Delone.jl) -------------------------------
# Primary boundary: in-memory BREP strings. TopoDS_Shape stays in OpenCascade;
# Netgen imports geometry via OCCGeometry_from_brep_string only.

"""
    occ_geometry_from_brep_string(brep) -> NetgenGeometry

Build a meshable Netgen `OCCGeometry` from an in-memory BREP string (from
`to_brep_string` in OpenCascade.jl — a different package, not part of
Delone.jl's own API). This is the stable interop path between CAD modeling
and Netgen meshing.
"""
occ_geometry_from_brep_string(brep::AbstractString) =
    Netgen.OCCGeometry_from_brep_string(String(brep))
