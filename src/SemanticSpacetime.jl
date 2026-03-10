module SemanticSpacetime

using Dates
using Printf
using UUIDs
using Unicode
using LinearAlgebra
import JSON3
import LibPQ
import DBInterface
using Genie

# Core types and constants
include("types.jl")

# Arrow directory management
include("arrows.jl")

# Context registration and normalization
include("context.jl")

# In-memory node directory with n-gram bucketing
include("node_directory.jl")

# Database connection and lifecycle
include("database.jl")

# Database schema creation
include("schema.jl")

# Database node operations
include("db_nodes.jl")

# Database link operations
include("db_links.jl")

# Database query operations
include("db_queries.jl")

# In-memory graph store (no DB required)
include("memory_store.jl")

# DBInterface.jl-based portable database store
include("db_store.jl")

# Appointed nodes subsystem
include("appointed_nodes.jl")

# SQL serialization utilities
include("sql_utils.jl")

# High-level Vertex/Edge API
include("api.jl")

# Graph analysis tools
include("graph_report.jl")

# Search operations
include("search.jl")

# Weighted search operations
include("weighted_search.jl")

# ETC type validation
include("etc_validation.jl")

# Inhibition/NOT context search
include("inhibition.jl")

# Causal cone traversal
include("cone_search.jl")

# Path solving with loop corrections
include("pathsolve.jl")

# Advanced graph traversal (adjoint, wave front, constrained cones)
include("graph_traversal.jl")

# Node orbit system and centrality analysis
include("node_orbits.jl")

# Terminal display and print functions
include("display.jl")

# Extended database query functions
include("db_queries_ext.jl")

# Text to N4L conversion
include("text2n4l.jl")

# Advanced n-gram text analysis
include("text_analysis.jl")

# Context intelligence and STM tracking
include("context_intelligence.jl")

# Semantic time parsing
include("time_semantics.jl")

# Built-in dynamic function evaluation
include("builtins.jl")

# Arrow closure composition
include("arrow_closures.jl")

# Session tracking (LastSeen)
include("session_tracking.jl")

# Utility tools (chapter removal, notes, JSON import)
include("tools.jl")

# N4L parser and compiler
include("n4l_parser.jl")

# N4L compiler (parser result → store)
include("n4l_compiler.jl")

# N4L standalone validation and summary
include("n4l_standalone.jl")

# RDF integration (bidirectional SST ↔ RDF conversion)
include("rdf_integration.jl")

# Web interface types (JSON serialization for web UI)
include("web_types.jl")

# HTTP server (Genie-based)
include("http_server.jl")

# Coordinate assignment system
include("coordinates.jl")

# Matrix algebra utilities
include("matrix_ops.jl")

# PageMap operations
include("pagemap_ops.jl")

# Database download/sync
include("db_sync.jl")

# Visualization (CairoMakie-based, gracefully handles missing dep)
include("visualization.jl")

# Todo features: focal view, ETC validation integration, provenance
include("todo_features.jl")

# Todo features 2: unified search, combinatorial search, SQL indexing
include("todo_features2.jl")

# Todo features 3: log analysis pipeline, text breakdown assistant
include("todo_features3.jl")

# Syntactic sugar: string macros, convenience macros, do-blocks
include("macros.jl")

export
    # Types
    STType, NEAR, LEADSTO, CONTAINS, EXPRESS,
    NodePtr, ClassedNodePtr, ArrowPtr, ContextPtr,
    Node, Link, ArrowEntry, ContextEntry,
    Etc, PageMap, Appointment, NodeDirectory,
    SSTConnection, NO_NODE_PTR,
    Coords, Orbit, WebPath, NodeEvent, Story,

    # Constants
    ST_ZERO, ST_TOP,
    CAUSAL_CONE_MAXLIMIT,
    N1GRAM, N2GRAM, N3GRAM, LT128, LT1024, GT1024,
    SCREENWIDTH, LEFTMARGIN, RIGHTMARGIN,
    CREDENTIALS_FILE,

    # Arrow functions
    insert_arrow!, insert_inverse_arrow!,
    get_arrow_by_name, get_arrow_by_ptr,
    get_stindex_by_name, get_sttype_from_arrows,
    print_stindex,

    # Context functions
    register_context!, try_context, get_context,
    compile_context_string, normalize_context_string,

    # Node directory functions
    new_node_directory, append_text_to_directory!,
    check_existing_or_alt_caps, get_node_txt_from_ptr,
    get_memory_node_from_ptr, n_channel,
    update_seq_status!,

    # Database functions
    open_sst, close_sst, configure!,
    create_type, create_table,
    append_db_link_to_node_command, append_db_link_array_to_node,

    # In-memory store
    AbstractSSTStore, MemoryStore,
    mem_vertex!, mem_edge!, mem_get_node,
    mem_get_nodes_by_name, mem_get_chapters,
    mem_search_text, node_count, link_count,

    # Appointed Nodes
    get_appointed_nodes_by_arrow, get_appointed_nodes_by_sttype,
    parse_appointed_node_cluster,

    # DBStore
    DBStore, create_db_schema!,
    db_vertex!, db_edge!, db_get_node, db_get_links,
    db_get_nodes_by_name, db_search_nodes,
    db_get_chapters, db_get_chapter_nodes, db_stats,
    db_upload_arrows!, db_load_arrows!,
    db_upload_contexts!, db_load_contexts!,
    open_sqlite, open_duckdb, close_db,

    # High-level API
    vertex!, edge!, hub_join!, graph_to_db!,

    # Graph analysis
    AdjacencyMatrix, add_edge!,
    build_adjacency, find_sources, find_sinks,
    detect_loops, eigenvector_centrality,
    symmetrize, graph_summary,

    # Search
    SearchParameters, decode_search_field,
    search_nodes, search_text,
    get_db_node_ptr_matching_nccs,
    split_quotes, deq, is_command, something_like,
    is_literal_nptr, is_nptr_str,
    is_bracketed_search_term, is_bracketed_search_list,
    is_exact_match, is_string_fragment,
    add_orphan, check_help_query, check_nptr_query,
    check_remind_query, check_concept_query,
    parse_literal_node_ptrs, score_context,
    search_term_len, all_exact,
    arrow_ptr_from_names, solve_node_ptrs, min_max_policy,
    is_quote_char, read_to_next,
    fill_in_parameters, is_param, decode_search_command,
    SEARCH_KEYWORDS, RECENT, NEVER_HORIZON,

    # SQL utilities
    sql_escape,
    format_sql_string_array, format_sql_int_array,
    format_sql_nodeptr_array, format_sql_link_array,
    parse_sql_array_string, parse_sql_nptr_array,
    parse_sql_link_string, parse_link_path,
    array2str, str2array, sttype_db_channel, storage_class,
    dirac_notation, sttype_name, escape_json_string,
    context_string, similar_string, in_list,
    match_arrows, match_contexts, matches_in_context, arrow2int,
    list2map, map2list, list2string, parse_map_link_array,

    # Weighted search
    WeightedPath, weighted_search, dijkstra_path, rank_by_weight,

    # ETC validation
    infer_etc, validate_etc, collapse_psi, show_psi, validate_graph_types,

    # Inhibition context
    InhibitionContext, parse_inhibition_context,
    matches_inhibition, search_with_inhibition,

    # Cone search
    ConeResult, forward_cone, backward_cone,
    entire_nc_cone, select_stories_by_arrow,
    get_fwd_paths_as_links, get_entire_cone_paths_as_links,

    # Path solving
    PathResult, find_paths, detect_path_loops,

    # Graph traversal
    adjoint_arrows, adjoint_sttype, adjoint_link_path,
    wave_front, nodes_overlap, wave_fronts_overlap,
    left_join, right_complement_join, is_dag,
    together!, idemp_add_nodeptr!, in_node_set,
    get_constrained_cone_paths, get_constrained_fwd_links,
    get_paths_and_symmetries,
    get_longest_axial_path, truncate_paths_by_arrow,
    get_paths_and_symmetries_legacy,

    # Node orbits and centrality
    get_node_orbit, assemble_satellites_by_sttype,
    idemp_add_satellite!,
    tally_path, betweenness_centrality,
    super_nodes_by_conic_path, super_nodes,
    get_path_transverse_super_nodes,

    # Text to N4L
    TextRank, TextSignificance,
    score_sentence, extract_significant_sentences,
    text_to_n4l,

    # Text analysis (n-gram fractionation)
    N_GRAM_MAX, N_GRAM_MIN, DUNBAR_5, DUNBAR_15, DUNBAR_30, DUNBAR_150,
    reset_ngram_state!, new_ngram_map,
    split_into_para_sentences, split_punctuation_text,
    un_paren, count_parens,
    clean_ngram, excluded_by_bindings,
    fractionate, next_word, fractionate_text, fractionate_text_file,
    ngram_static_intentionality, assess_static_intent,
    running_ngram_intentionality,
    intentional_ngram, interval_radius,
    assess_static_text_anomalies,
    assess_text_coherent_coactivation, assess_text_fast_slow,
    coherence_set, extract_intentional_tokens,

    # Context intelligence
    STMHistory, reset_stm!,
    context_intent_analysis, update_stm_context,
    add_context, commit_context_token!,
    intersect_context_parts, diff_clusters, overlap_matrix,
    get_context_token_frequencies,
    get_node_context, get_node_context_string, context_interferometry,

    # Time semantics
    GR_MONTH_TEXT, GR_DAY_TEXT, GR_SHIFT_TEXT,
    do_nowt, get_time_context, season, get_time_from_semantics,

    # Arrow closures
    ClosureRule, load_arrow_closures, apply_arrow_closures!,
    complete_inferences!, complete_closeness!, complete_sequences!,

    # Session tracking
    LastSeen, Coords,
    reset_session_tracking!,
    update_last_saw_section!, update_last_saw_nptr!,
    get_last_saw_section, get_last_saw_nptr, get_newly_seen_nptrs,

    # Tools
    remove_chapter!, browse_notes, import_json!,

    # N4L parser
    N4LState, N4LResult, N4LParseError,
    parse_n4l, parse_n4l_file, parse_config_file,
    find_config_dir, read_config_files, add_mandatory_arrows!,
    has_errors, has_warnings,
    ROLE_EVENT, ROLE_RELATION, ROLE_SECTION, ROLE_CONTEXT,
    ROLE_CONTEXT_ADD, ROLE_CONTEXT_SUBTRACT, ROLE_BLANK_LINE,
    ROLE_LINE_ALIAS, ROLE_LOOKUP, ROLE_COMPOSITION, ROLE_RESULT,

    # N4L compiler
    N4LCompileResult,
    compile_n4l!, compile_n4l_file!, compile_n4l_string!,

    # N4L standalone
    N4LValidationResult,
    validate_n4l, validate_n4l_file, n4l_summary,

    # RDF integration
    RDFTriple, SSTNamespace, PredicateMapping,
    sst_namespace, sst_to_rdf, rdf_to_sst!,
    export_turtle, import_turtle!,
    triples_to_turtle, parse_turtle,

    # Web types
    WebConePaths, PageView, SearchResponse,
    coords_to_dict, webpath_to_dict, orbit_to_dict, node_event_to_dict,
    json_node_event,
    link_web_paths, json_page, package_response,

    # HTTP server
    serve, stop_server, handle_search_dispatch,

    # Coordinates
    R0, R1, R2,
    relative_orbit, set_orbit_coords,
    assign_cone_coordinates, assign_story_coordinates,
    assign_page_coordinates, assign_chapter_coordinates,
    assign_context_set_coordinates, assign_fragment_coordinates,
    make_coordinate_directory,

    # Matrix operations
    symbol_matrix, symbolic_multiply,
    get_sparse_occupancy, symmetrize_matrix, transpose_matrix,
    make_init_vector, matrix_op_vector, compute_evc,
    find_gradient_field_top, get_hill_top,

    # PageMap operations
    upload_page_map_event!, get_page_map,
    get_chapters_by_chap_context, split_chapters,

    # DB sync
    download_arrows_from_db!, download_contexts_from_db!,
    synchronize_nptrs!, cache_node!, get_cached_node,
    reset_node_cache!,

    # Visualization
    ST_COLORS,
    plot_cone, plot_orbit, plot_graph_summary,
    plot_adjacency_heatmap, save_plot,

    # Display
    show_text, indent, print_node_orbit, print_link_orbit, print_link_path,
    show_context, print_sta_index, show_time,
    new_line, waiting, print_some_link_path,

    # Built-ins
    expand_dynamic_functions, evaluate_in_built, do_in_built_function,
    in_built_time_until, in_built_time_since,

    # Extended queries
    get_arrows_matching_name, get_arrows_by_sttype, get_arrow_with_name,
    next_link_arrow, inc_constraint_cone_links, get_singleton_by_sttype,
    get_sequence_containers, already_seen,

    # Syntactic sugar
    @n4l_str, @sst, @compile, @graph,
    connect!, links, neighbors, nodes, eachnode, eachlink,
    find_nodes, map_nodes, with_store, with_config,

    # Todo features 2: unified search, combinatorial, SQL indexing
    UnifiedSearchParams, unified_search,
    combinatorial_search, cross_chapter_search,
    SQLIndexConfig, index_sql_database!,

    # Todo features: focal view
    FocalView, focal_view, drill_down, drill_up, tree_view, hierarchy_roots,

    # Todo features: ETC validation integration
    validate_compiled_graph!,

    # Todo features: provenance
    Provenance, set_provenance!, get_provenance, compile_n4l_with_provenance!,

    # Todo features 3: log analysis pipeline
    LogFormat, LOG_SYSLOG, LOG_JSON, LOG_CSV, LOG_TSV, LOG_CUSTOM,
    LogParseConfig, default_log_config,
    parse_syslog_line, parse_json_log_line, parse_csv_log,
    parse_log_to_sst!,

    # Todo features 3: text breakdown assistant
    EntitySuggestion, LinkSuggestion, TextBreakdown,
    identify_entities, suggest_links, propose_structure, breakdown_to_n4l

end # module
