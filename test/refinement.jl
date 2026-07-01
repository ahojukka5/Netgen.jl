@testset "refine! in place (GetGeometry -> GetRefinement -> Refine)" begin
    geom = load_step(STEP)
    m = generate_mesh(geom; maxh=40.0)
    ne0 = I.GetNE(m)
    refine!(m)
    @test I.GetNE(m) > ne0
end

@testset "marked bisection refinement (mark_for_refinement! + bisect!)" begin
    geom = load_step(STEP)
    m = generate_mesh(geom; maxh=40.0)
    I.UpdateTopology(m)
    ne0 = I.GetNE(m)
    # mark a handful of elements and bisect
    marked = falses(ne0)
    marked[1:max(1, ne0 ÷ 4)] .= true
    mark_for_refinement!(m, marked)
    bisect!(m)
    @test I.GetNE(m) > ne0          # marked refinement grew the mesh
end

@testset "second-order curving (make_second_order!)" begin
    geom = load_step(STEP)
    m = generate_mesh(geom; maxh=40.0)
    np0 = I.GetNP(m)
    make_second_order!(m)
    @test I.GetNP(m) > np0           # edge midpoints added
end

@testset "geometry-aware refinement snaps nodes to the curved surface" begin
    # Unit cylinder (r=1): a node on the lateral surface satisfies √(x²+y²)=1.
    # A linearly-interpolated edge midpoint between two such nodes lies INSIDE
    # (r<1); geometry-aware refinement must project it back onto the surface.
    radius(p) = sqrt(p[1]^2 + p[2]^2)
    geom = load_brep(CYLINDER)
    m = generate_mesh(geom; maxh=0.5)
    np0 = I.GetNP(m); X0 = points(m)
    lateral0 = [j for j in 1:np0 if abs(radius(X0[:, j]) - 1) < 1e-9]
    @test !isempty(lateral0)
    @test maximum(abs(radius(X0[:, j]) - 1) for j in lateral0) < 1e-12  # coarse on surface

    refine!(m)
    np1 = I.GetNP(m); X1 = points(m); P = parent_nodes(m)
    latset = Set(lateral0)
    newlat = [j for j in (np0 + 1):np1 if P[1, j] in latset && P[2, j] in latset]
    @test !isempty(newlat)
    # without projection these would sit at the chord midpoint, strictly inside:
    @test minimum(radius((X1[:, P[1, j]] .+ X1[:, P[2, j]]) ./ 2) for j in newlat) < 0.99
    # with geometry-aware refinement, the actual new nodes are exactly on r=1:
    @test maximum(abs(radius(X1[:, j]) - 1) for j in newlat) < 1e-12

    # and it keeps following the surface through a second refinement
    refine!(m)
    np2 = I.GetNP(m); X2 = points(m)
    lateral2 = [j for j in 1:np2 if abs(radius(X2[:, j]) - 1) < 1e-9]
    @test length(lateral2) > length(lateral0)
    @test maximum(abs(radius(X2[:, j]) - 1) for j in lateral2) < 1e-12
end

@testset "adaptive bisection also snaps to the curved surface" begin
    # The element-wise adaptive path (mark + bisect) is a different Netgen
    # code path than uniform refine; it must project to geometry too.
    radius(p) = sqrt(p[1]^2 + p[2]^2)
    geom = load_brep(CYLINDER)
    m = generate_mesh(geom; maxh=0.5)
    np0 = I.GetNP(m); ne0 = I.GetNE(m); X0 = points(m)
    lateral0 = Set(j for j in 1:np0 if abs(radius(X0[:, j]) - 1) < 1e-9)

    I.UpdateTopology(m)
    T = tetrahedra(m)
    marked = [any(in(lateral0), T[:, e]) for e in 1:ne0]   # error indicator stand-in
    mark_for_refinement!(m, marked)
    bisect!(m)

    np1 = I.GetNP(m); X1 = points(m); P = parent_nodes(m)
    newlat = [j for j in (np0 + 1):np1 if P[1, j] in lateral0 && P[2, j] in lateral0]
    @test !isempty(newlat)
    @test minimum(radius((X1[:, P[1, j]] .+ X1[:, P[2, j]]) ./ 2) for j in newlat) < 0.99
    @test maximum(abs(radius(X1[:, j]) - 1) for j in newlat) < 1e-12
end
