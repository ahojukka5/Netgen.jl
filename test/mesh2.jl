@testset "I.EdgeDescriptor (1:1)" begin
    ed = I.EdgeDescriptor()
    I.SetEdgeNr(ed, 3)
    @test I.EdgeNr(ed) == 3
    I.SetSurfNr(ed, 0, 1)
    I.SetSurfNr(ed, 1, 2)
    @test I.SurfNr(ed, 0) == 1
    @test I.SurfNr(ed, 1) == 2
    I.SetName(ed, "boundary1")
    @test I.GetName(ed) == "boundary1"
    I.SetSingEdgeLeft(ed, 0.5)
    @test I.SingEdgeLeft(ed) ≈ 0.5
    I.SetSingEdgeRight(ed, 0.25)
    @test I.SingEdgeRight(ed) ≈ 0.25
end

@testset "Mesh GetBox" begin
    geom = load_step(STEP)
    m = generate_mesh(geom; maxh=40.0)
    b = I.GetBox(m)
    @test b isa I.Box3d
    @test I.MaxX(b) > I.MinX(b)
    @test I.MaxY(b) > I.MinY(b)
    @test I.MaxZ(b) > I.MinZ(b)
end

@testset "Mesh GetH / SetGlobalH / SetMinimalH" begin
    geom = load_step(STEP)
    m = generate_mesh(geom; maxh=40.0)
    h = I.GetH(m, I.Point3d(0.0, 0.0, 0.0))
    @test h > 0.0
    I.SetGlobalH(m, 20.0)
    I.SetMinimalH(m, 1.0)
end

@testset "Mesh CalcMinMaxAngle" begin
    geom = load_step(STEP)
    m = generate_mesh(geom; maxh=40.0)
    I.CalcMinMaxAngle(m, 0.1)   # void — runs quality check as side-effect
end

@testset "Mesh GetSurfaceElementsOfFace" begin
    geom = load_step(STEP)
    m = generate_mesh(geom; maxh=40.0)
    nse_total = I.GetNSE(m)
    @test nse_total > 0
    buf = zeros(Int32, nse_total)
    n = I.GetSurfaceElementsOfFace(m, 1, buf)
    @test n > 0
    @test all(buf[1:n] .>= 0)   # SurfaceElementIndex is 0-based
end

@testset "Mesh PureTetMesh / PureTrigMesh" begin
    geom = load_step(STEP)
    m = generate_mesh(geom; maxh=40.0)
    @test I.PureTetMesh(m)
    @test I.PureTrigMesh(m, 1)
end

@testset "Mesh SetDimension / SurfaceMeshOrientation" begin
    geom = load_step(STEP)
    m = generate_mesh(geom; maxh=40.0)
    I.SetDimension(m, 3)
    I.SurfaceMeshOrientation(m)
end
