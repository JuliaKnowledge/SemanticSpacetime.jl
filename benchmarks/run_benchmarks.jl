"""
Semantic Spacetime Benchmark Suite

Benchmarks SemanticSpacetime.jl in-memory operations using BenchmarkTools.
Optionally shells out to Go and Python for cross-language comparison.

Usage:
    julia --project=. benchmarks/run_benchmarks.jl [OPTIONS]

Options:
    --julia-only     Run only Julia benchmarks (skip Go/Python)
    --go-only        Run only Go comparison benchmarks
    --python-only    Run only Python comparison benchmarks
    --filter PATTERN Only run benchmarks whose name matches PATTERN
"""

using SemanticSpacetime
using BenchmarkTools
using Dates
using JSON3
using Printf
using Statistics

# ─── Configuration ────────────────────────────────────────────────────────

const REPO_ROOT   = dirname(@__DIR__)
const SST_GO_ROOT = joinpath(REPO_ROOT, "..", "SSTorytime")
const RESULTS_DIR = joinpath(@__DIR__, "results")

const HAS_GO     = try success(`go version`); catch; false; end
const HAS_PYTHON = try success(`python3 -c "import psycopg2"`); catch; false; end

mkpath(RESULTS_DIR)

# ─── Helpers ──────────────────────────────────────────────────────────────

struct BenchResult
    name::String
    category::String
    n::Int
    julia_median_ns::Float64
    julia_allocs::Int
    julia_memory::Int
    go_time_ns::Union{Float64, Nothing}
    python_time_ns::Union{Float64, Nothing}
end

"""Set up arrows needed for benchmarks (idempotent via reset)."""
function setup_arrows!()
    SemanticSpacetime.reset_arrows!()
    SemanticSpacetime.reset_contexts!()

    fwd = insert_arrow!("LEADSTO", "then", "leads to next", "+")
    bwd = insert_arrow!("LEADSTO", "prev", "preceded by", "-")
    insert_inverse_arrow!(fwd, bwd)

    fwd2 = insert_arrow!("CONTAINS", "has", "contains element", "+")
    bwd2 = insert_arrow!("CONTAINS", "in", "element of", "-")
    insert_inverse_arrow!(fwd2, bwd2)

    insert_arrow!("NEAR", "like", "is similar to", "+")
    nothing
end

"""Build a test graph with `n` nodes and `n-1` sequential edges."""
function build_test_graph(n::Int)
    setup_arrows!()
    store = MemoryStore()
    nodes = Node[]
    for i in 1:n
        nd = mem_vertex!(store, "node_$i", "bench_chapter")
        push!(nodes, nd)
    end
    for i in 1:n-1
        mem_edge!(store, nodes[i], "then", nodes[i+1])
    end
    return store, nodes
end

# ─── Julia Benchmarks ────────────────────────────────────────────────────

function bench_node_creation(n::Int)
    setup_arrows!()
    b = @benchmark begin
        store = MemoryStore()
        for i in 1:$n
            mem_vertex!(store, "bench_node_$i", "bench_ch")
        end
    end
    return b
end

function bench_edge_creation(n::Int)
    setup_arrows!()
    # Pre-create a store with nodes, then benchmark adding edges to a fresh copy
    b = @benchmark begin
        s = MemoryStore()
        nds = Node[]
        for i in 1:$n
            push!(nds, mem_vertex!(s, "edge_node_$i", "bench_ch"))
        end
        for i in 1:$n-1
            mem_edge!(s, nds[i], "then", nds[i+1])
        end
    end
    return b
end

function bench_text_search(n::Int)
    store, _ = build_test_graph(n)
    # Search for a term that exists near the middle
    query = "node_$(n ÷ 2)"
    b = @benchmark mem_search_text($store, $query)
    return b
end

function bench_node_lookup(n::Int)
    store, nodes = build_test_graph(n)
    # Look up a node in the middle
    target = nodes[n ÷ 2].nptr
    b = @benchmark mem_get_node($store, $target)
    return b
end

function bench_graph_traversal(n::Int)
    store, nodes = build_test_graph(n)
    # Build adjacency from the in-memory store and find sources/sinks
    adj = AdjacencyMatrix()
    for (nptr, node) in store.nodes
        for stidx in 1:ST_TOP
            for lnk in node.incidence[stidx]
                SemanticSpacetime.add_edge!(adj, nptr, lnk.dst, Float64(lnk.wgt))
            end
        end
    end
    b = @benchmark begin
        find_sources($adj)
        find_sinks($adj)
    end
    return b
end

# ─── Benchmark Definitions ───────────────────────────────────────────────

const JULIA_BENCHMARKS = [
    # (name, category, size, function)
    ("node_create_100",    "node_creation",    100,   bench_node_creation),
    ("node_create_1000",   "node_creation",    1000,  bench_node_creation),
    ("node_create_10000",  "node_creation",    10000, bench_node_creation),

    ("edge_create_100",    "edge_creation",    100,   bench_edge_creation),
    ("edge_create_1000",   "edge_creation",    1000,  bench_edge_creation),
    ("edge_create_10000",  "edge_creation",    10000, bench_edge_creation),

    ("text_search_100",    "text_search",      100,   bench_text_search),
    ("text_search_1000",   "text_search",      1000,  bench_text_search),
    ("text_search_10000",  "text_search",      10000, bench_text_search),

    ("node_lookup_100",    "node_lookup",      100,   bench_node_lookup),
    ("node_lookup_1000",   "node_lookup",      1000,  bench_node_lookup),
    ("node_lookup_10000",  "node_lookup",      10000, bench_node_lookup),

    ("traversal_100",      "graph_traversal",  100,   bench_graph_traversal),
    ("traversal_1000",     "graph_traversal",  1000,  bench_graph_traversal),
    ("traversal_10000",    "graph_traversal",  10000, bench_graph_traversal),
]

# ─── Go / Python shelling out ────────────────────────────────────────────

function run_go_benchmark()
    !HAS_GO && return nothing
    go_src = joinpath(SST_GO_ROOT, "src", "API_EXAMPLE_1.go")
    !isfile(go_src) && return nothing
    @warn "Go benchmarks require a database; skipping in DB-free mode."
    return nothing
end

function run_python_benchmark()
    !HAS_PYTHON && return nothing
    py_src = joinpath(SST_GO_ROOT, "src", "python_integration_example.py")
    !isfile(py_src) && return nothing
    @warn "Python benchmarks require a database; skipping in DB-free mode."
    return nothing
end

# ─── Main ────────────────────────────────────────────────────────────────

function main()
    # Parse CLI args
    julia_only  = "--julia-only"  in ARGS
    go_only     = "--go-only"     in ARGS
    python_only = "--python-only" in ARGS
    filter_pattern = nothing
    for i in 1:length(ARGS)-1
        if ARGS[i] == "--filter"
            filter_pattern = ARGS[i+1]
        end
    end

    run_julia  = !go_only && !python_only
    run_go     = !julia_only && !python_only
    run_python = !julia_only && !go_only

    println("=" ^ 80)
    println("  SemanticSpacetime.jl Benchmark Suite")
    println("=" ^ 80)
    println()
    println("  Julia version:  ", VERSION)
    println("  Go available:   ", HAS_GO)
    println("  Python+psycopg: ", HAS_PYTHON)
    println("  Run Julia:      ", run_julia)
    println("  Run Go:         ", run_go)
    println("  Run Python:     ", run_python)
    if !isnothing(filter_pattern)
        println("  Filter:         ", filter_pattern)
    end
    println()

    results = BenchResult[]

    # ── Julia benchmarks ──
    if run_julia
        println("  Warming up Julia...")
        setup_arrows!()
        s = MemoryStore()
        mem_vertex!(s, "warmup", "w")
        println("  Warm-up done.")
        println()

        for (name, category, n, fn) in JULIA_BENCHMARKS
            if !isnothing(filter_pattern) &&
               !occursin(filter_pattern, name) &&
               !occursin(filter_pattern, category)
                continue
            end

            print("  Running: $name (n=$n) ...")
            b = fn(n)
            med_ns  = median(b).time          # nanoseconds
            allocs  = median(b).allocs
            mem     = Int(median(b).memory)
            med_ms  = med_ns / 1e6

            push!(results, BenchResult(name, category, n, med_ns, allocs, mem,
                                       nothing, nothing))
            @printf(" median: %.3f ms  allocs: %d  memory: %.1f KiB\n",
                    med_ms, allocs, mem / 1024.0)
        end
    end

    # ── Go benchmarks ──
    if run_go && HAS_GO
        println()
        println("  Go benchmarks:")
        run_go_benchmark()
    end

    # ── Python benchmarks ──
    if run_python && HAS_PYTHON
        println()
        println("  Python benchmarks:")
        run_python_benchmark()
    end

    # ── Summary table ──
    println()
    println("=" ^ 80)
    println("  SUMMARY")
    println("=" ^ 80)
    println()
    @printf("  %-25s %-18s %7s %12s %10s %12s\n",
            "Benchmark", "Category", "N", "Median (ms)", "Allocs", "Memory (KiB)")
    println("  ", "-" ^ 86)
    for r in results
        @printf("  %-25s %-18s %7d %12.3f %10d %12.1f\n",
                r.name, r.category, r.n,
                r.julia_median_ns / 1e6, r.julia_allocs, r.julia_memory / 1024.0)
    end
    println()

    # ── Save results as JSON ──
    timestamp = Dates.format(now(), "yyyymmdd_HHMMSS")
    outfile = joinpath(RESULTS_DIR, "bench_$timestamp.json")
    json_results = [Dict(
        "name"            => r.name,
        "category"        => r.category,
        "n"               => r.n,
        "julia_median_ns" => r.julia_median_ns,
        "julia_median_ms" => r.julia_median_ns / 1e6,
        "julia_allocs"    => r.julia_allocs,
        "julia_memory"    => r.julia_memory,
        "go_time_ns"      => r.go_time_ns,
        "python_time_ns"  => r.python_time_ns,
    ) for r in results]
    meta = Dict(
        "timestamp"     => string(now()),
        "julia_version" => string(VERSION),
        "go_available"  => HAS_GO,
        "python_available" => HAS_PYTHON,
        "benchmarks"    => json_results,
    )
    open(outfile, "w") do io
        JSON3.pretty(io, meta)
    end
    println("  Results saved to: $outfile")
    println()
end

main()
