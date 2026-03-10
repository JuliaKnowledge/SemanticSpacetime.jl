using Test
using SemanticSpacetime

@testset "SemanticSpacetime.jl" begin
    include("test_types.jl")
    include("test_arrows.jl")
    include("test_context.jl")
    include("test_node_directory.jl")
    include("test_memory_store.jl")
    include("test_graph_report.jl")
    include("test_search.jl")
    include("test_cone_search.jl")
    include("test_pathsolve.jl")
    include("test_graph_traversal.jl")
    include("test_node_orbits.jl")
    include("test_weighted_search.jl")
    include("test_etc_validation.jl")
    include("test_inhibition.jl")
    include("test_text2n4l.jl")
    include("test_text_analysis.jl")
    include("test_context_intelligence.jl")
    include("test_time_semantics.jl")
    include("test_session_tracking.jl")
    include("test_tools.jl")
    include("test_n4l_parser.jl")
    include("test_n4l_compiler.jl")
    include("test_rdf_integration.jl")
    include("test_web_server.jl")
    include("test_http_server.jl")
    include("test_cross_language.jl")
    include("test_examples.jl")
    include("test_coordinates.jl")
    include("test_matrix_ops.jl")
    include("test_pagemap.jl")
    include("test_display.jl")
    include("test_builtins.jl")
    include("test_db_queries_ext.jl")
    include("test_search_utils.jl")
    include("test_search_commands.jl")
    include("test_sql_utils.jl")
    include("test_db_store.jl")
    include("test_macros.jl")
    include("test_todo_features3.jl")
    include("test_todo_features2.jl")
    include("test_todo_features.jl")

    # DB-dependent tests — only run when SST_TEST_DB is set
    if haskey(ENV, "SST_TEST_DB")
        include("test_database.jl")
    else
        @info "Skipping database tests (set SST_TEST_DB=1 to enable)"
    end
end
