local guard = require("meido.guard")
local actions = require("dyana.actions")

local tracks = {}

local modf = math.modf
local max = math.min
local min = math.min
local tointeger = math.tointeger

-- [track constructors]

tracks.single = function(duration, action)
    guard.number("duration", duration)
    guard.callable("action", action)

    local last_env = nil
    local last_valid_frame = -1

    return function(frame, env)
        if last_env ~= env then
            last_env = env
            last_valid_frame = -1
        end

        if frame > duration then
            if last_valid_frame ~= duration then
                last_valid_frame = duration
                action(1, env)
            end
            return
        end

        last_valid_frame = frame
        return action(frame / duration, env)
    end
end

tracks.offset_single = function(offset, duration, action)
    guard.number("offset", offset)
    guard.number("duration", duration)
    guard.callable("action", action)

    local end_frame = offset + duration
    local last_env = nil
    local last_valid_frame = -1

    return function(frame, env)
        if last_env ~= env then
            last_env = env
            last_valid_frame = -1
        end

        if frame > end_frame then
            if last_valid_frame ~= end_frame then
                last_valid_frame = end_frame
                action(1, env)
            end
            return
        elseif frame < offset then
            if last_valid_frame ~= offset then
                last_valid_frame = offset
                action(0, env)
            end
            return
        end

        last_valid_frame = frame
        return action((frame - offset) / duration, env)
    end
end

tracks.multiple = function(duration, ...)
    return tracks.single(duration, actions.combine(...))
end

tracks.sequence = function(actions)
    guard.table("actions", actions)

    local action_seq = {}
    local frame_acc = 0

    for i = 1, #actions do
        local entry = actions[i]
        local interval = entry[1]
        local duration = entry[2]
        local action = entry[3]

        guard.zero_or_positive("interval", interval)
        guard.positive("duration", duration)
        guard.callable("action", action)

        frame_acc = frame_acc + interval
        local end_frame = frame_acc + duration

        action_seq[#action_seq + 1] = {
            frame_acc, end_frame, duration, action
        }
        frame_acc = end_frame
    end

    local function find_action(seq, frame, li, ri)
        -- \binary search~!/
        local mid = tointeger((li + ri) / 2)
        local mid_action = seq[mid]

        if mid_action[1] <= frame then
            if frame <= mid_action[2] then
                return mid_action, mid
            elseif li ~= ri then
                return find_action(seq, frame, mid + 1, ri)
            else
                mid = mid + 1
                return seq[mid], mid
            end
        elseif li ~= ri then
            find_action(seq, frame, li, mid - 1)
        else
            return mid_action, mid
        end
    end

    local last_env = nil
    local curr_index = 1
    local curr = action_seq[1] -- current action entry
    local last_valid_frame = -1

    return function(frame, env)
        if last_env ~= env then
            last_env = env
            curr_index = 1
            curr = action_seq[1]
            last_valid_frame = 0
        end

        local full_search

        if frame >= curr[2] then
            if last_valid_frame ~= curr[2] then
                last_valid_frame = curr[2]
                curr[4](1, env)
            end

            if curr_index == #action_seq then
                return
            end

            local next = action_seq[curr_index + 1]

            if frame < next[2] then
                curr_index = curr_index + 1
                curr = next
                if frame < curr[1] then
                    return
                end
            else
                full_search = true
            end
        elseif frame <= curr[1] then
            if last_valid_frame ~= curr[1] then
                last_valid_frame = curr[1]
                curr[4](0, env)
            end

            if curr_index == 1 then
                return
            end

            local last = action_seq[curr_index - 1]
            if last[2] <= frame then
                return -- still in current action entry
            end

            if last[1] <= frame then
                curr_index = curr_index - 1
                curr = last
            else
                full_search = true
            end
        end

        if full_search then
            local first_act = action_seq[1]
            local last_act = action_seq[#action_seq]

            -- special cases for first & last actions are
            -- profitable, for sequences can be used by loops or
            -- in timelines where frames are frequently reset to
            -- 0 or total duration of the sequence.
            if frame <= first_act[2] then
                -- it is critical for actions to be reset in order!!!
                for i = curr_index, 2, -1 do
                    action_seq[i][4](0, env)
                end

                curr_index = 1
                curr = first_act

                if frame < curr[1] then
                    last_valid_frame = curr[1]
                    curr[4](0, env)
                    return
                end
                goto action_found
            elseif frame >= last_act[1] then
                for i = curr_index, #action_seq-1 do
                    action_seq[i][4](1, env)
                end

                curr_index = #action_seq
                curr = last_act

                if frame > curr[2] then
                    curr[4](1, env)
                    last_valid_frame = curr[2]
                    return
                end
                goto action_found
            end

            local entry
            local index

            if frame > curr[1] then
                entry, index = find_action(
                    action_seq, frame, curr_index + 1, #action_seq)

                for i = curr_index, index - 1 do
                    action_seq[i][4](1, env)
                end
            else
                entry, index = find_action(
                    action_seq, frame, 1, last_valid_index - 1)

                for i = curr_index, index, -1 do
                    action_seq[i][4](0, env)
                end
            end

            curr = entry
            curr_index = index
        end

        ::action_found::
        last_valid_frame = frame
        return curr[4]((frame - curr[1]) / curr[3], env)
    end
end

local function create_simple_loop(count, duration, action)
    if count ~= math.huge then
        local last_env
        local last_valid_frame = -1
        local end_frame = count * duration

        return function(frame, env)
            if last_env ~= env then
                last_env = env
                last_valid_frame = -1
            end

            if frame >= end_frame then
                if last_valid_frame ~= end_frame then
                    last_valid_frame = end_frame
                    action(1, env)
                end
                return
            end

            last_valid_frame = frame
            return action(frame % duration / duration, env)
        end
    else
        return function(frame, env)
            return action(frame % duration / duration, env)
        end
    end
end

local function create_seq_loop(count, actions)
    local seq_track = tracks.sequence(actions)
    local total_frames = 0

    for i = 1, #actions do
        local action = actions[i]
        total_frames = total_frames + action[1] + action[2]
    end

    local end_frame = total_frames * count

    if count ~= math.huge then
        return function(frame, env)
            if frame < end_frame then
                return seq_track(frame % total_frames, env)
            else
                -- sequence track will handle the situation
                -- where the frame is greater then the total
                -- frame length of all actions.
                return seq_track(total_frames + frame, env)
            end
        end
    else
        return function(frame, env)
            return seq_track(frame % total_frames, env)
        end
    end
end

tracks.loop = function(count, duration_or_actions, action)
    guard.positive("count", count)

    local t = type(duration_or_actions)
    if t == "number" then
        guard.positive("duration", duration_or_actions)
        guard.callable("action", action)
        return create_simple_loop(count, duration_or_actions, action)
    else
        guard.table("actions", duration_or_actions)
        return create_seq_loop(count, duration_or_actions)
    end
end

tracks.infinite_loop = function(duration_or_actions, action)
    return tracks.loop(math.huge, duration_or_actions, action)
end

tracks.simple_alternate = function(duration, action1, action2)
    guard.positive("duration", duration)
    guard.callable("action1", action1)
    guard.callable("action2", action2)

    return function(frame, env)
        local count, fract = modf(frame / duration)
        if count % 2 == 0 then
            return action1(fract, env)
        else
            return action2(fract, env)
        end
    end
end

tracks.alternate = function(duration1, action1, duration2, action2)
    guard.positive("duration1", duration1)
    guard.callable("action1", action1)
    guard.positive("duration2", duration2)
    guard.callable("action2", action2)

    local total_dur = duration1 + duration2
    -- prop: proportion in the total duration of both actions
    local act1_prop = duration1 / total_dur 
    local act2_prop = duration2 / total_dur

    return function(frame, env)
        local fract = frame % total_dur / total_dur
        if fract < act1_prop then
            return action1(fract / act1_prop, env)
        else
            return action2((fract - act1_prop) / act2_prop, env)
        end
    end
end

-- [track combinators]

tracks.combine = function(...)
    local count = select("#", ...)

    for i = 1, count do
        local t = select(i, ...)
        guard.callable("track", t)
    end

    if count == 1 then
        return select(1, ...)
    elseif count == 2 then
        local t1, t2 = ...
        return function(frame, env)
            t1(frame, env)
            t2(frame, env)
        end
    elseif count == 3 then
        local t1, t2, t3 = ...
        return function(frame, env)
            t1(frame, env)
            t2(frame, env)
            t3(frame, env)
        end
    elseif count == 4 then
        local t1, t2, t3, t4 = ...
        return function(frame, env)
            t1(frame, env)
            t2(frame, env)
            t3(frame, env)
            t4(frame, env)
        end
    else
        local tracks = {...}
        return function(frame, env)
            for i = 1, #tracks do
                tracks[i](frame, env)
            end
        end
    end
end

tracks.offset = function(offset, track)
    guard.number("offset", offset)
    guard.callable("track", track)

    if offset == 0 then
        return track
    end

    if offset > 0 then
        local last_env = nil
        local last_valid_frame = -1

        return function(frame, env)
            if last_env ~= env then
                last_env = env
                last_valid_frame = -1
            end

            if frame < offset then
                if last_valid_frame ~= offset then
                    last_valid_frame = offset
                    track(0, env)
                end
                return
            end

            last_valid_frame = frame
            return track(frame - offset, env)
        end
    else
        return function(frame, env)
            return track(frame - offset, env)
        end
    end
end

tracks.clip = function(start, duration, track)
    guard.zero_or_positive("start", start)
    guard.positive("duration", duration)
    guard.callable("track", track)

    local last_env = nil
    local last_valid_frame = -1
    
    return function(frame, env)
        if last_env ~= env then
            last_env = env
            last_valid_frame = -1
        end

        if frame > duration then
            if last_valid_frame ~= duration then
                last_valid_frame = duration
                track(start + duration, env)
            end
            return
        end

        last_valid_frame = frame
        return track(start + frame, env)
    end
end

tracks.mask = function(mask_start, mask_duration, track)
    guard.positive("mask_start", mask_start)
    guard.positive("mask_duration", mask_duration)
    guard.callable("track", track)

    local mask_end = mask_start + mask_duration

    local last_env = nil
    local last_valid_frame = -1

    return function(frame, env)
        if last_env ~= env then
            last_env = env
            last_valid_frame = -1
        end

        if frame > mask_end then
            if last_valid_frame ~= mask_end then
                last_valid_frame = mask_end
                track(mask_start, env)
            end
            return
        elseif frame < mask_start then
            if last_valid_frame ~= mask_start then
                last_valid_frame = mask_start
                track(mask_start, env)
            end
            return
        end

        return track(frame, env)
    end
end

tracks.scale = function(factor, track)
    guard.zero_or_positive("factor", factor)
    guard.callable("track", track)

    return function(frame, env)
        return track(frame * factor, env)
    end
end

return tracks