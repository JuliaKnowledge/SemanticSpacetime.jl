#=
Advanced n-gram text analysis for Semantic Spacetime.

Provides text fractionation, n-gram frequency/location tracking,
intentionality scoring, coherence analysis, and fast/slow rhythm separation.

Ported from SSTorytime/pkg/SSTorytime/SSTorytime.go.
=#

# ──────────────────────────────────────────────────────────────────
# Constants (DUNBAR_30 and DUNBAR_150 are in text2n4l.jl)
# ──────────────────────────────────────────────────────────────────

const N_GRAM_MAX = 6
const N_GRAM_MIN = 2
const DUNBAR_5 = 5
const DUNBAR_15 = 15
# DUNBAR_30 = 45 is already defined in text2n4l.jl
# DUNBAR_150 = 150 is already defined in text2n4l.jl

# ──────────────────────────────────────────────────────────────────
# Module-level n-gram state
# ──────────────────────────────────────────────────────────────────

const STM_NGRAM_FREQ = Ref{Vector{Dict{String,Float64}}}()
const STM_NGRAM_LOCA = Ref{Vector{Dict{String,Vector{Int}}}}()
const STM_NGRAM_LAST = Ref{Vector{Dict{String,Int}}}()

"""
    reset_ngram_state!()

Initialize (or reset) the module-level n-gram frequency, location, and
last-seen tracking maps. Each is a Vector of N_GRAM_MAX Dicts.
"""
function reset_ngram_state!()
    STM_NGRAM_FREQ[] = [Dict{String,Float64}() for _ in 1:N_GRAM_MAX]
    STM_NGRAM_LOCA[] = [Dict{String,Vector{Int}}() for _ in 1:N_GRAM_MAX]
    STM_NGRAM_LAST[] = [Dict{String,Int}() for _ in 1:N_GRAM_MAX]
end

"""
    new_ngram_map() -> Vector{Dict{String,Float64}}

Create a fresh n-gram frequency map (vector of N_GRAM_MAX empty dicts).
"""
function new_ngram_map()::Vector{Dict{String,Float64}}
    return [Dict{String,Float64}() for _ in 1:N_GRAM_MAX]
end

# ──────────────────────────────────────────────────────────────────
# Text splitting and cleaning
# ──────────────────────────────────────────────────────────────────

"""
    split_into_para_sentences(text::AbstractString) -> Vector{Vector{Vector{String}}}

Split text into paragraphs → sentences → fragments.
Returns a 3-level nested structure: paragraphs of sentences of fragment strings.
"""
function split_into_para_sentences(text::AbstractString)::Vector{Vector{Vector{String}}}
    result = Vector{Vector{Vector{String}}}()
    paras = split(text, "\n\n")

    for p in paras
        p = strip(String(p))
        isempty(p) && continue
        sentences = split_sentences_para(p)
        cleaned = Vector{Vector{String}}()

        for sent in sentences
            frags = split_punctuation_text(sent)
            codons = String[]
            for f in frags
                content = strip(f)
                length(content) > 2 && push!(codons, String(content))
            end
            !isempty(codons) && push!(cleaned, codons)
        end

        !isempty(cleaned) && push!(result, cleaned)
    end

    return result
end

"""
    split_sentences_para(para::AbstractString) -> Vector{String}

Split a paragraph into sentences on sentence-ending punctuation followed by whitespace.
Merges short fragments (< 10 chars) with the next sentence.
"""
function split_sentences_para(para::AbstractString)::Vector{String}
    small_string = 10
    # Insert delimiter after sentence-ending punctuation followed by whitespace
    marked = replace(String(para), r"([?!.。])([ \n\t])" => s"\1\2#")
    parts = split(marked, "#")

    sentences = String[]
    buf = ""
    for (i, part) in enumerate(parts)
        if i < length(parts) && length(part) < small_string
            buf *= String(part)
            continue
        end
        buf *= String(part)
        buf = replace(buf, '\n' => ' ')
        push!(sentences, buf)
        buf = ""
    end
    return sentences
end

"""
    split_punctuation_text(s::AbstractString) -> Vector{String}

Split text on intentional separators (quotes, dashes, colons, etc.),
respecting balanced parentheses.
"""
function split_punctuation_text(s::AbstractString)::Vector{String}
    subfrags = String[]
    frags = count_parens(String(s))

    for frag in frags
        contents, hasparen = un_paren(frag)

        if hasparen
            push!(subfrags, frag)
            # Recurse into parenthesized contents (but don't repeat)
            continue
        end

        sfrags = split(contents, r"[\"—\u201c\u201d!?,:;\u2014]+([ \n])")
        for sf in sfrags
            sf_str = strip(String(sf))
            !isempty(sf_str) && length(sf_str) > 1 && push!(subfrags, sf_str)
        end
    end

    return subfrags
end

"""
    un_paren(s::AbstractString) -> Tuple{String, Bool}

If `s` is wrapped in matching brackets/parens, return the inner content and true.
Otherwise return trimmed `s` and false.
"""
function un_paren(s::AbstractString)::Tuple{String,Bool}
    isempty(s) && return (String(s), false)
    first_char = s[1]
    counter = ' '
    if first_char == '('
        counter = ')'
    elseif first_char == '['
        counter = ']'
    elseif first_char == '{'
        counter = '}'
    end

    if counter != ' '
        if s[end] == counter
            trimmed = strip(String(s[nextind(s,1):prevind(s,lastindex(s))]))
            return (trimmed, true)
        end
    end
    return (strip(String(s)), false)
end

"""
    count_parens(s::AbstractString) -> Vector{String}

Split text respecting balanced parentheses/brackets/braces.
Returns fragments where parenthesized groups are kept intact.
"""
function count_parens(s::AbstractString)::Vector{String}
    text = collect(strip(String(s)))
    isempty(text) && return String[]

    match_char = ' '
    counts = Dict{Char,Int}()
    subfrags = String[]
    fragstart = 1

    for i in eachindex(text)
        ch = text[i]
        if ch == '('
            counts[')'] = get(counts, ')', 0) + 1
            if match_char == ' '
                match_char = ')'
                frag = strip(String(text[fragstart:i-1]))
                fragstart = i
                !isempty(frag) && push!(subfrags, frag)
            end
        elseif ch == '['
            counts[']'] = get(counts, ']', 0) + 1
            if match_char == ' '
                match_char = ']'
                frag = strip(String(text[fragstart:i-1]))
                fragstart = i
                !isempty(frag) && push!(subfrags, frag)
            end
        elseif ch == '{'
            counts['}'] = get(counts, '}', 0) + 1
            if match_char == ' '
                match_char = '}'
                frag = strip(String(text[fragstart:i-1]))
                fragstart = i
                !isempty(frag) && push!(subfrags, frag)
            end
        elseif ch in (')', ']', '}')
            counts[ch] = get(counts, ch, 0) - 1
            if get(counts, match_char, 0) == 0
                frag = String(text[fragstart:i])
                fragstart = i + 1
                push!(subfrags, frag)
                match_char = ' '
            end
        end
    end

    lastfrag = strip(String(text[fragstart:end]))
    !isempty(lastfrag) && push!(subfrags, lastfrag)

    return subfrags
end

# ──────────────────────────────────────────────────────────────────
# N-gram extraction
# ──────────────────────────────────────────────────────────────────

"""
    clean_ngram(s::AbstractString) -> String

Remove punctuation and lowercase an n-gram string.
"""
function clean_ngram(s::AbstractString)::String
    s = replace(String(s), r"[-][-][-].*" => "")
    s = replace(s, r"[\"—\u201c\u201d!?`,.:;\u2014()_]+" => "")
    s = replace(s, "  " => " ")
    s = strip(s, '-')
    s = strip(s, '\'')
    return lowercase(s)
end

"""
    excluded_by_bindings(firstword::AbstractString, lastword::AbstractString) -> Bool

Check if an n-gram starts or ends with binding words that promise to connect
to adjacent content, making the n-gram a poor standalone fragment.
"""
function excluded_by_bindings(firstword::AbstractString, lastword::AbstractString)::Bool
    forbidden_ending = Set([
        "but", "and", "the", "or", "a", "an", "its", "it's", "their", "your",
        "my", "of", "as", "are", "is", "was", "has", "be", "with", "using",
        "that", "who", "to", "no", "because", "at", "yes", "yeah", "yay",
        "in", "which", "what", "he", "she", "they", "all", "i", "from",
        "for", "then"
    ])

    forbidden_starter = Set([
        "and", "or", "of", "the", "it", "because", "in", "that", "these",
        "those", "is", "are", "was", "were", "but", "yes", "no", "yeah",
        "yay", "also", "me", "them", "him"
    ])

    (length(firstword) <= 2 || length(lastword) <= 2) && return true
    lowercase(String(lastword)) in forbidden_ending && return true
    lowercase(String(firstword)) in forbidden_starter && return true
    return false
end

"""
    next_word(word::AbstractString, rrbuffer::Vector{Vector{String}}) -> (Vector{Vector{String}}, Vector{Vector{String}})

Process one word through the n-gram round-robin buffer.
Returns (updated rrbuffer, change_set) where change_set[n] contains
the new n-grams formed at each length n.
"""
function next_word(word::AbstractString, rrbuffer::Vector{Vector{String}})
    change_set = [String[] for _ in 1:N_GRAM_MAX]
    w = String(word)

    for n in 2:N_GRAM_MAX
        # Pop from round-robin to maintain window of size n
        if length(rrbuffer[n]) > n - 1
            rrbuffer[n] = rrbuffer[n][2:n]
        end
        # Push new word
        push!(rrbuffer[n], w)

        # Assemble key only if buffer is full
        if length(rrbuffer[n]) >= n
            key = join(rrbuffer[n], " ")
            key = clean_ngram(key)

            if excluded_by_bindings(clean_ngram(rrbuffer[n][1]), clean_ngram(rrbuffer[n][n]))
                continue
            end
            push!(change_set[n], key)
        end
    end

    # Handle unigrams if N_GRAM_MIN <= 1
    cleaned = clean_ngram(w)
    if N_GRAM_MIN <= 1 && !excluded_by_bindings(cleaned, cleaned)
        push!(change_set[1], cleaned)
    end

    return (rrbuffer, change_set)
end

"""
    fractionate(frag::AbstractString, L::Int, frequency::Vector{Dict{String,Float64}}, min_n::Int) -> Vector{Vector{String}}

Extract n-grams from a text fragment using a round-robin buffer.
Returns change_set where change_set[n] contains n-grams of length n.
"""
function fractionate(frag::AbstractString, L::Int, frequency::Vector{Dict{String,Float64}}, min_n::Int)::Vector{Vector{String}}
    rrbuffer = [String[] for _ in 1:N_GRAM_MAX]
    change_set = [String[] for _ in 1:N_GRAM_MAX]

    words = split(String(frag), ' ')
    for w in words
        rrbuffer, cs = next_word(String(w), rrbuffer)
        for n in 1:N_GRAM_MAX
            append!(change_set[n], cs[n])
        end
    end

    return change_set
end

# ──────────────────────────────────────────────────────────────────
# File-level fractionation
# ──────────────────────────────────────────────────────────────────

"""
    fractionate_text(text::AbstractString) -> (Vector{Vector{Vector{String}}}, Int)

Clean, split, and build n-gram frequency/location maps from text.
Updates the module-level STM_NGRAM_FREQ and STM_NGRAM_LOCA state.
Returns (paragraphs, sentence_count).
"""
function fractionate_text(text::AbstractString)
    proto_text = clean_text(String(text))
    pbsf = split_into_para_sentences(proto_text)
    count = 0

    for p in pbsf
        for s in p
            count += 1
            for f in s
                change_set = fractionate(f, count, STM_NGRAM_FREQ[], N_GRAM_MIN)
                for n in N_GRAM_MIN:N_GRAM_MAX-1
                    for ngram in change_set[n]
                        STM_NGRAM_FREQ[][n][ngram] = get(STM_NGRAM_FREQ[][n], ngram, 0.0) + 1.0
                        locs = get!(STM_NGRAM_LOCA[][n], ngram, Int[])
                        push!(locs, count)
                    end
                end
            end
        end
    end
    return (pbsf, count)
end

"""
    fractionate_text_file(filename::AbstractString) -> (Vector{Vector{Vector{String}}}, Int)

Read file, clean, split, and build n-gram frequency/location maps.
Returns (paragraphs, sentence_count).
"""
function fractionate_text_file(filename::AbstractString)
    file_content = read(filename, String)
    return fractionate_text(file_content)
end

# ──────────────────────────────────────────────────────────────────
# Intentionality scoring (n-gram version with document length L)
# ──────────────────────────────────────────────────────────────────

"""
    ngram_static_intentionality(L::Int, s::AbstractString, freq::Float64) -> Float64

Compute the static significance of an n-gram string `s` within a document
of `L` sentences. Intentionality = work / probability, using exponential
deprecation based on SST cognitive scales (Dunbar numbers).
"""
function ngram_static_intentionality(L::Int, s::AbstractString, freq::Float64)::Float64
    work = Float64(length(s))
    freq < 2 && return 0.0

    phi = freq
    phi_0 = Float64(DUNBAR_30)
    rho = 1.0 / 30.0
    crit = phi / phi_0 - rho
    meaning = phi * work / (1.0 + exp(crit))
    return meaning
end

"""
    assess_static_intent(frag::AbstractString, L::Int, frequency::Vector{Dict{String,Float64}}, min_n::Int) -> Float64

Score a fragment by static intentionality using the n-gram round-robin buffer.
"""
function assess_static_intent(frag::AbstractString, L::Int, frequency::Vector{Dict{String,Float64}}, min_n::Int)::Float64
    rrbuffer = [String[] for _ in 1:N_GRAM_MAX]
    score = 0.0
    words = split(String(frag), ' ')

    for w in words
        rrbuffer, change_set = next_word(String(w), rrbuffer)
        for n in min_n:N_GRAM_MAX-1
            for ngram in change_set[n]
                freq = get(STM_NGRAM_FREQ[][n], ngram, 0.0)
                score += ngram_static_intentionality(L, ngram, freq)
            end
        end
    end

    return score
end

"""
    running_ngram_intentionality(t::Int, frag::AbstractString) -> Float64

Score a fragment with exponential decay based on the last-seen time of each n-gram.
"""
function running_ngram_intentionality(t::Int, frag::AbstractString)::Float64
    rrbuffer = [String[] for _ in 1:N_GRAM_MAX]
    score = 0.0
    words = split(String(frag), ' ')
    decayrate = Float64(DUNBAR_30)

    for w in words
        rrbuffer, change_set = next_word(String(w), rrbuffer)
        for n in N_GRAM_MIN:N_GRAM_MAX-1
            for ngram in change_set[n]
                work = Float64(length(ngram))
                lastseen = get(STM_NGRAM_LAST[][n], ngram, 0)
                if lastseen == 0
                    score = work
                else
                    score += work * (1 - exp(-Float64(t - lastseen) / decayrate))
                end
                STM_NGRAM_LAST[][n][ngram] = t
            end
        end
    end

    return score
end

# ──────────────────────────────────────────────────────────────────
# Coherence and anomaly analysis
# ──────────────────────────────────────────────────────────────────

"""
    intentional_ngram(n::Int, ngram::AbstractString, L::Int, coherence_length::Int) -> Bool

Determine if an n-gram is intentional (anomalous) vs ambient (repeated regular pattern).
Unigrams are never intentional. Short documents are all intentional.
For longer documents, checks if the distribution of inter-occurrence spacings is broad.
"""
function intentional_ngram(n::Int, ngram::AbstractString, L::Int, coherence_length::Int)::Bool
    n == 1 && return false
    L < coherence_length && return true

    occurrences, minr, maxr = interval_radius(n, ngram)
    occurrences < 2 && return true
    return maxr > minr + coherence_length
end

"""
    interval_radius(n::Int, ngram::AbstractString) -> (Int, Int, Int)

Find the minimax distances between occurrences of an n-gram (in sentences).
Returns (occurrences, min_delta, max_delta).
"""
function interval_radius(n::Int, ngram::AbstractString)
    locs = get(STM_NGRAM_LOCA[][n], String(ngram), Int[])
    occurrences = length(locs)
    dl = 0
    dlmin = 99
    dlmax = 0

    for occ in 1:occurrences
        d = locs[occ]
        delta = d - dl
        dl = d
        dl == 0 && continue
        delta > dlmax && (dlmax = delta)
        delta < dlmin && (dlmin = delta)
    end

    return (occurrences, dlmin, dlmax)
end

"""
    assess_static_text_anomalies(L::Int, frequencies, locations)

Split text n-grams into intentional (anomalous) vs ambient (contextual) parts.
Returns (intent, context) — both Vector{Vector{TextRank}} of size N_GRAM_MAX.
"""
function assess_static_text_anomalies(L::Int, frequencies, locations)
    coherence_length = DUNBAR_30

    anomalous = [TextRank[] for _ in 1:N_GRAM_MAX]
    ambient = [TextRank[] for _ in 1:N_GRAM_MAX]

    for n in N_GRAM_MIN:N_GRAM_MAX-1
        for ngram in keys(STM_NGRAM_LOCA[][n])
            sig = assess_static_intent(ngram, L, STM_NGRAM_FREQ[], N_GRAM_MIN)
            ns = TextRank(sig, ngram, 0, 0)

            if intentional_ngram(n, ngram, L, coherence_length)
                push!(anomalous[n], ns)
            else
                push!(ambient[n], ns)
            end
        end

        sort!(anomalous[n], by=r -> -r.significance)
        sort!(ambient[n], by=r -> -r.significance)
    end

    max_intentional = [0, 0, DUNBAR_150, DUNBAR_150, DUNBAR_30, DUNBAR_15]
    intent = [TextRank[] for _ in 1:N_GRAM_MAX]
    context = [TextRank[] for _ in 1:N_GRAM_MAX]

    for n in N_GRAM_MIN:N_GRAM_MAX-1
        for i in 1:min(max_intentional[n], length(anomalous[n]))
            push!(intent[n], anomalous[n][i])
        end
        for i in 1:min(max_intentional[n], length(ambient[n]))
            push!(context[n], ambient[n][i])
        end
    end

    return (intent, context)
end

"""
    coherence_set(ngram_loc, L::Int, coherence_length::Int)

Partition n-grams into coherence sets based on their occurrence locations.
Returns (C, partitions) where C[n][p] is a Dict{String,Int} for n-gram size n
and partition p.
"""
function coherence_set(ngram_loc, L::Int, coherence_length::Int)
    partitions = L ÷ coherence_length + 1

    C = [Vector{Dict{String,Int}}() for _ in 1:N_GRAM_MAX]

    for n in 1:N_GRAM_MAX-1
        C[n] = [Dict{String,Int}() for _ in 1:partitions]
        for (ngram, locs) in ngram_loc[n]
            for s_loc in locs
                p = s_loc ÷ coherence_length + 1
                p = min(p, partitions)
                C[n][p][ngram] = get(C[n][p], ngram, 0) + 1
            end
        end
    end

    return (C, partitions)
end

"""
    assess_text_coherent_coactivation(L::Int, ngram_loc)

Global coherence analysis — separate n-grams into those that overlap
across coherence intervals (ambient) and those unique to a single interval (condensate).
Returns (overlap, condensate, partitions).
"""
function assess_text_coherent_coactivation(L::Int, ngram_loc)
    coherence_length = DUNBAR_30
    C, partitions = coherence_set(ngram_loc, L, coherence_length)

    overlap = [Dict{String,Int}() for _ in 1:N_GRAM_MAX]
    condensate = [Dict{String,Int}() for _ in 1:N_GRAM_MAX]

    for n in 1:N_GRAM_MAX-1
        if partitions < 2
            # Very short: everything is overlap
            if !isempty(C[n])
                for ngram in keys(C[n][1])
                    overlap[n][ngram] = get(overlap[n], ngram, 0) + 1
                end
            end
        else
            for pi in 1:length(C[n])
                for pj in (pi+1):length(C[n])
                    for ngram in keys(C[n][pi])
                        if get(C[n][pi], ngram, 0) > 0 && get(C[n][pj], ngram, 0) > 0
                            delete!(condensate[n], ngram)
                            overlap[n][ngram] = get(overlap[n], ngram, 0) + 1
                        else
                            if !haskey(overlap[n], ngram)
                                condensate[n][ngram] = get(condensate[n], ngram, 0) + 1
                            end
                        end
                    end
                end
            end
        end
    end

    return (overlap, condensate, partitions)
end

"""
    assess_text_fast_slow(L::Int, ngram_loc)

Running fast/slow separation by coherence intervals.
For each pair of adjacent intervals, n-grams shared between them are "slow" (context),
and those unique to one are "fast" (intentional).
Returns (slow, fast, partitions).
"""
function assess_text_fast_slow(L::Int, ngram_loc)
    coherence_length = DUNBAR_30
    C, partitions = coherence_set(ngram_loc, L, coherence_length)

    slow = [Vector{Dict{String,Int}}() for _ in 1:N_GRAM_MAX]
    fast = [Vector{Dict{String,Int}}() for _ in 1:N_GRAM_MAX]

    for n in 1:N_GRAM_MAX-1
        slow[n] = [Dict{String,Int}() for _ in 1:partitions]
        fast[n] = [Dict{String,Int}() for _ in 1:partitions]

        if partitions < 2
            # Single partition: everything is fast
            if !isempty(C[n])
                for ngram in keys(C[n][1])
                    fast[n][1][ngram] = get(fast[n][1], ngram, 0) + 1
                end
            end
        else
            for p in 2:partitions
                for ngram in keys(C[n][p-1])
                    if get(C[n][p], ngram, 0) > 0 && get(C[n][p-1], ngram, 0) > 0
                        slow[n][p-1][ngram] = get(slow[n][p-1], ngram, 0) + 1
                    else
                        fast[n][p-1][ngram] = get(fast[n][p-1], ngram, 0) + 1
                    end
                end
            end
        end
    end

    return (slow, fast, partitions)
end

"""
    extract_intentional_tokens(L::Int, selected::Vector{TextRank}, nmin::Int, nmax::Int)

Extract fast/slow parts per partition and whole-document summaries.
Returns (fastparts, slowparts, fastwhole, slowwhole).
"""
function extract_intentional_tokens(L::Int, selected::Vector{TextRank}, nmin::Int, nmax::Int)
    POLICY_SKIM = 15
    REUSE_THRESHOLD = 0
    INTENT_THRESHOLD = 1.0

    slow, fast, doc_parts = assess_text_fast_slow(L, STM_NGRAM_LOCA[])

    grad_amb = [Dict{String,Float64}() for _ in 1:N_GRAM_MAX]
    grad_oth = [Dict{String,Float64}() for _ in 1:N_GRAM_MAX]

    fastparts = [String[] for _ in 1:doc_parts]
    slowparts = [String[] for _ in 1:doc_parts]
    fastwhole = String[]
    slowwhole = String[]

    for p in 1:doc_parts
        for n in nmin:nmax-1
            p > length(fast[n]) && continue

            amb = String[]
            other = String[]

            for (ngram, cnt) in fast[n][p]
                cnt > REUSE_THRESHOLD && push!(other, ngram)
            end
            for (ngram, cnt) in slow[n][p]
                cnt > REUSE_THRESHOLD && push!(amb, ngram)
            end

            # Sort by intentionality
            sort!(amb, by=ng -> -ngram_static_intentionality(L, ng, get(STM_NGRAM_FREQ[][n], ng, 0.0)))
            sort!(other, by=ng -> -ngram_static_intentionality(L, ng, get(STM_NGRAM_FREQ[][n], ng, 0.0)))

            for i in 1:min(POLICY_SKIM, length(amb))
                v = ngram_static_intentionality(L, amb[i], get(STM_NGRAM_FREQ[][n], amb[i], 0.0))
                push!(slowparts[p], amb[i])
                v > INTENT_THRESHOLD && (grad_amb[n][amb[i]] = get(grad_amb[n], amb[i], 0.0) + v)
            end

            for i in 1:min(POLICY_SKIM, length(other))
                v = ngram_static_intentionality(L, other[i], get(STM_NGRAM_FREQ[][n], other[i], 0.0))
                push!(fastparts[p], other[i])
                v > INTENT_THRESHOLD && (grad_oth[n][other[i]] = get(grad_oth[n], other[i], 0.0) + v)
            end
        end
    end

    # Summary ranking of whole doc, filtered by selected sentences
    for n in nmin:nmax-1
        for s in selected
            for ngram in collect(keys(grad_amb[n]))
                !occursin(ngram, s.fragment) && delete!(grad_amb[n], ngram)
            end
            for ngram in collect(keys(grad_oth[n]))
                !occursin(ngram, s.fragment) && delete!(grad_oth[n], ngram)
            end
        end

        amb_list = String[]
        other_list = String[]

        for ngram in keys(grad_oth[n])
            haskey(grad_amb[n], ngram) && continue
            push!(other_list, ngram)
        end
        for ngram in keys(grad_amb[n])
            push!(amb_list, ngram)
        end

        sort!(amb_list, by=ng -> -ngram_static_intentionality(L, ng, get(STM_NGRAM_FREQ[][n], ng, 0.0)))
        sort!(other_list, by=ng -> -ngram_static_intentionality(L, ng, get(STM_NGRAM_FREQ[][n], ng, 0.0)))

        for i in 1:min(POLICY_SKIM, length(amb_list))
            push!(slowwhole, amb_list[i])
        end
        for i in 1:min(POLICY_SKIM, length(other_list))
            push!(fastwhole, other_list[i])
        end
    end

    return (fastparts, slowparts, fastwhole, slowwhole)
end
