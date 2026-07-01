const STL_TET = joinpath(@__DIR__, "fixtures", "tet.stl")

@testset "I.STLParameters (1:1 fields)" begin
    p = I.STLParameters()
    v0 = I.yangle(p)
    @test v0 > 0.0
    I.yangle!(p, 30.0)
    @test I.yangle(p) ≈ 30.0
    I.contyangle!(p, 20.0)
    @test I.contyangle(p) ≈ 20.0
end

@testset "I.STLGeometry (I.LoadSTL / GetNT / GetNP)" begin
    stl = load_stl(STL_TET)
    @test I.GetNT(stl) == 4
    @test I.GetNP(stl) == 4
end
