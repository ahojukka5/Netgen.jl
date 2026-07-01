@testset "OCC load + generate_mesh + counts (Julian API)" begin
    geom = load_step(STEP)
    m = generate_mesh(geom; maxh=40.0)
    @test mesh_dimension(m) == 3
    @test num_nodes(m) > 0
    @test num_cells(m) > 0
    @test num_boundary_facets(m) > 0
    @test num_nodes(m) == I.GetNP(m)
    @test num_cells(m) == I.GetNE(m)
    @test num_boundary_facets(m) == I.GetNSE(m)
end

@testset "extraction (Julia loops over 1:1 accessors)" begin
    geom = load_step(STEP)
    m = generate_mesh(geom; maxh=40.0)
    P = points(m)
    @test size(P) == (3, num_nodes(m))
    T = tetrahedra(m)
    @test size(T) == (4, num_cells(m))
    @test all(1 .<= T .<= num_nodes(m))
    S = surface_triangles(m)
    @test size(S) == (3, num_boundary_facets(m))
    # element type via the 1:1 GetType
    @test I.GetType(I.VolumeElement(m, 1)) == NG_TET
    @test I.GetType(I.SurfaceElement(m, 1)) == NG_TRIG
end

@testset "topology (Julian update_topology!)" begin
    geom = load_step(STEP)
    m = generate_mesh(geom; maxh=40.0)
    update_topology!(m)
    t = I.GetTopology(m)
    @test I.GetNEdges(t) > 0
    @test I.GetNFaces(t) > 0
end

@testset "save_mesh / load_mesh round-trip" begin
    geom = load_step(STEP)
    m = generate_mesh(geom; maxh=40.0)
    tmp = tempname() * ".vol"
    save_mesh(m, tmp)
    @test isfile(tmp)
    m2 = load_mesh(tmp)
    @test num_nodes(m2) == num_nodes(m)
    rm(tmp; force=true)
end
