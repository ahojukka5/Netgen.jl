@testset "multigrid hierarchy (Ngx_Mesh levels + parent maps)" begin
    geom = load_step(STEP)
    m = generate_mesh(geom; maxh=40.0)
    np0 = I.GetNP(m)
    refine!(m)                            # uniform; populates the hierarchy
    @test num_levels(m) >= 2
    @test level_nvertices(m, 0) == np0    # level 0 == pre-refinement count
    P = parent_nodes(m)
    @test size(P) == (2, I.GetNP(m))
    @test all(0 .<= P .<= I.GetNP(m))
    # the newly added (fine) vertices must have two real parents
    nnew = count(j -> P[1, j] != 0 && P[2, j] != 0, 1:I.GetNP(m))
    @test nnew > 0
    # original coarse vertices carry no parents
    @test count(j -> P[1, j] == 0 && P[2, j] == 0, 1:I.GetNP(m)) >= np0
    PE = parent_elements(m)
    @test length(PE) == I.GetNE(m)
end

@testset "copy_mesh is an independent deep copy" begin
    geom = load_step(STEP)
    m = generate_mesh(geom; maxh=40.0)
    np = I.GetNP(m); ne = I.GetNE(m)
    c = copy_mesh(m)
    @test I.GetNP(c) == np
    @test I.GetNE(c) == ne
    @test I.GetDimension(c) == 3
    refine!(c)                            # refining the copy...
    @test I.GetNE(c) > ne
    @test I.GetNE(m) == ne           # ...leaves the original untouched
end

@testset "uniform_hierarchy builds nested GMG levels" begin
    geom = load_step(STEP)
    h = uniform_hierarchy(geom; maxh=40.0, levels=3)
    @test nlevels(h) == 3
    np = [I.GetNP(h[k]) for k in 1:3]
    @test np[1] < np[2] < np[3]           # strictly refining
    # nestedness: coarse vertices keep their coordinates in the finer level
    Xc = points(coarsest(h)); X1 = points(h[2])
    @test Xc ≈ X1[:, 1:size(Xc, 2)]
    # per-level prolongation stencil maps fine vertices to coarse parents
    P = prolongation(h, 2)
    @test size(P) == (2, np[2])
    @test all(0 .<= P .<= np[1])          # parents live on the coarser level
    @test count(j -> P[1, j] == 0 && P[2, j] == 0, 1:np[2]) == np[1]
    @test_throws ArgumentError prolongation(h, 1)
end

@testset "adaptive: grow hierarchy mid-simulation via refine_marked!" begin
    geom = load_step(STEP)
    h = mesh_hierarchy(geom; maxh=40.0)
    @test nlevels(h) == 1
    # mimic an error indicator: mark a spatial subset of the finest mesh
    m = finest(h); ne = I.GetNE(m)
    X = points(m); T = tetrahedra(m)
    cx = [sum(X[1, T[:, e]]) / 4 for e in 1:ne]
    marked = cx .< sort(cx)[ne ÷ 3]
    refine_marked!(h, marked)
    @test nlevels(h) == 2
    @test I.GetNE(finest(h)) > ne
    # the mapping is exact for adaptive refinement too
    np1 = I.GetNP(h[1]); np2 = I.GetNP(h[2])
    P = prolongation(h, 2)
    @test all(0 .<= P .<= np1)
    @test count(j -> P[1, j] == 0 && P[2, j] == 0, 1:np2) == np1
    # geometry is shared and carried across levels
    @test geometry(h) === geom
    # can keep refining further toward a 4-5 level hierarchy
    m2 = finest(h); ne2 = I.GetNE(m2)
    refine_marked!(h, trues(ne2))   # mark all => uniform-like bisection
    @test nlevels(h) == 3
    @test I.GetNE(finest(h)) > ne2
end
