"""
Focused Julia vs Go benchmark for SemanticSpacetime.

Compares in-memory Julia graph construction against Go's DB-backed API.
Go benchmarks require a database; they are skipped gracefully if unavailable.

Usage:
    julia --project=. benchmarks/bench_vs_go.jl
"""

using SemanticSpacetime
using BenchmarkTools
using Printf

# ─── Configuration ────────────────────────────────────────────────────────

const REPO_ROOT   = dirname(@__DIR__)
const SST_GO_ROOT = joinpath(REPO_ROOT, "..", "SSTorytime")
const HAS_GO      = try success(`go version`); catch; false; end

# ─── Helpers ──────────────────────────────────────────────────────────────

function setup_arrows!()
    SemanticSpacetime.reset_arrows!()
    SemanticSpacetime.reset_contexts!()
    fwd = insert_arrow!("LEADSTO", "then", "leads to next", "+")
    bwd = insert_arrow!("LEADSTO", "prev", "preceded by", "-")
    insert_inverse_arrow!(fwd, bwd)
    nothing
end

# ─── Julia benchmark ─────────────────────────────────────────────────────

function julia_bench(n::Int)
    setup_arrows!()
    t0 = time_ns()
    store = MemoryStore()
    nodes = Node[]
    for i in 1:n
        push!(nodes, mem_vertex!(store, "go_cmp_node_$i", "bench"))
    end
    for i in 1:n-1
        mem_edge!(store, nodes[i], "then", nodes[i+1])
    end
    elapsed_ms = (time_ns() - t0) / 1e6
    return elapsed_ms, node_count(store), link_count(store)
end

# ─── Go benchmark ────────────────────────────────────────────────────────

function go_bench()
    if !HAS_GO
        println("  Go not found in PATH; skipping Go benchmark.")
        return nothing
    end

    go_src = joinpath(SST_GO_ROOT, "src", "API_EXAMPLE_1.go")
    if !isfile(go_src)
        println("  Go source not found at: $go_src; skipping.")
        return nothing
    end

    # The Go examples require a PostgreSQL database.
    # We check for the credentials file; if absent, skip.
    creds = expanduser("~/.SSTorytime")
    if !isfile(creds)
        println("  Database credentials (~/.SSTorytime) not found.")
        println("  Go benchmarks require a running PostgreSQL instance; skipping.")
        return nothing
    end

    println("  Compiling and running Go API_EXAMPLE_1...")
    try
        tmpdir = mktempdir()
        t0 = time_ns()
        run(pipeline(`go run $go_src`, stdout=devnull, stderr=devnull))
        elapsed_ms = (time_ns() - t0) / 1e6
        return elapsed_ms
    catch e
        println("  Go benchmark failed: $e")
        return nothing
    end
end

# ─── Main ────────────────────────────────────────────────────────────────

function main()
    println("=" ^ 60)
    println("  Julia vs Go — SemanticSpacetime Benchmark")
    println("=" ^ 60)
    println()

    sizes = [100, 1000, 10000]

    println("  Julia (in-memory MemoryStore):")
    for n in sizes
        # Warm up
        julia_bench(n)
        # Timed run
        ms, nc, lc = julia_bench(n)
        @printf("    n=%5d  time: %8.2f ms  nodes: %d  links: %d\n", n, ms, nc, lc)
    end
    println()

    println("  Go (DB-backed, API_EXAMPLE_1):")
    go_ms = go_bench()
    if !isnothing(go_ms)
        @printf("    Go API_EXAMPLE_1 total: %.2f ms\n", go_ms)
    end

    println()
    println("  Note: Julia uses in-memory store (no DB); Go uses PostgreSQL.")
    println("  Direct comparison is illustrative, not apples-to-apples.")
    println()
end

main()
