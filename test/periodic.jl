# Periodic boundary condition setup (OCC face identification).
# Requires `using Monge` in runtests.jl (test dependency).

@testset "occ_nr_faces / occ_face_bbox on a unit box" begin
    geom = occ_geometry_from_brep_string(to_brep_string(box(1, 1, 1)))
    @test occ_nr_faces(geom) == 6
    bbox = occ_face_bbox(geom, 1)
    @test bbox isa NamedTuple
    @test_throws ArgumentError occ_face_bbox(geom, 0)
    @test_throws ArgumentError occ_face_bbox(geom, 7)
end

@testset "faces_on_plane finds exactly one face per side of a box" begin
    geom = occ_geometry_from_brep_string(to_brep_string(box(1, 1, 1)))
    @test length(faces_on_plane(geom, :x, 0.0)) == 1
    @test length(faces_on_plane(geom, :x, 1.0)) == 1
    @test isempty(faces_on_plane(geom, :x, 0.5))
    @test_throws ArgumentError faces_on_plane(geom, :w, 0.0)
    @test_throws ArgumentError faces_on_plane(geom, :x, 0.0; atol=0.0)
end

@testset "identify_periodic_box! + generate_mesh: exact node correspondence (x axis)" begin
    geom = occ_geometry_from_brep_string(to_brep_string(box(1, 1, 1)))
    geom = identify_periodic_box!(geom, :x; name="periodic_x")
    m = generate_mesh(geom; maxh=0.3)
    pairs = periodic_vertex_pairs(m, 1)
    @test !isempty(pairs)
    X = points(m)
    for (i, j) in pairs
        @test isapprox(X[:, j] .- X[:, i], [1.0, 0.0, 0.0]; atol=1e-8)
    end
end

@testset "identify_periodic_box! on all 3 axes: distinct, correctly-ordered idnr" begin
    geom = occ_geometry_from_brep_string(to_brep_string(box(1, 1, 1)))
    geom = identify_periodic_box!(geom, :x; name="periodic_x")
    geom = identify_periodic_box!(geom, :y; name="periodic_y")
    geom = identify_periodic_box!(geom, :z; name="periodic_z")
    m = generate_mesh(geom; maxh=0.3)
    X = points(m)
    for (idnr, expected) in ((1, [1.0, 0.0, 0.0]), (2, [0.0, 1.0, 0.0]), (3, [0.0, 0.0, 1.0]))
        pairs = periodic_vertex_pairs(m, idnr)
        @test !isempty(pairs)
        for (i, j) in pairs
            @test isapprox(X[:, j] .- X[:, i], expected; atol=1e-8)
        end
    end
end

@testset "identify_periodic!/identify_periodic_box! error paths" begin
    geom = occ_geometry_from_brep_string(to_brep_string(box(1, 1, 1)))
    @test_throws ArgumentError identify_periodic!(geom, 0, 2, (1.0, 0.0, 0.0))
    @test_throws ArgumentError identify_periodic!(geom, 1, 7, (1.0, 0.0, 0.0))
    # a face paired with itself under a wrong translation should find no match
    @test_throws ArgumentError identify_periodic!(geom, 1, 2, (5.0, 0.0, 0.0))
    @test_throws ArgumentError identify_periodic_box!(geom, :bogus)
end
