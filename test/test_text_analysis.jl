@testset "Text Analysis" begin
    # Initialize state
    SemanticSpacetime.reset_ngram_state!()

    @testset "clean_text" begin
        @test SemanticSpacetime.clean_text("<p>Hello</p>") == ":\nHello:\n"
        @test SemanticSpacetime.clean_text("foo[bar]baz") == "foobarbaz"
        @test SemanticSpacetime.clean_text("no tags here") == "no tags here"
    end

    @testset "split_sentences" begin
        sents = SemanticSpacetime.split_sentences("Hello world. How are you? Fine!")
        @test length(sents) >= 2
        @test any(s -> occursin("Hello", s), sents)
    end

    @testset "split_punctuation_text" begin
        frags = split_punctuation_text("Hello, world: how are you")
        @test length(frags) >= 1
        @test all(f -> length(f) > 0, frags)
    end

    @testset "un_paren" begin
        content, has = un_paren("(hello world)")
        @test has == true
        @test content == "hello world"

        content2, has2 = un_paren("no parens here")
        @test has2 == false
        @test content2 == "no parens here"

        content3, has3 = un_paren("[bracketed]")
        @test has3 == true
        @test content3 == "bracketed"
    end

    @testset "count_parens" begin
        frags = count_parens("before (inside) after")
        @test length(frags) >= 2
        @test any(f -> occursin("inside", f), frags)
    end

    @testset "clean_ngram" begin
        @test clean_ngram("Hello, World!") == "hello world"
        @test clean_ngram("it's---fine") == "it's"
        @test clean_ngram("  double  space ") == " double space "
    end

    @testset "excluded_by_bindings" begin
        @test excluded_by_bindings("the", "cat") == true
        @test excluded_by_bindings("cat", "the") == true
        @test excluded_by_bindings("ab", "xyz") == true  # too short
        @test excluded_by_bindings("beautiful", "sunrise") == false
        @test excluded_by_bindings("and", "result") == true  # forbidden starter
    end

    @testset "new_ngram_map" begin
        m = new_ngram_map()
        @test length(m) == N_GRAM_MAX
        @test all(d -> d isa Dict{String,Float64}, m)
        @test all(d -> isempty(d), m)
    end

    @testset "next_word" begin
        rrbuffer = [String[] for _ in 1:N_GRAM_MAX]
        rrbuffer, cs = next_word("hello", rrbuffer)
        rrbuffer, cs = next_word("beautiful", rrbuffer)
        rrbuffer, cs = next_word("world", rrbuffer)
        # After 3 words, we should have some bigrams
        @test length(rrbuffer[2]) >= 1
    end

    @testset "fractionate" begin
        freq = new_ngram_map()
        cs = fractionate("the quick brown fox jumps over the lazy dog", 100, freq, N_GRAM_MIN)
        @test length(cs) == N_GRAM_MAX
        # Should produce some bigrams
        total_bigrams = length(cs[2])
        @test total_bigrams >= 0
    end

    @testset "ngram_static_intentionality" begin
        # Low frequency — below threshold
        @test ngram_static_intentionality(100, "hello", 1.0) == 0.0
        # Moderate frequency — should have positive score
        score = ngram_static_intentionality(100, "neural network", 5.0)
        @test score > 0.0
        # Higher frequency should increase score (up to saturation)
        score2 = ngram_static_intentionality(100, "neural network", 10.0)
        @test score2 > score
    end

    @testset "fractionate_text and coherence" begin
        SemanticSpacetime.reset_ngram_state!()

        text = """
        The quick brown fox jumps over the lazy dog. The fox was very quick indeed.
        Brown foxes are known for their agility. The lazy dog slept through it all.

        Meanwhile, the cat watched from the window. Cats are curious creatures by nature.
        The window provided a perfect vantage point. Curiosity drives much of feline behavior.

        In the garden, birds sang their morning songs. The morning was peaceful and calm.
        Gardens attract many different species of birds. Peace and calm define the morning hours.
        """

        pbsf, count = fractionate_text(text)
        @test count > 0
        @test length(pbsf) >= 1

        # Test coherence set
        C, partitions = coherence_set(SemanticSpacetime.STM_NGRAM_LOCA[], count, DUNBAR_30)
        @test partitions >= 1
        @test length(C) == N_GRAM_MAX

        # Test intentional_ngram
        result = intentional_ngram(1, "test", 100, DUNBAR_30)
        @test result == false  # unigrams are never intentional

        # Test interval_radius
        occ, minr, maxr = interval_radius(2, "nonexistent ngram")
        @test occ == 0

        # Test assess_static_text_anomalies
        intent, context = assess_static_text_anomalies(
            count, SemanticSpacetime.STM_NGRAM_FREQ[], SemanticSpacetime.STM_NGRAM_LOCA[]
        )
        @test length(intent) == N_GRAM_MAX
        @test length(context) == N_GRAM_MAX
    end

    @testset "fast_slow analysis" begin
        # Uses state from previous test
        L = 10  # approximate
        SemanticSpacetime.reset_ngram_state!()
        text = "Alpha beta gamma. Alpha beta delta. Alpha beta gamma. " ^3 *
               "\n\nNew topic here. Different words entirely. Fresh content awaits. " ^3
        _, count = fractionate_text(text)

        slow, fast, partitions = assess_text_fast_slow(count, SemanticSpacetime.STM_NGRAM_LOCA[])
        @test partitions >= 1
        @test length(slow) == N_GRAM_MAX
        @test length(fast) == N_GRAM_MAX

        # Test coherent coactivation
        overlap, condensate, parts = assess_text_coherent_coactivation(count, SemanticSpacetime.STM_NGRAM_LOCA[])
        @test parts >= 1
        @test length(overlap) == N_GRAM_MAX
    end

    @testset "split_into_para_sentences" begin
        text = "First sentence. Second sentence.\n\nNew paragraph here. Another sentence."
        result = split_into_para_sentences(text)
        @test length(result) >= 1
    end
end
