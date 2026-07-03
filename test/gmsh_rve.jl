# DeloneGmshExt RVE-parity features: entity discovery, region/boundary
# tagging, local sizing fields, periodic BCs. Guarded exactly like
# test/gmsh_backend.jl -- only exercised when Gmsh is actually installed.

# Two genuinely distinct OCC solids in one BREP, for region-tagging tests
# that need per-solid element differentiation (not achievable with a single
# solid). Built via the low-level OCC.TopoDS_Compound/BRep_Builder API since
# Monge has no high-level `compound(...)` constructor yet.
function _two_solid_brep()
    b1 = box(1.0, 1.0, 1.0)
    b2 = box(Point(3.0, 3.0, 3.0), Point(3.5, 3.5, 3.5))
    builder = Monge.OCC.BRep_Builder()
    comp = Monge.OCC.TopoDS_Compound()
    Monge.OCC.MakeCompound(builder, comp)
    Monge.OCC.Add(builder, comp, Monge.occt(b1))
    Monge.OCC.Add(builder, comp, Monge.occt(b2))
    return to_brep_string(Monge._body(comp))
end

@testset "DeloneGmshExt RVE parity (Gmsh backend)" begin
    if Base.find_package("Gmsh") === nothing
        @info "Gmsh not installed; skipping DeloneGmshExt RVE-parity verification"
        @test_throws ArgumentError gmsh_geometry_info("dummy.step")
    else
        @eval using Gmsh

        @testset "gmsh_geometry_info + faces_on_plane(faces, axis, value)" begin
            path = tempname() * ".brep"
            write(path, to_brep_string(box(1.0, 1.0, 1.0)))
            info = gmsh_geometry_info(path)
            @test length(info.faces) == 6
            @test length(info.solids) == 1
            @test isapprox(collect((info.bounding_box.xmin, info.bounding_box.ymin, info.bounding_box.zmin)),
                           [0.0, 0.0, 0.0]; atol=1e-6)

            lo = faces_on_plane(info.faces, :x, 0.0)
            hi = faces_on_plane(info.faces, :x, 1.0)
            @test length(lo) == 1
            @test length(hi) == 1
            @test lo != hi
            @test isempty(faces_on_plane(info.faces, :x, 0.5))

            @test_throws ArgumentError faces_on_plane(info.faces, :w, 0.0)
            @test_throws ArgumentError faces_on_plane(info.faces, :x, 0.0; atol=0.0)
        end

        @testset "generate_gmsh_mesh: regions=/boundary_names= tagging" begin
            path = tempname() * ".brep"
            write(path, _two_solid_brep())
            info = gmsh_geometry_info(path)
            tags = sort([s.tag for s in info.solids])
            @test length(tags) == 2

            s = generate_gmsh_mesh(path; maxh=0.3,
                                    regions=Dict("matrix" => tags[1], "inclusion" => tags[2]))
            @test length(unique(s.cell_regions)) == 2
            @test Set(values(s.material_names)) == Set(["matrix", "inclusion"])
            @test all(1 .<= s.cell_regions .<= maximum(keys(s.material_names)))

            lo = faces_on_plane(info.faces, :x, 0.0)
            hi = faces_on_plane(info.faces, :x, 1.0)
            s2 = generate_gmsh_mesh(path; maxh=0.3,
                                     boundary_names=Dict("lo" => lo, "hi" => hi))
            @test Set(values(s2.boundary_names)) == Set(["lo", "hi"])
            @test 0 in s2.boundary_regions  # untagged faces default to 0

            # backward compatibility: no regions/boundary_names -> today's placeholders
            s3 = generate_gmsh_mesh(path; maxh=0.3)
            @test all(==(1), s3.cell_regions)
            @test all(==(0), s3.boundary_regions)
            @test isempty(s3.material_names)
            @test isempty(s3.boundary_names)

            @test_throws ArgumentError generate_gmsh_mesh(path; maxh=0.3, regions=Dict("bad" => 9999))
            @test_throws ArgumentError generate_gmsh_mesh(
                path; maxh=0.3, regions=Dict("a" => tags[1], "b" => tags[1]))
        end

        @testset "generate_gmsh_mesh: refine_near= local sizing fields" begin
            path = tempname() * ".brep"
            write(path, to_brep_string(box(1.0, 1.0, 1.0)))
            info = gmsh_geometry_info(path)
            hi_face = faces_on_plane(info.faces, :x, 1.0)

            s_uniform = generate_gmsh_mesh(path; maxh=0.3)
            s = generate_gmsh_mesh(path; maxh=0.3,
                refine_near=[(faces=hi_face, hmin=0.05, hmax=0.3, distmin=0.05, distmax=0.3)])
            @test size(s.volume_connectivity, 2) > size(s_uniform.volume_connectivity, 2)

            # point= entries must not leak an unreferenced node into the snapshot
            s_pt = generate_gmsh_mesh(path; maxh=0.3,
                refine_near=[(point=(0.5, 0.5, 0.5), hmin=0.05, hmax=0.3, distmin=0.05, distmax=0.3)])
            n = size(s_pt.coordinates, 2)
            referenced = falses(n)
            for j in 1:size(s_pt.volume_connectivity, 2), i in 1:4
                referenced[s_pt.volume_connectivity[i, j]] = true
            end
            for j in 1:size(s_pt.surface_connectivity, 2), i in 1:3
                referenced[s_pt.surface_connectivity[i, j]] = true
            end
            @test all(referenced)

            @test_throws ArgumentError generate_gmsh_mesh(
                path; maxh=0.3, refine_near=[(faces=hi_face, curves=[1],
                    hmin=0.05, hmax=0.3, distmin=0.05, distmax=0.3)])
            @test_throws ArgumentError generate_gmsh_mesh(
                path; maxh=0.3, refine_near=[(faces=hi_face,
                    hmin=-1.0, hmax=0.3, distmin=0.05, distmax=0.3)])
            @test_throws ArgumentError generate_gmsh_mesh(
                path; maxh=0.3, refine_near=[(faces=[9999],
                    hmin=0.05, hmax=0.3, distmin=0.05, distmax=0.3)])
        end

        @testset "generate_gmsh_mesh: periodic_box= (exact node correspondence)" begin
            path = tempname() * ".brep"
            write(path, to_brep_string(box(1.0, 1.0, 1.0)))

            res = generate_gmsh_mesh(path; maxh=0.3, periodic_box=:x, result=true)
            @test res isa GmshMeshGenerationResult
            @test length(res.periodic_groups) == 1
            g = res.periodic_groups[1]
            @test g.translation == (1.0, 0.0, 0.0)
            @test !isempty(g.vertex_pairs)
            X = res.snapshot.coordinates
            for (i, j) in g.vertex_pairs
                @test isapprox(X[:, j] .- X[:, i], [1.0, 0.0, 0.0]; atol=1e-8)
            end

            # all 3 axes at once
            res3 = generate_gmsh_mesh(path; maxh=0.3, periodic_box=[:x, :y, :z], result=true)
            @test length(res3.periodic_groups) == 3
            X3 = res3.snapshot.coordinates
            expected = Dict("periodic_x" => [1.0, 0.0, 0.0], "periodic_y" => [0.0, 1.0, 0.0],
                             "periodic_z" => [0.0, 0.0, 1.0])
            for g3 in res3.periodic_groups
                for (i, j) in g3.vertex_pairs
                    @test isapprox(X3[:, j] .- X3[:, i], expected[g3.name]; atol=1e-8)
                end
            end

            # result=false: periodicity still applied to the mesh, just no readback
            s = generate_gmsh_mesh(path; maxh=0.3, periodic_box=:x)
            @test s isa MeshLevelSnapshot{3,Float64,Int32}

            @test_throws ArgumentError generate_gmsh_mesh(path; maxh=0.3, periodic_box=:w)
        end

        @testset "generate_gmsh_mesh: periodic= explicit entries" begin
            path = tempname() * ".brep"
            write(path, to_brep_string(box(1.0, 1.0, 1.0)))
            info = gmsh_geometry_info(path)
            lo = faces_on_plane(info.faces, :y, 0.0)
            hi = faces_on_plane(info.faces, :y, 1.0)

            res = generate_gmsh_mesh(path; maxh=0.3,
                periodic=[(lo=lo, hi=hi, translation=(0.0, 1.0, 0.0), name="periodic_y")],
                result=true)
            g = res.periodic_groups[1]
            @test g.name == "periodic_y"
            X = res.snapshot.coordinates
            for (i, j) in g.vertex_pairs
                @test isapprox(X[:, j] .- X[:, i], [0.0, 1.0, 0.0]; atol=1e-8)
            end

            @test_throws ArgumentError generate_gmsh_mesh(
                path; maxh=0.3, periodic=[(lo=lo, hi=[hi[1], hi[1]], translation=(0.0, 1.0, 0.0))])
            @test_throws ArgumentError generate_gmsh_mesh(
                path; maxh=0.3, periodic=[(lo=[9999], hi=hi, translation=(0.0, 1.0, 0.0))])
        end

        @testset "generate_gmsh_mesh: periodic_box= rejects a fragmented periodic face" begin
            # Mirrors test/periodic.jl's fragmented-box fixture: unlike the
            # Netgen backend (multi-fragment matching added earlier), Gmsh's
            # position-paired setPeriodic can't safely disambiguate fragments.
            matrix = box(1.0, 1.0, 1.0)
            notch_lo = box(Point(-0.1, 0.4, 0.0), Point(0.15, 0.6, 1.0))
            notch_hi = box(Point(0.85, 0.4, 0.0), Point(1.1, 0.6, 1.0))
            frag = subtract(subtract(matrix, notch_lo), notch_hi)
            path = tempname() * ".brep"
            write(path, to_brep_string(frag))
            @test_throws ArgumentError generate_gmsh_mesh(path; maxh=0.15, periodic_box=:x)
        end
    end
end
