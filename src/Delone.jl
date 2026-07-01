"""
    Delone

Delone.jl is a high-level, LLM-friendly meshing, refinement, mesh-diagnostics,
and mesh-hierarchy package for numerical simulation workflows. It is built on
top of **Netgen/NGSolve**, a mature and powerful open-source meshing
technology — Delone.jl does not replace Netgen; it provides a Julian,
simulation-oriented, agent-friendly layer above it.

Raw Netgen/NGSolve C++ bindings live in [`Internals`](@ref) (`Delone.Internals`)
— strict 1:1 names from `NetgenCxxWrap_jll` — for advanced users and backend
development. Most users and LLM agents should use the high-level exported API:
composition, 1-based ids, sessions, snapshots, and structured meshing/hierarchy
reports for downstream solvers (e.g. Oodi.jl) and LLM-driven workflows.
"""
module Delone

import OCCT_jll  # load before Internals.__init__ runs @initcxx (BREP bridge)

# `report`/`validate`/`readiness`/`to_namedtuple` and their base marker/report
# types are owned by OodiCore, the shared Oodi-ecosystem introspection contract
# (see ../OodiCore.jl AGENTS.md). Delone only adds methods/subtypes here — it
# must never redefine these names locally (that would shadow the shared
# generic instead of extending it). Plain `using OodiCore` is not enough to
# extend those four generics from other files' bare `function report(...)`
# definitions — Julia needs an explicit `import` for that, or each definition
# would silently create a new Delone-local generic instead.
using OodiCore
import OodiCore: report, validate, readiness, to_namedtuple

include("internals.jl")
include("constants.jl")
include("diagnostics.jl")
include("geometry.jl")
include("extraction.jl")
include("tags.jl")
include("mesh.jl")
include("options.jl")
include("validation.jl")
include("quality.jl")
include("tag_report.jl")
include("mesh_report.jl")
include("generation_result.jl")
include("refinement.jl")
include("hierarchy.jl")
include("meshability.jl")
include("export_mesh.jl")
include("hp.jl")
include("fem.jl")
include("session.jl")
include("hierarchy_report.jl")
include("snapshots.jl")
include("refinement_result.jl")
include("oodi_readiness.jl")
include("partition.jl")
include("interop.jl")
include("introspection.jl")

# --- constants --------------------------------------------------------------
export NG_TET, NG_TRIG
export NG_REFINE_H, NG_REFINE_P, NG_REFINE_HP
export MESHING3_OK, MESHING3_GIVEUP, MESHING3_NEGVOL,
       MESHING3_OUTERSTEPSEXCEEDED, MESHING3_TERMINATE, MESHING3_BADSURFACEMESH

# --- geometry ---------------------------------------------------------------
export load_step, load_iges, load_brep, load_geometry, load_stl, load_splinegeometry2d
export geometry2d, Circle, Rectangle, CSG2d
export occ_geometry_from_brep_string

# --- mesh generation & I/O --------------------------------------------------
export MeshOptions, mesh_options, validate_options!, to_meshing_parameters
export meshing_parameters, generate_mesh, generate_mesh_result, try_generate_mesh
export MeshGenerationResult, MeshGenerationDiagnostics, mesh
export save_mesh, load_mesh
export update_topology!, compress!

# --- mesh introspection -----------------------------------------------------
export num_nodes, num_cells, num_boundary_facets, mesh_dimension, connectivity
export points, tetrahedra, surface_triangles
export volume_tetrahedra, triangles2d, segments2d

# --- LLM-native introspection contract (OodiCore, re-exported for convenience)
export report, validate, readiness, to_namedtuple
export AbstractOodiReport, AbstractValidationReport, AbstractReadinessReport
export AbstractPipelineTarget, PipelineTarget, ValidationReport, ReadinessReport
export ObjectReport, ArtifactRef
export DiagnosticMessage, info, warning, error_diagnostic
export MeshingTarget, OodiImportTarget, GeometricMultigridTarget

# --- mesh validation & quality reports --------------------------------------
export MeshValidationReport, isvalid, topology_report
export MeshQualityReport, quality, mesh_quality
export MeshTagReport, tag_report, boundary_tags, region_tags
export has_boundary_tag, has_region_tag
export MeshReport, mesh_report

# --- meshability / diagnostics ----------------------------------------------
export MeshabilityReport, meshability_report, meshing_diagnostics, suggest_mesh_fixes

# --- mesh quality (operations) ----------------------------------------------
export check_mesh, improve_mesh!, optimize_volume!, mesh_bounding_box

# --- refinement -------------------------------------------------------------
export refine!, mark_for_refinement!, bisect!, make_second_order!
export RefinementResult, refine_session!

# --- multigrid hierarchy ----------------------------------------------------
export copy_mesh, MeshHierarchy, coarse_hierarchy, uniform_hierarchy, mesh_hierarchy
export refine_uniform!, refine_marked!
export nlevels, coarsest, finest, geometry, prolongation

# --- hierarchy reports ------------------------------------------------------
export MeshLevelReport, TransferReport, MeshHierarchyReport
export level_report, transfer_report, hierarchy_report

# --- ngx parent maps --------------------------------------------------------
export num_levels, level_nvertices
export parent_nodes, parent_elements, parent_surface_elements

# --- live session -----------------------------------------------------------
export MeshHierarchySession, mesh_session, level_mesh, unsafe_level_mesh
export mutate_level_mesh!, generation
export request_uniform_refinement!, request_marked_refinement!, request_second_order!
export request_set_element_orders!, request_set_element_order!
export request_marked_p_refinement!, request_marked_hp_refinement!
export request_hp_refine!, request_split_alfeld!

# --- snapshots --------------------------------------------------------------
export MeshLevelSnapshot, HierarchyTransferSnapshot, MeshHierarchySnapshot
export level_snapshot, transfer_snapshot, hierarchy_snapshot
export supported_snapshot_topology, transfer_weight_semantics

# --- Oodi readiness ---------------------------------------------------------
export OodiSnapshotReadiness, oodi_snapshot_readiness

# --- export / preview ---------------------------------------------------------
export export_vtk, export_obj, export_mesh_preview, export_svg_2d
export mesh_preview, mesh_previews

# --- tags & regions ---------------------------------------------------------
export cell_regions, boundary_regions
export material_names, boundary_names
export region_name_volume, region_name_surface, region_name_segment
export material_codim_name

# --- hp-adaptivity ----------------------------------------------------------
export element_order, element_orders, element_orders_xyz
export surface_element_order, surface_element_orders, hp_element_levels
export set_element_order!, set_element_orders!
export set_surface_element_order!, set_surface_element_orders!
export mark_for_ngx_refinement!, ngx_refine!, hp_refine!, split_alfeld!
export hp_clusters_available
export cluster_rep_vertex, cluster_rep_edge, cluster_rep_face, cluster_rep_element
export cluster_rep_vertices, cluster_rep_elements

# --- FEM geometry -----------------------------------------------------------
export volume_element_transformation, surface_element_transformation
export domain_element_transformation, segment_element_transformation
export volume_element_transformations

# --- topology tables --------------------------------------------------------
export enable_topology_table!
export has_parent_edges, parent_edges, parent_faces, face_edges
export periodic_vertex_pairs

# --- partition & search -----------------------------------------------------
export find_element, mesh_h_at_point
export native_partition_hint

end # module Delone
