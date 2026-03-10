"""
Focused Julia vs Python benchmark for SemanticSpacetime.

Compares in-memory Julia graph construction against Python's DB-backed API.
Python benchmarks require psycopg2 and a database; they skip gracefully.

Usage:
    julia --project=. benchmarks/bench_vs_python.jl
"""

using SemanticSpacetime
using BenchmarkTools
using Printf

# ─── Configuration ────────────────────────────────────────────────────────

const REPO_ROOT   = dirname(@__DIR__)
const SST_GO_ROOT = joinpath(REPO_ROOT, "..", "SSTorytime")
const HAS_PYTHON  = try success(`python3 -c "import psycopg2"`); catch; false; end

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
        push!(nodes, mem_vertex!(store, "py_cmp_node_$i", "bench"))
    end
    for i in 1:n-1
        mem_edge!(store, nodes[i], "then", nodes[i+1])
    end
    elapsed_ms = (time_ns() - t0) / 1e6
    return elapsed_ms, node_count(store), link_count(store)
end

# ─── Python benchmark ────────────────────────────────────────────────────

function python_bench(n::Int)
    if !HAS_PYTHON
        println("  python3 with psycopg2 not found; skipping Python benchmark.")
        return nothing
    end

    py_src = joinpath(SST_GO_ROOT, "src", "python_integration_example.py")
    if !isfile(py_src)
        println("  Python example not found at: $py_src; skipping.")
        return nothing
    end

    # Check for database credentials
    creds = expanduser("~/.SSTorytime")
    if !isfile(creds)
        println("  Database credentials (~/.SSTorytime) not found.")
        println("  Python benchmarks require a running PostgreSQL instance; skipping.")
        return nothing
    end

    # Create a small timing wrapper
    py_code = """
import time
import sys
sys.path.insert(0, '$(joinpath(SST_GO_ROOT, "src"))')

try:
    from SSTorytime import *
except ImportError:
    print("SKIP")
    sys.exit(0)

try:
    t0 = time.perf_counter_ns()
    sst = OpenSST(False)
    for i in range($n):
        Vertex(sst, f"py_bench_node_{i}", "bench")
    CloseSST(sst)
    elapsed_ns = time.perf_counter_ns() - t0
    print(elapsed_ns)
except Exception as e:
    print(f"ERROR:{e}")
"""

    try
        output = strip(read(`python3 -c $py_code`, String))
        if output == "SKIP" || startswith(output, "ERROR:")
            println("  Python benchmark skipped: $output")
            return nothing
        end
        return parse(Float64, output) / 1e6  # convert ns to ms
    catch e
        println("  Python benchmark failed: $e")
        return nothing
    end
end

# ─── Main ────────────────────────────────────────────────────────────────

function main()
    println("=" ^ 60)
    println("  Julia vs Python — SemanticSpacetime Benchmark")
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

    println("  Python (DB-backed via SSTorytime.py):")
    for n in sizes
        py_ms = python_bench(n)
        if !isnothing(py_ms)
            @printf("    n=%5d  time: %8.2f ms\n", n, py_ms)
        end
    end

    println()
    println("  Note: Julia uses in-memory store (no DB); Python uses PostgreSQL.")
    println("  Direct comparison is illustrative, not apples-to-apples.")
    println()
end

main()
