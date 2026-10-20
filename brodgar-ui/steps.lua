-- The pages of the setup guide (guide.lua turns them). A step is {title = ..., build = function(column),
-- centred = true or nil}: build fills a column the guide made for that page, and a centred one is placed in the
-- middle of the page once built.
--
-- A control's Changed runs inside the addon layer's tree, while a client option or another addon's option is
-- written from the step, which holds no tree (api/threading.md): every write goes through write(), a timer of 0.
--
-- A bundled addon gets a page of its own when it exports two functions:
--   setup()              -> {title =, summary =, settings = {{name =, label =, type =, tooltip =, ...}, ...}}
--                           a "choice" setting carries choices = {...}, a "number" min = and max =
--   setting(name[, v])   -> reads the value of that setting, or writes v first; the addon's own option does the work

BrodgarUI = {}

local Steps = {}
BrodgarUI.Steps = Steps

-- The addons this bundle carries, in the order their pages and their keys are shown.
local MEMBERS = {
  "themes", "simple-minimap", "simple-chat", "quick-search", "actionbars",
  "hider", "hitboxes", "stockpile-take", "multi-session",
}

-- The interface sizes offered, as the Options window's scale.
local INTERFACE_SIZES = {1.0, 1.25, 1.5, 1.75, 2.0}

-- The client's cameras, by the names :cam and Options > Game > Camera use.
local CAMERAS = {"follow", "worse", "bad", "ortho", "rts"}

local CONTROL_WIDTH = 180
local KEY_BUTTON_WIDTH = 130
local HEADING_WIDTH = 380

-- ---------------------------------------------------------------- building blocks

local function write(what, callback)
  hafen.timer():after(0, function()
    local written, failure = pcall(callback)
    if not written then
      hafen.log():write("setup guide: " .. what .. " was not written -- " .. tostring(failure))
    end
  end)
end

local function addLine(column, text)
  return hafen.ui():label():parent(column):text(text)
end

local function addHeading(column, text)
  hafen.ui():separator():parent(column):size(HEADING_WIDTH)
  return addLine(column, text)
end

local function contains(list, value)
  for _, entry in ipairs(list) do
    if entry == value then return true end
  end
  return false
end

-- A dropdown with its caption above it. onPick(row) runs when the user picks another row.
local function addDropdown(column, caption, rows, current, onPick, tooltip)
  addLine(column, caption)
  local dropdown = hafen.ui():dropdown():parent(column):size(CONTROL_WIDTH):rows(rows)
  if tooltip then dropdown:tooltip(tooltip) end
  if contains(rows, current) then dropdown:value(current) end
  dropdown:on("Changed", onPick)
  return dropdown
end

-- A slider whose caption carries its value, since a slider shows no number. onRelease(value) runs once the
-- user lets go of the knob.
local function addSlider(column, caption, low, high, current, describe, onRelease, tooltip)
  local label = addLine(column, caption .. ": " .. describe(current))
  local slider = hafen.ui():slider():parent(column):size(CONTROL_WIDTH):range(low, high):value(current)
  if tooltip then slider:tooltip(tooltip) end
  slider:on("Changed", function(event)
    local value = math.floor(event:value() + 0.5)
    label:text(caption .. ": " .. describe(value))
    if event:final() then onRelease(value) end
  end)
  return slider
end

local function addCheck(column, caption, current, onChange, tooltip)
  local check = hafen.ui():check():parent(column):text(caption):value(current == true)
  if tooltip then check:tooltip(tooltip) end
  check:on("Changed", onChange)
  return check
end

local function asPercent(value)
  return value .. "%"
end

local function asNumber(value)
  return tostring(value)
end

-- ---------------------------------------------------------------- welcome

-- Lines centred on one another: a column keeps every child at its left edge, so each line stands in a row
-- after a blank widget half the difference to the widest line wide.
local function addCentredLines(column, lines)
  local spacers, labels, widest = {}, {}, 0
  for index, text in ipairs(lines) do
    local row = hafen.ui():row():parent(column)
    spacers[index] = hafen.ui():widget():parent(row):size(1, 1)
    labels[index] = hafen.ui():label():parent(row):text(text)
    widest = math.max(widest, labels[index]:size().w)
  end
  for index, label in ipairs(labels) do
    spacers[index]:size(math.max(1, math.floor((widest - label:size().w) / 2)), 1)
  end
end

local function buildWelcome(column)
  addCentredLines(column, {
    "Welcome to Brodgar UI.",
    "",
    "This guide sets up the client and the nine addons",
    "that come with it, one page at a time.",
    "",
    "Every change applies at once, and every page can be",
    "skipped: all of it is in Options as well.",
  })
end

-- ---------------------------------------------------------------- the client

local function interfaceSizeRow(scale)
  return math.floor(scale * 100 + 0.5) .. "%"
end

local function buildClient(column)
  local options = hafen.client():options()

  local sizeRows, scaleOfRow = {}, {}
  for _, scale in ipairs(INTERFACE_SIZES) do
    local row = interfaceSizeRow(scale)
    sizeRows[#sizeRows + 1] = row
    scaleOfRow[row] = scale
  end
  addDropdown(column, "Interface size", sizeRows, interfaceSizeRow(options:interface():scale()), function(row)
    write("the interface size", function() options:interface():scale(scaleOfRow[row]) end)
  end, "how big the windows, buttons and text are drawn")
  addLine(column, "The new size shows the next time the client starts.")
  addLine(column, "")

  addCheck(column, "Shadows", options:video():shadows(), function(checked)
    write("shadows", function() options:video():shadows(checked) end)
  end, "objects cast shadows on the ground; off draws faster")
  addLine(column, "")

  addDropdown(column, "Camera", CAMERAS, options:camera():mode(), function(mode)
    write("the camera", function() options:camera():mode(mode) end)
  end, "the camera the world is drawn through, as :cam names it")
  addLine(column, "")

  local volume = options:audio():masterVolume() or 1
  addSlider(column, "Volume", 0, 100, math.floor(volume * 100 + 0.5), asPercent, function(value)
    write("the volume", function() options:audio():masterVolume(value / 100) end)
  end, "the loudness of every sound the client plays")
end

-- ---------------------------------------------------------------- keys

-- Ids ordered with their numbers read as numbers, so "slot 2" comes before "slot 10".
local function naturalKey(text)
  return (string.gsub(text, "%d+", function(digits) return string.format("%08d", tonumber(digits)) end))
end

-- The hotkeys an addon has declared, by the registry's ids ("addon/<id>/<name>"), in natural order.
local function hotkeysOf(id)
  local prefix = "addon/" .. id .. "/"
  local bindings = {}
  for _, binding in ipairs(hafen.client():options():keybindings():binding():list(prefix)) do
    if string.sub(binding:id(), 1, #prefix) == prefix then
      bindings[#bindings + 1] = binding
    end
  end
  table.sort(bindings, function(first, second) return naturalKey(first:id()) < naturalKey(second:id()) end)
  return bindings, prefix
end

-- The bindings a key button takes right now: another addon's hotkey only while that addon declares it. Asked
-- of one bare key button, destroyed before it is ever drawn.
local function bindable(bindings)
  local probe = hafen.ui():keybinding()
  local accepted = {}
  for _, binding in ipairs(bindings) do
    if pcall(probe.bind, probe, binding) then
      accepted[#accepted + 1] = binding
    end
  end
  probe:destroy()
  return accepted
end

-- The addon's name, then one row per hotkey: the client's own key button joined to that addon's binding, and
-- the hotkey's name. An addon that is off, or has no hotkey declared, gets nothing.
local function addHotkeys(column, id)
  local info = hafen.client():addons():get(id):info()
  if info == nil or info.status ~= "loaded" then return end
  local bindings, prefix = hotkeysOf(id)
  bindings = bindable(bindings)
  if #bindings == 0 then return end
  addHeading(column, info.name)
  for _, binding in ipairs(bindings) do
    local row = hafen.ui():row():gap(8):parent(column)
    hafen.ui():keybinding():parent(row):size(KEY_BUTTON_WIDTH):bind(binding)
    addLine(row, string.sub(binding:id(), #prefix + 1))
  end
end

local function buildKeys(column)
  addLine(column, "Click a button, then press the key you want.")
  addLine(column, "Escape cancels, Delete leaves it without a key.")
  for _, id in ipairs(MEMBERS) do
    addHotkeys(column, id)
  end
end

-- ---------------------------------------------------------------- a bundled addon's own page

local function copyOf(list)
  local copy = {}
  for index, entry in ipairs(list) do copy[index] = entry end
  return copy
end

local function addSetting(column, api, setting)
  local read, current = pcall(api.setting, setting.name)
  if not read then
    addLine(column, setting.label .. ": unavailable")
    return
  end
  local function writeSetting(value)
    write(setting.label, function() api.setting(setting.name, value) end)
  end
  if setting.type == "boolean" then
    addCheck(column, setting.label, current, writeSetting, setting.tooltip)
  elseif setting.type == "choice" then
    addDropdown(column, setting.label, copyOf(setting.choices), current, writeSetting, setting.tooltip)
  elseif setting.type == "number" then
    addSlider(column, setting.label, setting.min, setting.max, current, asNumber, writeSetting, setting.tooltip)
  end
end

-- The page of a bundled addon that exports setup() and setting(); nil for one that is off or exports neither.
local function addonStep(id)
  local api = hafen.client():addons():get(id):api()
  if api == nil or type(api.setup) ~= "function" or type(api.setting) ~= "function" then return nil end
  local described, description = pcall(api.setup)
  if not described or type(description) ~= "table" or type(description.settings) ~= "table" then return nil end
  if #description.settings == 0 then return nil end
  return {
    title = description.title or id,
    build = function(column)
      if description.summary then
        addLine(column, description.summary)
        addLine(column, "")
      end
      for _, setting in ipairs(description.settings) do
        addSetting(column, api, setting)
      end
    end,
  }
end

-- ---------------------------------------------------------------- done

local function buildDone(column)
  addLine(column, "That's it: the client is set up.")
  addLine(column, "")
  addLine(column, "Open this guide again with :brodgarui in the console,")
  addLine(column, "or from Options > AddOns > Brodgar UI.")
end

-- ---------------------------------------------------------------- the list

-- The pages for the addons that are on right now: the client, the look, the keys, then each addon's own.
function Steps.list()
  local steps = {
    {title = "Welcome", build = buildWelcome, centred = true},
    {title = "The client", build = buildClient},
  }
  local themeStep = addonStep("themes")
  if themeStep then steps[#steps + 1] = themeStep end
  steps[#steps + 1] = {title = "Keys", build = buildKeys}
  for _, id in ipairs(MEMBERS) do
    if id ~= "themes" then
      local step = addonStep(id)
      if step then steps[#steps + 1] = step end
    end
  end
  steps[#steps + 1] = {title = "Done", build = buildDone}
  return steps
end
