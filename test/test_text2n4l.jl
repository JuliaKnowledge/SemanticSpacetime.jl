@testset "Text2N4L" begin
    @testset "TextRank construction" begin
        tr = SemanticSpacetime.TextRank(1.5, "hello world", 1, 0)
        @test tr.significance == 1.5
        @test tr.fragment == "hello world"
        @test tr.order == 1
        @test tr.partition == 0
    end

    @testset "TextSignificance construction" begin
        ts = SemanticSpacetime.TextSignificance()
        @test isempty(ts.ngram_freq)
        @test isempty(ts.ngram_last)
        @test ts.total_sentences == 0
    end

    @testset "clean_text" begin
        @test SemanticSpacetime.clean_text("<p>Hello</p>") == ":\nHello:\n"
        @test SemanticSpacetime.clean_text("No [tags]") == "No tags"
    end

    @testset "split_sentences" begin
        sents = SemanticSpacetime.split_sentences("Hello world. This is a test. And another one!")
        @test length(sents) == 3
        @test sents[1] == "Hello world."
        @test sents[2] == "This is a test."
        @test sents[3] == "And another one!"

        # Newline splitting
        sents2 = SemanticSpacetime.split_sentences("Line one\nLine two\nLine three")
        @test length(sents2) == 3
    end

    @testset "extract_ngrams" begin
        words = ["the", "quick", "brown", "fox"]
        @test SemanticSpacetime.extract_ngrams(words, 1) == ["the", "quick", "brown", "fox"]
        @test SemanticSpacetime.extract_ngrams(words, 2) == ["the quick", "quick brown", "brown fox"]
        @test SemanticSpacetime.extract_ngrams(words, 3) == ["the quick brown", "quick brown fox"]
        @test isempty(SemanticSpacetime.extract_ngrams(words, 5))
    end

    @testset "score_sentence" begin
        vocab = Dict("the" => 50, "quantum" => 3, "physics" => 5, "is" => 40, "a" => 45)

        # Words appearing a moderate number of times should score higher
        score1 = SemanticSpacetime.score_sentence("quantum physics", vocab)
        @test score1 > 0.0

        # Very common words should score differently than rare ones
        score2 = SemanticSpacetime.score_sentence("the is a", vocab)
        @test score2 > 0.0  # Common words still score, but differently

        # Empty sentence
        @test SemanticSpacetime.score_sentence("", vocab) == 0.0

        # Words not in vocab (freq=0, below threshold) should contribute 0
        score3 = SemanticSpacetime.score_sentence("nonexistent words", vocab)
        @test score3 == 0.0
    end

    @testset "static_intentionality" begin
        # Below threshold
        @test SemanticSpacetime.static_intentionality(100, "word", 1.0) == 0.0

        # Above threshold
        val = SemanticSpacetime.static_intentionality(100, "quantum", 5.0)
        @test val > 0.0

        # Higher frequency → different score
        val2 = SemanticSpacetime.static_intentionality(100, "quantum", 10.0)
        @test val2 != val
    end

    @testset "build_vocab" begin
        sentences = ["the cat sat", "the dog sat on the mat"]
        vocab = SemanticSpacetime.build_vocab(sentences)
        @test vocab["the"] == 3
        @test vocab["sat"] == 2
        @test vocab["cat"] == 1
        @test vocab["mat"] == 1
    end

    @testset "extract_significant_sentences" begin
        # Generate enough text for meaningful analysis
        text = """
        The theory of quantum mechanics is fundamental to modern physics.
        It describes the behavior of particles at the atomic scale.
        Classical mechanics fails to explain quantum phenomena.
        Quantum entanglement is one of the strangest features.
        The double slit experiment demonstrates wave-particle duality.
        Heisenberg's uncertainty principle limits measurement precision.
        Schrodinger's equation governs quantum state evolution.
        The Copenhagen interpretation is widely accepted.
        """

        result = SemanticSpacetime.extract_significant_sentences(text; target_percent=50.0)
        @test !isempty(result)
        @test length(result) <= 8  # at most all sentences
        @test all(s -> !isempty(s), result)

        # Very small target should return fewer
        result2 = SemanticSpacetime.extract_significant_sentences(text; target_percent=10.0)
        @test length(result2) <= length(result)
    end

    @testset "sanitize_n4l" begin
        @test SemanticSpacetime.sanitize_n4l("hello (world)") == "hello [world]"
        @test SemanticSpacetime.sanitize_n4l("no parens") == "no parens"
    end

    @testset "text_to_n4l" begin
        text = """
        Quantum mechanics describes nature at the smallest scales.
        Energy levels are quantized in atoms.
        The photoelectric effect confirms photon theory.
        Wave functions collapse upon measurement.
        """

        n4l = SemanticSpacetime.text_to_n4l(text; chapter="quantum", target_percent=50.0)

        @test occursin("_sequence_", n4l)
        @test occursin("quantum", n4l)
        @test occursin("(begin)", n4l)
        @test occursin("(end)", n4l)
        @test occursin("@sen", n4l)
        @test occursin(SemanticSpacetime.INV_CONT_FOUND_IN_S, n4l)
        @test occursin("Final fraction", n4l)
        @test occursin("Selected", n4l)
    end

    @testset "text_to_n4l default chapter" begin
        n4l = SemanticSpacetime.text_to_n4l("Hello world. This is a test sentence with enough words.")
        @test occursin("document", n4l)
    end

    @testset "select_by_significance" begin
        ranks = [
            SemanticSpacetime.TextRank(10.0, "high", 3, 0),
            SemanticSpacetime.TextRank(5.0, "medium", 1, 0),
            SemanticSpacetime.TextRank(1.0, "low", 2, 0),
        ]

        selected = SemanticSpacetime.select_by_significance(ranks, 50.0)
        # Should select ~50% (1-2 of 3), highest scoring first
        @test length(selected) >= 1
        @test length(selected) <= 2
        # Should be in document order (by order field)
        if length(selected) > 1
            @test selected[1].order < selected[2].order
        end

        # Empty input
        @test isempty(SemanticSpacetime.select_by_significance(SemanticSpacetime.TextRank[], 50.0))
    end
end
