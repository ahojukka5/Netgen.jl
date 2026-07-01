"""
    Netgen

A CxxWrap-based Julia binding and extension layer for the exported C++ API of
NGSolve/Netgen, with Julia-side utilities for geometry-backed mesh hierarchies
and geometric-multigrid / hp-adaptivity integration.

The native binding (`NetgenCxxWrap_jll` / `libnetgen_cxxwrap`) is a **strict 1:1**
CxxWrap module: every wrapped name matches Netgen's own C++ name (`GetNP`,
`UpdateTopology`, `GetTopology`, `GetNEdges`, `LoadOCC_STEP`, `GenerateMesh`,
`Refine`, `Point`, `VolumeElement`, `PNum`, …) and forwards to exactly one Netgen
member. **All higher-level logic lives here**, in Julia: composing those calls,
looping to build arrays, and hierarchy helpers.
"""
module Netgen

using CxxWrap
using Libdl
using Artifacts
import OCCT_jll
import Zlib_jll

const _netgen_dir = artifact"NGSolveNetgen"
const _wrap_dir = artifact"libnetgen_cxxwrap"
const libnetgen_cxxwrap = joinpath(_wrap_dir, "lib", "libnetgen_cxxwrap.$(Libdl.dlext)")

@wrapmodule(() -> libnetgen_cxxwrap)

function __init__()
    flags = Libdl.RTLD_LAZY | Libdl.RTLD_GLOBAL
    Libdl.dlopen(joinpath(_netgen_dir, "lib", "libngcore.$(Libdl.dlext)"), flags)
    Libdl.dlopen(joinpath(_netgen_dir, "lib", "libnglib.$(Libdl.dlext)"), flags)
    @initcxx                  # Netgen module first (registers NetgenGeometry, …)
    OCC.__occ_initcxx()       # then the OCC module (OCCGeometry returns NetgenGeometry)
end

# Netgen ELEMENT_TYPE ids (for comparing GetType results).
const NG_TET = 20
const NG_TRIG = 10

# Netgen NG_REFINEMENT_TYPE ids (for Ngx_Mesh-style refinement selection).
const NG_REFINE_H = 0
const NG_REFINE_P = 1
const NG_REFINE_HP = 2

# --- geometry loading -------------------------------------------------------
# Thin Julia aliases over the exact 1:1 loaders. Extension dispatch (a higher-
# level convenience) also lives here, not in the C++ wrapper.
load_step(path::AbstractString) = LoadOCC_STEP(String(path))
load_iges(path::AbstractString) = LoadOCC_IGES(String(path))
load_brep(path::AbstractString) = LoadOCC_BREP(String(path))
load_stl(path::AbstractString) = LoadSTL(String(path))
load_splinegeometry2d(path::AbstractString) = LoadSplineGeometry2d(String(path))

function load_geometry(path::AbstractString)
    ext = lowercase(splitext(path)[2])
    ext in (".step", ".stp") && return LoadOCC_STEP(String(path))
    ext == ".brep"           && return LoadOCC_BREP(String(path))
    ext in (".iges", ".igs") && return LoadOCC_IGES(String(path))
    error("unsupported geometry extension: $ext")
end

# --- 2D geometry (geom2d / csg2d) -------------------------------------------
# `Circle`, `Rectangle`, `CSG2d`, the boolean ops `+`/`*`/`-`, and `BC`/`Maxh`/
# `Mat` are wrapped directly from Netgen's geom2d module. `geometry2d(solid)`
# turns a Solid2d (or composite) into a meshable geometry.

"""
    geometry2d(solid) -> geometry

Wrap a `Solid2d` (or a boolean composite of them) into a `SplineGeometry2d` that
can be passed to [`generate_mesh`](@ref) / [`coarse_hierarchy`](@ref). Curved
boundaries (e.g. a [`Circle`](@ref)) are followed under refinement.
"""
function geometry2d(solid)
    g = CSG2d()
    Add(g, solid)
    return GenerateSplineGeometry(g)
end

# --- mesh generation (compose the 1:1 calls) --------------------------------
function generate_mesh(geom; maxh::Real)
    m = new_mesh()
    SetGeometry(m, geom)
    mp = MeshingParameters()
    maxh!(mp, Float64(maxh))
    GenerateMesh(geom, m, mp)
    return m
end

# --- extraction (loop over the 1:1 accessors) -------------------------------
"""points(mesh) -> 3×GetNP Matrix{Float64} of node coordinates (Netgen p(i))."""
function points(m)
    np = GetNP(m)
    P = Matrix{Float64}(undef, 3, np)
    for i in 1:np
        p = Point(m, i)
        P[1, i] = p(0); P[2, i] = p(1); P[3, i] = p(2)
    end
    return P
end

"""tetrahedra(mesh) -> 4×GetNE Matrix{Int32}, 1-based node ids (Element::PNum)."""
function tetrahedra(m)
    ne = GetNE(m)
    T = Matrix{Int32}(undef, 4, ne)
    for i in 1:ne
        e = VolumeElement(m, i)
        for j in 1:4
            T[j, i] = PNum(e, j)
        end
    end
    return T
end

"""surface_triangles(mesh) -> 3×GetNSE Matrix{Int32}, 1-based node ids."""
function surface_triangles(m)
    nse = GetNSE(m)
    S = Matrix{Int32}(undef, 3, nse)
    for i in 1:nse
        e = SurfaceElement(m, i)
        for j in 1:3
            S[j, i] = PNum(e, j)
        end
    end
    return S
end

# --- refinement (compose GetGeometry -> GetRefinement -> Refine) ------------
"""refine!(mesh) -> mesh, refined uniformly in place (geometry-aware)."""
function refine!(m)
    Refine(GetRefinement(GetGeometry(m)), m)
    return m
end

"""
    mark_for_refinement!(mesh, marked) -> mesh

Set each volume element's refinement flag from `marked` (a `1:GetNE`-indexed
boolean vector / predicate); elements not listed are cleared. Use before
[`bisect!`](@ref).
"""
function mark_for_refinement!(m, marked)
    for i in 1:GetNE(m)
        SetRefinementFlag(VolumeElement(m, i), Bool(marked[i]))
    end
    return m
end

"""
    bisect!(mesh; onlyonce=false, maxlevel=0) -> mesh

Marked-element bisection refinement (geometry-aware) — the adaptive-refinement
path. Mark elements first with [`mark_for_refinement!`](@ref). Composes
`GetRefinement(GetGeometry(m))` → `Refinement::Bisect` with a `BisectionOptions`
whose `usemarkedelements` is enabled.
"""
function bisect!(m; onlyonce::Bool=false, maxlevel::Integer=0)
    opt = BisectionOptions()
    usemarkedelements!(opt, 1)
    onlyonce!(opt, onlyonce)
    maxlevel > 0 && maxlevel!(opt, Int(maxlevel))
    Bisect(GetRefinement(GetGeometry(m)), m, opt)
    return m
end

"""
    make_second_order!(mesh) -> mesh

Curve the mesh to second order (geometry-aware), via `Refinement::MakeSecondOrder`.
"""
function make_second_order!(m)
    MakeSecondOrder(GetRefinement(GetGeometry(m)), m)
    return m
end

# --- multigrid hierarchy (read via Ngx_Mesh: levels + parent maps) ----------
# Ngx_Mesh wraps the same shared_ptr<Mesh>; its parent maps are populated by
# Refine/Bisect and are exactly the data a geometric multigrid prolongation
# needs. Build one fresh after refining so it reflects the current hierarchy.

"""num_levels(mesh) -> number of refinement levels (`Ngx_Mesh::GetNLevels`)."""
num_levels(m) = GetNLevels(Ngx_Mesh(m))

"""level_nvertices(mesh, level) -> vertex count at `level` (0-based level index)."""
level_nvertices(m, level::Integer) = GetNVLevel(Ngx_Mesh(m), Int(level))

# Ngx_Mesh accessors are 0-based with -1 meaning "none" (the NGSolve convention).
# We normalize to the package's 1-based ids with 0 == none, so the parent maps
# index directly into `points`/`tetrahedra`.
_ngx_to_1based(v::Integer) = Int32(v) + Int32(1)

"""
    parent_nodes(mesh) -> 2×GetNP Matrix{Int32}

For each (1-based) vertex, its two coarse-level parent vertices (the endpoints of
the edge it bisects). A column of `(0, 0)` marks a vertex already present on the
coarser level. These ids index directly into [`points`](@ref) — the prolongation
stencil for nodal geometric multigrid.
"""
function parent_nodes(m)
    nm = Ngx_Mesh(m)
    np = GetNP(m)
    P = Matrix{Int32}(undef, 2, np)
    buf = zeros(Cint, 2)
    for i in 1:np
        GetParentNodes(nm, i - 1, buf)   # Ngx_Mesh query index is 0-based
        P[1, i] = _ngx_to_1based(buf[1]); P[2, i] = _ngx_to_1based(buf[2])
    end
    return P
end

"""
    parent_elements(mesh) -> Vector{Int32}

For each (1-based) volume element, its parent element on the coarser level (1-based;
`0` if none), via `Ngx_Mesh::GetParentElement`. Transfers element data across levels.
"""
function parent_elements(m)
    nm = Ngx_Mesh(m)
    ne = GetNE(m)
    return Int32[_ngx_to_1based(GetParentElement(nm, i - 1)) for i in 1:ne]
end

"""
    parent_surface_elements(mesh) -> Vector{Int32}

Per surface element, its parent on the coarser level (1-based; `0` if none), via
`Ngx_Mesh::GetParentSElement`.
"""
function parent_surface_elements(m)
    nm = Ngx_Mesh(m)
    nse = GetNSE(m)
    return Int32[_ngx_to_1based(GetParentSElement(nm, i - 1)) for i in 1:nse]
end

# --- mesh hierarchy (distinct mesh object per level) ------------------------

"""
    copy_mesh(mesh) -> mesh

A deep copy of `mesh` (points, elements, geometry), via `new_mesh` + the
`Mesh::operator=` binding. The copy carries no refinement history, so it is ready
to be refined into the next level of a hierarchy.
"""
function copy_mesh(src)
    m = new_mesh()
    assign(m, src)
    return m
end

"""
    MeshHierarchy

A growable stack of nested meshes `M₁ ⊂ M₂ ⊂ … ⊂ Mₙ` sharing one `geometry`.
Each level is a distinct mesh obtained by refining a *copy* of the previous
finest level, so a coarse vertex keeps its index in every finer level. That index
invariant is what makes the per-level parent maps ([`prolongation`](@ref) /
[`prolongation_operator`](@ref)) exact, which is what the geometric-multigrid
transfer operators are built from.

Build a coarse hierarchy with [`coarse_hierarchy`](@ref), then grow it *during*
the simulation with [`refine_uniform!`](@ref) (whole mesh) or
[`refine_marked!`](@ref) (error-driven, element-wise). Refinement is always
geometry-aware: new boundary vertices project onto the true CAD surface.
"""
struct MeshHierarchy
    geometry::Any
    meshes::Vector{Any}
end

Base.length(h::MeshHierarchy) = length(h.meshes)
Base.getindex(h::MeshHierarchy, k::Integer) = h.meshes[k]
Base.lastindex(h::MeshHierarchy) = length(h.meshes)
Base.iterate(h::MeshHierarchy, s=1) = s > length(h.meshes) ? nothing : (h.meshes[s], s + 1)

"""nlevels(h) -> number of mesh levels currently in the hierarchy."""
nlevels(h::MeshHierarchy) = length(h.meshes)
"""coarsest(h) / finest(h) -> the coarsest / finest mesh."""
coarsest(h::MeshHierarchy) = h.meshes[1]
finest(h::MeshHierarchy) = h.meshes[end]
"""geometry(h) -> the shared CAD geometry backing every level."""
geometry(h::MeshHierarchy) = h.geometry

"""
    coarse_hierarchy(geom; maxh) -> MeshHierarchy

Start a hierarchy with a single coarse mesh of `geom` (level 1). Solve on
`finest(h)`, then grow finer levels with [`refine_marked!`](@ref) /
[`refine_uniform!`](@ref) as the simulation proceeds.
"""
coarse_hierarchy(geom; maxh::Real) =
    MeshHierarchy(geom, Any[generate_mesh(geom; maxh=maxh)])

"""
    refine_uniform!(h) -> h

Append a new finest level: a uniformly refined copy of the current finest mesh
(`Refinement::Refine`). The new level's mapping is available as
`prolongation(h, nlevels(h))`.
"""
function refine_uniform!(h::MeshHierarchy)
    m = copy_mesh(finest(h))
    refine!(m)
    push!(h.meshes, m)
    return h
end

"""
    refine_marked!(h, marked) -> h

Append a new finest level by **element-wise, geometry-aware bisection** of a copy
of the current finest mesh — the adaptive-refinement step. `marked` is indexed
`1:GetNE(finest(h))` (a Bool vector / predicate from your error indicator);
marked elements are bisected (Netgen adds conforming closure refinement as
needed). The coarse→fine mapping is available as `prolongation(h, nlevels(h))`.
"""
function refine_marked!(h::MeshHierarchy, marked)
    m = copy_mesh(finest(h))
    UpdateTopology(m)
    mark_for_refinement!(m, marked)
    bisect!(m)
    push!(h.meshes, m)
    return h
end

"""
    uniform_hierarchy(geom; maxh, levels) -> MeshHierarchy

Convenience: a `levels`-deep hierarchy meshed at `maxh` (level 1) and uniformly
refined for each finer level, all built up front. Equivalent to
[`coarse_hierarchy`](@ref) followed by `levels-1` calls to
[`refine_uniform!`](@ref).
"""
function uniform_hierarchy(geom; maxh::Real, levels::Integer)
    levels >= 1 || throw(ArgumentError("levels must be ≥ 1 (got $levels)"))
    h = coarse_hierarchy(geom; maxh=maxh)
    for _ in 2:levels
        refine_uniform!(h)
    end
    return h
end

# --- per-level mapping (the data GMG transfer operators are built from) -----

"""
    prolongation(h, k) -> 2×GetNP(h[k]) Matrix{Int32}

The nodal parent map from level `k-1` to level `k`: for each vertex of `h[k]`, its
two parent vertices in `h[k-1]`, or `(0, 0)` for a vertex inherited unchanged.
`k` must be ≥ 2. This is the raw coarse→fine mapping; the actual transfer
operators are assembled from it elsewhere. Equivalent to `parent_nodes(h[k])`.
"""
function prolongation(h::MeshHierarchy, k::Integer)
    k >= 2 || throw(ArgumentError("prolongation is defined for levels k ≥ 2 (got $k)"))
    return parent_nodes(h.meshes[k])
end

# --- live session / snapshots / tags / hp / partition (consumer contract) ---
# Julia-only layers on top of the strict 1:1 bindings. See
# audit/NETGEN_LIVE_HIERARCHY_AND_PARTITION_CONTRACT_2026-07-01.md.
include("tags.jl")        # element extraction + region/tag helpers
include("hp.jl")          # hp-adaptivity readiness (order/hp-level readers)
include("session.jl")     # MeshHierarchySession + refinement requests
include("snapshots.jl")   # copied snapshot data contract for consumers
include("partition.jl")   # partition/load-balancing data contract

# --- OCC: raw OpenCASCADE modeling kernel -----------------------------------
"""
    Netgen.OCC

The OpenCASCADE modeling kernel wrapped 1:1 — raw OCCT class names, no
convenience helpers. Build a shape from primitives/builders/booleans, then turn
it into a meshable geometry with `OCCGeometry`:

    using Netgen, Netgen.OCC
    shape = BRepPrimAPI_MakeCylinder(gp_Ax2(gp_Pnt(0,0,0), gp_Dir(0,0,1)), 1.0, 2.0) |> Shape
    geom  = OCCGeometry(shape)
    mesh  = generate_mesh(geom; maxh=0.3)

All higher-level logic belongs in the consuming package.
"""
module OCC

using CxxWrap
using Libdl
using Artifacts

# A second CxxWrap module in the same shared library; these types/functions are
# defined HERE (in Netgen.OCC), not in the parent module.
const _libnetgen_cxxwrap =
    joinpath(artifact"libnetgen_cxxwrap", "lib", "libnetgen_cxxwrap.$(Libdl.dlext)")

@wrapmodule(() -> _libnetgen_cxxwrap, :define_julia_module_occ)

# Finalized explicitly from Netgen.__init__ AFTER the parent module's @initcxx,
# so OCCGeometry's NetgenGeometry return type is already registered.
__occ_initcxx() = @initcxx

# CxxWrap does not auto-export; export the raw OCCT names so `using Netgen.OCC`
# brings them into scope.
export gp_XYZ, gp_Pnt, gp_Vec, gp_Dir, gp_Ax1, gp_Ax2, gp_Ax3, gp_Trsf,
       gp_XY, gp_Pnt2d, gp_Vec2d, gp_Dir2d, gp_Ax2d, gp_Trsf2d,
       gp_Lin, gp_Circ, gp_Pln, gp_Elips, gp_Parab, gp_Hypr, gp_Mat, gp_GTrsf,
       gp_Cylinder, gp_Cone, gp_Sphere, gp_Torus,
       TopoDS_Shape, TopoDS_Vertex, TopoDS_Edge, TopoDS_Wire, TopoDS_Face,
       TopoDS_Shell, TopoDS_Solid, TopoDS_Compound, TopoDS_CompSolid,
       TopExp_Explorer, TopoDS_Iterator,
       BRepPrimAPI_MakeBox, BRepPrimAPI_MakeCylinder, BRepPrimAPI_MakeSphere,
       BRepPrimAPI_MakeCone, BRepPrimAPI_MakeTorus, BRepPrimAPI_MakePrism,
       BRepPrimAPI_MakeRevol, BRepPrimAPI_MakeHalfSpace, BRepPrimAPI_MakeWedge,
       BRepBuilderAPI_MakeVertex, BRepBuilderAPI_MakeEdge, BRepBuilderAPI_MakeWire,
       BRepBuilderAPI_MakeFace, BRepBuilderAPI_MakeSolid, BRepBuilderAPI_MakePolygon,
       BRepBuilderAPI_Transform, BRepBuilderAPI_Copy, BRepBuilderAPI_GTransform,
       BRepAlgoAPI_Fuse, BRepAlgoAPI_Cut, BRepAlgoAPI_Common, BRepAlgoAPI_Section,
       STEPControl_Reader, STEPControl_Writer, IGESControl_Reader, IGESControl_Writer,
       GProp_GProps, Bnd_Box, BRepFilletAPI_MakeFillet, BRepFilletAPI_MakeChamfer,
       TopTools_IndexedMapOfShape,
       BRepTools_WireExplorer, BRepLProp_SLProps, BRepLProp_CLProps,
       BRepBuilderAPI_Sewing, BRepClass3d_SolidClassifier,
       BRepExtrema_DistShapeShape, ShapeAnalysis_ShapeContents,
       BRep_Builder, BRepOffsetAPI_MakeOffset,
       IntCurvesFace_ShapeIntersector,
       GProp_PrincipalProps, Bnd_OBB,
       BRepClass_FaceClassifier,
       ShapeAnalysis_FreeBounds, ShapeAnalysis_Shell, ShapeAnalysis_Edge,
       BRepMesh_IncrementalMesh, BRepAlgoAPI_Check,
       ShapeFix_FreeBounds, ShapeFix_ShapeTolerance, ShapeFix_Wireframe,
       ShapeUpgrade_UnifySameDomain,
       TopTools_ListOfShape, BRepFeat_MakePrism, BRepFeat_MakeRevol,
       BRepOffsetAPI_MakeThickSolid, BRepOffsetAPI_DraftAngle,
       Geom_Curve, Geom_Surface,
       GeomAPI_ProjectPointOnCurve, GeomAPI_ProjectPointOnSurf, GeomAPI_ExtremaCurveCurve,
       OCCGeometry,
       X, Y, Z, Coord, SetX, SetY, SetZ, Distance, Magnitude,
       Location, Direction, XDirection, YDirection, Radius, MajorRadius, MinorRadius,
       SetLocation, Axis, XAxis, YAxis, Focus, Parameter,
       SetTranslation, SetRotation, SetScale,
       SetValue, IsNegative, VectorialPart, SetVectorialPart,
       TranslationPart, SetTranslationPart,
       IsNull, ShapeType, Orientation, IsSame, IsEqual, NbChildren,
       Reversed, Nullify, Init, More, Next, Current, Value, Add, Close,
       Shape, Solid, Vertex, Edge, Wire, Face,
       BRepTools_Write, BRepTools_Read,
       ReadFile, TransferRoots, NbShapes, OneShape, Transfer, Write, AddShape,
       Mass, CentreOfMass, MatrixOfInertia,
       IsVoid, IsOpenXmin, IsOpenXmax, IsOpenYmin, IsOpenYmax, IsOpenZmin, IsOpenZmax,
       CornerMin_X, CornerMin_Y, CornerMin_Z, CornerMax_X, CornerMax_Y, CornerMax_Z,
       Enlarge, IsOut,
       BRepGProp_LinearProperties, BRepGProp_SurfaceProperties, BRepGProp_VolumeProperties,
       BRepBndLib_Add, BRep_Tool_Pnt,
       Build, IsDone, NbContours,
       Extent, Contains, FindIndex, FindKey, Clear, TopExp_MapShapes,
       TopAbs_COMPOUND, TopAbs_COMPSOLID, TopAbs_SOLID, TopAbs_SHELL,
       TopAbs_FACE, TopAbs_WIRE, TopAbs_EDGE, TopAbs_VERTEX, TopAbs_SHAPE,
       TopAbs_IN, TopAbs_OUT, TopAbs_ON, TopAbs_UNKNOWN,
       TopExp_FirstVertex, TopExp_LastVertex,
       BRepAdaptor_Curve, BRepAdaptor_Surface,
       FirstParameter, LastParameter, Tolerance, IsClosed, IsPeriodic,
       D0, D1, D2,
       FirstUParameter, LastUParameter, FirstVParameter, LastVParameter, Normal,
       BRepCheck_Analyzer, ShapeFix_Shape,
       IsValid, Perform, SetPrecision, SetMinTolerance, SetMaxTolerance,
       BRep_Tool_ToleranceEdge, BRep_Tool_ToleranceFace, BRep_Tool_ToleranceVertex,
       BRep_Tool_IsClosed, BRep_Tool_Degenerated, BRep_Tool_SameParameter,
       BRep_Tool_FirstParameter, BRep_Tool_LastParameter,
       BRepOffsetAPI_MakePipe, BRepOffsetAPI_ThruSections, BRepOffsetAPI_MakeOffsetShape,
       AddWire, AddVertex, ErrorOnSurface, CheckCompatibility, PerformBySimple,
       CurrentVertex, SetParameters,
       IsNormalDefined, IsCurvatureDefined,
       MinCurvature, MaxCurvature, MeanCurvature, GaussianCurvature,
       SewedShape, SetTolerance, Tolerance,
       NbFreeEdges, NbContigousEdges, NbMultipleEdges,
       Load, PerformInfinitePoint, State, IsOnAFace,
       NbSolution, PointOnShape1, PointOnShape2, InnerSolution,
       NbSolids, NbShells, NbFaces, NbWires, NbEdges, NbVertices,
       MakeCompound, MakeShell, Remove,
       SetCurve, SetParameter, Curvature, CentreOfCurvature, IsTangentDefined, Tangent,
       GeomAbs_Arc, GeomAbs_Tangent, GeomAbs_Intersection,
       NbPnt, Pnt,
       PerformNearest, SortResult, WParameter, UParameter, VParameter, Transition,
       IntCurveSurface_In, IntCurveSurface_Out, IntCurveSurface_Tangent,
       HasSymmetryAxis, HasSymmetryPoint,
       FirstAxisOfInertia, SecondAxisOfInertia, ThirdAxisOfInertia,
       PrincipalProperties, MomentOfInertia,
       XHSize, YHSize, ZHSize, IsAABox, IsCompletelyInside,
       Center, SetXComponent, SetYComponent, SetZComponent,
       BRepBndLib_AddOBB,
       GetClosedWires, GetOpenWires,
       LoadShells, CheckOrientedShells, NbLoaded, IsLoaded,
       HasBadEdges, BadEdges, HasFreeEdges, FreeEdges, HasConnectedEdges,
       BRepTools_OuterWire, BRepTools_Compare, BRepTools_IsReallyClosed,
       BRepTools_Update, BRepTools_CleanGeometry, BRepTools_RemoveUnusedPCurves,
       BRepTools_UpdateFaceUVPoints, BRepTools_Clean,
       SetFocal, Directrix, Focal,
       Eccentricity, Asymptote1, Asymptote2, OtherBranch,
       Focus1, Focus2, SetMajorRadius, SetMinorRadius,
       GetStatusFlags, IsModified,
       SetAxis, SetPosition, Position,
       SetRadius, SetSemiAngle, Apex, RefRadius, SemiAngle, Area, Volume, Direct,
       HasCurve3d, IsClosed3d, HasPCurve, IsSeam,
       FirstVertex, LastVertex,
       GetShape, LimitTolerance, SetTolerance,
       FixWireGaps, FixSmallEdges, SetLimitAngle, LimitAngle,
       Initialize, AllowInternalEdges, KeepShape, SetSafeInputMode,
       SetLinearTolerance, SetAngularTolerance, Build,
       Append, IsEmpty, First, Last,
       Error, BRepBuilderAPI_WireDone, BRepBuilderAPI_EmptyWire,
       BRepBuilderAPI_DisconnectedWire, BRepBuilderAPI_NonManifoldWire,
       IsDeleted,
       IsConstant,
       AddDA, SetDists, SetDistAngle,
       MakeThickSolidBySimple, MakeThickSolidByJoin, Modified,
       BRepOffset_Skin, BRepOffset_Pipe, BRepOffset_RectoVerso,
       AddDone,
       PerformUntilEnd, PerformFromEnd, PerformThruAll,
       PerformUntilHeight, PerformUntilAngle,
       BRepLib_CheckSameRange, BRepLib_SameRange, BRepLib_BuildCurve3d,
       BRepLib_BuildCurves3d, BRepLib_SameParameter, BRepLib_OrientClosedSolid,
       BRepLib_EncodeRegularity,
       GeomAbs_C0, GeomAbs_G1, GeomAbs_C1, GeomAbs_G2, GeomAbs_C2, GeomAbs_C3, GeomAbs_CN,
       Continuity, IsUClosed, IsVClosed, IsUPeriodic, IsVPeriodic,
       Geom_BSplineCurve, Geom_BezierCurve, GeomAPI_PointsToBSpline,
       BRep_Tool_Curve, BRep_Tool_Surface,
       NbPoints, Point, NbExtrema, IsParallel, LowerDistance, TotalLowerDistance,
       LowerDistanceParameter, NearestPoint

end # module OCC

# MESHING3_RESULT enum values (returned as Int by MeshVolume / OptimizeVolume)
const MESHING3_OK                  = 0
const MESHING3_GIVEUP              = 1
const MESHING3_NEGVOL              = 2
const MESHING3_OUTERSTEPSEXCEEDED  = 3
const MESHING3_TERMINATE           = 4
const MESHING3_BADSURFACEMESH      = 5

export load_step, load_iges, load_brep, load_geometry, generate_mesh,
       geometry2d, Circle, Rectangle, CSG2d,
       points, tetrahedra, surface_triangles,
       refine!, mark_for_refinement!, bisect!, make_second_order!,
       num_levels, level_nvertices, parent_nodes, parent_elements,
       parent_surface_elements,
       copy_mesh, MeshHierarchy, coarse_hierarchy, uniform_hierarchy,
       refine_uniform!, refine_marked!,
       nlevels, coarsest, finest, geometry, prolongation,
       # live session (authoritative handles + refinement requests)
       MeshHierarchySession, mesh_session, level_mesh, unsafe_level_mesh,
       mutate_level_mesh!, generation,
       request_uniform_refinement!, request_marked_refinement!,
       request_second_order!,
       # snapshot data contract (copies for downstream consumers)
       MeshLevelSnapshot, HierarchyTransferSnapshot, MeshHierarchySnapshot,
       level_snapshot, transfer_snapshot, hierarchy_snapshot,
       supported_snapshot_topology, transfer_weight_semantics,
       # element extraction + region/tag helpers
       volume_tetrahedra, triangles2d, segments2d,
       cell_regions, boundary_regions, material_names, boundary_names,
       # hp-adaptivity readiness
       element_order, element_orders, surface_element_order,
       surface_element_orders, hp_element_levels,
       # partitioning / load-balancing data contract
       native_partition_hint,
       NG_TET, NG_TRIG, NG_REFINE_H, NG_REFINE_P, NG_REFINE_HP,
       Segment, FaceDescriptor, LocalH, new_localh,
       STLParameters, STLGeometry, LoadSTL, load_stl,
       Box3d, Point3dTree, new_point3dtree,
       SplineGeometry2d, LoadSplineGeometry2d, load_splinegeometry2d,
       EdgeDescriptor,
       MeshVolume, OptimizeVolume, RemoveIllegalElements, ConformToFreeSegments,
       MESHING3_OK, MESHING3_GIVEUP, MESHING3_NEGVOL,
       MESHING3_OUTERSTEPSEXCEEDED, MESHING3_TERMINATE, MESHING3_BADSURFACEMESH

end # module Netgen
