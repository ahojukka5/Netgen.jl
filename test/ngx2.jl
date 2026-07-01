@testset "Ngx_Mesh GetPoint" begin
    geom = load_step(STEP)
    m = generate_mesh(geom; maxh=40.0)
    nm = I.Ngx_Mesh(m)
    np = I.GetNP(m)
    @test np > 0
    p = I.GetPoint(nm, 0)   # 0-based indexing
    @test I.X(p) isa Float64
    @test I.Y(p) isa Float64
    @test I.Z(p) isa Float64
end

@testset "Ngx_Mesh GetNIdentifications" begin
    geom = load_step(STEP)
    m = generate_mesh(geom; maxh=40.0)
    nm = I.Ngx_Mesh(m)
    @test I.GetNIdentifications(nm) >= 0
end

@testset "Ngx_Mesh element-face connectivity (requires UpdateTopology)" begin
    geom = load_step(STEP)
    m = generate_mesh(geom; maxh=40.0)
    I.UpdateTopology(m)
    nm = I.Ngx_Mesh(m)
    ne = I.GetNE(m)
    @test ne > 0
    buf = zeros(Int32, 6)
    n = I.GetElement_Faces(nm, 0, buf)
    @test n == 4        # tet has 4 faces
    @test all(buf[1:n] .>= 0)
end

@testset "Ngx_Mesh GetSurfaceElement_Face" begin
    geom = load_step(STEP)
    m = generate_mesh(geom; maxh=40.0)
    I.UpdateTopology(m)
    nm = I.Ngx_Mesh(m)
    nse = I.GetNSE(m)
    @test nse > 0
    fi = I.GetSurfaceElement_Face(nm, 0)
    @test fi >= 0
end

@testset "I.OptimizeVolume (free function)" begin
    geom = load_step(STEP)
    m = generate_mesh(geom; maxh=40.0)
    mp = I.MeshingParameters()
    I.maxh!(mp, 40.0)
    result = I.OptimizeVolume(mp, m)
    @test result == MESHING3_OK
end
