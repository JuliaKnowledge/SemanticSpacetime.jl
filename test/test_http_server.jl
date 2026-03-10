using HTTP
import JSON3
import Sockets

@testset "HTTP Server" begin
    # Reset global state
    SemanticSpacetime.reset_arrows!()
    SemanticSpacetime.reset_contexts!()

    # Register arrows
    fwd = insert_arrow!("LEADSTO", "then", "leads to next", "+")
    bwd = insert_arrow!("LEADSTO", "prev", "preceded by", "-")
    insert_inverse_arrow!(fwd, bwd)

    contains_fwd = insert_arrow!("CONTAINS", "has", "contains element", "+")
    contains_bwd = insert_arrow!("CONTAINS", "in", "element of", "-")
    insert_inverse_arrow!(contains_fwd, contains_bwd)

    # Build a small test graph
    store = MemoryStore()
    n1 = mem_vertex!(store, "Alice", "chapter1")
    n2 = mem_vertex!(store, "Bob", "chapter1")
    n3 = mem_vertex!(store, "Charlie", "chapter2")
    mem_edge!(store, n1, "then", n2)
    mem_edge!(store, n2, "then", n3)
    mem_edge!(store, n1, "has", n3)

    # Pick a port in the ephemeral range
    port = 18700 + (getpid() % 100)
    base = "http://127.0.0.1:$port"

    server = serve(store; port=port, verbose=false)
    sleep(2)

    try
        @testset "health endpoint" begin
            resp = HTTP.get("$base/health")
            @test resp.status == 200
            body = JSON3.read(String(resp.body))
            @test body["status"] == "ok"
        end

        @testset "search endpoint" begin
            resp = HTTP.get("$base/search?q=Alice")
            @test resp.status == 200
            body = JSON3.read(String(resp.body))
            @test body["query"] == "Alice"
            @test length(body["results"]) == 1
            @test body["results"][1]["text"] == "Alice"

            # Case insensitive
            resp2 = HTTP.get("$base/search?q=alice")
            body2 = JSON3.read(String(resp2.body))
            @test length(body2["results"]) == 1

            # No results
            resp3 = HTTP.get("$base/search?q=zzzzz")
            body3 = JSON3.read(String(resp3.body))
            @test isempty(body3["results"])

            # Missing q parameter
            resp4 = HTTP.get("$base/search?q="; status_exception=false)
            @test resp4.status == 400
        end

        @testset "node endpoint" begin
            cls = n1.nptr.class
            cptr = n1.nptr.cptr
            resp = HTTP.get("$base/node/$cls/$cptr")
            @test resp.status == 200
            body = JSON3.read(String(resp.body))
            @test body["text"] == "Alice"
            @test body["chapter"] == "chapter1"
            @test body["nptr"]["class"] == cls
            @test body["nptr"]["cptr"] == cptr

            # Not found
            resp2 = HTTP.get("$base/node/1/9999"; status_exception=false)
            @test resp2.status == 404
        end

        @testset "links endpoint" begin
            cls = n1.nptr.class
            cptr = n1.nptr.cptr
            resp = HTTP.get("$base/links/$cls/$cptr")
            @test resp.status == 200
            body = JSON3.read(String(resp.body))
            # n1 has forward LEADSTO to n2 and forward CONTAINS to n3
            @test !isempty(body)

            # Not found
            resp2 = HTTP.get("$base/links/1/9999"; status_exception=false)
            @test resp2.status == 404
        end

        @testset "cone endpoint" begin
            cls = n1.nptr.class
            cptr = n1.nptr.cptr
            resp = HTTP.get("$base/cone/$cls/$cptr?direction=forward&depth=3")
            @test resp.status == 200
            body = JSON3.read(String(resp.body))
            @test body["root"]["class"] == cls
            @test body["root"]["cptr"] == cptr
            @test !isempty(body["paths"])

            # Backward cone from n3
            cls3 = n3.nptr.class
            cptr3 = n3.nptr.cptr
            resp2 = HTTP.get("$base/cone/$cls3/$cptr3?direction=backward&depth=3")
            @test resp2.status == 200
            body2 = JSON3.read(String(resp2.body))
            @test body2["root"]["class"] == cls3
        end

        @testset "graph endpoint" begin
            resp = HTTP.get("$base/graph")
            @test resp.status == 200
            body = JSON3.read(String(resp.body))
            @test body["nodes"] == 3
            @test body["links"] > 0
            @test haskey(body, "sources")
            @test haskey(body, "sinks")
            @test haskey(body, "top_centrality")
        end

        @testset "searchN4L endpoint" begin
            resp = HTTP.get("$base/searchN4L?name=Alice")
            @test resp.status == 200
            body = JSON3.read(String(resp.body))
            @test haskey(body, "type")
            @test body["type"] == "orbit"
            @test !isempty(body["results"])

            # Empty search returns stats
            resp2 = HTTP.get("$base/searchN4L")
            @test resp2.status == 200
            body2 = JSON3.read(String(resp2.body))
            @test haskey(body2, "type") || haskey(body2, "nodes")
        end

        @testset "api/orbit endpoint" begin
            cls = n1.nptr.class
            cptr = n1.nptr.cptr
            resp = HTTP.get("$base/api/orbit/$cls/$cptr")
            @test resp.status == 200
            body = JSON3.read(String(resp.body))
            @test body["text"] == "Alice"
            @test haskey(body, "orbits")
        end

        @testset "api/cone endpoint" begin
            cls = n1.nptr.class
            cptr = n1.nptr.cptr
            resp = HTTP.get("$base/api/cone/$cls/$cptr?direction=forward&depth=3")
            @test resp.status == 200
            body = JSON3.read(String(resp.body))
            @test haskey(body, "origin")
            @test haskey(body, "paths")
        end

        @testset "api/chapters endpoint" begin
            resp = HTTP.get("$base/api/chapters")
            @test resp.status == 200
            body = JSON3.read(String(resp.body))
            @test haskey(body, "chapters")
            @test "chapter1" in body["chapters"]
            @test "chapter2" in body["chapters"]
        end

        @testset "api/stats endpoint" begin
            resp = HTTP.get("$base/api/stats")
            @test resp.status == 200
            body = JSON3.read(String(resp.body))
            @test body["nodes"] == 3
        end

        @testset "api/contexts endpoint" begin
            resp = HTTP.get("$base/api/contexts")
            @test resp.status == 200
            body = JSON3.read(String(resp.body))
            @test haskey(body, "contexts")
        end

        @testset "api/pagemap endpoint" begin
            resp = HTTP.get("$base/api/pagemap")
            @test resp.status == 200
            body = JSON3.read(String(resp.body))
            @test haskey(body, "title")
            @test haskey(body, "notes")
        end

        @testset "api/stories endpoint" begin
            resp = HTTP.get("$base/api/stories")
            @test resp.status == 200
            body = JSON3.read(String(resp.body))
            @test haskey(body, "type")
            @test body["type"] == "stories"
        end

        @testset "UI static files" begin
            resp = HTTP.get("$base/")
            @test resp.status == 200
            @test occursin("SemanticSpacetime", String(resp.body))

            resp2 = HTTP.get("$base/style.css")
            @test resp2.status == 200
            @test occursin("--bg:", String(resp2.body))
        end

        @testset "api/chapters/detailed endpoint" begin
            resp = HTTP.get("$base/api/chapters/detailed")
            @test resp.status == 200
            body = JSON3.read(String(resp.body))
            @test length(body) >= 2  # chapter1, chapter2
            # Each entry should have name and count
            @test haskey(body[1], "name")
            @test haskey(body[1], "count")
        end

        @testset "api/links enhanced endpoint" begin
            cls = n1.nptr.class
            cptr = n1.nptr.cptr
            resp = HTTP.get("$base/api/links/$cls/$cptr")
            @test resp.status == 200
            body = JSON3.read(String(resp.body))
            @test haskey(body, "links")
            @test haskey(body, "count")
            @test body["count"] > 0
            # Check link entries have rich data
            lnk = body["links"][1]
            @test haskey(lnk, "arrow_name")
            @test haskey(lnk, "dst_text")
            @test haskey(lnk, "sttype")
        end

        @testset "api/orbit/ui endpoint" begin
            cls = n1.nptr.class
            cptr = n1.nptr.cptr
            resp = HTTP.get("$base/api/orbit/ui/$cls/$cptr")
            @test resp.status == 200
            body = JSON3.read(String(resp.body))
            @test haskey(body, "center_text")
            @test body["center_text"] == "Alice"
            @test haskey(body, "satellites")
            sats = body["satellites"]
            @test haskey(sats, "leadsto") || haskey(sats, "contains")
        end

    finally
        stop_server()
        sleep(1)
    end

    # Clean up global state
    SemanticSpacetime.reset_arrows!()
    SemanticSpacetime.reset_contexts!()
end
