@testset "split_to_tets! (no-op on a pure-tet OCC mesh)" begin
    geom = load_step(STEP)
    m = generate_mesh(geom; maxh=60.0)
    @test pure_tet_mesh(m)
    ne_before = num_cells(m)
    split_to_tets!(m)
    @test num_cells(m) == ne_before
    @test pure_tet_mesh(m)
end

@testset "split_into_parts! (renumbers by connectivity, resets names)" begin
    geom = load_step(STEP)
    m = generate_mesh(geom; maxh=60.0)
    nfd_before = I.GetNFD(m)
    @test nfd_before > 2   # frame.step has many named boundary faces
    regs_before = cell_regions(m)
    @test length(unique(regs_before)) == 1   # single connected solid

    split_into_parts!(m)

    @test I.GetNFD(m) <= nfd_before
    regs_after = cell_regions(m)
    @test length(unique(regs_after)) == 1    # verified: volume stays one part on this fixture
    # boundary/material names collapse to generic placeholders after renumbering
    names_after = unique(values(boundary_names(m)))
    @test all(==("default"), names_after)
end

@testset "merge_mesh_file! (appends points/volume elements from a file)" begin
    geom = load_step(STEP)
    m = generate_mesh(geom; maxh=60.0)
    np_before, ne_before, nse_before, nseg_before =
        num_nodes(m), num_cells(m), I.GetNSE(m), I.GetNSeg(m)

    path = tempname() * ".vol"
    save_mesh(m, path)
    m2 = load_mesh(path)

    @test_throws ArgumentError merge_mesh_file!(m2, path * ".doesnotexist")

    merge_mesh_file!(m2, path)
    rm(path, force=true)

    @test num_nodes(m2) == 2 * np_before
    @test num_cells(m2) == 2 * ne_before
    # Verified surprise (see mesh_surgery.jl docstring): boundary/segment
    # counts were NOT observed to double in this build.
    @test I.GetNSE(m2) == nse_before
    @test I.GetNSeg(m2) == nseg_before
end

@testset "get_sub_mesh (domains/faces are regexes over names, not index ranges)" begin
    geom = load_step(STEP)
    m = generate_mesh(geom; maxh=60.0)
    @test material_names(m) == Dict{Int32,String}(1 => "default")

    full = get_sub_mesh(m, ".*")
    @test num_nodes(full) == num_nodes(m)
    @test num_cells(full) == num_cells(m)
    @test num_boundary_facets(full) == num_boundary_facets(m)

    named = get_sub_mesh(m, "default")
    @test num_cells(named) == num_cells(m)

    # "1" does NOT regex-match the material name "default" -- confirms this
    # is a name-regex grammar, not a "domain index 1" selector.
    empty_by_index = get_sub_mesh(m, "1")
    @test num_cells(empty_by_index) == 0
    @test num_nodes(empty_by_index) == 0

    none = get_sub_mesh(m, "nonexistent-material-name")
    @test num_cells(none) == 0
end

@testset "pure_tet_mesh / pure_trig_mesh (thin wraps)" begin
    geom = load_step(STEP)
    m = generate_mesh(geom; maxh=60.0)
    @test pure_tet_mesh(m) isa Bool
    @test pure_tet_mesh(m)
    @test pure_trig_mesh(m, 1) isa Bool
    @test pure_trig_mesh(m, 1)
    @test pure_trig_mesh(m, 0)   # 0 checks the whole surface mesh
end

@testset "surface_mesh_orientation! (idempotent on an already-consistent mesh)" begin
    geom = load_step(STEP)
    m = generate_mesh(geom; maxh=60.0)
    before = copy(surface_triangles(m))
    surface_mesh_orientation!(m)
    @test surface_triangles(m) == before
end

@testset "NodeTree / node_tree / build_node_tree / nodes_near" begin
    geom = load_step(STEP)
    m = generate_mesh(geom; maxh=60.0)
    P = points(m)

    tree = build_node_tree(m)
    @test tree isa NodeTree
    @test size(tree.points) == size(P)

    tree2 = node_tree(P)
    @test size(tree2.points, 2) == size(P, 2)

    @test_throws ArgumentError node_tree(zeros(4, 3))
    @test_throws ArgumentError node_tree(zeros(3, 0))
    @test_throws ArgumentError nodes_near(tree, P[:, 1], -1.0)

    # Brute-force cross-check on several query points/radii.
    for (col, radius) in ((1, 20.0), (100, 15.0), (size(P, 2), 30.0))
        center = P[:, col]
        brute = Set(i for i in 1:size(P, 2)
                    if sum((P[:, i] .- center) .^ 2) <= radius^2)
        found = Set(nodes_near(tree, center, radius))
        @test found == brute
        @test !isempty(found)   # the query point itself is always within radius
    end
end
