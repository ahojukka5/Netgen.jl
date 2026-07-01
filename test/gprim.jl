@testset "I.Box3d (constructor / PMin / PMax)" begin
    pmin = I.Point3d(1.0, 2.0, 3.0)
    pmax = I.Point3d(4.0, 5.0, 6.0)
    b = I.Box3d(pmin, pmax)
    bmin = I.PMin(b)
    bmax = I.PMax(b)
    @test I.MinX(b) ≈ 1.0
    @test I.MaxZ(b) ≈ 6.0
    @test I.IsIn(b, I.Point3d(2.0, 3.0, 4.0)) != 0
    @test I.IsIn(b, I.Point3d(10.0, 10.0, 10.0)) == 0
end

@testset "I.Point3dTree (I.new_point3dtree / Insert / GetIntersecting)" begin
    pmin = I.Point3d(0.0, 0.0, 0.0)
    pmax = I.Point3d(10.0, 10.0, 10.0)
    tree = I.new_point3dtree(pmin, pmax)
    I.Insert(tree, I.Point3d(1.0, 1.0, 1.0), 42)
    I.Insert(tree, I.Point3d(9.0, 9.0, 9.0), 99)
    hits = I.GetIntersecting(tree,
                                  I.Point3d(0.5, 0.5, 0.5),
                                  I.Point3d(2.0, 2.0, 2.0))
    @test 42 in hits
    @test !(99 in hits)
end
