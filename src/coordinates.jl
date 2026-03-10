#=
Coordinate assignment system for Semantic Spacetime visualization.

Assigns 2D/3D coordinates to nodes for graphical rendering of cones,
stories, page maps, chapters, and orbital structures.

Ported from SSTorytime/pkg/SSTorytime/SSTorytime.go.
=#

# Orbital radius constants (must not overlap)
const R0 = 0.4
const R1 = 0.3
const R2 = 0.1

# ──────────────────────────────────────────────────────────────────
# Relative orbit placement
# ──────────────────────────────────────────────────────────────────

"""
    relative_orbit(origin::Coords, radius::Float64, n::Int, max::Int) -> Coords

Place a satellite node at angular position `n` of `max` around `origin`
at the given `radius`. R1 orbits get a -π/6 offset, R2 orbits get +π/6.
"""
function relative_orbit(origin::Coords, radius::Float64, n::Int, max::Int)::Coords
    offset = 0.0
    if radius == R1
        offset = -π / 6.0
    elseif radius == R2
        offset = π / 6.0
    end
    max = max == 0 ? 1 : max
    angle = offset + 2π * n / max
    return Coords(
        origin.x + radius * cos(angle),
        origin.y + radius * sin(angle),
        origin.z,
        origin.r,
        origin.lat,
        origin.lon,
    )
end

# ──────────────────────────────────────────────────────────────────
# Set orbit coordinates on Orbit arrays
# ──────────────────────────────────────────────────────────────────

"""
    set_orbit_coords(xyz::Coords, orb::Vector{Vector{Orbit}}) -> Vector{Vector{Orbit}}

Assign OOO (origin) and XYZ (position) coordinates to each Orbit entry.
Radius-1 orbits are placed around `xyz`, radius-2 orbits are sub-orbits
anchored to the preceding radius-1 orbit.
"""
function set_orbit_coords(xyz::Coords, orb::Vector{Vector{Orbit}})::Vector{Vector{Orbit}}
    r1max = 0
    r2max = 0
    for sti in 1:length(orb)
        for o in orb[sti]
            if o.radius == 1
                r1max += 1
            elseif o.radius == 2
                r2max += 1
            end
        end
    end

    # Build new orbits with coordinates assigned
    new_orb = [Orbit[] for _ in 1:length(orb)]
    r1 = 0
    r2 = 0

    for sti in 1:length(orb)
        new_sti = Orbit[]
        o = 1
        while o <= length(orb[sti])
            entry = orb[sti][o]
            if entry.radius == 1
                anchor = relative_orbit(xyz, R1, r1, r1max)
                new_entry = Orbit(entry.radius, entry.arrow, entry.stindex, entry.dst,
                                  entry.ctx, entry.text, anchor, xyz)
                push!(new_sti, new_entry)
                r1 += 1
                # Process following radius-2 entries as sub-orbits
                op = o + 1
                while op <= length(orb[sti]) && orb[sti][op].radius == 2
                    sub = orb[sti][op]
                    sub_pos = relative_orbit(anchor, R2, r2, r2max)
                    new_sub = Orbit(sub.radius, sub.arrow, sub.stindex, sub.dst,
                                    sub.ctx, sub.text, sub_pos, anchor)
                    push!(new_sti, new_sub)
                    r2 += 1
                    op += 1
                end
                o = op
            else
                push!(new_sti, entry)
                o += 1
            end
        end
        new_orb[sti] = new_sti
    end

    return new_orb
end

# ──────────────────────────────────────────────────────────────────
# Cone coordinate assignment
# ──────────────────────────────────────────────────────────────────

"""
    assign_cone_coordinates(cone::Vector{Vector{Link}}, nth::Int, swimlanes::Int) -> Dict{NodePtr,Coords}

Assign coordinates to nodes in a causal cone visualization.
Deduplicates nodes, finds the longest path, counts channels per depth step,
then delegates to `make_coordinate_directory`.
"""
function assign_cone_coordinates(cone::Vector{Vector{Link}}, nth::Int, swimlanes::Int)::Dict{NodePtr,Coords}
    unique = Vector{NodePtr}[]
    already = Dict{NodePtr,Bool}()

    swimlanes = swimlanes == 0 ? 1 : swimlanes

    # Find the longest path length
    maxlen_tz = 0
    for x in 1:length(cone)
        if length(cone[x]) > maxlen_tz
            maxlen_tz = length(cone[x])
        end
    end

    xchannels = zeros(Float64, maxlen_tz)

    # Count the expanding wavefront sections for unique node entries
    for tz in 1:maxlen_tz
        unique_section = NodePtr[]
        for x in 1:length(cone)
            if tz <= length(cone[x])
                dst = cone[x][tz].dst
                if !get(already, dst, false)
                    push!(unique_section, dst)
                    already[dst] = true
                    xchannels[tz] += 1.0
                end
            end
        end
        push!(unique, unique_section)
    end

    return make_coordinate_directory(xchannels, unique, maxlen_tz, nth, swimlanes)
end

# ──────────────────────────────────────────────────────────────────
# Story coordinate assignment
# ──────────────────────────────────────────────────────────────────

"""
    assign_story_coordinates(axis::Vector{Link}, nth::Int, swimlanes::Int;
                             limit::Int=100, already::Dict{NodePtr,Bool}=Dict{NodePtr,Bool}()) -> Dict{NodePtr,Coords}

Assign coordinates along a story/sequence axis.
"""
function assign_story_coordinates(axis::Vector{Link}, nth::Int, swimlanes::Int;
                                  limit::Int=100,
                                  already::Dict{NodePtr,Bool}=Dict{NodePtr,Bool}())::Dict{NodePtr,Coords}
    unique = Vector{NodePtr}[]

    swimlanes = swimlanes == 0 ? 1 : swimlanes

    maxlen_tz = length(axis)
    if limit < maxlen_tz
        maxlen_tz = limit
    end

    xchannels = zeros(Float64, maxlen_tz)

    for tz in 1:maxlen_tz
        unique_section = NodePtr[]
        dst = axis[tz].dst
        if !get(already, dst, false)
            push!(unique_section, dst)
            already[dst] = true
            xchannels[tz] += 1.0
        end
        push!(unique, unique_section)
    end

    return make_coordinate_directory(xchannels, unique, maxlen_tz, nth, swimlanes)
end

# ──────────────────────────────────────────────────────────────────
# Page coordinate assignment
# ──────────────────────────────────────────────────────────────────

"""
    assign_page_coordinates(maplines::Vector{PageMap}) -> Dict{NodePtr,Coords}

Layout notes page-by-page. Axial nodes run along the Z axis;
satellite notes orbit around their axial leader.
"""
function assign_page_coordinates(maplines::Vector{PageMap})::Dict{NodePtr,Coords}
    directory = Dict{NodePtr,Coords}()
    already = Dict{NodePtr,Bool}()
    axis = NodePtr[]
    satellites = Dict{NodePtr,Vector{NodePtr}}()
    allnotes = 0

    for depth in 1:length(maplines)
        isempty(maplines[depth].path) && continue

        axial_nptr = maplines[depth].path[1].dst

        if !get(already, axial_nptr, false)
            allnotes += 1
            already[axial_nptr] = true
            push!(axis, axial_nptr)
        end

        ax = maplines[depth].path[1].dst

        for sat in 2:length(maplines[depth].path)
            orbit = maplines[depth].path[sat].dst
            if !get(already, orbit, false)
                if !haskey(satellites, ax)
                    satellites[ax] = NodePtr[]
                end
                push!(satellites[ax], orbit)
                already[orbit] = true
            end
        end
    end

    screen = 2.0
    z_start = -1.0
    zinc = allnotes > 0 ? screen / allnotes : 0.0

    for tz in 1:length(axis)
        leader = Coords(0.0, 0.0, z_start + (tz - 1) * zinc, 0.0, 0.0, 0.0)
        directory[axis[tz]] = leader

        sats = get(satellites, axis[tz], NodePtr[])
        satrange = Float64(length(sats))

        for (i, sat) in enumerate(sats)
            pos = Float64(i - 1)
            radius = 0.5 + 0.2 * leader.z
            sr = satrange == 0.0 ? 1.0 : satrange
            satc = Coords(
                radius * cos(2.0 * pos * π / sr),
                radius * sin(2.0 * pos * π / sr),
                leader.z, 0.0, 0.0, 0.0,
            )
            directory[sat] = satc
        end
    end

    return directory
end

# ──────────────────────────────────────────────────────────────────
# Chapter coordinate assignment (Fibonacci lattice on sphere)
# ──────────────────────────────────────────────────────────────────

"""
    assign_chapter_coordinates(nth::Int, swimlanes::Int) -> Coords

Assign a chapter header position on a sphere using the Fibonacci lattice.
"""
function assign_chapter_coordinates(nth::Int, swimlanes::Int)::Coords
    N = Float64(swimlanes)
    n = Float64(nth)
    fibratio = 1.618
    rho = 0.75

    latitude = asin(clamp(2n / (2N + 1), -1.0, 1.0))
    longitude = 2π * n / fibratio

    if longitude < -π
        longitude += 2π
    end
    if longitude > π
        longitude -= 2π
    end

    return Coords(
        -rho * sin(longitude),
        rho * sin(latitude),
        rho * cos(longitude) * cos(latitude),
        rho, latitude, longitude,
    )
end

# ──────────────────────────────────────────────────────────────────
# Context set coordinate assignment
# ──────────────────────────────────────────────────────────────────

"""
    assign_context_set_coordinates(origin::Coords, nth::Int, swimlanes::Int) -> Coords

Assign coordinates for a context set around a chapter origin on a sphere.
"""
function assign_context_set_coordinates(origin::Coords, nth::Int, swimlanes::Int)::Coords
    N = Float64(swimlanes)
    n = Float64(nth)
    latitude = origin.lat
    longitude = origin.lon
    rho = 0.85
    orbital_angle = π / 8

    if N == 1.0
        return Coords(-rho * sin(longitude), rho * sin(latitude),
                       rho * cos(longitude) * cos(latitude), 0.0, 0.0, 0.0)
    end

    delta_lon = orbital_angle * sin(2π * n / N)
    delta_lat = orbital_angle * cos(2π * n / N)

    return Coords(
        -rho * sin(longitude + delta_lon),
        rho * sin(latitude + delta_lat),
        rho * cos(longitude + delta_lon) * cos(latitude + delta_lat),
        0.0, 0.0, 0.0,
    )
end

# ──────────────────────────────────────────────────────────────────
# Fragment coordinate assignment
# ──────────────────────────────────────────────────────────────────

"""
    assign_fragment_coordinates(origin::Coords, nth::Int, swimlanes::Int) -> Coords

Assign coordinates for fragments around a context origin on a sphere.
Staggers radius for crowded display.
"""
function assign_fragment_coordinates(origin::Coords, nth::Int, swimlanes::Int)::Coords
    N = Float64(swimlanes)
    n = Float64(nth)
    latitude = origin.lat
    longitude = origin.lon
    rho = 0.3 + (nth % 2) * 0.1
    orbital_angle = π / 12

    if N == 1.0
        return Coords(-rho * sin(longitude), rho * sin(latitude),
                       rho * cos(longitude) * cos(latitude), 0.0, 0.0, 0.0)
    end

    delta_lon = orbital_angle * sin(2π * n / N)
    delta_lat = orbital_angle * cos(2π * n / N)

    return Coords(
        -rho * sin(longitude + delta_lon),
        rho * sin(latitude + delta_lat),
        rho * cos(longitude + delta_lon) * cos(latitude + delta_lat),
        0.0, 0.0, 0.0,
    )
end

# ──────────────────────────────────────────────────────────────────
# Core layout: make_coordinate_directory
# ──────────────────────────────────────────────────────────────────

"""
    make_coordinate_directory(xchannels::Vector{Float64}, unique::Vector{Vector{NodePtr}},
                              maxlen_tz::Int, nth::Int, swimlanes::Int) -> Dict{NodePtr,Coords}

Core layout function: distribute nodes in a 2D grid.
X-axis = swimlane position, Z-axis = time/depth step.
Each step allocates horizontal space proportional to node count.
"""
function make_coordinate_directory(xchannels::Vector{Float64}, unique::Vector{Vector{NodePtr}},
                                   maxlen_tz::Int, nth::Int, swimlanes::Int)::Dict{NodePtr,Coords}
    directory = Dict{NodePtr,Coords}()

    totwidth = 2.0   # width dimension of the paths -1 to +1
    totdepth = 2.0   # depth dimension of the paths -1 to +1
    arbitrary_elevation = 0.0

    x_lanewidth = totwidth / swimlanes
    tz_steplength = maxlen_tz > 0 ? totdepth / maxlen_tz : 0.0
    x_lane_start = (nth - 1) * x_lanewidth - totwidth / 2.0

    for tz in 1:min(maxlen_tz, length(unique))
        x_increment = xchannels[tz] > 0 ? x_lanewidth / (xchannels[tz] + 1) : x_lanewidth
        z_left = -totwidth / 2.0
        x_left = x_lane_start + x_increment

        xyz = Coords(x_left, arbitrary_elevation, z_left + tz_steplength * (tz - 1), 0.0, 0.0, 0.0)

        for uniqptr in 1:length(unique[tz])
            directory[unique[tz][uniqptr]] = xyz
            xyz = Coords(xyz.x + x_increment, xyz.y, xyz.z, 0.0, 0.0, 0.0)
        end
    end

    return directory
end
