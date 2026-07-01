# BREP string interop: Monge (OCCT) shape → Netgen meshable geometry.
# Requires `using Monge` in runtests.jl (test dependency).

@testset "BREP round-trip (to_brep_string / from_brep_string)" begin
    shape = box(1, 1, 1)
    brep = to_brep_string(shape)
    @test brep isa String
    @test !isempty(brep)
    shape2 = from_brep_string(brep)
    @test !is_empty(shape2)
end

@testset "occ_geometry_from_brep_string meshes a box" begin
    geom = occ_geometry_from_brep_string(to_brep_string(box(1, 1, 1)))
    m = generate_mesh(geom; maxh=0.5)
    @test I.GetNP(m) > 0
    @test I.GetNE(m) > 0
end

@testset "BREP bridge mesh counts stable under shape round-trip" begin
    brep = to_brep_string(sphere(1.0))
    m1 = generate_mesh(occ_geometry_from_brep_string(brep); maxh=0.5)
    m2 = generate_mesh(
        occ_geometry_from_brep_string(to_brep_string(from_brep_string(brep))); maxh=0.5)
    @test I.GetNP(m1) == I.GetNP(m2)
    @test I.GetNE(m1) == I.GetNE(m2)
end

@testset "BREP bridge sphere refines onto the curved surface (r=1)" begin
    radius(p) = sqrt(p[1]^2 + p[2]^2 + p[3]^2)
    geom = occ_geometry_from_brep_string(to_brep_string(sphere(1.0)))
    m = generate_mesh(geom; maxh=0.5)
    bverts() = unique(vec(surface_triangles(m)))
    X = points(m)
    @test maximum(abs(radius(X[:, j]) - 1) for j in bverts()) < 1e-12
    np0 = I.GetNP(m)
    refine!(m)
    X = points(m)
    @test I.GetNP(m) > np0
    @test maximum(abs(radius(X[:, j]) - 1) for j in bverts()) < 1e-12
end
