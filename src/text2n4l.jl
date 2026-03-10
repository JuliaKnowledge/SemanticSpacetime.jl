#=
Plain text to N4L format converter for Semantic Spacetime.

Scans a document and extracts sentences measured to be high in
"intentionality" or potential knowledge significance, using both
dynamic running patterns and static post-hoc assessment.

Ported from SSTorytime/src/text2N4L.go and the text fractionation
functions in SSTorytime/pkg/SSTorytime/SSTorytime.go.
=#

# ──────────────────────────────────────────────────────────────────
# Constants
# ──────────────────────────────────────────────────────────────────

const DUNBAR_30 = 45
const DUNBAR_150 = 150
const STATIC_IGNORE_THRESHOLD = 2
const STATIC_RHO = 1 / 30.0

# ──────────────────────────────────────────────────────────────────
# TextRank and TextSignificance
# ──────────────────────────────────────────────────────────────────

"""
    TextRank

A sentence with its computed significance score and original ordering.
"""
struct TextRank
    significance::Float64
    fragment::String
    order::Int
    partition::Int
end

"""
    TextSignificance

Tracks word/n-gram frequencies and last-seen positions for
computing intentionality scores during text analysis.
"""
mutable struct TextSignificance
    ngram_freq::Dict{String,Float64}
    ngram_last::Dict{String,Int}
    total_sentences::Int
end

TextSignificance() = TextSignificance(Dict{String,Float64}(), Dict{String,Int}(), 0)

# ──────────────────────────────────────────────────────────────────
# Text cleaning and splitting
# ──────────────────────────────────────────────────────────────────

"""
    clean_text(s::AbstractString) -> String

Strip HTML/XML tags and normalise whitespace.
"""
function clean_text(s::AbstractString)
    # Strip HTML/XML tags
    s = replace(s, r"<[^>]*>" => ":\n")
    # Remove brackets
    s = replace(s, '[' => "")
    s = replace(s, ']' => "")
    return s
end

"""
    split_sentences(text::AbstractString) -> Vector{String}

Split text into individual sentences on '.', '!' , '?', and newline boundaries.
Returns non-empty, stripped sentences.
"""
function split_sentences(text::AbstractString)
    # Split on sentence-ending punctuation followed by whitespace or newlines
    raw = split(text, r"(?<=[.!?])\s+|\n+")
    sentences = String[]
    for s in raw
        s = strip(String(s))
        !isempty(s) && push!(sentences, s)
    end
    return sentences
end

"""
    extract_ngrams(words::Vector{<:AbstractString}, n::Int) -> Vector{String}

Extract n-grams from a word list.
"""
function extract_ngrams(words::Vector{<:AbstractString}, n::Int)
    ngrams = String[]
    length(words) < n && return ngrams
    for i in 1:(length(words) - n + 1)
        push!(ngrams, join(words[i:i+n-1], " "))
    end
    return ngrams
end

# ──────────────────────────────────────────────────────────────────
# Intentionality scoring
# ──────────────────────────────────────────────────────────────────

"""
    static_intentionality(total_sentences::Int, ngram::String, freq::Float64) -> Float64

Compute the static significance of an n-gram based on its frequency
in the document. Uses an exponential deprecation based on SST cognitive
scales (Dunbar numbers).
"""
function static_intentionality(total_sentences::Int, ngram::String, freq::Float64)
    work = Float64(length(ngram))
    freq < STATIC_IGNORE_THRESHOLD && return 0.0

    phi = freq
    phi_0 = Float64(DUNBAR_30)
    crit = phi / phi_0 - STATIC_RHO
    meaning = phi * work / (1.0 + exp(crit))
    return meaning
end

"""
    score_sentence(text::String, vocab::Dict{String,Int}) -> Float64

Compute an intentionality score for a sentence given a vocabulary
of word frequencies. Higher scores indicate more distinctive/meaningful
sentences.

Uses a simplified static intentionality model: words that appear
a moderate number of times (not too rare, not too common) in the
corpus score highest.
"""
function score_sentence(text::String, vocab::Dict{String,Int})
    words = split(lowercase(text))
    isempty(words) && return 0.0
    total = max(sum(values(vocab)), 1)

    score = 0.0
    for word in words
        freq = Float64(get(vocab, String(word), 0))
        score += static_intentionality(total, String(word), freq)
    end
    return score
end

"""
    build_vocab(sentences::Vector{String}) -> Dict{String,Int}

Build a word frequency vocabulary from a list of sentences.
"""
function build_vocab(sentences::Vector{String})
    vocab = Dict{String,Int}()
    for sent in sentences
        for word in split(lowercase(sent))
            w = String(word)
            vocab[w] = get(vocab, w, 0) + 1
        end
    end
    return vocab
end

# ──────────────────────────────────────────────────────────────────
# Selection algorithms
# ──────────────────────────────────────────────────────────────────

"""
    running_intentionality_score(sentence_idx::Int, text::String,
                                 sig::TextSignificance) -> Float64

Compute a running intentionality score for a sentence, accounting
for temporal decay of previously-seen n-grams.
"""
function running_intentionality_score(sentence_idx::Int, text::String,
                                      sig::TextSignificance)
    words = split(lowercase(text))
    isempty(words) && return 0.0
    decayrate = Float64(DUNBAR_30)
    score = 0.0

    for word in words
        w = String(word)
        work = Float64(length(w))
        lastseen = get(sig.ngram_last, w, 0)
        if lastseen == 0
            score += work
        else
            score += work * (1 - exp(-Float64(sentence_idx - lastseen) / decayrate))
        end
        sig.ngram_last[w] = sentence_idx
        sig.ngram_freq[w] = get(sig.ngram_freq, w, 0.0) + 1.0
    end
    return score
end

"""
    select_by_significance(ranked::Vector{TextRank}, percentage::Float64) -> Vector{TextRank}

Select the top `percentage` of sentences by significance score,
then re-sort by original document order.
"""
function select_by_significance(ranked::Vector{TextRank}, percentage::Float64)
    isempty(ranked) && return TextRank[]

    sorted = sort(ranked, by=r -> -r.significance)
    threshold = percentage / 100.0
    limit = max(1, round(Int, threshold * length(sorted)))
    selected = sorted[1:min(limit, length(sorted))]

    # Restore document order
    return sort(selected, by=r -> r.order)
end

# ──────────────────────────────────────────────────────────────────
# Public API
# ──────────────────────────────────────────────────────────────────

"""
    extract_significant_sentences(text::String; target_percent::Float64=50.0) -> Vector{String}

Extract the most significant sentences from a text, combining both
running and static intentionality analysis. Returns approximately
`target_percent` of the original sentences (merged from both methods).
"""
function extract_significant_sentences(text::String; target_percent::Float64=50.0)
    cleaned = clean_text(text)
    sentences = split_sentences(cleaned)
    isempty(sentences) && return String[]

    vocab = build_vocab(sentences)
    coherence_length = DUNBAR_30
    total = length(sentences)

    # Running intentionality ranking
    sig = TextSignificance()
    running_ranks = TextRank[]
    for (idx, sent) in enumerate(sentences)
        score = running_intentionality_score(idx, sent, sig)
        partition = (idx - 1) ÷ coherence_length
        push!(running_ranks, TextRank(score, sent, idx, partition))
    end
    selection1 = select_by_significance(running_ranks, target_percent)

    # Static intentionality ranking
    static_ranks = TextRank[]
    for (idx, sent) in enumerate(sentences)
        score = score_sentence(sent, vocab)
        partition = (idx - 1) ÷ coherence_length
        push!(static_ranks, TextRank(score, sent, idx, partition))
    end
    selection2 = select_by_significance(static_ranks, target_percent)

    # Merge selections, deduplicate by order
    seen = Set{Int}()
    merged = TextRank[]
    for tr in selection1
        if !(tr.order in seen)
            push!(merged, tr)
            push!(seen, tr.order)
        end
    end
    for tr in selection2
        if !(tr.order in seen)
            push!(merged, tr)
            push!(seen, tr.order)
        end
    end

    # Restore document order
    sort!(merged, by=r -> r.order)
    return [tr.fragment for tr in merged]
end

"""
    sanitize_n4l(s::AbstractString) -> String

Replace parentheses with brackets for N4L output (parentheses are reserved).
"""
function sanitize_n4l(s::AbstractString)
    return replace(replace(s, '(' => '['), ')' => ']')
end

"""
    text_to_n4l(text::String; chapter::String="", target_percent::Float64=50.0) -> String

Convert plain text to N4L format output. Extracts the most significant
sentences and formats them as N4L notation with chapter structure,
sequence markers, and extract relationships.

Returns the N4L formatted string.
"""
function text_to_n4l(text::String; chapter::String="", target_percent::Float64=50.0)
    filealias = isempty(chapter) ? "document" : chapter
    selection = extract_significant_sentences(text; target_percent=target_percent)

    io = IOBuffer()

    println(io, " - Samples from $(filealias)")
    println(io)
    println(io, "# (begin) ************")
    println(io)
    println(io, " :: _sequence_ , $(filealias)::")
    println(io)

    for (i, sent) in enumerate(selection)
        part = "part $((i - 1) ÷ DUNBAR_30) of $(filealias)"
        println(io, "@sen$(i)   $(sanitize_n4l(sent))")
        println(io, "              \" ($(INV_CONT_FOUND_IN_S)) $(part)")
        println(io)
    end

    println(io, " -:: _sequence_ , $(filealias)::")
    println(io)
    println(io, "# (end) ************")
    println(io)

    total = length(split_sentences(clean_text(text)))
    actual_pct = total > 0 ? length(selection) * 100.0 / total : 0.0
    println(io, "# Final fraction $(round(actual_pct, digits=2)) of requested $(target_percent)")
    println(io, "# Selected $(length(selection)) samples of $(total)")

    return String(take!(io))
end
