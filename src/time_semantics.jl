#=
Semantic time parsing for Semantic Spacetime.

Converts between DateTime objects and semantic time representations
using torus-based (cyclic) temporal coordinates.

Ported from SSTorytime/pkg/SSTorytime/SSTorytime.go.
=#

# ──────────────────────────────────────────────────────────────────
# Time constants
# ──────────────────────────────────────────────────────────────────

# Month names (1-indexed to match Julia's Dates.month())
const GR_MONTH_TEXT = [
    "January", "February", "March", "April", "May", "June",
    "July", "August", "September", "October", "November", "December"
]

# Day-of-week names (1-indexed, Monday=1 matching Julia's dayofweek())
const GR_DAY_TEXT = [
    "Monday", "Tuesday", "Wednesday", "Thursday",
    "Friday", "Saturday", "Sunday"
]

# Shift names (4 shifts of 6 hours each)
const GR_SHIFT_TEXT = ["Night", "Morning", "Afternoon", "Evening"]

# ──────────────────────────────────────────────────────────────────
# Semantic time functions
# ──────────────────────────────────────────────────────────────────

"""
    season(month::AbstractString) -> Tuple{String, String}

Returns (northern_hemisphere_season, southern_hemisphere_season) for the given month name.
"""
function season(month::AbstractString)::Tuple{String,String}
    m = String(month)
    if m in ("December", "January", "February")
        return ("N_Winter", "S_Summer")
    elseif m in ("March", "April", "May")
        return ("N_Spring", "S_Autumn")
    elseif m in ("June", "July", "August")
        return ("N_Summer", "S_Winter")
    elseif m in ("September", "October", "November")
        return ("N_Autumn", "S_Spring")
    end
    return ("hurricane", "typhoon")
end

"""
    do_nowt(then::DateTime) -> Tuple{String, String}

Convert a DateTime to a semantic time representation.
Returns (when_description, time_key) where:
- when_description is a human-readable semantic time string
- time_key is a compact key for database/context use
"""
function do_nowt(then::DateTime)::Tuple{String,String}
    yr = "Yr$(Dates.year(then))"
    month_name = GR_MONTH_TEXT[Dates.month(then)]
    d = Dates.day(then)
    hr = @sprintf("Hr%02d", Dates.hour(then))
    quarter = "Qu$(Dates.minute(then) ÷ 15 + 1)"
    shift = GR_SHIFT_TEXT[Dates.hour(then) ÷ 6 + 1]

    n_season, s_season = season(month_name)

    dayname = Dates.dayname(then)
    dow = dayname[1:min(3, length(dayname))]
    daynum = "Day$d"

    interval_start = (Dates.minute(then) ÷ 5) * 5
    interval_end = (interval_start + 5) % 60
    minD = @sprintf("Min%02d_%02d", interval_start, interval_end)

    when = "$n_season, $s_season, $shift, $dayname, $daynum, $month_name, $yr, $hr, $quarter"
    key = "$dow:$hr:$quarter-$minD"

    return (when, key)
end

"""
    get_time_context() -> Tuple{String, String, Int64}

Returns (context_string, time_key, unix_timestamp) for the current time.
"""
function get_time_context()::Tuple{String,String,Int64}
    now = Dates.now()
    context, keyslot = do_nowt(now)
    unix_ts = round(Int64, Dates.datetime2unix(now))
    return (context, keyslot, unix_ts)
end

"""
    get_time_from_semantics(speclist::Vector{String}, now::DateTime) -> DateTime

Parse a semantic time specification (Day3, Hr14, Mon, etc.) into a DateTime.
The first element of speclist is ignored (it's typically a command prefix).
"""
function get_time_from_semantics(speclist::Vector{String}, now::DateTime)::DateTime
    day = 0
    hour = 0
    mins = 0
    weekday_idx = 0
    month_val = 0
    year = 0
    days_to_next = 0

    hasweekday = false
    hasmonth = false

    for (i, v) in enumerate(speclist)
        i == 1 && continue  # skip first element

        if startswith(v, "Day")
            day = parse(Int, v[4:end]; base=10)
            continue
        end

        if startswith(v, "Yr")
            year = parse(Int, v[3:end]; base=10)
            continue
        end

        if startswith(v, "Min")
            # Handle Min05_10 format
            parts = split(v[4:end], "_")
            mins = parse(Int, parts[1]; base=10)
            continue
        end

        if startswith(v, "Hr")
            hour = parse(Int, v[3:end]; base=10)
            continue
        end

        if !hasweekday
            idx = _in_list(v, GR_DAY_TEXT)
            if idx > 0
                weekday_idx = idx
                hasweekday = true
                intended = weekday_idx
                actual = Dates.dayofweek(now)
                days_to_next = mod(intended - actual, 7)
                continue
            end
        end

        if !hasmonth
            idx = _in_list(v, GR_MONTH_TEXT)
            if idx > 0
                month_val = idx
                hasmonth = true
                continue
            end
        end
    end

    if hasweekday && (day > 0 || hasmonth || year > 0)
        # Weekday only makes sense as next occurrence without a date
        # Fall through to date construction
    elseif hasweekday
        return DateTime(Dates.year(now), Dates.month(now), Dates.day(now)) + Dates.Day(days_to_next)
    end

    year == 0 && (year = Dates.year(now))
    day == 0 && (day = Dates.day(now))
    month_val == 0 && (month_val = Dates.month(now))
    hour == 0 && (hour = Dates.hour(now))

    return DateTime(year, month_val, day, hour, mins)
end

# ──────────────────────────────────────────────────────────────────
# Internal helpers
# ──────────────────────────────────────────────────────────────────

function _in_list(s::AbstractString, list::Vector{String})::Int
    for (i, v) in enumerate(list)
        s == v && return i
    end
    return 0
end
