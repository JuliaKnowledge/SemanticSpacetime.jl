# Reminders and Attached Assets
Simon Frost

## Introduction

Recent SSTorytime updates emphasize two note-centric workflows:

1.  reminder-style notes that expand dynamic time expressions at read
    time; and
2.  lightweight asset attachments keyed to a note’s text, chapter, and
    context.

This vignette shows the same pattern in `SemanticSpacetime.jl` using the
built-in dynamic helpers plus the new asset cache utilities.

## Setup

``` julia
using SemanticSpacetime

SemanticSpacetime.reset_arrows!()
SemanticSpacetime.reset_contexts!()
SemanticSpacetime.add_mandatory_arrows!()
```

## Dynamic reminder strings

The reminder examples in SSTorytime use `Dynamic:` strings with embedded
`{TimeUntil ...}` and `{TimeSince ...}` expressions.

``` julia
reminders = [
    "Dynamic: Time remaining until Christmas ... {TimeUntil 25 December}",
    "Dynamic: {TimeSince Day25 May Yr2018 Hr13} have elapsed since the company was founded",
    "Dynamic: Regular coordination meeting at 11:30 - TIME REMAINING .. {TimeUntil Hr11 Min30} !!",
]

for line in reminders
    println("SOURCE : ", line)
    println("EXPANDS: ", expand_dynamic_functions(line))
    println()
end
```

    SOURCE : Dynamic: Time remaining until Christmas ... {TimeUntil 25 December}
    EXPANDS:  Time remaining until Christmas ... 243 Days, 23 Hours, 13 Minutes

    SOURCE : Dynamic: {TimeSince Day25 May Yr2018 Hr13} have elapsed since the company was founded
    EXPANDS:  7 Years, 323 Days, 21 Hours, 46 Minutes have elapsed since the company was founded

    SOURCE : Dynamic: Regular coordination meeting at 11:30 - TIME REMAINING .. {TimeUntil Hr11 Min30} !!
    EXPANDS:  Regular coordination meeting at 11:30 - TIME REMAINING .. 43 Minutes !!

## Create a reminder note and attach assets

Assets are stored under a cache directory derived from the note text,
chapter, and context. This mirrors the recent SSTorytime note-asset
flow, but from a Julia API.

``` julia
asset_root = mktempdir()
chapter = "reminders"
context = "Monday, Hr10"
note_text = reminders[3]

agenda_source = joinpath(asset_root, "agenda.txt")
write(agenda_source, "Bring notebooks, finalize agenda, and review follow-up items.")

local_cached = attach_asset!(agenda_source, note_text, chapter; context=context, root=asset_root)

uri_source = joinpath(asset_root, "slides.txt")
write(uri_source, "Slide deck placeholder for the Monday coordination meeting.")
uri_cached = attach_asset_from_uri!("file://$(uri_source)", note_text, chapter;
    context=context, root=asset_root, filename="slides.txt")

println("Cache directory:")
println(asset_cache_location(note_text, chapter; context=context, root=asset_root))
println()
println("Cached assets:")
for path in list_cached_assets(note_text, chapter; context=context, root=asset_root)
    println("  • ", basename(path))
end
```

    Cache directory:
    /var/folders/yh/30rj513j6mn1n7x556c2v4w80000gn/T/jl_u2X72A/cacheroot/reminders/Monday_Hr10/Dynamic_Regular_coordination_544c259a679825436118ceac1efee40b7472beaa

    Cached assets:
      • agenda.txt
      • slides.txt

## Surface those assets in page-map notes

The page-map JSON that backs notes/browse views can now include attached
asset URLs for each rendered note line.

``` julia
store = MemoryStore()
ctx_ptr = register_context!(["Monday", "Hr10"])
note = mem_vertex!(store, note_text, chapter)

upload_page_map_event!(store, PageMap(chapter, "", ctx_ptr, 1, [
    Link(0, 1.0f0, ctx_ptr, note.nptr),
]))

page = json_page(store, get_page_map(store; chapter=chapter); assets_root=asset_root)

println("Page title   : ", page["title"])
println("Page context : ", page["context"])
println("Attached URLs:")
for asset in page["notes"][1][1]["assets"]
    println("  • ", asset)
end
```

    Page title   : reminders
    Page context : Hr10,Monday
    Attached URLs:

## Why this matters

This brings a newer SSTorytime workflow into the Julia port:

- **dynamic reminder notes** can be expanded without rewriting stored
  text;
- **attachments** can be keyed to the same note identity used by
  browse/page-map views; and
- **page-map JSON** can now surface those assets to the web layer
  directly.

That keeps reminder-oriented notes and supporting artifacts together
without turning the note model into a heavyweight media database.
