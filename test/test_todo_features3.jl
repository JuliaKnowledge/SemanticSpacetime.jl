config_dir = let d = joinpath(@__DIR__, "..", "..", "SSTorytime", "SSTconfig")
    isdir(d) ? d : nothing
end
SemanticSpacetime.reset_arrows!()
add_mandatory_arrows!()
if config_dir !== nothing
    st = SemanticSpacetime.N4LState()
    for cf in read_config_files(config_dir)
        SemanticSpacetime.parse_config_file(cf; st=st)
    end
end

@testset "Log Data Analysis Pipeline" begin
    @testset "default_log_config" begin
        cfg = default_log_config()
        @test cfg.format == LOG_SYSLOG
        @test cfg.chapter == "logs"
        @test cfg.link_sequential == true
        @test isempty(cfg.extract_patterns)
    end

    @testset "parse_syslog_line" begin
        line = "Jan 15 10:30:45 myhost sshd[1234]: Accepted password for user"
        parsed = parse_syslog_line(line)
        @test parsed.timestamp == "Jan 15 10:30:45"
        @test parsed.source == "myhost"
        @test parsed.service == "sshd"
        @test parsed.pid == "1234"
        @test parsed.message == "Accepted password for user"

        # Without PID
        line2 = "Feb  3 08:00:00 server cron: running job"
        parsed2 = parse_syslog_line(line2)
        @test parsed2.source == "server"
        @test parsed2.service == "cron"
        @test parsed2.pid == ""
        @test parsed2.message == "running job"

        # Malformed line fallback
        parsed3 = parse_syslog_line("not a syslog line")
        @test parsed3.message == "not a syslog line"
    end

    @testset "parse_json_log_line" begin
        line = """{"timestamp":"2024-01-15T10:30:45Z","level":"ERROR","message":"disk full","source":"web1"}"""
        parsed = parse_json_log_line(line)
        @test parsed.timestamp == "2024-01-15T10:30:45Z"
        @test parsed.level == "ERROR"
        @test parsed.message == "disk full"
        @test parsed.source == "web1"

        # Empty line
        empty_parsed = parse_json_log_line("")
        @test empty_parsed.message == ""
    end

    @testset "parse_csv_log" begin
        csv = """timestamp,level,message,source
2024-01-15,ERROR,disk full,web1
2024-01-16,WARN,high load,web2"""
        entries = parse_csv_log(csv)
        @test length(entries) == 2
        @test entries[1].timestamp == "2024-01-15"
        @test entries[1].level == "ERROR"
        @test entries[1].message == "disk full"
        @test entries[1].source == "web1"
        @test entries[2].level == "WARN"

        # TSV
        tsv = "timestamp\tlevel\tmessage\n2024-01-15\tINFO\tstarted\n"
        entries2 = parse_csv_log(tsv; delimiter='\t')
        @test length(entries2) == 1
        @test entries2[1].message == "started"

        # No header
        raw = "2024-01-15,disk full\n2024-01-16,all clear\n"
        entries3 = parse_csv_log(raw; header=false)
        @test length(entries3) == 2
        @test entries3[1].timestamp == "2024-01-15"
    end

    @testset "parse_log_to_sst! syslog" begin
        store = MemoryStore()
        syslog_text = """Jan 15 10:30:45 host1 sshd[100]: login accepted
Jan 15 10:30:46 host1 sshd[100]: session opened
Jan 15 10:31:00 host2 cron: job started"""
        stats = parse_log_to_sst!(store, syslog_text)
        @test stats["entries_parsed"] == 3
        @test stats["nodes_created"] >= 3
        # Sequential links should exist
        if get_arrow_by_name("then") !== nothing
            @test stats["links_created"] >= 2  # at least 2 LEADSTO links
        end
    end

    @testset "parse_log_to_sst! JSON" begin
        store = MemoryStore()
        json_text = """{"timestamp":"2024-01-15","level":"ERROR","message":"fail1","source":"s1"}
{"timestamp":"2024-01-16","level":"WARN","message":"fail2","source":"s2"}"""
        cfg = LogParseConfig(LOG_JSON, "timestamp", "message", "level", "source",
                             "json_logs", true, Regex[])
        stats = parse_log_to_sst!(store, json_text; config=cfg)
        @test stats["entries_parsed"] == 2
        @test stats["nodes_created"] >= 2
    end

    @testset "parse_log_to_sst! with patterns" begin
        store = MemoryStore()
        syslog_text = "Jan 15 10:30:45 host1 app[1]: error code=42 ip=10.0.0.1\n"
        cfg = LogParseConfig(LOG_SYSLOG, "timestamp", "message", "level", "source",
                             "logs", false, [r"code=\d+", r"ip=[\d.]+"])
        stats = parse_log_to_sst!(store, syslog_text; config=cfg)
        @test stats["entries_parsed"] == 1
        if get_arrow_by_name("note") !== nothing
            @test stats["links_created"] >= 1
        end
    end
end

@testset "Text Breakdown Assistant" begin
    @testset "EntitySuggestion construction" begin
        e = EntitySuggestion("Alice", :person, 0.9, 1:5)
        @test e.text == "Alice"
        @test e.entity_type == :person
        @test e.confidence == 0.9
        @test e.span == 1:5
    end

    @testset "LinkSuggestion construction" begin
        l = LinkSuggestion("Alice", "Bob", "then", LEADSTO, 0.8)
        @test l.source == "Alice"
        @test l.target == "Bob"
        @test l.sttype == LEADSTO
    end

    @testset "identify_entities" begin
        text = "Alice and Bob visited London on 2024-01-15."
        entities = identify_entities(text)
        @test !isempty(entities)

        names = [e.text for e in entities]
        # Should find the date
        @test any(e -> e.entity_type == :event && occursin("2024", e.text), entities)
        # Should find capitalized proper nouns (Alice, Bob, London)
        proper = filter(e -> e.entity_type == :person, entities)
        proper_names = [e.text for e in proper]
        @test "Alice" in proper_names || "Bob" in proper_names || "London" in proper_names
    end

    @testset "identify_entities quoted concepts" begin
        text = """The concept of "machine learning" is important."""
        entities = identify_entities(text)
        concepts = filter(e -> e.entity_type == :concept, entities)
        @test any(e -> e.text == "machine learning", concepts)
    end

    @testset "identify_entities abstract suffixes" begin
        text = "The motivation and development of the organization."
        entities = identify_entities(text)
        abstract_concepts = filter(e -> e.entity_type == :concept, entities)
        abstract_texts = [e.text for e in abstract_concepts]
        @test "motivation" in abstract_texts || "development" in abstract_texts || "organization" in abstract_texts
    end

    @testset "identify_entities temporal" begin
        text = "We met on Monday in January."
        entities = identify_entities(text)
        events = filter(e -> e.entity_type == :event, entities)
        event_texts = map(e -> lowercase(e.text), events)
        @test "monday" in event_texts || "january" in event_texts || "Monday" in [e.text for e in events] || "January" in [e.text for e in events]
    end

    @testset "suggest_links" begin
        text = "Alice causes Bob to react."
        entities = [
            EntitySuggestion("Alice", :person, 0.9, 1:5),
            EntitySuggestion("Bob", :person, 0.9, 14:16),
        ]
        links = suggest_links(text, entities)
        @test length(links) >= 1
        @test links[1].sttype == LEADSTO
        @test links[1].arrow_name == "then"
    end

    @testset "suggest_links contains" begin
        text = "The box contains the ball."
        entities = [
            EntitySuggestion("box", :thing, 0.7, 5:7),
            EntitySuggestion("ball", :thing, 0.7, 22:25),
        ]
        links = suggest_links(text, entities)
        @test length(links) >= 1
        @test links[1].sttype == CONTAINS
    end

    @testset "suggest_links near" begin
        text = "Cats are similar to dogs."
        entities = [
            EntitySuggestion("Cats", :thing, 0.7, 1:4),
            EntitySuggestion("dogs", :thing, 0.7, 20:23),
        ]
        links = suggest_links(text, entities)
        @test length(links) >= 1
        @test links[1].sttype == NEAR
    end

    @testset "suggest_links too few entities" begin
        links = suggest_links("hello", EntitySuggestion[])
        @test isempty(links)
        links2 = suggest_links("hello", [EntitySuggestion("x", :thing, 0.5, 1:1)])
        @test isempty(links2)
    end

    @testset "propose_structure" begin
        text = "Alice causes Bob to react. The result is dramatic."
        tb = propose_structure(text; chapter="test_chapter")
        @test tb.original == text
        @test !isempty(tb.sentences)
        @test tb isa TextBreakdown
        @test !isempty(tb.n4l_suggestion)
    end

    @testset "breakdown_to_n4l" begin
        tb = TextBreakdown(
            "Alice causes Bob to react.",
            ["Alice causes Bob to react."],
            [EntitySuggestion("Alice", :person, 0.9, 1:5),
             EntitySuggestion("Bob", :person, 0.9, 14:16)],
            [LinkSuggestion("Alice", "Bob", "then", LEADSTO, 0.7)],
            "",
        )
        n4l = breakdown_to_n4l(tb; chapter="my_chapter")
        @test occursin("my_chapter", n4l)
        @test occursin("Alice", n4l)
        @test occursin("Bob", n4l)
        @test occursin("then", n4l)
    end
end
