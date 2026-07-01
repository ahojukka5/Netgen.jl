@testset "I.Segment (1:1)" begin
    s = I.Segment()
    @test I.GetNP(s) == 2
    I.SetIndex(s, 7)
    @test I.GetIndex(s) == 7
end

@testset "I.FaceDescriptor (1:1)" begin
    fd = I.FaceDescriptor()
    I.SetDomainIn(fd, 1)
    I.SetDomainOut(fd, 0)
    I.SetBCProperty(fd, 3)
    @test I.DomainIn(fd) == 1
    @test I.DomainOut(fd) == 0
    @test I.BCProperty(fd) == 3
    I.SetBCName(fd, "wall")
    @test I.GetBCName(fd) == "wall"
end

@testset "I.LocalH (I.new_localh + SetH/GetH)" begin
    pmin = I.Point3d(0.0, 0.0, 0.0)
    pmax = I.Point3d(1.0, 1.0, 1.0)
    lh = I.new_localh(pmin, pmax, 0.3)
    p = I.Point3d(0.5, 0.5, 0.5)
    I.SetH(lh, p, 0.1)
    @test I.GetH(lh, p) <= 0.1 + 1e-10
    hmin = I.GetMinH(lh, pmin, pmax)
    @test hmin > 0.0
end

@testset "MeshTopology connectivity (GetEdgeVertices / GetFaceVertices / GetFaceEdges)" begin
    geom = load_step(STEP)
    m = generate_mesh(geom; maxh=40.0)
    I.UpdateTopology(m)
    t = I.GetTopology(m)
    ne = I.GetNEdges(t)
    @test ne > 0

    buf2 = zeros(Int32, 2)
    I.GetEdgeVertices(t, 1, buf2)
    @test buf2[1] >= 1 && buf2[2] >= 1
    @test buf2[1] != buf2[2]

    nf = I.GetNFaces(t)
    @test nf > 0
    buf4 = zeros(Int32, 4)
    n = I.GetFaceVertices(t, 1, buf4)
    @test n >= 3
    @test all(buf4[1:n] .>= 1)

    buf3 = zeros(Int32, 4)
    ne_face = I.GetFaceEdges(t, 1, buf3)
    @test ne_face >= 3
end

@testset "Additional Mesh methods (AddPoint / CheckVolumeMesh)" begin
    m = I.new_mesh()
    p = I.Point3d(0.0, 0.0, 0.0)
    idx = I.AddPoint(m, p)
    @test I.GetNP(m) >= 1

    geom = load_step(STEP)
    m2 = generate_mesh(geom; maxh=40.0)
    @test I.CheckVolumeMesh(m2) == 0
    @test I.CheckConsistentBoundary(m2) == 0
end
