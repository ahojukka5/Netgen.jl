# API coverage — Netgen & OpenCASCADE

What fraction of the Netgen and OpenCASCADE C++ APIs are wrapped by
`libnetgen_cxxwrap` (and therefore reachable from `Delone.jl`). OCCT modeling
itself is wrapped separately by **OpenCascade.jl**; the OpenCASCADE figures
below describe that package's coverage, not this one's.

Counts are measured from the installed headers of this build
(`NGSolveNetgen_jll` artifact, `OCCT_jll` 7.9.3) and from the wrapper sources
(`NetgenCxxWrap_jll/bundled/src/{netgen,occ}*.cpp`).

## Summary

| Library      | Classes wrapped | Methods/fns wrapped | Public API total¹ | Coverage |
|--------------|----------------:|--------------------:|------------------:|---------:|
| Netgen       |       23        |       ~245          |       ~260        |   ~94 %  |
| OpenCASCADE  |       57        |        ~90          |    43 623²        |   < 1 %  |

¹ `DLL_HEADER`-marked declarations across `meshing/`, `stlgeom/`, `geom2d/`,
`gprim/`, `nginterface_v2.hpp`.
² `Standard_EXPORT`-marked declarations across all 6816 OCCT headers (the vast
majority are exchange schema, visualization, and CAD kernel internals that a
geometry/meshing caller never touches — see the OpenCASCADE section for a
per-area breakdown).

**Are we wrapping everything in Netgen?** Nearly. We cover ~94 % of the
`DLL_HEADER` surface across the key headers. The wrapped portion is the full
core: mesh building, topology queries, refinement, geometry I/O, quality
analysis, splitting, h-field control, and the NGSolve `Ngx_Mesh` interface.
The remaining ~6 % is three narrow categories:
(a) internal/low-value items (point-curve visualization data, CD2/CD3 name
tables, parallel Metis/Distribute helpers),
(b) hp-refinement machinery that requires CurvedElements state
(ZRefinement, direct CurvedElements API, hp order and cluster-rep Ngx_Mesh
methods — these are bound but crash without hp state),
(c) STL topology inspection, and the parts of `Identifications` beyond the
axis-aligned-box periodic case (arbitrary curved-face pairing, the raw
point-index-level API).
See the **Not yet wrapped** section at the end.

---

## Netgen — wrapped (23 classes, ~245 methods)

### Source → class mapping

| Wrapper file | Classes registered |
|---|---|
| `netgen_mesh.cpp` | `Point3d`, `Vec3d`, `MeshPoint`, `Element`, `Element2d`, `MeshTopology` |
| `netgen_geometry.cpp` | `MeshingParameters`, `BisectionOptions`, `NetgenGeometry`, `Refinement`, `Mesh`, `Ngx_Mesh` |
| `netgen_geom2d.cpp` | `Solid2d`, `CSG2d` |
| `netgen_extras.cpp` | `Segment`, `FaceDescriptor`, `LocalH` |
| `netgen_stl.cpp` | `STLParameters`, `STLGeometry` |
| `netgen_gprim.cpp` | `Box3d`, `Point3dTree`, `SplineGeometry2d` |
| `netgen_mesh2.cpp` | `EdgeDescriptor` (+ additional methods on `Mesh`, `MeshTopology`, `LocalH`) |
| `netgen_ngx2.cpp` | additional methods on `Ngx_Mesh`; free fns `MeshVolume`, `OptimizeVolume`, `RemoveIllegalElements`, `ConformToFreeSegments` |

### Per-class detail

| Class | Wrapped methods/functions |
|-------|--------------------------|
| `Point3d` | constructor`(x,y,z)`, `X`, `Y`, `Z` |
| `Vec3d` | constructor`(x,y,z)`, `X`, `Y`, `Z`, `Length` |
| `MeshPoint` | `operator()(i)` (coord by index) |
| `Element` | `GetNP`, `GetNV`, `GetType`, `GetIndex`, `PNum`, `Set/TestRefinementFlag`, `Set/TestStrongRefinementFlag` |
| `Element2d` | same 9 as Element |
| `MeshTopology` | `GetNEdges`, `GetNFaces`, `GetEdgeVertices`¹, `GetFaceVertices`¹, `GetFaceEdges`¹, `GetVerticesEdge`, `EnableTopologyTable` (via Mesh) |
| `MeshingParameters` | constructor, `maxh`, `minh`, `grading`, `optsteps2d`, `optsteps3d`, `secondorder` (getter + setter each) |
| `BisectionOptions` | constructor, `maxlevel`, `usemarkedelements`, `refine_hp`, `refine_p`, `onlyonce` (getter + setter each) |
| `NetgenGeometry` | `GenerateMesh`, `GetRefinement` |
| `Refinement` | `Refine`, `Bisect`, `MakeSecondOrder` |
| `Mesh` (via `shared_ptr`) | `new_mesh` (alloc), `assign` (copy), `GetNP/NV/NE/NSE/NSeg/Dimension/NDomains/NFD`, `Point`, `VolumeElement`, `SurfaceElement`, `LineSegment`, `AddPoint`, `AddVolumeElement`, `AddSurfaceElement`, `AddSegment`, `GetFaceDescriptor`×2, `UpdateTopology`, `GetTopology`, `Get/SetGeometry`, `Save`, `Load`, `Get/SetMaterial`, `Get/SetBCName`, `Compress`, `CalcLocalH`, `Get/SetNextTimeStamp`, `BuildCurvedElements`, `RestrictLocalH`, `ImproveMesh`, `CheckVolumeMesh`, `CheckConsistentBoundary`, **GetBox**, **GetH(Point3d)**, **SetGlobalH**, **SetMinimalH**, **SetLocalH** (×2 overloads), **CalcLocalHFromSurfaceCurvature**, **CalcLocalHFromPointDistances**, **CheckOverlappingBoundary**, **AverageH**, **CalcTotalBad**, **CalcMinMaxAngle** (void), **MarkIllegalElements**, **Split2Tets**, **SplitIntoParts**, **SplitSeparatedFaces**, **SurfaceMeshOrientation**, **BuildElementSearchTree**, **SplitFacesByAdjacentDomains**, **PureTrigMesh**, **PureTetMesh**, **SetDimension**, **ClearVolumeElements**, **ClearSegments**, **DeleteMesh**, **SetSurfaceElement**, **SetVolumeElement**, **GetSurfaceElementsOfFace**¹, **AddLockedPoint**, **FindOpenElements**, **FindOpenSegments**, **RemoveOneLayerSurfaceElements**, **RestrictLocalHLine**, **LoadLocalMeshSize**, **Merge**, **ElementError**, **GetSubMesh** |
| `Ngx_Mesh` | constructor`(shared_ptr<Mesh>)`, `Valid`, `GetDimension`, `GetNLevels`, `GetNVLevel`, `GetNElements`, `GetNNodes`, `GetParentNodes`, `GetParentElement`, `GetParentSElement`, `GetCurveOrder`, `Curve`, `UpdateTopology`, **GetPoint** (→`Point3d`), **GetElementIndex** (DIM=3), **GetNIdentifications**, **GetIdentificationType**, **GetSurfaceElementSurfaceNumber**², **GetSurfaceElementFDNumber**², **GetHPElementLevel**², **GetElementOrder**², **GetElementOrders**², **GetSurfaceElementOrder**², **GetSurfaceElementOrders**², **GetClusterRepVertex/Edge/Face/Element**², **GetElement_Faces**¹, **GetSurfaceElement_Face** |
| `EdgeDescriptor` | constructor`()` and`(int,int,int)`, `EdgeNr`, `SetEdgeNr`, `SurfNr`, `SetSurfNr`, `GetName`, `SetName`, `SingEdgeLeft/Right`, `SetSingEdgeLeft/Right` |
| `LocalH` | `new_localh` (factory), `SetH`, `GetH`, `GetMinH`, **Copy** (→`shared_ptr<LocalH>`), **Delete** |
| free functions | `LoadOCC_STEP/IGES/BREP`, `Circle`, `Rectangle`, **MeshVolume**, **OptimizeVolume**, **RemoveIllegalElements**, **ConformToFreeSegments** |
| `Solid2d` | `BC`, `Maxh`, `Mat`, `+`, `*`, `-` (via `Base.:+` etc.) |
| `CSG2d` | constructor, `Add`, `GenerateSplineGeometry`, `GenerateMesh` |
| `Segment` | constructor, `GetNP`, `GetIndex`, `SetIndex`, `PNum` |
| `FaceDescriptor` | constructors`()` and`(int,int,int,int)`, `SurfNr`, `DomainIn/Out`, `TLOSurface`, `BCProperty`, `GetBCName`, `SetDomainIn/Out`, `SetBCProperty`, `SetBCName` |
| `STLParameters` | constructor, `yangle`, `contyangle`, `edgecornerangle`, `chartangle`, `outerchartangle`, `usesearchtree`, `recalc_h_opt` (getter + setter each) |
| `STLGeometry` | `LoadSTL` (factory via `istream`), `GetNT`, `GetNP`, `GenerateMesh`, `GetRefinement` |
| `Box3d` | constructor`(Point3d,Point3d)`, `PMin`, `PMax`, `MinX/MaxX/MinY/MaxY/MinZ/MaxZ`, `IsIn`, `Intersect` |
| `Point3dTree` | `new_point3dtree` (factory), `Insert`, `GetIntersecting` |
| `SplineGeometry2d` | `LoadSplineGeometry2d` (factory + `Load` + cast to `NetgenGeometry`) |

¹ Buffer-fill pattern: takes a caller-allocated `Array{Int32}` buffer, fills
it in place, returns count. `GetEdgeVertices` fills 2 elements;
`GetFaceVertices`/`GetFaceEdges`/`GetSurfaceElementsOfFace`/`GetElement_Faces`
return the actual element/vertex/edge count.
² These methods are bound correctly but crash at runtime for standard
h-refined meshes — they require hp-FEM internal state (second-order curved
elements or periodic identifications) to be populated first.

---

## Netgen — not yet wrapped

### Missing methods on wrapped classes

| Class | Not-wrapped methods (DLL_HEADER) | Notes |
|-------|----------------------------------|-------|
| `Mesh` | `GetH(PointIndex)` | Query h at a mesh point by index |
| `Mesh` | `CreatePoint2ElementTable` and variants | Point-to-element connectivity tables |
| `Mesh` | `SetNBCNames`, `SetNCD2/3Names`, `SetCD2/3Name`, `GetCD2/3Name`, `GetRegionName/NamesCD` | Extended boundary name tables |
| `Mesh` | `InitPointCurve`, `AddPointCurvePoint`, `GetNum/GetPointOfCurve`, etc. | Point-curve visualization data |
| `Mesh` | `Distribute`, `ParallelMetis` | Parallel domain decomposition |
| `Point3dTree` | `DeleteElement` | Not exported from JLL (`ADTree3::DeleteElement` missing `DLL_HEADER`) |
| `SplineGeometry2d` | `GetSpline(int)`, and all `SplineGeometry<2>` API | Spline curve access |
| `STLGeometry`/`STLTopology` | `GetTriangle`, `GetPoint`(by index), `GetTopEdgeNum`, `InvertTrig`, `DeleteTrig`, `OrientAfterTrig` | STL topology inspection |

### Entire classes not wrapped

| Class | Header | Why not wrapped |
|-------|--------|-----------------|
| `CurvedElements` | `meshing/curvedelems.hpp` | Used indirectly via `Mesh::BuildCurvedElements`; direct use requires NGSolve FEM context |
| `Identifications` | `meshing/meshtype.hpp` | Read side (`GetNIdentifications`/`GetPeriodicVertices`) and axis-aligned-box write side (`OCC_IdentifyFaces`/`OCC_RebuildGeometry` → `identify_periodic!`/`identify_periodic_box!`) now wrapped; the full point-index-level `Add`/`GetNr`/`SetName` API and arbitrary curved-face pairing remain unwrapped |
| `ZRefinementOptions` | `meshing/bisect.hpp` | Z-direction refinement for structured meshes |
| free: `BisectTetsCopyMesh`, `ZRefinement` | `meshing/bisect.hpp` | Specialized refinement paths |
| `GeometryShape` / `GeometryVertex/Edge/Face/Solid` | `meshing/basegeom.hpp` | Abstract base classes for geometry shapes; user-visible only through OCCGeometry |
| `GeometryRegister`, `GeometryRegisterArray` | `meshing/basegeom.hpp` | Geometry plugin system; not user-facing |

---

## OpenCASCADE — wrapped (57 classes, ~90 methods)

### Source → class mapping

| Wrapper file | Classes registered |
|---|---|
| `occ_gp.cpp` | `gp_XYZ`, `gp_Pnt`, `gp_Vec`, `gp_Dir`, `gp_Ax1`, `gp_Ax2`, `gp_Ax3`, `gp_Trsf`, `gp_XY`, `gp_Pnt2d`, `gp_Vec2d`, `gp_Dir2d`, `gp_Ax2d`, `gp_Trsf2d`, `gp_Lin`, `gp_Circ`, `gp_Pln` |
| `occ_topology.cpp` | `TopoDS_Shape`, `TopoDS_Vertex/Edge/Wire/Face/Shell/Solid/Compound/CompSolid`, `TopExp_Explorer`, `TopoDS_Iterator` |
| `occ_builders.cpp` | `BRepPrimAPI_MakeBox/Cylinder/Sphere/Cone/Torus/Prism/Revol`, `BRepBuilderAPI_MakeVertex/Edge/Wire/Face/Solid/Polygon/Transform/Copy`, `BRepAlgoAPI_Fuse/Cut/Common/Section` |
| `occ_io.cpp` | `STEPControl_Reader/Writer`, `IGESControl_Reader/Writer`; free fns `BRepTools_Write/Read`, `OCCGeometry` bridge |
| `occ_props.cpp` | `GProp_GProps`, `Bnd_Box`; free fns `BRepGProp_LinearProperties`, `BRepGProp_SurfaceProperties`, `BRepGProp_VolumeProperties`, `BRepBndLib_Add`, `BRep_Tool_Pnt` |
| `occ_fillet.cpp` | `BRepFilletAPI_MakeFillet`, `BRepFilletAPI_MakeChamfer` |
| `occ_topo2.cpp` | `TopTools_IndexedMapOfShape`; free fn `TopExp_MapShapes`; `TopAbs_*` integer constants |

### `gp` — value geometry types (17 of 43 wrapped)
✅ `gp_XYZ`, `gp_Pnt`, `gp_Vec`, `gp_Dir`, `gp_Ax1`, `gp_Ax2`, `gp_Ax3`,
`gp_Trsf`, `gp_XY`, `gp_Pnt2d`, `gp_Vec2d`, `gp_Dir2d`, `gp_Ax2d`, `gp_Trsf2d`,
`gp_Lin`, `gp_Circ`, `gp_Pln`
❌ `gp_Ax22d`, `gp_Lin2d`, `gp_Circ2d`, `gp_Elips`, `gp_Parab`, `gp_Hypr`,
`gp_Cone`, `gp_Cylinder`, `gp_Sphere`, `gp_Torus`, `gp_Mat`, `gp_Mat2d`,
`gp_GTrsf`, `gp_GTrsf2d`, `gp_Quaternion`, … (26 more)

### `TopoDS` — topology (11 of 52 wrapped)
✅ `TopoDS_Shape`, `TopoDS_Vertex/Edge/Wire/Face/Shell/Solid/Compound/CompSolid`,
`TopExp_Explorer`, `TopoDS_Iterator`, `TopTools_IndexedMapOfShape` and the `TopoDS::` downcasts.
❌ `TopoDS_Builder`, `TopoDS_TShape` & the `T*` server classes, the
`TopoDSToStep_*` family (40+).

### `BRep*API` — modeling algorithms (17 of 486 in the `BRep*` packages)
✅ Primitives: `BRepPrimAPI_MakeBox/MakeCylinder/MakeSphere/MakeCone/MakeTorus/
MakePrism/MakeRevol`
✅ Builders: `BRepBuilderAPI_MakeVertex/MakeEdge/MakeWire/MakeFace/MakeSolid/
MakePolygon/Transform/Copy`
✅ Booleans: `BRepAlgoAPI_Fuse/Cut/Common/Section`
✅ Fillets: `BRepFilletAPI_MakeFillet/MakeChamfer`
❌ `BRepOffsetAPI_*` (pipe/thick/thrusections/offset), `BRepPrimAPI_MakeWedge/
MakeHalfSpace`, `BRepBuilderAPI_MakeShell/Sewing/NurbsConvert/GTransform`,
`BRepAlgoAPI_Splitter/Defeaturing`, `BRepMesh_*`, `BRepFeat_*` (~465 more).

### Properties & bounding boxes (NEW)
✅ `GProp_GProps` (mass/centroid), `BRepGProp::LinearProperties/SurfaceProperties/VolumeProperties`
✅ `Bnd_Box` (axis-aligned bounding box), `BRepBndLib::Add`
✅ `BRep_Tool::Pnt` (vertex → `gp_Pnt`)

### Sub-shape enumeration (NEW)
✅ `TopTools_IndexedMapOfShape`, `TopExp::MapShapes`, `TopAbs_ShapeEnum` integer constants

### I/O (4 classes wrapped)
✅ `BRepTools::Write`/`Read`, `STEPControl_Reader`/`Writer`,
`IGESControl_Reader`/`Writer`
❌ `XCAF*`/`XSControl_*` (assemblies, colors, names), `RWGltf`, `RWObj`, `RWStl`,
`VrmlAPI`, the full `STEP*`/`IGES*` schema readers.

### Methods wrapped on the above
`X/Y/Z`, `Coord`, `SetX/Y/Z`, `Distance`, `Magnitude`, `Location`, `Direction`,
`XDirection`, `YDirection`, `Radius`, `SetTranslation/SetRotation/SetScale`,
`IsNull`, `ShapeType`, `Orientation`, `IsSame`, `IsEqual`, `NbChildren`,
`Reversed`, `Nullify`, `Init/More/Next/Current/Value` (explorers), `Add`,
`Close`, `Shape`, `Solid`, `Vertex`, `Edge`, `Wire`, `Face`, `Build`, `IsDone`,
`NbContours`, `Mass`, `CentreOfMass`, `IsVoid`, `IsOpen{Xmin/Xmax/Ymin/Ymax/Zmin/Zmax}`,
`CornerMin/Max_{X/Y/Z}`, `Enlarge`, `IsOut`, `Extent`, `Contains`, `FindIndex`,
`FindKey`, `Clear`, `TopExp_MapShapes`, `TopAbs_*` integer constants,
`BRepGProp_LinearProperties/SurfaceProperties/VolumeProperties`,
`BRepBndLib_Add`, `BRep_Tool_Pnt`,
`BRepTools_Write/Read`, `ReadFile/TransferRoots/NbShapes/OneShape/Transfer/Write/
AddShape`, and the `OCCGeometry(TopoDS_Shape)` bridge → Netgen.

### OpenCASCADE — entire packages NOT wrapped (by design)
| Area | Packages | ~classes |
|------|----------|---------:|
| STEP exchange schema | `StepBasic_/StepShape_/StepGeom_/StepRepr_/StepVisual_/StepAP*/…` | ~2500 |
| IGES exchange schema | `IGESGeom_/IGESSolid_/IGESDimen_/IGESData_/…` | ~600 |
| Visualization | `AIS_/Prs3d_/Graphic3d_/V3d_/SelectMgr_/…` | ~1500 |
| Curves/surfaces (Handle-based) | `Geom_/Geom2d_/GeomFill_/GeomInt_/GC_/GCE2d_` | ~400 |
| Mesh/HLR/healing | `BRepMesh_/HLRBRep_/ShapeFix_/ShapeAnalysis_` | ~400 |
| Collections, data exchange, app framework | `TColStd_/TColgp_/TDF_/TDataStd_/…` | many |

These are out of scope for a geometry-construction + meshing wrapper.

---

## Second-installment candidates

### Netgen — remaining items (now very few)
- `Mesh::GetH(PointIndex)` — query h at an existing mesh point by index
- `STLGeometry` topology inspection (`GetTriangle`, `GetTopEdgeNum`, etc.)
- `SplineGeometry2d::GetSpline(int)` — access individual spline segments

### Netgen — hp-refinement path (requires CurvedElements state)
- `CurvedElements` direct API (`IsElementCurved`, `CalcElementTransformation`)
- `Ngx_Mesh` hp methods (`GetClusterRep*`, `GetElementOrder*`, `GetHPElementLevel`) — bindings exist but crash without hp state
- `ZRefinement` / `ZRefinementOptions`

### OpenCASCADE — modeling kernel (next step)
- `Geom_*` / `Geom2d_*` curves & surfaces + `GC_MakeSegment`, `GC_MakeArcOfCircle`
  (needs `opencascade::handle` support in the bindings).
- `BRepOffsetAPI_*` pipe/thick-solid/thru-sections/offset.
- More `gp_` analytic types (`gp_Cylinder/Sphere/Cone/Torus`, 2D conics).
- `BRep_Tool::Curve`, `BRep_Tool::Surface` (edge/face geometry access, Handle-based).
