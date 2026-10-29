-- Barrel Content: labels every barrel in view with what it holds.
-- Settings in Options > AddOns > Barrel Content; the show/hide hotkey is assigned there too.

local BARREL = "gfx/terobjs/barrel"
-- A filled barrel carries a native overlay named after its content: "gfx/terobjs/barrel-water".
local CONTENT_PREFIX = "gfx/terobjs/barrel-"
local EMPTY_TEXT = "Empty"

local OVERLAY_KEY = "content"

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

-- A barrel whose resource is still resolving has no name and refuses the overlay; try again this often.
local RETRY_DELAY = 0.5
local RETRY_COUNT = 10

local options = hafen.client():options():addon()
local showOption = options:boolean("show"):default(true):add()
local showEmptyOption = options:boolean("show-empty"):default(false):add()
local textColorOption = options:choice("text-color"):choices(TEXT_COLOR_NAMES):default("White"):add()
local textSizeOption = options:number("text-size"):range(8, 24):default(11):add()
local backgroundOption = options:boolean("background"):default(true):add()
local backgroundOpacityOption = options:number("background-opacity"):range(10, 100):default(60):add()  -- percent
local heightOption = options:number("height"):range(0, 40):default(15):add()   -- world units up the barrel

-- Bold with a black outline so the text reads over grass, snow and floors alike.
local function buildFont(size)
  return hafen.font():get("sans"):derive():size(size):bold(true):outline{0, 0, 0}
end
local labelFont = buildFont(textSizeOption:value())

local function startsWith(text, prefix)
  return text ~= nil and text:sub(1, #prefix) == prefix
end

-- The prefix also catches a barrel variant; the scan only narrows the gobs whose overlays are read.
local function mayBeBarrel(gob)
  return startsWith(gob:name(), BARREL)
end

-- "gfx/terobjs/barrel-water" -> "Water"; dashes inside the content name become spaces.
local function contentLabel(barrel)
  for _, overlay in ipairs(barrel:overlay():list(CONTENT_PREFIX)) do
    local overlayKey = overlay:key()
    if overlay:native() and startsWith(overlayKey, CONTENT_PREFIX) then
      local contentName = overlayKey:sub(#CONTENT_PREFIX + 1):gsub("%-", " ")
      return (contentName:gsub("^%l", string.upper))
    end
  end
  return nil
end

-- The text kind is drawn by the client with no Lua per frame; the background needs a painter.
local function attachLabel(barrel, labelText)
  local labelOverlay = barrel:overlay():add(OVERLAY_KEY)
  local textColor = TEXT_COLOR_VALUES[textColorOption:value()]
  if not backgroundOption:value() then
    labelOverlay:text(labelText):color(textColor):font(labelFont)
  else
    local font = labelFont
    local textOptions = {font = font, color = textColor}
    local textBox = hafen.ui():measure(labelText, {font = font})
    local backgroundAlpha = math.floor(backgroundOpacityOption:value() * 255 / 100)
    labelOverlay:draw(function(graphics, gob, screen_x, screen_y)
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

-- Puts the label on, relabels it, or takes it off. The overlay hangs on the object, so one call through
-- any session that sees the barrel reaches every session's copy.
local function showContent(barrel, retriesLeft)
  local barrelName = barrel:name()
  local labelText = contentLabel(barrel)
  if not labelText and showEmptyOption:value() and barrelName == BARREL then labelText = EMPTY_TEXT end
  local attached = false
  if labelText then
    attached = barrelName ~= nil and pcall(attachLabel, barrel, labelText)
  else
    barrel:overlay():remove(OVERLAY_KEY)
    attached = barrelName ~= nil
  end
  if not attached and retriesLeft > 0 then
    hafen.timer():after(RETRY_DELAY, function()
      if showOption:value() and barrel:exists() then showContent(barrel, retriesLeft - 1) end
    end)
  end
end

local function showContents(session)
  for _, barrel in ipairs(session:world():gob():list(mayBeBarrel)) do
    showContent(barrel, RETRY_COUNT)
  end
end

-- A remove reaches only the copies of sessions that still hold the barrel, so every session is asked.
local function hideContents()
  for _, session in ipairs(hafen.session():list()) do
    for _, barrel in ipairs(session:world():gob():list(mayBeBarrel)) do
      barrel:overlay():remove(OVERLAY_KEY)
    end
  end
end

local function refreshAll()
  if not showOption:value() then
    hideContents()
    return
  end
  for _, session in ipairs(hafen.session():list()) do
    showContents(session)
  end
end

-- The event's gob is looked up by id in the first session that holds it.
local function refreshBarrel(event)
  if not showOption:value() or not event:native() or not startsWith(event:key(), CONTENT_PREFIX) then return end
  local barrelId = event:gob():id()
  for _, session in ipairs(hafen.session():list()) do
    local barrel = session:world():gob():get(barrelId)
    if barrel:exists() then
      showContent(barrel, RETRY_COUNT)
      return
    end
  end
end

local keybindings = hafen.client():options():keybindings()
keybindings:on("toggle", function()
  showOption:value(not showOption:value())
end)
local toggleBinding = keybindings:binding():get("toggle")

textSizeOption:on("Changed", function(size)
  labelFont = buildFont(size)
  refreshAll()
end)
for _, option in ipairs{showOption, showEmptyOption, textColorOption, backgroundOption,
                        backgroundOpacityOption, heightOption} do
  option:on("Changed", refreshAll)
end

-- A gob still resolving has no name yet, so whether it is a barrel is asked again on a timer.
local function labelIfBarrel(gob, retriesLeft)
  if gob:name() == nil then
    if retriesLeft > 0 then
      hafen.timer():after(RETRY_DELAY, function()
        if showOption:value() and gob:exists() then labelIfBarrel(gob, retriesLeft - 1) end
      end)
    end
  elseif mayBeBarrel(gob) then
    showContent(gob, RETRY_COUNT)
  end
end

-- Only an empty barrel needs this: a filled one is labelled when its content overlay lands.
hafen.event():on("GobAdded", function(gob)
  if showOption:value() and showEmptyOption:value() then labelIfBarrel(gob, RETRY_COUNT) end
end)

-- Covers a barrel coming into view already filled, a barrel being filled, and one being emptied.
hafen.event():on("GobOverlayAdded", refreshBarrel)
hafen.event():on("GobOverlayRemoved", refreshBarrel)

-- A character entering the world may load barrels no other session has seen.
hafen.event():on("SessionEnteredWorld", function(session)
  if showOption:value() then showContents(session) end
end)

-- A slider shows no number, so its label carries the value.
local function addSlider(root, option, caption, unit)
  local sliderLabel = hafen.ui():label():parent(root):text(caption .. ": " .. option:value() .. unit)
  local slider = hafen.ui():slider():parent(root):size(200):bind(option)
  slider:on("Changed", function(event) sliderLabel:text(caption .. ": " .. event:value() .. unit) end)
end

options:panel(function(root)
  root:gap(6)
  local keyRow = hafen.ui():row():gap(8):parent(root)
  hafen.ui():label():parent(keyRow):text("Show or hide the labels")
  hafen.ui():keybinding():parent(keyRow):bind(toggleBinding)

  hafen.ui():check():parent(root):text("Show barrel contents"):bind(showOption)
  hafen.ui():check():parent(root):text("Label empty barrels \"" .. EMPTY_TEXT .. "\""):bind(showEmptyOption)

  local colorRow = hafen.ui():row():gap(8):parent(root)
  hafen.ui():label():parent(colorRow):text("Text colour")
  hafen.ui():dropdown():parent(colorRow):size(120):bind(textColorOption)
  addSlider(root, textSizeOption, "Text size", "")

  hafen.ui():check():parent(root):text("Dark background behind the text"):bind(backgroundOption)
  addSlider(root, backgroundOpacityOption, "Background opacity", "%")

  addSlider(root, heightOption, "Height above the barrel", "")
end)

-- Barrels already in view when the addon is enabled or reloaded.
refreshAll()
