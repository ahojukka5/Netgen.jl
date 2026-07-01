@testset "2D geometry (geom2d/csg2d): circle, refine, hierarchy mapping" begin
    radius(p) = sqrt(p[1]^2 + p[2]^2)
    disk = Circle(0.0, 0.0, 1.0, "disk", "circle")   # unit disk, programmatic
    geo = geometry2d(disk)
    m = generate_mesh(geo; maxh=0.4)
    @test I.GetDimension(m) == 2
    @test I.GetNSE(m) > 0                          # triangles are surface elems in 2D
    np0 = I.GetNP(m); X0 = points(m)
    bnd0 = [j for j in 1:np0 if abs(radius(X0[:, j]) - 1) < 1e-9]
    @test !isempty(bnd0)

    refine!(m)
    np1 = I.GetNP(m); X1 = points(m); P = parent_nodes(m)
    bset = Set(bnd0)
    newb = [j for j in (np0 + 1):np1 if P[1, j] in bset && P[2, j] in bset]
    @test !isempty(newb)
    @test minimum(radius((X1[:, P[1, j]] .+ X1[:, P[2, j]]) ./ 2) for j in newb) < 0.99  # chord inside
    @test maximum(abs(radius(X1[:, j]) - 1) for j in newb) < 1e-12                        # snapped to circle
    # mapping back to coarse level is exact (parents are coarse vertices)
    @test all(0 .<= P .<= np1)
    @test count(j -> P[1, j] == 0 && P[2, j] == 0, 1:np1) == np0
end

@testset "2D boolean CSG (Circle - Rectangle)" begin
    outer = Circle(0.0, 0.0, 1.0, "d", "c")
    notch = Rectangle(-0.2, -1.5, 0.2, 0.0, "n", "r")
    geo = geometry2d(outer - notch)                    # difference
    m = generate_mesh(geo; maxh=0.3)
    @test I.GetNSE(m) > 0
end
