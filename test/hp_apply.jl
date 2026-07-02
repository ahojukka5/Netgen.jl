# hp-adaptivity apply API (new CxxWrap bindings + Julia helpers)

@testset "set_element_order! / set_element_orders! (p-refinement apply)" begin
    geom = load_step(STEP)
    m = generate_mesh(geom; maxh=40.0)
    ne = I.GetNE(m)
    @test all(element_orders(m) .== 1)
    set_element_order!(m, 1, 2)
    @test element_orders(m)[1] == 2
    orders = fill(1, ne)
    orders[1:min(5, ne)] .= 3
    set_element_orders!(m, orders)
    @test element_orders(m)[1] == 3
    @test element_order(m) == 3
    ox, oy, oz = element_orders_xyz(m)   # positional destructuring still works
    @test length(ox) == ne
    oxyz = element_orders_xyz(m)
    @test oxyz isa NamedTuple
    @test oxyz.ox == ox && oxyz.oy == oy && oxyz.oz == oz
end

@testset "set_element_orders_xyz! (single-cell anisotropic)" begin
    geom = load_step(STEP)
    m = generate_mesh(geom; maxh=40.0)
    set_element_orders_xyz!(m, 1, 2, 3, 4)
    oxyz = element_orders_xyz(m)
    @test oxyz.ox[1] == 2 && oxyz.oy[1] == 3 && oxyz.oz[1] == 4
    @test_deprecated set_element_orders!(m, 1, 2, 3, 4)
end

@testset "set_surface_element_order! (3D boundary)" begin
    geom = load_step(STEP)
    m = generate_mesh(geom; maxh=40.0)
    nse = I.GetNSE(m)
    set_surface_element_order!(m, 1, 2)
    @test surface_element_orders(m)[1] == 2
    sos = fill(1, nse); sos[1:3] .= 2
    set_surface_element_orders!(m, sos)
    @test all(surface_element_orders(m)[1:3] .== 2)
end

@testset "mark_for_ngx_refinement! + ngx_refine! (marked p-refinement)" begin
    geom = load_step(STEP)
    m = generate_mesh(geom; maxh=40.0)
    ne = I.GetNE(m)
    I.UpdateTopology(m)
    marked = falses(ne)
    marked[1:max(1, ne ÷ 10)] .= true
    mark_for_ngx_refinement!(m, marked)
    ngx_refine!(m; reftype=NG_REFINE_P, onlyonce=true)
    @test element_order(m) >= 2
end

@testset "hp_refine! and split_alfeld! (global hp drivers)" begin
    geom = load_step(STEP)
    m = generate_mesh(geom; maxh=40.0)
    @test all(hp_element_levels(m) .== -1)
    hp_refine!(m; levels=1)
    L = hp_element_levels(m)
    @test size(L) == (3, I.GetNE(m))
    @test any(!=(-1), L)                         # hp table populated
    m2 = generate_mesh(geom; maxh=40.0)
    ne0 = I.GetNE(m2)
    split_alfeld!(m2)
    @test I.GetNE(m2) >= ne0
end

@testset "cluster representative helpers (require hp mesh)" begin
    geom = load_step(STEP)
    m = generate_mesh(geom; maxh=40.0)
    @test !hp_clusters_available(m)
    @test_throws ArgumentError cluster_rep_vertices(m)
    @test_throws ArgumentError cluster_rep_elements(m)
    @test_throws ArgumentError cluster_rep_edge(m, 1)
    @test_throws ArgumentError cluster_rep_face(m, 1)
    hp_refine!(m; levels=1)
    @test hp_clusters_available(m)
    crv = cluster_rep_vertices(m)
    @test length(crv) == I.GetNP(m)
    cre = cluster_rep_elements(m)
    @test length(cre) == I.GetNE(m)
end

@testset "hp.jl ArgumentError branches: length checks, dimension guards, bad reftype" begin
    geom = load_step(STEP)
    m = generate_mesh(geom; maxh=40.0)
    ne = I.GetNE(m)

    # set_element_orders!(mesh, orders): wrong length
    @test_throws ArgumentError set_element_orders!(m, fill(1, ne + 1))

    # set_surface_element_order!/orders! are 3D-only -> ArgumentError on a 2D mesh
    disk = Circle(0.0, 0.0, 1.0, "disk", "circle")
    m2 = generate_mesh(geometry2d(disk); maxh=0.4)
    @test_throws ArgumentError set_surface_element_order!(m2, 1, 2)
    @test_throws ArgumentError set_surface_element_orders!(m2, 1, 2, 2)
    @test_throws ArgumentError set_surface_element_orders!(m2, [1, 2])

    # set_surface_element_orders!(mesh, orders): wrong length (3D mesh)
    nse = I.GetNSE(m)
    @test_throws ArgumentError set_surface_element_orders!(m, fill(1, nse + 1))

    # mark_for_ngx_refinement!: wrong length
    @test_throws ArgumentError mark_for_ngx_refinement!(m, falses(ne + 1))

    # ngx_refine!: reftype must be NG_REFINE_H/P/HP
    @test_throws ArgumentError ngx_refine!(m; reftype=999)
end

@testset "session hp apply (in-place, generation tracking)" begin
    geom = load_step(STEP)
    s = mesh_session(geom; maxh=40.0)
    ne = I.GetNE(finest(s))
    g0 = generation(s)
    @test nlevels(s) == 1

    request_set_element_orders!(s, fill(2, ne))
    @test generation(s) == g0 + 1
    @test all(element_orders(finest(s)) .== 2)
    @test nlevels(s) == 1                       # in place, no new level

    g1 = generation(s)
    marked = falses(ne); marked[1:max(1, ne ÷ 10)] .= true
    request_marked_p_refinement!(s, marked; onlyonce=true)
    @test generation(s) == g1 + 1
    @test nlevels(s) == 1

    g2 = generation(s)
    request_hp_refine!(s; levels=1)
    @test generation(s) == g2 + 1
    @test any(!=(-1), hp_element_levels(finest(s)))

    g3 = generation(s)
    request_split_alfeld!(s)
    @test generation(s) == g3 + 1
end

@testset "request_marked_refinement! with refine_hp appends hp-refined level" begin
    geom = load_step(STEP)
    s = mesh_session(geom; maxh=40.0)
    ne = I.GetNE(finest(s))
    marked = falses(ne); marked[1:max(1, ne ÷ 5)] .= true
    request_marked_refinement!(s, marked; refine_hp=true)
    @test nlevels(s) == 2
    @test I.GetNE(finest(s)) > ne
end

@testset "2D set_element_orders! on disk mesh" begin
    disk = Circle(0.0, 0.0, 1.0, "disk", "circle")
    m = generate_mesh(geometry2d(disk); maxh=0.4)
    nse = I.GetNSE(m)
    set_element_orders!(m, fill(2, nse))
    @test all(element_orders(m) .== 2)
end
