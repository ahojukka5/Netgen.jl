# Live MeshHierarchySession API, snapshot contract, and stable identity.

@testset "mesh_session creates a live hierarchy with one level" begin
    geom = load_step(STEP)
    s = mesh_session(geom; maxh=40.0)
    @test s isa MeshHierarchySession
    @test nlevels(s) == 1
    @test generation(s) == 0
    @test geometry(s) === geom
    @test level_mesh(s, 1) === coarsest(s) === finest(s)
    @test s.metadata[:maxh] == 40.0
    @test Netgen.GetNP(finest(s)) > 0
end

@testset "request_uniform_refinement! appends a level & bumps generation" begin
    geom = load_step(STEP)
    s = mesh_session(geom; maxh=40.0)
    ne0 = Netgen.GetNE(finest(s))
    g0 = generation(s)
    request_uniform_refinement!(s)
    @test nlevels(s) == 2
    @test generation(s) == g0 + 1
    @test Netgen.GetNE(finest(s)) > ne0
    # previous level preserved and untouched
    @test Netgen.GetNE(level_mesh(s, 1)) == ne0
end

@testset "request_marked_refinement! appends a level and grows the mesh" begin
    geom = load_step(STEP)
    s = mesh_session(geom; maxh=40.0)
    m = finest(s); ne = Netgen.GetNE(m)
    X = points(m); T = tetrahedra(m)
    cx = [sum(X[1, T[:, e]]) / 4 for e in 1:ne]
    marked = cx .< sort(cx)[ne ÷ 3]
    g0 = generation(s)
    request_marked_refinement!(s, marked)
    @test nlevels(s) == 2
    @test generation(s) == g0 + 1
    @test Netgen.GetNE(finest(s)) > ne
end

@testset "level_mesh returns a live Netgen mesh handle" begin
    geom = load_step(STEP)
    s = mesh_session(geom; maxh=40.0)
    request_uniform_refinement!(s)
    m1 = level_mesh(s, 1)
    m2 = level_mesh(s, 2)
    @test Netgen.GetDimension(m1) == 3
    @test Netgen.GetNP(m2) > Netgen.GetNP(m1)
    # it is *the* live handle: refining it in place changes the session's level
    ne = Netgen.GetNE(m2)
    refine!(m2)
    @test Netgen.GetNE(level_mesh(s, 2)) > ne
    @test_throws ArgumentError level_mesh(s, 3)
end

@testset "request_second_order! curves the finest mesh in place (no new level)" begin
    geom = load_step(STEP)
    s = mesh_session(geom; maxh=40.0)
    np0 = Netgen.GetNP(finest(s))
    g0 = generation(s)
    request_second_order!(s)
    @test nlevels(s) == 1                       # documented: in place, no new level
    @test generation(s) == g0 + 1
    @test Netgen.GetNP(finest(s)) > np0         # edge-midpoint nodes added
    @test s.metadata[:curved_order] == 2
    @test_throws ArgumentError request_second_order!(s; order=3)
end

@testset "level_snapshot returns coordinates/connectivity/tags (3D)" begin
    geom = load_step(STEP)
    s = mesh_session(geom; maxh=40.0)
    request_uniform_refinement!(s)
    snap = level_snapshot(s, 2)
    m = level_mesh(s, 2)
    @test snap isa MeshLevelSnapshot{3}
    @test size(snap.coordinates) == (3, Netgen.GetNP(m))
    @test size(snap.volume_connectivity) == (4, Netgen.GetNE(m))
    @test size(snap.surface_connectivity) == (3, Netgen.GetNSE(m))
    @test length(snap.cell_regions) == Netgen.GetNE(m)
    @test length(snap.boundary_regions) == Netgen.GetNSE(m)
    @test snap.element_type == :tet
    @test snap.boundary_element_type == :tri
    @test snap.level == 2
    @test snap.generation == generation(s)
    @test all(1 .<= snap.volume_connectivity .<= Netgen.GetNP(m))
    # snapshot is a copy — mutating it does not touch the live mesh
    snap.coordinates[1, 1] = -999.0
    @test points(level_mesh(s, 2))[1, 1] != -999.0
end

@testset "transfer_snapshot returns parent maps with correct dimensions" begin
    geom = load_step(STEP)
    s = mesh_session(geom; maxh=40.0)
    request_uniform_refinement!(s)
    m = level_mesh(s, 2)
    t = transfer_snapshot(s, 2)
    @test t isa HierarchyTransferSnapshot
    @test t.level_from == 1 && t.level_to == 2
    @test size(t.parent_nodes) == (2, Netgen.GetNP(m))
    @test length(t.parent_elements) == Netgen.GetNE(m)
    @test length(t.parent_surface_elements) == Netgen.GetNSE(m)
    @test t.weights === nothing
end

@testset "transfer_snapshot(session, 1) throws ArgumentError" begin
    geom = load_step(STEP)
    s = mesh_session(geom; maxh=40.0)
    @test_throws ArgumentError transfer_snapshot(s, 1)
end

@testset "hierarchy_snapshot returns all levels and all transfers" begin
    geom = load_step(STEP)
    s = mesh_session(geom; maxh=40.0)
    request_uniform_refinement!(s)
    request_uniform_refinement!(s)
    hs = hierarchy_snapshot(s)
    @test hs isa MeshHierarchySnapshot
    @test length(hs.levels) == 3
    @test length(hs.transfers) == 2
    @test hs.generation == generation(s)
    @test [l.level for l in hs.levels] == [1, 2, 3]
    @test [(t.level_from, t.level_to) for t in hs.transfers] == [(1, 2), (2, 3)]
end

@testset "curved-boundary refinement still snaps new nodes to geometry" begin
    radius(p) = sqrt(p[1]^2 + p[2]^2)
    geom = load_brep(CYLINDER)
    s = mesh_session(geom; maxh=0.5)
    m0 = finest(s); np0 = Netgen.GetNP(m0); X0 = points(m0)
    lateral0 = Set(j for j in 1:np0 if abs(radius(X0[:, j]) - 1) < 1e-9)
    request_uniform_refinement!(s)
    m1 = finest(s); np1 = Netgen.GetNP(m1); X1 = points(m1)
    P = parent_nodes(m1)
    newlat = [j for j in (np0 + 1):np1 if P[1, j] in lateral0 && P[2, j] in lateral0]
    @test !isempty(newlat)
    # chord midpoints would fall inside; snapped nodes are exactly on r=1
    @test minimum(radius((X1[:, P[1, j]] .+ X1[:, P[2, j]]) ./ 2) for j in newlat) < 0.99
    @test maximum(abs(radius(X1[:, j]) - 1) for j in newlat) < 1e-12
end

@testset "stable identity convention: uniform refinement" begin
    geom = load_step(STEP)
    s = mesh_session(geom; maxh=40.0)
    request_uniform_refinement!(s)
    c = level_snapshot(s, 1); f = level_snapshot(s, 2)
    npc = size(c.coordinates, 2)
    t = transfer_snapshot(s, 2)
    # node ids one-based; parents live on the coarse level or are 0 (inherited)
    @test all(0 .<= t.parent_nodes .<= npc)
    # inherited coarse nodes keep their ids: exactly npc columns are (0,0)
    @test count(j -> t.parent_nodes[1, j] == 0 && t.parent_nodes[2, j] == 0,
                1:size(f.coordinates, 2)) == npc
    # ...and those inherited nodes keep their coordinates
    @test c.coordinates ≈ f.coordinates[:, 1:npc]
    # cell/element parent ids one-based into the coarse level (0 = none)
    @test all(0 .<= t.parent_elements .<= size(c.volume_connectivity, 2))
end

@testset "stable identity convention: marked refinement" begin
    geom = load_step(STEP)
    s = mesh_session(geom; maxh=40.0)
    m = finest(s); ne = Netgen.GetNE(m)
    X = points(m); T = tetrahedra(m)
    cx = [sum(X[1, T[:, e]]) / 4 for e in 1:ne]
    marked = cx .< sort(cx)[ne ÷ 3]
    request_marked_refinement!(s, marked)
    npc = Netgen.GetNP(level_mesh(s, 1))
    t = transfer_snapshot(s, 2)
    @test all(0 .<= t.parent_nodes .<= npc)
    @test count(j -> t.parent_nodes[1, j] == 0 && t.parent_nodes[2, j] == 0,
                1:size(t.parent_nodes, 2)) == npc
    # inherited coarse nodes keep coordinates on the finer level
    Xc = points(level_mesh(s, 1)); Xf = points(level_mesh(s, 2))
    @test Xc ≈ Xf[:, 1:npc]
end

@testset "2D level snapshot (triangles + segments)" begin
    disk = Circle(0.0, 0.0, 1.0, "disk", "circle")
    s = mesh_session(geometry2d(disk); maxh=0.4)
    m = finest(s)
    snap = level_snapshot(s, 1)
    @test snap isa MeshLevelSnapshot{2}
    @test size(snap.coordinates) == (2, Netgen.GetNP(m))
    @test size(snap.volume_connectivity) == (3, Netgen.GetNSE(m))
    @test size(snap.surface_connectivity) == (2, Netgen.GetNSeg(m))
    @test snap.element_type == :tri
    @test snap.boundary_element_type == :segment
end
