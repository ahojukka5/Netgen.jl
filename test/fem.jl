# FEM geometry: curved maps, parent topology, codim names, partition hints.

@testset "volume_element_transformation after second-order curving" begin
    geom = load_step(STEP)
    m = generate_mesh(geom; maxh=40.0)
    make_second_order!(m)
    x, J = volume_element_transformation(m, 1, [0.0, 0.0, 0.0])
    @test length(x) == 3
    @test all(isfinite, x)
    @test size(J) == (3, 3)
    @test all(isfinite, J)
    X, Js = volume_element_transformations(m, 1, [0.0 0.5; 0.0 0.0; 0.0 0.0])
    @test size(X) == (3, 2)
    @test length(Js) == 2
    @test all(size(J) == (3, 3) for J in Js)
end

@testset "surface_element_transformation (3D boundary)" begin
    geom = load_step(STEP)
    m = generate_mesh(geom; maxh=40.0)
    make_second_order!(m)
    x, J = surface_element_transformation(m, 1, [0.0, 0.0])
    @test length(x) == 3
    @test size(J) == (3, 2)
end

@testset "parent edge/face maps (EnableTopologyTable + refine)" begin
    geom = load_step(STEP)
    m = generate_mesh(geom; maxh=40.0)
    @test !has_parent_edges(m)
    enable_topology_table!(m, "parentedges")
    enable_topology_table!(m, "parentfaces")
    refine!(m)
    I.UpdateTopology(m)
    @test has_parent_edges(m)
    info, e1, e2, e3 = parent_edges(m, 1)
    @test info isa Int && e1 isa Int && e2 isa Int && e3 isa Int
    finfo, f1, f2, f3, f4 = parent_faces(m, 1)
    @test finfo isa Int && f1 isa Int
    edges = face_edges(m, 1)
    @test !isempty(edges)
    @test all(e -> e >= 0, edges)
end

@testset "material_codim_name matches bulk dictionaries (3D)" begin
    geom = load_step(STEP)
    m = generate_mesh(geom; maxh=40.0)
    mats = material_names(m)
    cr = cell_regions(m)
    @test material_codim_name(m, 0, cr[1]) == mats[cr[1]]
    bnames = boundary_names(m)
    br = boundary_regions(m)
    @test material_codim_name(m, 1, br[1]) == bnames[br[1]]
end

@testset "periodic_vertex_pairs on mesh without identifications" begin
    geom = load_step(STEP)
    m = generate_mesh(geom; maxh=40.0)
    @test periodic_vertex_pairs(m) == Tuple{Int,Int}[]
end

@testset "find_element locates a 3D tet centroid" begin
    geom = load_step(STEP)
    m = generate_mesh(geom; maxh=40.0)
    T = tetrahedra(m)
    X = points(m)
    cen = vec(sum(X[:, T[:, 1]], dims=2) ./ 4)
    hit = find_element(m, cen)
    @test hit !== nothing
    el, lami = hit
    @test el isa Int && el >= 1 && el <= I.GetNE(m)
    @test length(lami) == 4
    # centroid of a linear tet: all barycentric weights positive
    @test all(lami .> -1e-6)
end

@testset "find_element locates a 2D triangle centroid" begin
    disk = Circle(0.0, 0.0, 1.0, "disk", "circle")
    m = generate_mesh(geometry2d(disk); maxh=0.4)
    T = triangles2d(m)
    X = points(m)
    cen = vec(sum(X[:, T[:, 1]], dims=2) ./ 3)
    hit = find_element(m, cen[1:2])
    @test hit !== nothing
    el, lami = hit
    @test 1 <= el <= I.GetNSE(m)
    @test length(lami) == 2
end

@testset "find_element returns nothing outside the mesh" begin
    disk = Circle(0.0, 0.0, 1.0, "disk", "circle")
    m = generate_mesh(geometry2d(disk); maxh=0.4)
    @test find_element(m, [10.0, 10.0]) === nothing
end

@testset "mesh_h_at_point matches GetH at the node coordinates" begin
    geom = load_step(STEP)
    m = generate_mesh(geom; maxh=40.0)
    X = points(m)
    h_idx = mesh_h_at_point(m, 1)
    h_pt = I.GetH(m, I.Point3d(X[1, 1], X[2, 1], X[3, 1]))
    @test h_idx > 0
    @test isapprox(h_idx, h_pt; rtol=1e-12)
end

@testset "domain_element_transformation (2D)" begin
    disk = Circle(0.0, 0.0, 1.0, "disk", "circle")
    m = generate_mesh(geometry2d(disk); maxh=0.4)
    make_second_order!(m)
    x, J = domain_element_transformation(m, 1, [0.0, 0.0])
    @test length(x) == 2
    @test size(J) == (2, 2)
    segnr = 1
    xs, Js = segment_element_transformation(m, segnr, [0.0])
    @test length(xs) == 2
    @test length(Js) == 2
    @test region_name_segment(m, segnr) isa String
end
