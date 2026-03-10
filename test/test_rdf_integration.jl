@testset "RDF Integration" begin
    # Reset global arrow/context state for clean tests
    SemanticSpacetime.reset_arrows!()
    SemanticSpacetime.reset_contexts!()

    # Register arrows for testing
    fwd = insert_arrow!("LEADSTO", "then", "leads to next", "+")
    bwd = insert_arrow!("LEADSTO", "prev", "preceded by", "-")
    insert_inverse_arrow!(fwd, bwd)

    contains_fwd = insert_arrow!("CONTAINS", "has", "contains element", "+")
    contains_bwd = insert_arrow!("CONTAINS", "in", "element of", "-")
    insert_inverse_arrow!(contains_fwd, contains_bwd)

    near_arr = insert_arrow!("NEAR", "like", "is similar to", "+")

    @testset "SSTNamespace" begin
        ns = sst_namespace()
        @test ns.base == "http://sst.example.org/"
        @test ns.vocab == "http://sst.example.org/vocab#"

        ns2 = sst_namespace("http://example.com/sst")
        @test ns2.base == "http://example.com/sst/"
        @test ns2.vocab == "http://example.com/sst/vocab#"
    end

    @testset "RDFTriple basics" begin
        t1 = RDFTriple("http://a", "http://b", "http://c")
        t2 = RDFTriple("http://a", "http://b", "http://c")
        t3 = RDFTriple("http://a", "http://b", "http://d")
        @test t1 == t2
        @test t1 != t3
        @test hash(t1) == hash(t2)
    end

    @testset "SST → RDF conversion" begin
        store = MemoryStore()
        n1 = mem_vertex!(store, "Event A", "chapter1")
        n2 = mem_vertex!(store, "Event B", "chapter1")
        mem_edge!(store, n1, "then", n2)

        ns = sst_namespace()
        triples = sst_to_rdf(store; namespace=ns)
        @test !isempty(triples)

        # Check node triples exist
        subj_a = ns.base * "node/Event_A"
        subj_b = ns.base * "node/Event_B"

        type_triples = filter(t -> t.predicate == SemanticSpacetime.RDF_TYPE && t.object == ns.vocab * "Node", triples)
        @test length(type_triples) >= 2

        label_triples = filter(t -> t.predicate == SemanticSpacetime.RDFS_LABEL, triples)
        labels = Set(t.object for t in label_triples)
        @test "Event A" in labels
        @test "Event B" in labels

        # Check edge triple
        arrow_uri = ns.vocab * "then"
        edge_triples = filter(t -> t.predicate == arrow_uri, triples)
        @test length(edge_triples) >= 1
        @test any(t -> t.subject == subj_a && t.object == subj_b, edge_triples)

        # Check chapter triples
        chapter_triples = filter(t -> t.predicate == ns.vocab * "chapter", triples)
        @test length(chapter_triples) >= 2
    end

    @testset "RDF → SST conversion" begin
        SemanticSpacetime.reset_arrows!()
        SemanticSpacetime.reset_contexts!()

        # Re-register arrows
        fwd2 = insert_arrow!("LEADSTO", "then", "leads to next", "+")
        bwd2 = insert_arrow!("LEADSTO", "prev", "preceded by", "-")
        insert_inverse_arrow!(fwd2, bwd2)

        ns = sst_namespace()
        triples = [
            RDFTriple(ns.base * "node/Alice", SemanticSpacetime.RDFS_LABEL, "Alice"),
            RDFTriple(ns.base * "node/Bob", SemanticSpacetime.RDFS_LABEL, "Bob"),
            RDFTriple(ns.base * "node/Alice", ns.vocab * "chapter", ns.base * "chapter/people"),
            RDFTriple(ns.base * "node/Bob", ns.vocab * "chapter", ns.base * "chapter/people"),
            RDFTriple(ns.base * "node/Alice", ns.vocab * "then", ns.base * "node/Bob"),
        ]

        store = MemoryStore()
        rdf_to_sst!(store, triples; namespace=ns, chapter="default")

        @test node_count(store) == 2

        alice_nodes = mem_get_nodes_by_name(store, "Alice")
        @test length(alice_nodes) == 1
        @test alice_nodes[1].chap == "people"

        bob_nodes = mem_get_nodes_by_name(store, "Bob")
        @test length(bob_nodes) == 1
        @test bob_nodes[1].chap == "people"

        # Check edge was created
        @test link_count(store) > 0
    end

    @testset "round-trip SST → RDF → SST" begin
        SemanticSpacetime.reset_arrows!()
        SemanticSpacetime.reset_contexts!()

        fwd3 = insert_arrow!("LEADSTO", "then", "leads to next", "+")
        bwd3 = insert_arrow!("LEADSTO", "prev", "preceded by", "-")
        insert_inverse_arrow!(fwd3, bwd3)
        insert_arrow!("NEAR", "like", "is similar to", "+")

        # Build original store
        store1 = MemoryStore()
        a = mem_vertex!(store1, "Alpha", "ch1")
        b = mem_vertex!(store1, "Beta", "ch1")
        c = mem_vertex!(store1, "Gamma", "ch2")
        mem_edge!(store1, a, "then", b)
        mem_edge!(store1, b, "like", c)

        ns = sst_namespace()
        triples = sst_to_rdf(store1; namespace=ns)

        # Import into a new store
        store2 = MemoryStore()
        rdf_to_sst!(store2, triples; namespace=ns, chapter="default")

        # Verify nodes round-tripped
        @test node_count(store2) >= 3
        @test !isempty(mem_get_nodes_by_name(store2, "Alpha"))
        @test !isempty(mem_get_nodes_by_name(store2, "Beta"))
        @test !isempty(mem_get_nodes_by_name(store2, "Gamma"))

        # Verify edges exist
        @test link_count(store2) > 0
    end

    @testset "Turtle export" begin
        SemanticSpacetime.reset_arrows!()
        SemanticSpacetime.reset_contexts!()

        insert_arrow!("LEADSTO", "then", "leads to next", "+")

        store = MemoryStore()
        n1 = mem_vertex!(store, "Hello", "ch1")
        n2 = mem_vertex!(store, "World", "ch1")
        mem_edge!(store, n1, "then", n2)

        turtle = export_turtle(store)
        @test occursin("@prefix", turtle)
        @test occursin("sst:", turtle)
        @test occursin("Hello", turtle)
        @test occursin("World", turtle)
    end

    @testset "Turtle parse" begin
        turtle_text = """
        @prefix rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#> .
        @prefix rdfs: <http://www.w3.org/2000/01/rdf-schema#> .

        <http://example.org/Alice> <http://www.w3.org/2000/01/rdf-schema#label> "Alice" .
        <http://example.org/Bob> <http://www.w3.org/2000/01/rdf-schema#label> "Bob" .
        <http://example.org/Alice> <http://example.org/knows> <http://example.org/Bob> .
        """

        triples = parse_turtle(turtle_text)
        @test length(triples) == 3

        labels = filter(t -> t.predicate == "http://www.w3.org/2000/01/rdf-schema#label", triples)
        @test length(labels) == 2

        knows = filter(t -> t.predicate == "http://example.org/knows", triples)
        @test length(knows) == 1
        @test knows[1].subject == "http://example.org/Alice"
        @test knows[1].object == "http://example.org/Bob"
    end

    @testset "Turtle import into store" begin
        SemanticSpacetime.reset_arrows!()
        SemanticSpacetime.reset_contexts!()

        insert_arrow!("LEADSTO", "then", "leads to next", "+")

        turtle_text = """
        <http://sst.example.org/node/Sun> <http://www.w3.org/2000/01/rdf-schema#label> "Sun" .
        <http://sst.example.org/node/Moon> <http://www.w3.org/2000/01/rdf-schema#label> "Moon" .
        <http://sst.example.org/node/Sun> <http://sst.example.org/vocab#then> <http://sst.example.org/node/Moon> .
        """

        store = MemoryStore()
        import_turtle!(store, turtle_text; chapter="astro")

        @test node_count(store) == 2
        @test !isempty(mem_get_nodes_by_name(store, "Sun"))
        @test !isempty(mem_get_nodes_by_name(store, "Moon"))
        @test link_count(store) > 0
    end

    @testset "Turtle round-trip" begin
        SemanticSpacetime.reset_arrows!()
        SemanticSpacetime.reset_contexts!()

        insert_arrow!("LEADSTO", "then", "leads to next", "+")

        store1 = MemoryStore()
        mem_vertex!(store1, "Foo", "ch1")
        mem_vertex!(store1, "Bar", "ch1")
        mem_edge!(store1, mem_get_nodes_by_name(store1, "Foo")[1], "then",
                  mem_get_nodes_by_name(store1, "Bar")[1])

        turtle = export_turtle(store1)

        store2 = MemoryStore()
        import_turtle!(store2, turtle; chapter="ch1")

        @test !isempty(mem_get_nodes_by_name(store2, "Foo"))
        @test !isempty(mem_get_nodes_by_name(store2, "Bar"))
        @test link_count(store2) > 0
    end

    @testset "custom namespace" begin
        SemanticSpacetime.reset_arrows!()
        SemanticSpacetime.reset_contexts!()

        insert_arrow!("LEADSTO", "then", "leads to next", "+")

        ns = sst_namespace("http://myproject.org/kg")
        store = MemoryStore()
        n1 = mem_vertex!(store, "X", "ch1")
        n2 = mem_vertex!(store, "Y", "ch1")
        mem_edge!(store, n1, "then", n2)

        triples = sst_to_rdf(store; namespace=ns)
        @test all(t -> !startswith(t.subject, "http://sst.example.org/") || !SemanticSpacetime._is_uri(t.subject), triples)
        # All node URIs should use the custom namespace
        node_triples = filter(t -> t.predicate == SemanticSpacetime.RDF_TYPE && t.object == ns.vocab * "Node", triples)
        for t in node_triples
            @test startswith(t.subject, "http://myproject.org/kg/node/")
        end
    end

    @testset "custom predicate mapping" begin
        SemanticSpacetime.reset_arrows!()
        SemanticSpacetime.reset_contexts!()

        insert_arrow!("EXPRESS", "color", "has color", "+")

        ns = sst_namespace()
        custom_map = Dict{String, PredicateMapping}(
            "http://example.org/hasColor" => PredicateMapping("http://example.org/hasColor", "color", "EXPRESS", "+")
        )

        triples = [
            RDFTriple("http://example.org/Apple", SemanticSpacetime.RDFS_LABEL, "Apple"),
            RDFTriple("http://example.org/Red", SemanticSpacetime.RDFS_LABEL, "Red"),
            RDFTriple("http://example.org/Apple", "http://example.org/hasColor", "http://example.org/Red"),
        ]

        store = MemoryStore()
        rdf_to_sst!(store, triples; namespace=ns, chapter="fruits", predicate_map=custom_map)

        @test node_count(store) == 2
        @test link_count(store) > 0
    end

    # Clean up global state
    SemanticSpacetime.reset_arrows!()
    SemanticSpacetime.reset_contexts!()
end
