# LLM-friendly meshing feedback loop: structured reports, hierarchy, snapshots.

@testset "MeshOptions validation" begin
    opts = MeshOptions(maxh=2.0, minh=0.1, grading=0.3)
    @test opts.maxh == 2.0
    @test validate_options!(opts) === opts
    @test_throws ArgumentError validate_options!(MeshOptions(maxh=-1.0))
    @test_throws ArgumentError validate_options!(MeshOptions(maxh=1.0, minh=2.0))
end

@testset "generate_mesh structured result (3D STEP)" begin
    geom = load_step(STEP)
    opts = MeshOptions(maxh=40.0, grading=0.3)
    result = generate_mesh(geom; options=opts, result=true)
    @test result isa MeshGenerationResult
    @test result.success
    @test result.mesh !== nothing
    @test result.options.maxh == 40.0
    @test num_cells(result.mesh) > 0
    @test result.elapsed_seconds >= 0
    m = mesh(result)
    @test num_nodes(m) == num_nodes(result.mesh)
end

@testset "generate_mesh legacy maxh path" begin
    geom = load_step(STEP)
    m = generate_mesh(geom; maxh=40.0)
    @test num_cells(m) > 0
end

@testset "generate_mesh failure report (null geometry)" begin
    opts = MeshOptions(maxh=1.0)
    result = generate_mesh_result(nothing, opts)
    @test !result.success
    @test result.mesh === nothing
    @test result.diagnostics.failure_stage == :geometry_import
    @test !isempty(result.diagnostics.messages)
end

@testset "mesh_report / validate / quality (3D)" begin
    geom = load_step(STEP)
    m = generate_mesh(geom; maxh=40.0)
    r = mesh_report(m)
    @test r isa MeshReport
    @test r.validation.valid
    @test r.validation.node_count > 0
    @test r.validation.element_count > 0
    @test isvalid(m)
    q = quality(m)
    @test isfinite(q.min_quality)
    @test isfinite(q.mean_quality)
    @test q.min_edge_length > 0
    @test q.max_edge_length >= q.min_edge_length
    # printable
    @test length(string(r)) > 20
end

@testset "tag_report (3D STEP)" begin
    geom = load_step(STEP)
    m = generate_mesh(geom; maxh=40.0)
    tr = Delone.tag_report(m)
    @test tr isa MeshTagReport
    @test length(string(tr)) > 10
end

@testset "2D disk: mesh, report, hierarchy" begin
    disk = Circle(0.0, 0.0, 1.0, "disk", "boundary")
    geom = geometry2d(disk)
    opts = MeshOptions(maxh=0.5)
    m = generate_mesh(geom; options=opts)
    r = mesh_report(m)
    @test r.validation.dimension == 2
    @test r.validation.valid
    @test r.validation.element_count > 0
    q = quality(m)
    @test isfinite(q.mean_quality)

    h = mesh_hierarchy(geom; maxh=0.5, levels=1)
    refine!(h; mode=:uniform, result=true)
    hr = hierarchy_report(h)
    @test hr.nlevels == 2
    @test hr.levels[2].element_count > hr.levels[1].element_count
    @test hr.transfers[1].inherited_node_count > 0
    @test length(string(hr)) > 20
end

@testset "session hierarchy report and Oodi readiness" begin
    geom = load_step(STEP)
    s = mesh_session(geom; maxh=40.0)
    request_uniform_refinement!(s)
    hr = hierarchy_report(s)
    @test hr.nlevels == 2
    @test hr.generation == generation(s)

    ready = oodi_snapshot_readiness(s)
    @test ready isa OodiSnapshotReadiness
    @test ready.dimension == 3
    @test ready.hierarchy_levels == 2
    @test ready.parent_node_transfers == :available
    @test length(string(ready)) > 20

    snap = hierarchy_snapshot(s)
    @test length(snap.levels) == 2
    @test length(snap.transfers) == 1
end

@testset "refine_session! structured result" begin
    geom = load_step(STEP)
    s = mesh_session(geom; maxh=40.0)
    res = refine_session!(s; mode=:uniform, result=true)
    @test res isa RefinementResult
    @test res.success
    @test res.new_level_count == 2
    @test res.new_element_count > res.old_element_count
end

@testset "meshability_report" begin
    geom = load_step(STEP)
    opts = MeshOptions(maxh=40.0)
    mr = Delone.meshability_report(geom; options=opts)
    @test mr.likely_meshable == true
    @test !isempty(mr.suggestions)
end

@testset "export_vtk and export_svg_2d" begin
    geom = load_step(STEP)
    m = generate_mesh(geom; maxh=40.0)
    vtk = tempname() * ".vtk"
    export_vtk(m, vtk)
    @test isfile(vtk)
    @test occursin("UNSTRUCTURED_GRID", read(vtk, String))
    rm(vtk; force=true)

    disk = Circle(0.0, 0.0, 1.0, "disk", "boundary")
    m2 = generate_mesh(geometry2d(disk); maxh=0.5)
    svg = tempname() * ".svg"
    export_svg_2d(m2, svg)
    @test isfile(svg)
    @test occursin("<svg", read(svg, String))
    rm(svg; force=true)
end

@testset "public reports do not expose Internals types" begin
    geom = load_step(STEP)
    m = generate_mesh(geom; maxh=40.0)
    r = mesh_report(m)
    @test !(r.validation isa Delone.Internals.Mesh)
    ready = oodi_snapshot_readiness(m)
    @test !(ready isa Delone.Internals.Mesh)
end

@testset "introspection contract: report/validate/readiness" begin
    geom = load_step(STEP)

    # validate(MeshOptions) is non-throwing and structured (OodiCore.ValidationReport)
    @test isvalid(validate(MeshOptions(maxh=40.0)))
    bad = validate(MeshOptions(maxh=1.0, minh=2.0))
    @test !isvalid(bad)
    @test any(d -> d.severity == :error, bad.diagnostics)

    # readiness(geom, MeshingTarget) delegates to meshability
    mt = readiness(geom, Delone.MeshingTarget(options=MeshOptions(maxh=40.0)))
    @test mt isa Delone.MeshabilityReport
    @test mt.likely_meshable == true
    @test_throws ArgumentError readiness(geom, Delone.MeshingTarget())  # no options

    m = generate_mesh(geom; maxh=40.0)

    # report(mesh) -> MeshReport
    @test report(m) isa MeshReport
    # readiness(mesh, OodiImportTarget) -> OodiSnapshotReadiness
    @test readiness(m, OodiImportTarget()) isa OodiSnapshotReadiness

    # hierarchy report + readiness
    h = mesh_hierarchy(geom; maxh=40.0, levels=1)
    refine!(h; mode=:uniform)
    @test report(h) isa MeshHierarchyReport
    gmg = readiness(h, GeometricMultigridTarget())
    @test gmg isa ReadinessReport
    @test gmg.subject == :geometric_multigrid
    @test isready(gmg)
    @test readiness(h, OodiImportTarget()).ready

    # single-level hierarchy is not GMG-ready
    h1 = mesh_hierarchy(geom; maxh=40.0, levels=1)
    @test !readiness(h1, GeometricMultigridTarget()).ready

    # generation-result report is the result itself
    res = generate_mesh(geom; maxh=40.0, result=true)
    @test report(res) === res
end

@testset "to_namedtuple serialization (no raw handles)" begin
    geom = load_step(STEP)
    m = generate_mesh(geom; maxh=40.0)

    nt = to_namedtuple(report(m))
    @test nt isa NamedTuple
    @test nt.validation.valid
    @test nt.quality.min_quality isa Real

    ntr = to_namedtuple(generate_mesh(geom; maxh=40.0, result=true))
    @test ntr.success
    @test ntr.has_mesh
    @test ntr.node_count > 0
    @test !haskey(ntr, :mesh)  # raw handle never serialized

    nto = to_namedtuple(MeshOptions(maxh=40.0, grading=0.3))
    @test nto.maxh == 40.0
    @test nto.grading == 0.3

    # readiness reports serialize too
    nrd = to_namedtuple(readiness(m, OodiImportTarget()))
    @test haskey(nrd, :ready)
end
