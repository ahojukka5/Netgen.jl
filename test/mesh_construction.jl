# mesh_from_arrays: building a mesh from plain point/connectivity arrays,
# the inverse of points/tetrahedra/surface_triangles/cell_regions/boundary_regions.
# See src/mesh_construction.jl for the reverse-engineered `.vol` grammar and
# why direct Netgen.Element construction is not viable.

@testset "mesh_from_arrays: hand-built single tetrahedron" begin
    P = [0.0 1.0 0.0 0.0;
         0.0 0.0 1.0 0.0;
         0.0 0.0 0.0 1.0]
    T = reshape([1, 2, 3, 4], 4, 1)
    S = [1 1 1 2;
         2 2 3 3;
         3 4 4 4]

    m = mesh_from_arrays(P, T; surface=S, boundary_regions=[1, 2, 3, 4])
    @test num_nodes(m) == 4
    @test num_cells(m) == 1
    @test num_boundary_facets(m) == 4
    @test points(m) ≈ P
    @test tetrahedra(m) == Int32.(T)
    @test surface_triangles(m) == Int32.(S)
    @test cell_regions(m) == Int32[1]
    @test boundary_regions(m) == Int32[1, 2, 3, 4]
    @test I.GetNDomains(m) == 1

    # boundary_regions defaults to 1 for every triangle when omitted
    m0 = mesh_from_arrays(P, T; surface=S)
    @test boundary_regions(m0) == Int32[1, 1, 1, 1]
end

@testset "mesh_from_arrays: no surface -> volume-only mesh" begin
    P = [0.0 1.0 0.0 0.0;
         0.0 0.0 1.0 0.0;
         0.0 0.0 0.0 1.0]
    T = reshape([1, 2, 3, 4], 4, 1)

    m = mesh_from_arrays(P, T)
    @test num_nodes(m) == 4
    @test num_cells(m) == 1
    @test num_boundary_facets(m) == 0
end

@testset "mesh_from_arrays: cell_regions / boundary_regions / naming" begin
    P = [0.0 1.0 0.0 0.0;
         0.0 0.0 1.0 0.0;
         0.0 0.0 0.0 1.0]
    T = reshape([1, 2, 3, 4], 4, 1)
    S = [1 1 1 2;
         2 2 3 3;
         3 4 4 4]

    m = mesh_from_arrays(P, T; surface=S, boundary_regions=[10, 20, 30, 40])
    @test boundary_regions(m) == Int32[10, 20, 30, 40]

    m2 = mesh_from_arrays(P, T; surface=S, boundary_regions=[1, 2, 3, 4],
        material_names=Dict(1 => "steel"),
        boundary_names=Dict(1 => "inlet", 2 => "outlet", 3 => "wall", 4 => "sym"))
    @test material_names(m2) == Dict{Int32,String}(1 => "steel")
    @test boundary_names(m2) == Dict{Int32,String}(1 => "inlet", 2 => "outlet", 3 => "wall", 4 => "sym")
end

@testset "mesh_from_arrays: validation" begin
    P = [0.0 1.0 0.0 0.0;
         0.0 0.0 1.0 0.0;
         0.0 0.0 0.0 1.0]
    T = reshape([1, 2, 3, 4], 4, 1)
    S = [1 1 1 2;
         2 2 3 3;
         3 4 4 4]

    @test_throws ArgumentError mesh_from_arrays(P[1:2, :], T)               # points not 3×np
    @test_throws ArgumentError mesh_from_arrays(P, T[1:3, :])               # tets not 4×ne
    @test_throws ArgumentError mesh_from_arrays(P, reshape([1, 2, 3, 5], 4, 1))  # index out of range
    @test_throws ArgumentError mesh_from_arrays(P, reshape([0, 2, 3, 4], 4, 1))  # non-1-based index
    @test_throws ArgumentError mesh_from_arrays(P, T; cell_regions=[1, 2])       # length mismatch
    @test_throws ArgumentError mesh_from_arrays(P, T; surface=S, boundary_regions=[1, 2])  # length mismatch
    @test_throws ArgumentError mesh_from_arrays(P, T; boundary_regions=[1, 2, 3, 4])       # no surface
    @test_throws ArgumentError mesh_from_arrays(P, T; surface=S[1:2, :])         # surface not 3×nse
end

@testset "mesh_from_arrays: real round-trip via frame.step" begin
    geom = load_step(STEP)
    m = generate_mesh(geom; maxh=40.0)

    P = points(m)
    T = tetrahedra(m)
    S = surface_triangles(m)
    cr = cell_regions(m)
    br = boundary_regions(m)
    matnames = material_names(m)

    m2 = mesh_from_arrays(P, T; surface=S, cell_regions=Int.(cr), boundary_regions=Int.(br))

    @test num_nodes(m2) == num_nodes(m)
    @test num_cells(m2) == num_cells(m)
    @test num_boundary_facets(m2) == num_boundary_facets(m)
    @test points(m2) ≈ P
    @test tetrahedra(m2) == T
    @test surface_triangles(m2) == S
    @test cell_regions(m2) == cr
    @test boundary_regions(m2) == br
    @test I.GetNDomains(m2) == I.GetNDomains(m)
    @test I.GetNFD(m2) == I.GetNFD(m)

    # spot-check a random sample of tet connectivity rows byte-for-byte
    T2 = tetrahedra(m2)
    idxs = rand(1:size(T, 2), min(20, size(T, 2)))
    @test all(T[:, i] == T2[:, i] for i in idxs)

    if !isempty(matnames)
        m3 = mesh_from_arrays(P, T; surface=S, cell_regions=Int.(cr), boundary_regions=Int.(br),
            material_names=matnames)
        @test material_names(m3) == matnames
    end
end

@testset "add_volume_element! on a bare mesh (no pre-existing face descriptors needed)" begin
    m = I.new_mesh()
    p1 = I.AddPoint(m, I.Point3d(0.0, 0.0, 0.0))
    p2 = I.AddPoint(m, I.Point3d(1.0, 0.0, 0.0))
    p3 = I.AddPoint(m, I.Point3d(0.0, 1.0, 0.0))
    p4 = I.AddPoint(m, I.Point3d(0.0, 0.0, 1.0))
    @test num_nodes(m) == 4
    @test num_cells(m) == 0

    add_volume_element!(m, (p1, p2, p3, p4); region=1)
    @test num_cells(m) == 1
    @test sort(tetrahedra(m)[:, 1]) == [p1, p2, p3, p4]
    @test cell_regions(m)[1] == 1

    # error paths: wrong arity, out-of-range point id, region < 1
    @test_throws ArgumentError add_volume_element!(m, (p1, p2, p3); region=1)
    @test_throws ArgumentError add_volume_element!(m, (p1, p2, p3, 999); region=1)
    @test_throws ArgumentError add_volume_element!(m, (p1, p2, p3, p4); region=0)

    # returns the mesh, per the `!`-function convention
    @test add_volume_element!(m, (p1, p2, p3, p4); region=1) === m
end

@testset "add_surface_element! requires a pre-existing face descriptor" begin
    # A mesh with zero face descriptors: region=1 must be rejected with a
    # clean ArgumentError, NOT passed through to Netgen.AddSurfaceElement
    # (which segfaults on an unknown face-descriptor index -- see the
    # docstring's warning; this is the regression test for that).
    bare = I.new_mesh()
    p1 = I.AddPoint(bare, I.Point3d(0.0, 0.0, 0.0))
    p2 = I.AddPoint(bare, I.Point3d(1.0, 0.0, 0.0))
    p3 = I.AddPoint(bare, I.Point3d(0.0, 1.0, 0.0))
    @test I.GetNFD(bare) == 0
    @test_throws ArgumentError add_surface_element!(bare, (p1, p2, p3); region=1)

    # A mesh built via mesh_from_arrays already has real face descriptors --
    # add_surface_element! onto an existing, valid region works normally.
    P = [0.0 1.0 0.0 0.0; 0.0 0.0 1.0 0.0; 0.0 0.0 0.0 1.0]
    T = reshape([1, 2, 3, 4], 4, 1)
    S = reshape([1, 2, 3], 3, 1)
    m = mesh_from_arrays(P, T; surface=S, cell_regions=[1], boundary_regions=[1])
    @test I.GetNFD(m) >= 1
    nse_before = num_boundary_facets(m)

    add_surface_element!(m, (1, 3, 4); region=1)
    @test num_boundary_facets(m) == nse_before + 1
    @test sort(surface_triangles(m)[:, end]) == [1, 3, 4]

    @test_throws ArgumentError add_surface_element!(m, (1, 2); region=1)
    @test_throws ArgumentError add_surface_element!(m, (1, 2, 999); region=1)
    @test_throws ArgumentError add_surface_element!(m, (1, 2, 3); region=0)
    @test_throws ArgumentError add_surface_element!(m, (1, 2, 3); region=I.GetNFD(m) + 1)

    # returns the mesh, per the `!`-function convention
    @test add_surface_element!(m, (1, 3, 4); region=1) === m
end
