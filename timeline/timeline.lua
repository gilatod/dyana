local guard = require("meido.guard")
local meta = require("meido.meta")
local array = require("meido.array")

local readonly = meta.readonly
local remove_item = array.remove_item
local find = array.find
local clear = array.clear

local timeline = {}
timeline.__index = timeline

setmetatable(timeline, {
    __call = function(self, config)
        local t = setmetatable({
            frame = 0,
            tracks = {},
            enabled_tracks = {}
        }, self)

        if config then
            guard.table("config", config)
            for k, entry in pairs(config) do
                guard.table("entry", entry)
                t:set_track(k, entry[1], entry[2])
            end
        end

        return t
    end
})

function timeline:get_frame()
    return self.frame
end

function timeline:set_frame(frame)
    self.frame = frame

    local ts = self.enabled_tracks
    for i = 1, #ts do
        local entry = ts[i]
        entry[1](frame, entry[2])
    end
end

function timeline:modify_frame(offset)
    self:set_frame(self.frame + offset)
end

function timeline:last_frame()
    self:set_frame(self.frame - 1)
end

function timeline:next_frame()
    self:set_frame(self.frame + 1)
end

function timeline:iter_tracks()
    return next, self.tracks
end

function timeline:get_track(key)
    local e = self.tracks[key]
    if not e then
        return nil
    end
    return e[1], e[2]
end

local function enable_track(self, entry)
    local ts = self.enabled_tracks
    ts[#ts+1] = entry
    entry[1](self.frame, entry[2])
end

local function disable_track(self, entry)
    remove_item(self.enabled_tracks, entry)
end

local function get_track_entry(self, key)
    local entry = self.tracks[key]
    if not entry then
        error("track '"..tostring(key).."' not found")
    end
    return entry
end

function timeline:set_track(key, env, track)
    guard.non_nil("key", key)
    guard.callable("track", track)

    local entry = readonly {track, env}
    self.tracks[key] = entry
    enable_track(self, entry)
    return self
end

function timeline:remove_track(key)
    local entry = get_track_entry(self, key)
    disable_track(self, entry)
    self.tracks[key] = nil
    return self
end

function timeline:set_track_env(key, env)
    local entry = get_track_entry(self, key)

    local new_entry = readonly {entry[1], env}
    self.tracks[key] = new_entry

    if self:is_track_enabled(key) then
        disable_track(self, entry)
        enable_track(self, new_entry)
    end
    return self
end

function timeline:is_track_enabled(key)
    local entry = get_track_entry(self, key)
    return find(self.enabled_tracks, entry) and true
end

function timeline:set_track_enabled(key, enabled)
    local entry = get_track_entry(self, key)

    if self:is_track_enabled(key) == enabled then
        return self
    end

    if enabled then
        enable_track(self, entry)
    else
        disable_track(self, entry)
    end
    return self
end

function timeline:disable_all_tracks()
    clear(self.enabled_tracks)
end

function timeline:set_enabled_tracks(...)
    local ts = self.enabled_tracks
    clear(ts)

    for i = 1, select("#", ...) do
        local key = select(i, ...)
        ts[#ts+1] = get_track_entry(self, key)
    end
end

function timeline:clear_tracks()
    local tracks = self.tracks
    for k in pairs(tracks) do
        tracks[k] = nil
    end
    self:disable_all_tracks()
end

function timeline:clear()
    self:clear_tracks()
    self.frame = 0
end

return timeline