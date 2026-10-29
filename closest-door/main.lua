-- Closest Door -- one key (Shift+A unless you change it) goes through the door nearest the character on
-- screen: a house's front door, a door inside one, a ladder, a staircase, a cellar, a mine's way in or out.
--
-- A building's door is one part of the building's mesh, and the server only lets you in when the click
-- names that part, so a building is clicked at its door point with the door's mesh id: the message a real
-- right-click on the door sends. world:click names the whole object and cannot carry a mesh id, which is
-- why this goes out through the map view's own "click" (widget.send). Everything else -- the doors inside a
-- building, ladders, stairs, cave entrances -- is the whole object, clicked where it stands.

local DEFAULT_KEY = "Shift+A"
local REACH       = 40 * 11   -- world units: forty tiles
local NO_MESH     = -1        -- the mesh id of a click on the whole object

-- Each building's doors: where the door stands, in world units from the building's centre before the
-- building's own facing turns it, and the id of the door's part of the mesh.
local BUILDINGS = {
  ["gfx/terobjs/arch/logcabin"]       = { {22, 0, 16} },
  ["gfx/terobjs/arch/timberhouse"]    = { {33, 0, 16} },
  ["gfx/terobjs/arch/stonestead"]     = { {44, 0, 16} },
  ["gfx/terobjs/arch/stonemansion"]   = { {48, 0, 16} },
  ["gfx/terobjs/arch/greathall"]      = { {77, -28, 18}, {77, 0, 17}, {77, 28, 16} },
  ["gfx/terobjs/arch/stonetower"]     = { {36, 0, 16} },
  ["gfx/terobjs/arch/windmill"]       = { {0, 28, 16} },
  -- The great hall's inside door has three doors of its own, so it is a building here too.
  ["gfx/terobjs/arch/greathall-door"] = { {0, -30, 18}, {0, 0, 17}, {0, 30, 16} },
}

-- Everything else that is a way through, by the end of its resource name.
local PASSAGES = { "-door", "ladder", "upstairs", "downstairs", "cellarstairs", "cavein", "caveout" }

local function isPassage(name)
  for _, suffix in ipairs(PASSAGES) do
    if name:sub(-#suffix) == suffix then return true end
  end
  return false
end

local function isWayThrough(gob)
  local name = gob:name()
  return name ~= nil and (BUILDINGS[name] ~= nil or isPassage(name))
end

-- The nearest door within reach of `from`: the object to click, the place to click it at and its mesh id.
local function nearestDoor(world, from)
  local best
  for _, gob in ipairs(world:gob():list(isWayThrough)) do
    local position = gob:position()
    if position then
      local doors = BUILDINGS[gob:name()]
      if doors then
        local facing = gob:facing() or 0
        local c, s = math.cos(facing), math.sin(facing)
        for _, door in ipairs(doors) do
          local dx, dy, mesh = door[1], door[2], door[3]
          local at = position:offset(dx * c - dy * s, dy * c + dx * s)
          local distance = from:distance(at)
          if distance and (not best or distance < best.distance) then
            best = { gob = gob, at = at, mesh = mesh, distance = distance }
          end
        end
      else
        local distance = from:distance(position)
        if distance and (not best or distance < best.distance) then
          best = { gob = gob, at = position, mesh = NO_MESH, distance = distance }
        end
      end
    end
  end
  if best and best.distance <= REACH then return best end
  return nil
end

local keybindings = hafen.client():options():keybindings()
keybindings:on("door", function()
  local session = hafen.session():current()
  local world = session and session:world()
  local me = session and session:player():gob()
  local from = me and me:position()
  if not (world and from) then return end
  local door = nearestDoor(world, from)
  if not door then return end
  local map = session:ui():match("@MapView")
  if not map then return end
  -- A right-click on the door: screen point, map point, button 3, no modifiers, then the object clicked
  -- ({no overlay, id, where, overlay id, mesh id}). A Position goes on the wire as the map's own coordinate.
  map:send("click", {x = 0, y = 0}, door.at, 3, 0, 0, door.gob:id(), door.at, 0, door.mesh)
end)

-- The hotkey sits on Shift+A for as long as the user has not chosen a key of their own. A key they assign,
-- or "None", is theirs and stays.
local door_binding = keybindings:binding():get("door")
if not door_binding:assigned() then
  local held = false
  for _, binding in ipairs(keybindings:binding():list()) do
    if binding ~= door_binding and binding:assigned() and binding:key() == DEFAULT_KEY then held = true break end
  end
  if held then
    hafen.log():write("Closest Door: " .. DEFAULT_KEY .. " is assigned elsewhere; assign a key in Options > AddOns > Closest Door")
  else
    local ok, problem = pcall(function() door_binding:key(DEFAULT_KEY) end)
    if not ok then hafen.log():write("Closest Door: could not put the key on " .. DEFAULT_KEY .. ": " .. tostring(problem)) end
  end
end

hafen.client():options():addon():panel(function(root)
  local key_row = hafen.ui():row():gap(8):parent(root)
  hafen.ui():label():parent(key_row):text("Go through the closest door")
  hafen.ui():keybinding():parent(key_row):bind(door_binding)
end)
