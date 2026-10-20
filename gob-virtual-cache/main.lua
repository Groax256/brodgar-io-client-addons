-- Target resource patterns to match and cache.
-- Substrings or exact resource paths are accepted.
-- Populate this table with the resources you want to track and display virtually.
local TARGET_RESOURCE_PATTERNS = {
    "gfx/terobjs/",
}

-- Never cached, even when a target pattern matches: things that move or are picked up.
local EXCLUDED_RESOURCE_PATTERNS = {
    "gfx/terobjs/vehicle/",
    "gfx/terobjs/items/",
}

-- A ghost closer than this (world units) to a live object that appears is the same object.
local SAME_OBJECT_DISTANCE = 2.0
-- A cached object this close to the player that is not in view is gone (chopped, picked, destroyed).
-- 20 tiles: well inside the area the server always shows.
local VERIFY_RADIUS = 220
-- How often that is checked, and how many checks in a row the player must have stood in the world
-- (no login, no teleport) before an absence counts.
local VERIFY_EVERY = 2.0
local VERIFY_SETTLE = 2
-- How long dirty rows wait before they are written, all in one transaction.
local FLUSH_DELAY = 2.0
-- How many cached ghosts are stood per tick while restoring.
local RESTORE_BATCH = 150

-- Storage setup: persistent SQLite table for cached objects across sessions
local addon_store = hafen.store()
local cached_objects_table = addon_store:table("cached_virtual_gobs")
    :column("position_key", "text")
    :column("resource_name", "text")
    :column("facing", "real")
    :column("scale", "real")
    :column("grid_id", "text")
    :column("offset_x", "real")
    :column("offset_y", "real")
    :column("saved_position", "json")
    :column("sdt", "json")
    :key("position_key")
    :create()

-- In-memory state. Everything the hot paths read lives here, so a GobAdded costs no SQL and no
-- walk over every ghost.
local known_rows = {}             -- position_key -> { resource_name, facing, scale, grid_id, x, y, sdt }
local rows_by_grid = {}           -- grid_id -> { position_key = true }
local tracked_live_gobs = {}      -- gob_id -> { resource_name, position, position_key, facing, scale, grid_id, x, y, sdt }
local live_keys = {}              -- position_key -> gob_id
local live_buckets = {}           -- bucket -> { position_key = true }
local active_virtual_ghosts = {}  -- position_key -> { ghost, bucket }
local ghost_buckets = {}          -- bucket -> { position_key = true }
local pending_writes = {}         -- position_key -> row to put
local pending_deletes = {}        -- position_key -> true
local flush_scheduled = false

-- Checks a resource name against a pattern list
local function matches_any(resource_name, patterns)
    for _, target_pattern in ipairs(patterns) do
        if resource_name == target_pattern or resource_name:find(target_pattern, 1, true) ~= nil then
            return true
        end
    end
    return false
end

local function matches_target_resource(resource_name)
    return resource_name ~= nil and matches_any(resource_name, TARGET_RESOURCE_PATTERNS)
        and not matches_any(resource_name, EXCLUDED_RESOURCE_PATTERNS)
end

-- Spatial bucket of a place inside its grid, sized so a 3x3 look covers SAME_OBJECT_DISTANCE
local BUCKET_SIZE = 4
local function bucket_of(grid_id, x, y, dx, dy)
    return grid_id .. ":" .. (math.floor(x / BUCKET_SIZE) + (dx or 0)) .. ":" .. (math.floor(y / BUCKET_SIZE) + (dy or 0))
end

local function set_add(index, bucket, key)
    local members = index[bucket]
    if not members then
        members = {}
        index[bucket] = members
    end
    members[key] = true
end

local function set_remove(index, bucket, key)
    local members = index[bucket]
    if members then
        members[key] = nil
        if next(members) == nil then
            index[bucket] = nil
        end
    end
end

local function same_bytes(a, b)
    if a == nil or b == nil then
        return a == b
    end
    if #a ~= #b then
        return false
    end
    for i = 1, #a do
        if a[i] ~= b[i] then
            return false
        end
    end
    return true
end

-- Writes and deletes queued rows in one transaction
local function flush_store()
    flush_scheduled = false
    local writes, deletes = pending_writes, pending_deletes
    if next(writes) == nil and next(deletes) == nil then
        return
    end
    pending_writes, pending_deletes = {}, {}
    addon_store:transaction(function()
        for _, record in pairs(writes) do
            cached_objects_table:put(record)
        end
        for position_key in pairs(deletes) do
            cached_objects_table:remove(position_key)
        end
    end)
end

local function schedule_flush()
    if not flush_scheduled then
        flush_scheduled = true
        hafen.timer():after(FLUSH_DELAY, flush_store)
    end
end

local function index_row(position_key, row)
    known_rows[position_key] = row
    if row.grid_id ~= "" then
        set_add(rows_by_grid, row.grid_id, position_key)
    end
end

local function unindex_row(position_key)
    local row = known_rows[position_key]
    if row then
        known_rows[position_key] = nil
        if row.grid_id ~= "" then
            set_remove(rows_by_grid, row.grid_id, position_key)
        end
    end
end

for _, row in ipairs(cached_objects_table:list()) do
    if matches_target_resource(row.resource_name) then
        local saved = type(row.saved_position) == "table" and row.saved_position or {}
        index_row(row.position_key, {
            resource_name = row.resource_name,
            facing = row.facing or 0,
            scale = row.scale or 1.0,
            grid_id = (row.grid_id and row.grid_id ~= "") and tostring(row.grid_id)
                or (saved.gridId and tostring(saved.gridId)) or "",
            x = tonumber(row.offset_x) or tonumber(saved.x),
            y = tonumber(row.offset_y) or tonumber(saved.y),
            sdt = type(row.sdt) == "table" and row.sdt or nil,
        })
    else
        pending_deletes[row.position_key] = true
    end
end
if next(pending_deletes) ~= nil then
    schedule_flush()
end

-- Whether a ghost can be drawn from what is known of the object. Its state bytes (a crop's stage, a
-- tree's growth) are part of how it is drawn, and a resource whose code reads them cannot be built
-- without them. A row recorded before they were kept stands as it did, except a growing plant,
-- which never could; it is drawn again once it has been seen and its bytes recorded.
local function drawable(resource_name, sdt)
    if sdt ~= nil then
        return true
    end
    return resource_name:find("gfx/terobjs/plants/", 1, true) == nil
end

-- Locates an active session's world subsystem handle
local function find_active_world_subsystem()
    local current_session = hafen.session():current()
    if current_session and current_session:exists() and current_session:character() then
        return current_session:world()
    end
    for _, session_handle in ipairs(hafen.session():list()) do
        if session_handle:exists() and session_handle:character() then
            return session_handle:world()
        end
    end
    return nil
end

-- Removes one active ghost by key
local function remove_ghost_by_key(position_key)
    local entry = active_virtual_ghosts[position_key]
    if not entry then
        return
    end
    active_virtual_ghosts[position_key] = nil
    set_remove(ghost_buckets, entry.bucket, position_key)
    if entry.ghost:exists() then
        pcall(function()
            hafen.virtual():ghost():remove(entry.ghost)
        end)
    end
end

-- The keys in `index` within SAME_OBJECT_DISTANCE of a place, looking only at its neighbouring buckets
local function keys_near(index, coords_of, grid_id, x, y)
    local found = {}
    if grid_id == "" or not x or not y then
        return found
    end
    local limit = SAME_OBJECT_DISTANCE * SAME_OBJECT_DISTANCE
    for dx = -1, 1 do
        for dy = -1, 1 do
            local members = index[bucket_of(grid_id, x, y, dx, dy)]
            if members then
                for key in pairs(members) do
                    local ox, oy = coords_of(key)
                    if ox then
                        ox, oy = ox - x, oy - y
                        if ox * ox + oy * oy < limit then
                            found[#found + 1] = key
                        end
                    end
                end
            end
        end
    end
    return found
end

local function row_coords(key)
    local row = known_rows[key]
    if row then
        return row.x, row.y
    end
end

local function live_coords(key)
    local gob_id = live_keys[key]
    local tracked = gob_id and tracked_live_gobs[gob_id]
    if tracked then
        return tracked.x, tracked.y
    end
end

-- Removes any active ghost at or near a place
local function remove_virtual_ghost_at(position_key, grid_id, x, y)
    remove_ghost_by_key(position_key)
    for _, key in ipairs(keys_near(ghost_buckets, row_coords, grid_id, x, y)) do
        remove_ghost_by_key(key)
    end
end

-- Spawns an opaque virtual ghost in the world at the target position
local function spawn_virtual_ghost(position_key, resource_name, target_position, facing_angle, scale_factor, grid_id, x, y, sdt)
    if not target_position or not resource_name or not drawable(resource_name, sdt) then
        return nil
    end

    local existing = active_virtual_ghosts[position_key]
    if existing then
        if existing.ghost:exists() then
            return existing.ghost
        end
        remove_ghost_by_key(position_key)
    end

    local call_success, virtual_ghost = pcall(function()
        local ghost_entity = hafen.virtual():ghost():add(resource_name, target_position)
        if ghost_entity then
            if sdt and #sdt > 0 then
                ghost_entity:res(resource_name, sdt)
            end
            if facing_angle then
                ghost_entity:rotate(facing_angle)
            end
            if scale_factor and scale_factor ~= 1.0 then
                ghost_entity:scale(scale_factor)
            end
            ghost_entity:clickable(false)
        end
        return ghost_entity
    end)

    if call_success and virtual_ghost then
        local bucket = (grid_id ~= "" and x and y) and bucket_of(grid_id, x, y) or ("nogrid:" .. position_key)
        active_virtual_ghosts[position_key] = { ghost = virtual_ghost, bucket = bucket }
        set_add(ghost_buckets, bucket, position_key)
        return virtual_ghost
    end
    return nil
end

-- Queues the row for the store when it is new or changed; an unchanged object costs nothing
local function remember_gob(position_key, resource_name, facing_angle, scale_factor, grid_id, x, y, sdt)
    local row = known_rows[position_key]
    if row and row.resource_name == resource_name and math.abs((row.facing or 0) - facing_angle) < 1e-4
        and math.abs((row.scale or 1.0) - scale_factor) < 1e-4 and same_bytes(row.sdt, sdt) then
        return
    end
    unindex_row(position_key)
    index_row(position_key, {
        resource_name = resource_name, facing = facing_angle, scale = scale_factor,
        grid_id = grid_id, x = x, y = y, sdt = sdt,
    })
    pending_deletes[position_key] = nil
    pending_writes[position_key] = {
        position_key = position_key,
        resource_name = resource_name,
        facing = facing_angle,
        scale = scale_factor,
        grid_id = grid_id,
        offset_x = x,
        offset_y = y,
        saved_position = { gridId = grid_id, x = x, y = y },
        sdt = sdt,
    }
    schedule_flush()
end

-- Forgets a cached object: its row, and any ghost standing for it
local function forget_gob(position_key)
    remove_ghost_by_key(position_key)
    unindex_row(position_key)
    pending_writes[position_key] = nil
    pending_deletes[position_key] = true
    schedule_flush()
end

-- Processes a live game object entering view
local function handle_gob_added(game_object, retries_remaining)
    if not game_object:exists() then
        return
    end

    local gob_id = game_object:id()
    if tracked_live_gobs[gob_id] then
        return
    end

    local resource_name = game_object:name()
    if not resource_name then
        if retries_remaining and retries_remaining > 0 then
            hafen.timer():after(0.25, function()
                handle_gob_added(game_object, retries_remaining - 1)
            end)
        end
        return
    end

    if not matches_target_resource(resource_name) then
        return
    end

    local target_position = game_object:position()
    if not target_position then
        return
    end

    local position_info = target_position:info()
    local grid_id, x, y, position_key
    if position_info and position_info.gridId then
        grid_id, x, y = tostring(position_info.gridId), position_info.x, position_info.y
        position_key = string.format("%s:%.1f:%.1f", grid_id, x, y)
    else
        x, y = target_position:x(), target_position:y()
        if not x or not y then
            return
        end
        grid_id = ""
        position_key = string.format("local:%.1f:%.1f", x, y)
    end

    local facing_angle = game_object:facing() or 0
    local scale_factor = game_object:scale() or 1.0
    local sdt = game_object:sdt()

    remove_virtual_ghost_at(position_key, grid_id, x, y)

    tracked_live_gobs[gob_id] = {
        resource_name = resource_name,
        position = target_position,
        position_key = position_key,
        facing = facing_angle,
        scale = scale_factor,
        grid_id = grid_id,
        x = x,
        y = y,
        sdt = sdt,
        bucket = grid_id ~= "" and bucket_of(grid_id, x, y) or nil,
    }
    live_keys[position_key] = gob_id
    if grid_id ~= "" then
        set_add(live_buckets, bucket_of(grid_id, x, y), position_key)
    end

    if sdt ~= nil or known_rows[position_key] == nil then
        remember_gob(position_key, resource_name, facing_angle, scale_factor, grid_id, x, y, sdt)
    end
end

-- The state bytes arrive or change: a crop grows, a tree is given its stage
local function handle_sdt_changed(event)
    local gob_id = event:gob():id()
    local tracked = tracked_live_gobs[gob_id]
    if not tracked then
        return
    end
    tracked.sdt = event:sdt()
    remember_gob(tracked.position_key, tracked.resource_name, tracked.facing, tracked.scale,
        tracked.grid_id, tracked.x, tracked.y, tracked.sdt)
end

-- Processes a live game object leaving view
local function handle_gob_removed(game_object)
    local gob_id = game_object:id()
    local tracked = tracked_live_gobs[gob_id]
    if not tracked then
        return
    end
    tracked_live_gobs[gob_id] = nil
    if live_keys[tracked.position_key] == gob_id then
        live_keys[tracked.position_key] = nil
        if tracked.bucket then
            set_remove(live_buckets, tracked.bucket, tracked.position_key)
        end
    end

    -- Destroyed or merely left behind, it is ghosted; one that was destroyed is forgotten by
    -- verify_nearby once the player stands close to where it was.
    if known_rows[tracked.position_key] then
        spawn_virtual_ghost(tracked.position_key, tracked.resource_name, tracked.position,
            tracked.facing, tracked.scale, tracked.grid_id, tracked.x, tracked.y, tracked.sdt)
    end
end

-- Forgets cached objects next to the player that the server does not show any more
local settled_checks = 0
local last_player_x, last_player_y = nil, nil

local function verify_nearby()
    local ok, info, px, py = pcall(function()
        local position = hafen.session():current():player():gob():position()
        return position:info(), position:x(), position:y()
    end)
    if not ok or not info or not info.gridId or not px then
        settled_checks = 0
        return
    end
    if last_player_x and ((px - last_player_x) ^ 2 + (py - last_player_y) ^ 2) > 500 * 500 then
        settled_checks = 0                     -- a teleport: what is around is still arriving
    end
    last_player_x, last_player_y = px, py
    settled_checks = settled_checks + 1
    if settled_checks <= VERIFY_SETTLE then
        return
    end

    local members = rows_by_grid[tostring(info.gridId)]
    if not members then
        return
    end
    local limit = VERIFY_RADIUS * VERIFY_RADIUS
    local gone = {}
    for key in pairs(members) do
        local row = known_rows[key]
        if row and row.x and not live_keys[key] then
            local dx, dy = row.x - info.x, row.y - info.y
            if dx * dx + dy * dy < limit and #keys_near(live_buckets, live_coords, row.grid_id, row.x, row.y) == 0 then
                gone[#gone + 1] = key
            end
        end
    end
    for _, key in ipairs(gone) do
        forget_gob(key)
    end
end

-- Builds a Position for a cached row
local function resolve_position(world_subsystem, row)
    if not row.x or not row.y then
        return nil
    end
    local call_success, position = pcall(function()
        if row.grid_id ~= "" and row.grid_id:match("^%d+$") then
            return world_subsystem:position({ gridId = row.grid_id, x = row.x, y = row.y })
        end
        return world_subsystem:position(row.x, row.y)
    end)
    return call_success and position or nil
end

-- Restores ghosts for cached objects not live right now, a batch per tick
local restore_generation = 0
local function restore_cached_ghosts()
    restore_generation = restore_generation + 1
    local generation = restore_generation
    settled_checks = 0

    local world_subsystem = find_active_world_subsystem()
    if not world_subsystem then
        return
    end
    for _, game_object in ipairs(world_subsystem:gob():list()) do
        handle_gob_added(game_object, 0)
    end

    local queue = {}
    for position_key, row in pairs(known_rows) do
        if not live_keys[position_key] and drawable(row.resource_name, row.sdt) then
            local existing = active_virtual_ghosts[position_key]
            if not (existing and existing.ghost:exists()) then
                queue[#queue + 1] = position_key
            end
        end
    end

    local index = 1
    local function step()
        if generation ~= restore_generation then
            return
        end
        local world = find_active_world_subsystem()
        if not world then
            return
        end
        local stop = math.min(index + RESTORE_BATCH - 1, #queue)
        for i = index, stop do
            local position_key = queue[i]
            local row = known_rows[position_key]
            if row and not live_keys[position_key] then
                local position = resolve_position(world, row)
                if position then
                    spawn_virtual_ghost(position_key, row.resource_name, position, row.facing, row.scale,
                        row.grid_id, row.x, row.y, row.sdt)
                end
            end
        end
        index = stop + 1
        if index <= #queue then
            hafen.timer():after(0, step)
        end
    end
    step()
end

-- Event subscriptions
hafen.event():on("GobAdded", function(game_object)
    handle_gob_added(game_object, 3)
end)

hafen.event():on("GobRemoved", function(game_object)
    handle_gob_removed(game_object)
end)

hafen.event():on("GobSdtChanged", handle_sdt_changed)

-- Settle delay ensures MapView is attached and ready to receive virtual entities
hafen.event():on("SessionEnteredWorld", function()
    hafen.timer():after(0.6, restore_cached_ghosts)
end)

hafen.event():on("SessionSelected", function()
    hafen.timer():after(0.1, restore_cached_ghosts)
end)

-- Rows still queued are written before the addon goes away
hafen.event():on("Disable", flush_store)

hafen.timer():every(VERIFY_EVERY, verify_nearby)

-- Initial restoration on startup or console :reload
hafen.timer():after(0.6, restore_cached_ghosts)
