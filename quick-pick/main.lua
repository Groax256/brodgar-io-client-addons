-- Quick Pick -- one key picks up the nearest critter or herb near the character on screen.
--
-- A critter (anything under gfx/kritter/, and grubs) within reach comes first; with none in reach, the
-- nearest herb (gfx/terobjs/herbs/, and jellyfish). The pick is a right-click on it, and when that opens
-- a radial menu offering "Pick", the menu is picked without being painted. Animals you fight or lead
-- rather than catch are left alone: right-clicking one only walks you up to it.

local DEFAULT_KEY = "Q"
local MENU_WAIT   = 5      -- seconds a right-click may take to put its menu up
local TILE        = 11     -- world units per tile
local COLUMNS     = 3      -- checkboxes per row on the options page

local CRITTERS = { "gfx/kritter/", "gfx/terobjs/items/grub" }
local HERBS    = { "gfx/terobjs/herbs/", "gfx/kritter/jellyfish/" }

-- Every animal the page offers, by resource name: gfx/kritter/<family>/<kind>, and an entry names either
-- part (gfx/kritter/sheep/mouflon answers to "sheep" and to "mouflon"). An object is picked only when
-- every part of its name it has an entry for is ticked, so an unticked "caverat" holds back the cave rat
-- while "rat" still picks the rest. A name with no entry at all is picked.
--
-- What is ticked to begin with follows the Ring of Brodgar wiki: a critter, or an animal its page says you
-- catch by right-clicking, is ticked; one you fight, lead or have to kill first is not.
local CATCH = {
  {"bayshrimp", "Bay Shrimp"}, {"bogturtle", "Bog Turtle"}, {"brimstonebutterfly", "Brimstone Butterfly"},
  {"bullfinch", "Bullfinch"}, {"cavecentipede", "Cave Centipede"}, {"cavemoth", "Cave Moth"},
  {"chicken", "Chicken"}, {"crab", "Crab"}, {"cranefly", "Crane Fly"}, {"dragonfly", "Dragonfly"},
  {"dumbledore", "Dumbledore"}, {"earthworm", "Earthworm"}, {"firefly", "Firefly"},
  {"forestlizard", "Forest Lizard"}, {"forestsnail", "Forest Snail"}, {"frog", "Frog"},
  {"garefowl", "Garefowl"}, {"grasshopper", "Grasshopper"}, {"grub", "Grub"}, {"hedgehog", "Hedgehog"},
  {"irrbloss", "Irrlight"}, {"jellyfish", "Jellyfish"}, {"ladybug", "Ladybug"}, {"lobster", "Lobster"},
  {"magpie", "Magpie"}, {"mallard", "Mallard"}, {"mole", "Mole"}, {"monarchbutterfly", "Monarch Butterfly"},
  {"moonmoth", "Moonmoth"}, {"opiumdragon", "Opium Dragon"}, {"ptarmigan", "Ptarmigan"}, {"quail", "Quail"},
  {"rabbit", "Rabbit"}, {"rat", "Rat"}, {"rockdove", "Rock Dove"}, {"sandflea", "Sand Flea"},
  {"seagull", "Seagull"}, {"silkmoth", "Silkmoth"}, {"springbumblebee", "Springtime Bumblebee"},
  {"squirrel", "Squirrel"}, {"stagbeetle", "Stag Beetle"}, {"stalagoomba", "Stalagoomba"}, {"swan", "Swan"},
  {"tick", "Tick"}, {"toad", "Toad"}, {"waterstrider", "Waterstrider"},
  {"whirlingsnowflake", "Whirling Snowflake"}, {"woodgrouse", "Wood Grouse"},
  {"woodscorpion", "Wood Scorpion"}, {"woodworm", "Woodworm"},
}
local FIGHT = {
  {"adder", "Adder"}, {"ant", "Ant"}, {"ants", "Ants"}, {"badger", "Badger"}, {"bat", "Bat"},
  {"bear", "Bear"}, {"beaver", "Beaver"}, {"bees", "Bees"}, {"boar", "Boar"}, {"boreworm", "Boreworm"},
  {"spermwhale", "Cachalot"}, {"cattle", "Cattle"}, {"caveangler", "Cave Angler"},
  {"cavelouse", "Cave Louse"}, {"caverat", "Cave Rat"}, {"chasmconch", "Chasm Conch"}, {"crane", "Crane"},
  {"dryad", "Dryad"}, {"eagleowl", "Eagle Owl"}, {"fox", "Fox"}, {"goat", "Goat"},
  {"goldeneagle", "Golden Eagle"}, {"goshawk", "Goshawk"}, {"ooze", "Green Ooze"},
  {"greyseal", "Grey Seal"}, {"horse", "Horse"}, {"lynx", "Lynx"}, {"mammoth", "Mammoth"},
  {"midgeswarm", "Midge Swarm"}, {"moose", "Moose"}, {"narwhal", "Narwhal"}, {"nidbane", "Nidbane"},
  {"orca", "Orca"}, {"otter", "Otter"}, {"pelican", "Pelican"}, {"pig", "Pig"}, {"ratking", "Rat King"},
  {"reddeer", "Red Deer"}, {"reindeer", "Reindeer"}, {"roedeer", "Roe Deer"}, {"seal", "Seal"},
  {"sheep", "Sheep"}, {"stoat", "Stoat"}, {"ent", "Treant"}, {"troll", "Troll"}, {"walrus", "Walrus"},
  {"wildbees", "Wild Bees"}, {"wolf", "Wolf"}, {"wolverine", "Wolverine"},
}

local options = hafen.client():options():addon()
local reach   = options:number("reach"):range(1, 30):default(8):add()        -- tiles

local picks = {}            -- [resource name part] = the boolean option: ticked is picked
for _, entry in ipairs(CATCH) do picks[entry[1]] = options:boolean("pick-" .. entry[1]):default(true):add() end
for _, entry in ipairs(FIGHT) do picks[entry[1]] = options:boolean("pick-" .. entry[1]):default(false):add() end

local function startsWithAny(name, prefixes)
  for _, prefix in ipairs(prefixes) do
    if name:sub(1, #prefix) == prefix then return true end
  end
  return false
end

local function wanted(name)
  local rest = name:match("^gfx/kritter/(.+)")
  if rest then
    for part in rest:gmatch("[^/]+") do
      local option = picks[part]
      if option and not option:value() then return false end
    end
  end
  return true
end

-- The nearest gob whose name starts with one of `prefixes`, within reach, or nil.
local function nearest(world, prefixes)
  local found = world:gob():nearest(function(gob)
    if gob:id() < 0 then return false end              -- client-only effects, never pickable
    local name = gob:name()
    return name ~= nil and startsWithAny(name, prefixes) and wanted(name)
  end)
  local distance = found and found:distance()
  if distance and distance <= reach:value() * TILE then return found end
  return nil
end

-- The gob the last press right-clicked, until its menu comes up or MENU_WAIT runs out.
local pending

local keybindings = hafen.client():options():keybindings()
keybindings:on("pick", function()
  local session = hafen.session():current()
  local world = session and session:world()
  if not world then return end
  local target = nearest(world, CRITTERS) or nearest(world, HERBS)
  if not target then return end
  pending = target
  world:click(target, 3)
  hafen.timer():after(MENU_WAIT, function()
    if pending == target then pending = nil end
  end)
end)

hafen.event():on("FlowerMenuAdded", function(petals, session)
  if not pending or session:flowermenu():gob() ~= pending then return end
  pending = nil
  for _, petal in ipairs(petals) do
    if petal:label() == "Pick" then
      session:flowermenu():visible(false):select("Pick")
      return
    end
  end
  -- No "Pick" on the ring: leave it up for the player.
end)

-- The hotkey sits on Q for as long as the user has not chosen a key of their own. A key they assign, or
-- "None", is theirs and stays; one they themselves put on Q is left alone.
local pick_binding = keybindings:binding():get("pick")
if not pick_binding:assigned() then
  local held = false
  for _, binding in ipairs(keybindings:binding():list()) do
    if binding ~= pick_binding and binding:assigned() and binding:key() == DEFAULT_KEY then held = true break end
  end
  if held then
    hafen.log():write("Quick Pick: " .. DEFAULT_KEY .. " is assigned elsewhere; assign a key in Options > AddOns > Quick Pick")
  else
    local ok, problem = pcall(function() pick_binding:key(DEFAULT_KEY) end)
    if not ok then hafen.log():write("Quick Pick: could not put the key on " .. DEFAULT_KEY .. ": " .. tostring(problem)) end
  end
end

-- One section of ticks, COLUMNS to a row, each with its resource name as hover text.
local function addChecks(root, caption, entries)
  hafen.ui():label():parent(root):text(caption)
  local row = hafen.ui():row():gap(16):parent(root)
  local columns = {}
  for index = 1, COLUMNS do columns[index] = hafen.ui():column():gap(2):parent(row) end
  local per_column = math.ceil(#entries / COLUMNS)
  for index, entry in ipairs(entries) do
    local column = columns[math.floor((index - 1) / per_column) + 1]
    hafen.ui():check():parent(column):text(entry[2]):tooltip("resource name part: " .. entry[1]):bind(picks[entry[1]])
  end
end

options:panel(function(root)
  root:gap(6)
  local key_row = hafen.ui():row():gap(8):parent(root)
  hafen.ui():label():parent(key_row):text("Pick up the nearest")
  hafen.ui():keybinding():parent(key_row):bind(pick_binding)

  -- A slider shows no number, so its label carries the value.
  local reach_label = hafen.ui():label():parent(root):text("Reach: " .. reach:value() .. " tiles")
  local reach_slider = hafen.ui():slider():parent(root):size(200):bind(reach)
  reach_slider:on("Changed", function(event) reach_label:text("Reach: " .. event:value() .. " tiles") end)

  addChecks(root, "Critters: ticked ones are picked up", CATCH)
  addChecks(root, "Animals you fight or lead: ticked ones are clicked too", FIGHT)
end)
