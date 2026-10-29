-- Inspect Info: res-name tooltip while inspecting, res name appended to the Inspect answer, and the
-- inspected quality labelled over the object. Settings in Options > AddOns > Inspect Info.
--
-- Inspect cursor: the server sets it with "curs" to the root widget as a per-login resource number. The
-- glass's number is learned from the "curs" after "act inspect", or from the cursor up when an answer lands.
-- Answer matching: the answer names no object, so the clicked gob is kept per login until the first line
-- carrying a quality (read from the System log, so msg and msg2 both count). The next map click replaces it;
-- 60 s without an answer drops it.
-- Storage: gob ids change between sessions, so a quality is keyed by res name + durable grid position.
-- :inspectinfo logs every message an inspection moves for 60 s.

local OVERLAY_KEY = "quality"
local TIP_KEY = "tip"
local INSPECT_ACT = "inspect"      -- the action data of paginae/act/inspect
local ANSWER_TIMEOUT = 60         -- seconds a click waits for its answer, the walk to the object included
local NAMING_WINDOW = 2.0          -- seconds in which a line with no quality is still the click's answer
local MAX_REMEMBERED = 5000        -- the oldest inspection is forgotten past this many

-- A gob still resolving has no name or place yet and refuses the overlay; try again this often.
local RETRY_DELAY = 0.5
local RETRY_COUNT = 10

local POINTER_GAP = 18
local PLATE_PADDING = 4
local LINE_HEIGHT = 14
local PLATE_COLOUR = {18, 20, 24, 215}
local NAME_COLOUR = {236, 238, 242}
local QUALITY_COLOUR = {255, 220, 120}
local TIP_FONT = hafen.font():get("sans"):derive():size(11)

local TEXT_COLORS = {
  {"White",  {255, 255, 255}},
  {"Yellow", {255, 230, 90}},
  {"Orange", {255, 170, 60}},
  {"Green",  {140, 230, 110}},
  {"Cyan",   {110, 220, 240}},
  {"Pink",   {255, 150, 210}},
}
local TEXT_COLOR_NAMES = {}
local TEXT_COLOR_VALUES = {}
for _, entry in ipairs(TEXT_COLORS) do
  table.insert(TEXT_COLOR_NAMES, entry[1])
  TEXT_COLOR_VALUES[entry[1]] = entry[2]
end

local BACKGROUND_PADDING = 2   -- design pixels between the text and the edge of its background

local options = hafen.client():options():addon()
local hoverOption = options:boolean("show-hover"):default(true):add()
local resNameOption = options:boolean("show-resname"):default(true):add()
local qualityOption = options:boolean("show-quality"):default(true):add()
local textColorOption = options:choice("text-color"):choices(TEXT_COLOR_NAMES):default("White"):add()
local textSizeOption = options:number("text-size"):range(8, 24):default(11):add()
local backgroundOption = options:boolean("background"):default(true):add()
local backgroundOpacityOption = options:number("background-opacity"):range(10, 100):default(60):add()  -- percent
local heightOption = options:number("height"):range(0, 40):default(15):add()   -- world units up the object

-- ["gfx/terobjs/barrel@<grid id>,<x>,<y>"] = {q = 23, t = os.time()}
local remembered = hafen.store():var("quality-by-place")

-- Bold with a black outline so the text reads over grass, snow and floors alike.
local function buildFont(size)
  return hafen.font():get("sans"):derive():size(size):bold(true):outline{0, 0, 0}
end
local labelFont = buildFont(textSizeOption:value())

-- ---- the Inspect cursor, per login -----------------------------------------------------------------------

-- [session user] = {cursor = what the root shows now, study = the glass's number, expectStudy = bool}
local logins = {}

local function loginOf(session)
  session = session or hafen.session():current()
  local user = session and session:user()
  if not user then return nil end
  local login = logins[user]
  if not login then
    login = {}
    logins[user] = login
  end
  return login
end

-- true / false when this login knows its glass, nil while it has not learned it yet.
local function inspecting(session)
  local login = loginOf(session)
  if not login or login.study == nil then return nil end
  return login.cursor == login.study
end

hafen.event():action():on("act", function(event)
  if event:args()[1] ~= INSPECT_ACT then return end
  local login = loginOf(event:widget():session())
  if login then login.expectStudy = true end
end)

local trace   -- defined with the inspection below

hafen.event():message():on("curs", function(event)
  trace("curs to " .. event:widget():type() .. ": " .. tostring(event:args()[1]))
  if event:widget():type() ~= "RootWidget" then return end
  local login = loginOf(event:widget():session())
  if not login then return end
  local cursor = event:args()[1]
  login.cursor = cursor
  if type(cursor) == "string" then
    if cursor:find("curs/study", 1, true) then login.study = cursor end
  elseif cursor ~= nil and login.expectStudy then
    login.study = cursor
  end
  login.expectStudy = false
end)

-- ---- the label over the object ---------------------------------------------------------------------------

local function round(value)
  return math.floor(value + 0.5)
end

-- nil while the object has no name or no durable place yet.
local function placeKey(gob)
  local name = gob:name()
  local place = gob:position()
  local anchored = name and place and place:durable() and place:info()
  if not anchored then return nil end
  return name .. "@" .. anchored.gridId .. "," .. round(anchored.x) .. "," .. round(anchored.y)
end

-- The text kind is drawn by the client with no Lua per frame; the background needs a painter.
local function attachLabel(gob, quality)
  local labelText = "q" .. quality
  local labelOverlay = gob:overlay():add(OVERLAY_KEY)
  local textColor = TEXT_COLOR_VALUES[textColorOption:value()] or TEXT_COLOR_VALUES.White
  if not backgroundOption:value() then
    labelOverlay:text(labelText):color(textColor):font(labelFont)
  else
    local textOptions = {font = labelFont, color = textColor}
    local textBox = hafen.ui():measure(labelText, {font = labelFont})
    local backgroundAlpha = math.floor(backgroundOpacityOption:value() * 255 / 100)
    labelOverlay:draw(function(graphics, _, screen_x, screen_y)
      -- Bottom-centred on the point, where the text kind puts its label.
      local left = screen_x - textBox.w / 2
      local top = screen_y - textBox.h
      graphics:color(0, 0, 0, backgroundAlpha)
      graphics:frect(left - BACKGROUND_PADDING, top - BACKGROUND_PADDING,
        textBox.w + 2 * BACKGROUND_PADDING, textBox.h + 2 * BACKGROUND_PADDING)
      graphics:color()
      graphics:text(labelText, left, top, textOptions)
    end)
  end
  labelOverlay:height(heightOption:value())
end

-- Labels the object with what is filed under its place. `quality` labels it with that instead, filing it
-- first. A gob still resolving is asked again on a timer.
local function label(gob, quality, retriesLeft)
  if not gob:exists() then return end
  local key = placeKey(gob)
  if key and quality then
    remembered[key] = {q = quality, t = os.time()}
  end
  local entry = key and remembered[key]
  local shown = quality or (entry and entry.q)
  local wantsLabel = qualityOption:value() and shown ~= nil
  local attached = wantsLabel and gob:name() ~= nil and pcall(attachLabel, gob, shown)
  -- Retry until the label is up and, for a new quality, until it is filed too.
  local done = (not wantsLabel or attached) and (not quality or key ~= nil)
  if not done and retriesLeft > 0 then
    hafen.timer():after(RETRY_DELAY, function() label(gob, quality, retriesLeft - 1) end)
  end
end

local function forgetOldest()
  local count, oldestKey, oldestTime = 0, nil, math.huge
  for key, entry in pairs(remembered) do
    count = count + 1
    local time = entry.t or 0
    if time < oldestTime then oldestKey, oldestTime = key, time end
  end
  if count > MAX_REMEMBERED and oldestKey then remembered[oldestKey] = nil end
end

local function isRemembered(gob)
  local key = placeKey(gob)
  return key ~= nil and remembered[key] ~= nil
end

-- A remove reaches only the copies of sessions that still hold the object, so every session is asked.
local function hideAll()
  for _, session in ipairs(hafen.session():list()) do
    for _, gob in ipairs(session:world():gob():list()) do
      gob:overlay():remove(OVERLAY_KEY)
    end
  end
end

local function labelAll(session)
  for _, gob in ipairs(session:world():gob():list(isRemembered)) do
    label(gob, nil, RETRY_COUNT)
  end
end

local function refreshAll()
  if not qualityOption:value() then
    hideAll()
    return
  end
  for _, session in ipairs(hafen.session():list()) do labelAll(session) end
end

-- ---- the inspection --------------------------------------------------------------------------------------

-- :inspectinfo -- for a minute, every message an inspection moves is written to the console.
local traceUntil = 0
function trace(text)
  if os.clock() < traceUntil then hafen.log():write(text) end
end

local function describeArgs(args)
  local parts = {}
  for index = 1, #args do
    local value = args[index]
    if type(value) == "table" and value.x then
      parts[index] = "{" .. tostring(value.x) .. "," .. tostring(value.y) .. "}"
    elseif type(value) == "string" then
      parts[index] = string.format("%q", value)
    else
      parts[index] = type(value) == "userdata" and "<" .. type(value) .. ">" or tostring(value)
    end
  end
  return table.concat(parts, ", ")
end

-- The click of that login still waiting for its answer, or nil. login.pending = {gob, name, at, named}.
local function openClick(login)
  local click = login and login.pending
  if click and os.clock() - click.at <= ANSWER_TIMEOUT then return click end
  return nil
end

local function qualityIn(text)
  return text:match("[Qq]uality:?%s*(%d+)")
end

-- One line that may be the answer, wherever it was read. One carrying a quality is: it labels the object
-- and ends the wait. Answers true when it did.
local function takeAnswer(login, click, text)
  local quality = qualityIn(text)
  if not quality then return false end
  -- An answer came back, so whatever the root shows now is the glass, if this login did not know it yet.
  if login.study == nil and login.cursor ~= nil then login.study = login.cursor end
  login.pending = nil
  local gob = click.gob
  trace("answer for " .. tostring(click.name) .. ": quality " .. quality)
  -- The label is an overlay write; it waits for the step rather than running inside a delivery.
  hafen.timer():after(0, function()
    label(gob, tonumber(quality), RETRY_COUNT)
    forgetOldest()
  end)
  return true
end

-- A left-click on an object, with the glass up, is the object an answer will be about; any other map click
-- of that login ends the wait.
hafen.event():action():on("click", function(event)
  if event:widget():type() ~= "MapView" then return end
  local gob = event:gob()
  local session = event:widget():session()
  local login = loginOf(session)
  if not login then return end
  local button = event:args()[3]
  local glass = inspecting(session)
  trace("click: button " .. tostring(button) .. " on " .. (gob and (gob:name() or "?") or "the ground")
    .. ", inspecting " .. tostring(glass))
  if gob and button == 1 and glass ~= false then
    login.pending = {gob = gob, name = gob:name(), at = os.clock()}
  else
    login.pending = nil
  end
end)

-- A plain text answer, before the HUD draws it: the resource name joins the line that carries a quality,
-- or, from an object with none, the line that comes straight after the click.
hafen.event():message():on("msg", function(event)
  local args = event:args()
  trace("msg to " .. event:widget():type() .. ": " .. describeArgs(args))
  local login = loginOf(event:widget():session())
  local click = openClick(login)
  local text = args[1]
  if not click or type(text) ~= "string" then return end
  local isAnswer = qualityIn(text) ~= nil or os.clock() - click.at <= NAMING_WINDOW
  local name = click.name or (click.gob:exists() and click.gob:name()) or nil
  if resNameOption:value() and isAnswer and name and not click.named then
    click.named = true
    args[1] = text .. "  (" .. name .. ")"
    event:rewrite(args)
  end
  takeAnswer(login, click, text)
end)

-- An answer the client words from a resource of the server's has no text on the wire; the System log line
-- the HUD writes for it does, and so does the line of a plain answer. Our own console lines are skipped.
hafen.event():on("MessageAdded", function(message, session)
  if message:kind() ~= "chat.system" then return end
  local text = message:raw() or message:text()
  if not text or text:find("inspect-info", 1, true) then return end
  trace("system line: " .. text)
  local login = loginOf(session)
  local click = openClick(login)
  if click then takeAnswer(login, click, text) end
end)

hafen.event():message():on("msg2", function(event)
  trace("msg2 to " .. event:widget():type() .. ": " .. describeArgs(event:args()))
end)

hafen.event():action():on("act", function(event)
  trace("act: " .. describeArgs(event:args()))
end)

hafen.console():on("inspectinfo", function()
  traceUntil = os.clock() + 60
  local login = loginOf(nil)
  hafen.log():write("tracing for 60 s; glass " .. tostring(login and login.study)
    .. ", cursor now " .. tostring(login and login.cursor))
end)

-- ---- the tooltip while inspecting ------------------------------------------------------------------------

local hoveredGob = nil
local pickSub = nil      -- held only while the tooltip is up; holding it is what runs the client's pick pass

local function tipLines()
  local gob = hoveredGob
  if gob and gob:exists() then
    local lines = {{text = gob:name() or "(still loading)", colour = NAME_COLOUR}}
    local key = placeKey(gob)
    local entry = key and remembered[key]
    if entry then lines[2] = {text = "q" .. entry.q, colour = QUALITY_COLOUR} end
    return lines
  end
  local place = hafen.ui():mouse():ground()
  local session = hafen.session():current()
  local tile = place and session and session:world():tile(place)
  if tile then return {{text = tile.name or "(still loading)", colour = NAME_COLOUR}} end
  return nil
end

-- A line's width, measured once per distinct string; emptied rather than grown without bound.
local measuredWidth, measuredCount = {}, 0
local function widthOf(text)
  local width = measuredWidth[text]
  if not width then
    if measuredCount > 400 then measuredWidth, measuredCount = {}, 0 end
    width = hafen.ui():measure(text, {font = TIP_FONT}).w
    measuredWidth[text], measuredCount = width, measuredCount + 1
  end
  return width
end

local function paintTip(graphics, screenWidth, screenHeight)
  local lines = tipLines()
  if not lines then return end
  local width = 0
  for _, line in ipairs(lines) do width = math.max(width, widthOf(line.text)) end
  local height = #lines * LINE_HEIGHT
  local mouse = hafen.ui():mouse()
  local left, top = mouse:x() + POINTER_GAP, mouse:y() + POINTER_GAP
  if left + width + PLATE_PADDING > screenWidth then left = mouse:x() - POINTER_GAP - width end
  if top + height + PLATE_PADDING > screenHeight then top = mouse:y() - POINTER_GAP - height end
  graphics:color(PLATE_COLOUR)
  graphics:frect(left - PLATE_PADDING, top - PLATE_PADDING, width + 2 * PLATE_PADDING, height + 2 * PLATE_PADDING)
  graphics:color()
  for index, line in ipairs(lines) do
    graphics:text(line.text, left, top + (index - 1) * LINE_HEIGHT, {font = TIP_FONT, color = line.colour})
  end
end

local function setTip(on)
  if on == (pickSub ~= nil) then return end
  if on then
    pickSub = hafen.ui():mouse():on("PickChanged", function(gob) hoveredGob = gob end)
    hafen.ui():overlay():add(TIP_KEY):draw(paintTip)
  else
    pickSub:off()
    pickSub, hoveredGob = nil, nil
    hafen.ui():overlay():remove(TIP_KEY)
  end
end

hafen.event():on("Update", function()
  setTip(hoverOption:value() and inspecting(hafen.session():current()) == true)
end)

-- ---- keeping the labels ----------------------------------------------------------------------------------

-- An object inspected earlier coming back into view, after a walk or a relog. Its name and place may not
-- have resolved yet, so the lookup itself is retried.
local function labelIfRemembered(gob, retriesLeft)
  if not gob:exists() then return end
  if placeKey(gob) == nil then
    if retriesLeft > 0 then
      hafen.timer():after(RETRY_DELAY, function() labelIfRemembered(gob, retriesLeft - 1) end)
    end
  elseif isRemembered(gob) then
    label(gob, nil, RETRY_COUNT)
  end
end

hafen.event():on("GobAdded", function(gob)
  if qualityOption:value() then labelIfRemembered(gob, RETRY_COUNT) end
end)

-- A character entering the world may load objects no other session has seen.
hafen.event():on("SessionEnteredWorld", function(session)
  if qualityOption:value() then labelAll(session) end
end)

for _, option in ipairs{qualityOption, heightOption, textColorOption, backgroundOption,
                        backgroundOpacityOption} do
  option:on("Changed", refreshAll)
end
textSizeOption:on("Changed", function(size)
  labelFont = buildFont(size)
  refreshAll()
end)

local function forgetAll()
  for key in pairs(remembered) do remembered[key] = nil end
  hideAll()
end

-- ---- the settings page -----------------------------------------------------------------------------------

-- A slider shows no number, so its label carries the value.
local function addSlider(root, option, caption, unit)
  unit = unit or ""
  local sliderLabel = hafen.ui():label():parent(root):text(caption .. ": " .. option:value() .. unit)
  local slider = hafen.ui():slider():parent(root):size(200):bind(option)
  slider:on("Changed", function(event) sliderLabel:text(caption .. ": " .. event:value() .. unit) end)
end

options:panel(function(root)
  root:gap(6)
  hafen.ui():check():parent(root):text("Name what the pointer is on while inspecting"):bind(hoverOption)
  hafen.ui():check():parent(root):text("Add the resource name to the Inspect answer"):bind(resNameOption)
  hafen.ui():check():parent(root):text("Show the inspected quality over the object"):bind(qualityOption)
  local colorRow = hafen.ui():row():gap(8):parent(root)
  hafen.ui():label():parent(colorRow):text("Text colour")
  hafen.ui():dropdown():parent(colorRow):size(120):bind(textColorOption)
  addSlider(root, textSizeOption, "Text size")
  hafen.ui():check():parent(root):text("Dark background behind the text"):bind(backgroundOption)
  addSlider(root, backgroundOpacityOption, "Background opacity", "%")
  addSlider(root, heightOption, "Height above the object")
  local countLabel = hafen.ui():label():parent(root)
  local function showCount()
    local count = 0
    for _ in pairs(remembered) do count = count + 1 end
    countLabel:text("Qualities remembered: " .. count)
  end
  showCount()
  hafen.ui():button():parent(root):size(200):text("Forget every quality"):on("Pressed", function()
    forgetAll()
    showCount()
  end)
end)

-- Objects already in view when the addon is enabled or reloaded.
refreshAll()
