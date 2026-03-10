# Text Analysis API

## Text to N4L

```@docs
TextRank
TextSignificance
score_sentence
extract_significant_sentences
text_to_n4l
```

## N-gram Fractionation

```@docs
reset_ngram_state!
new_ngram_map
split_into_para_sentences
split_punctuation_text
un_paren
count_parens
clean_ngram
excluded_by_bindings
fractionate
next_word
fractionate_text
fractionate_text_file
```

## N-gram Intentionality

```@docs
ngram_static_intentionality
assess_static_intent
running_ngram_intentionality
intentional_ngram
interval_radius
assess_static_text_anomalies
assess_text_coherent_coactivation
assess_text_fast_slow
coherence_set
extract_intentional_tokens
```

## Context Intelligence

```@docs
STMHistory
reset_stm!
context_intent_analysis
update_stm_context
add_context
commit_context_token!
intersect_context_parts
diff_clusters
overlap_matrix
get_context_token_frequencies
get_node_context
get_node_context_string
context_interferometry
```

## Time Semantics

```@docs
do_nowt
get_time_context
season
get_time_from_semantics
```

## Log Analysis

```@docs
LogFormat
LogParseConfig
default_log_config
parse_syslog_line
parse_json_log_line
parse_csv_log
parse_log_to_sst!
```

## Text Breakdown

```@docs
EntitySuggestion
LinkSuggestion
TextBreakdown
identify_entities
suggest_links
propose_structure
breakdown_to_n4l
```
