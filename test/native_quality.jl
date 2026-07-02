@testset "native_quality(mesh) -> NativeQualityReport (3D)" begin
    geom = load_step(STEP)
    m = generate_mesh(geom; maxh=40.0)
    nq = Delone.native_quality(m)

    # Netgen's own CalcTetBadness is normalized so a perfect (equilateral)
    # tet scores 1.0; every element badness must be >= that.
    @test nq.min_element_badness >= 1.0 - 1e-6
    @test nq.max_element_badness >= nq.min_element_badness
    @test nq.mean_element_badness >= nq.min_element_badness
    @test nq.total_bad > 0
    @test nq.volume_mesh_ok isa Bool
    @test nq.boundary_ok isa Bool
    @test nq.overlapping_boundary isa Bool
    @test isempty(nq.warnings)

    # Sanity-checked against Netgen directly (native_quality is a thin,
    # maxh-invariant wrapper around CalcTotalBad/ElementError/Check*).
    mp = I.MeshingParameters()
    @test nq.total_bad ≈ I.CalcTotalBad(m, mp)
    @test nq.volume_mesh_ok == (I.CheckVolumeMesh(m) == 0)
    @test nq.boundary_ok == (I.CheckConsistentBoundary(m) == 0)
    @test nq.overlapping_boundary == (I.CheckOverlappingBoundary(m) != 0)
end

@testset "native_quality is maxh-invariant and matches per-element ElementError" begin
    geom = load_step(STEP)
    m = generate_mesh(geom; maxh=40.0)
    nq = Delone.native_quality(m)

    mp = Delone.meshing_parameters(; maxh=1.0)
    ne = I.GetNE(m)
    errs = [I.ElementError(m, i, mp) for i in 1:ne]
    @test nq.min_element_badness ≈ minimum(errs)
    @test nq.max_element_badness ≈ maximum(errs)
    @test nq.mean_element_badness ≈ sum(errs) / ne
end

@testset "native_quality dimension guard (2D mesh)" begin
    outer = Circle(0.0, 0.0, 1.0, "d", "c")
    geo = geometry2d(outer)
    m2 = generate_mesh(geo; maxh=0.3)
    @test I.GetDimension(m2) == 2

    nq2 = Delone.native_quality(m2)
    @test isnan(nq2.min_element_badness)
    @test isnan(nq2.max_element_badness)
    @test isnan(nq2.mean_element_badness)
    @test nq2.total_bad == 0.0
    @test !isempty(nq2.warnings)
    @test nq2.warnings[1].code == :unsupported_dimension
end

@testset "quality(mesh) embeds native_quality fields (netgen_* provenance)" begin
    geom = load_step(STEP)
    m = generate_mesh(geom; maxh=40.0)
    q = quality(m)
    nq = Delone.native_quality(m)

    @test q.netgen_total_bad == nq.total_bad
    @test q.netgen_min_element_badness == nq.min_element_badness
    @test q.netgen_max_element_badness == nq.max_element_badness
    @test q.netgen_mean_element_badness == nq.mean_element_badness
    @test q.netgen_volume_mesh_ok == nq.volume_mesh_ok
    @test q.netgen_boundary_ok == nq.boundary_ok
    @test q.netgen_overlapping_boundary == nq.overlapping_boundary

    # Julia-side proxy metrics (min_quality etc.) live on their own [0,1]
    # scale and are untouched by the native fields being present.
    @test 0.0 <= q.min_quality <= 1.0
    @test 0.0 <= q.mean_quality <= 1.0

    # mesh_report composes quality() unchanged: the combined report's Base.show
    # must not error now that MeshQualityReport carries extra fields.
    r = mesh_report(m)
    io = IOBuffer()
    show(io, r)
    s = String(take!(io))
    @test occursin("MeshReport", s)
    @test occursin("netgen_total_bad", s)
end

@testset "quality(mesh) on 2D mesh leaves netgen_* fields at neutral defaults" begin
    outer = Circle(0.0, 0.0, 1.0, "d", "c")
    geo = geometry2d(outer)
    m2 = generate_mesh(geo; maxh=0.3)
    q2 = quality(m2)
    @test isnan(q2.netgen_min_element_badness)
    @test q2.netgen_volume_mesh_ok == true   # neutral default, not a real check
end

@testset "suggest_mesh_fixes surfaces native Netgen diagnostics" begin
    geom = load_step(STEP)
    opts = mesh_options(; maxh=40.0)
    r = generate_mesh_result(geom, opts)
    @test r.success
    report = mesh_report(r.mesh)
    sugs = suggest_mesh_fixes(r, report)
    @test sugs isa Vector{DiagnosticMessage}
    # On this well-formed fixture at a coarse maxh, Netgen's native checks
    # should all come back clean, so no netgen_* suggestion codes fire.
    @test !any(s -> s.code in (:netgen_orientation_check, :netgen_boundary_check,
                               :netgen_overlap_check, :netgen_open_boundary), sugs)
end

@testset "open_element_count / open_segment_count (real watertightness signal)" begin
    geom = load_step(STEP)
    m = generate_mesh(geom; maxh=40.0)
    nq = native_quality(m)
    # A properly generated, closed volume mesh has no unpaired boundary facets.
    @test nq.open_element_count == 0
    @test nq.open_element_count isa Int
    @test nq.open_segment_count isa Int
    q = quality(m)
    @test q.netgen_open_element_count == nq.open_element_count
    @test q.netgen_open_segment_count == nq.open_segment_count

    # A hand-built tet with NO surface elements is maximally "open": all 4
    # faces are unpaired. This is the real, verified behavior of
    # GetNOpenElements (not assumed) -- confirms open_element_count is a
    # meaningful watertightness signal, not a decorative field.
    m2 = I.new_mesh()
    p1 = I.AddPoint(m2, I.Point3d(0.0, 0.0, 0.0))
    p2 = I.AddPoint(m2, I.Point3d(1.0, 0.0, 0.0))
    p3 = I.AddPoint(m2, I.Point3d(0.0, 1.0, 0.0))
    p4 = I.AddPoint(m2, I.Point3d(0.0, 0.0, 1.0))
    add_volume_element!(m2, (p1, p2, p3, p4); region=1)
    nq2 = native_quality(m2)
    @test nq2.open_element_count == 4

    # This mesh's suggest_mesh_fixes should now surface the open-boundary
    # suggestion, since it genuinely has unpaired facets.
    mr = mesh_report(m2)
    sugs = suggest_mesh_fixes(generate_mesh_result(geom, mesh_options(; maxh=40.0)), mr)
    @test any(s -> s.code == :netgen_open_boundary, sugs)
end
