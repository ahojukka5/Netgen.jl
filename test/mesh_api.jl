@testset "meshing_parameters kwargs" begin
    geom = load_step(STEP)
    m = generate_mesh(geom; maxh=40.0, minh=1.0, grading=0.3)
    @test num_cells(m) > 0
end

@testset "connectivity" begin
    geom = load_step(STEP)
    m = generate_mesh(geom; maxh=40.0)
    vol, surf = connectivity(m)   # positional destructuring still works
    @test vol == tetrahedra(m)
    @test surf == surface_triangles(m)
    c = connectivity(m)
    @test c isa NamedTuple
    @test c.volume == vol
    @test c.surface == surf
end

@testset "mesh_bounding_box" begin
    geom = load_step(STEP)
    m = generate_mesh(geom; maxh=40.0)
    (lo, hi) = mesh_bounding_box(m)   # positional destructuring still works
    @test all(lo .< hi)
    b = I.GetBox(m)
    @test lo[1] ≈ I.MinX(b)
    @test hi[3] ≈ I.MaxZ(b)
    bbox = mesh_bounding_box(m)
    @test bbox isa NamedTuple
    @test bbox.min == lo
    @test bbox.max == hi
end

@testset "check_mesh" begin
    geom = load_step(STEP)
    m = generate_mesh(geom; maxh=40.0)
    ok = check_mesh(m)
    @test ok.volume_ok
    @test ok.boundary_ok
end

@testset "compress!" begin
    geom = load_step(STEP)
    m = generate_mesh(geom; maxh=40.0)
    np_before = num_nodes(m)
    compress!(m)
    @test num_nodes(m) <= np_before
end

@testset "optimize_volume!" begin
    geom = load_step(STEP)
    m = generate_mesh(geom; maxh=40.0)
    status = optimize_volume!(m; maxh=40.0, throw_on_error=false)
    @test status == MESHING3_OK
end

@testset "load_geometry (.stl)" begin
    stl_path = joinpath(@__DIR__, "fixtures", "tet.stl")
    geom = load_geometry(stl_path)
    @test I.GetNT(geom) == 4
end

@testset "load_geometry: unsupported extension throws ArgumentError" begin
    @test_throws ArgumentError load_geometry("model.xyz")
end
