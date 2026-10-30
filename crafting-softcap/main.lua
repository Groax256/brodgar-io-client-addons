-- Crafting Softcap -- the recipe window names the stats a product's quality draws on, as a row of icons after
-- "Quality:", and says nothing about how far they take it. This writes your value for each stat on its icon,
-- and after the row the softcap: the geometric mean of those values, which is the quality the product is
-- soft-capped at.
--
-- A quality input is the picture gfx/hud/chr/<name>, and <name> is a base attribute or an ability. The values
-- are re-read once a second while a recipe is open -- a buff or a meal moves them, and nothing announces that.

-- ------------------------------------------------------------------ the recipe window's own layout
--
-- Makewindow draws its quality row by hand, in design pixels: the label "Quality:" at x 0, then the icons from
-- x = max(label + 5, 45), each 20 square at y 38 and one apart, then a gap of 25; the tools after it the same
-- way. The overlay is drawn in the window's own design pixels, so the same numbers place it.

local ROW_Y     = 38
local ICON      = 20
local ICON_STEP = ICON + 1
local ROW_X     = 45
local LABEL_GAP = 5
local GROUP_GAP = 25

local QUALITY_LABEL_W = hafen.ui():measure("Quality:").w
local TOOLS_LABEL_W   = hafen.ui():measure("Tools:").w

local VALUE_FONT  = hafen.font():get("sans"):derive():bold(true):outline{0, 0, 0}
local OVERLAY_KEY = "crafting-softcap"

-- ------------------------------------------------------------------ what the recipe says

-- Every attribute and ability of the character, by name.
local function statsOf(char)
  local stats = {}
  for _, attr in ipairs(char:attr():list()) do stats[attr:name()] = attr end
  for _, ability in ipairs(char:ability():list()) do stats[ability:name()] = ability end
  return stats
end

-- One reading of the open recipe: the value under each quality icon ("?" while it cannot be read), the softcap
-- (nil unless every value was read), and how many tools the window draws after the row.
local function readRecipe(session)
  local craft = session:craft()
  if not craft:exists() then return nil end
  local stats = statsOf(session:char())
  local values, product, complete = {}, 1, true
  for _, spec in ipairs(craft:qualityInputs():list()) do
    local name = (spec:res() or ""):match("^gfx/hud/chr/(.+)$")
    local stat = name and stats[name]
    local value = stat and stat:composite()
    if value then
      values[#values + 1] = tostring(value)
      product = product * value
    else
      values[#values + 1] = "?"
      complete = false
    end
  end
  local softcap = nil
  if complete and #values > 0 then softcap = math.floor(product ^ (1 / #values) + 1e-9) end
  return { values = values, softcap = softcap, tools = craft:tools():count() }
end

-- ------------------------------------------------------------------ one recipe window

local function paint(reading)
  return function(graphics)
    if reading.current == nil or #reading.current.values == 0 then return end
    local recipe = reading.current
    local x = math.max(QUALITY_LABEL_W + LABEL_GAP, ROW_X)
    for i, value in ipairs(recipe.values) do
      local right = x + (i - 1) * ICON_STEP + ICON
      graphics:atext(value, right, ROW_Y + ICON, 1, 1, { font = VALUE_FONT })
    end
    x = x + #recipe.values * ICON_STEP + GROUP_GAP
    if recipe.tools > 0 then
      x = math.max(x + TOOLS_LABEL_W + LABEL_GAP, ROW_X) + recipe.tools * ICON_STEP + GROUP_GAP
    end
    local text = recipe.softcap and ("Softcap: " .. recipe.softcap) or "Softcap: ?"
    graphics:atext(text, x, ROW_Y + ICON / 2, 0, 0.5)
  end
end

local function decorate(session, window)
  local reading = {}
  local function refresh()
    local ok, recipe = pcall(readRecipe, session)
    reading.current = ok and recipe or nil
  end
  refresh()
  window:overlay():add(OVERLAY_KEY):draw(paint(reading))
  local ticker = hafen.timer():every(1, refresh)
  window:on("Removed", function() ticker:cancel() end)
end

-- ------------------------------------------------------------------ lifecycle

local sessionSubscriptions = {}                      -- Session -> the subscription that watches its recipe windows

local function forgetSession(session)
  local subscription = sessionSubscriptions[session]
  if subscription == nil then return end
  subscription:off()
  sessionSubscriptions[session] = nil
end

-- "Added" also fires for a recipe window already open when the subscription is made.
local function watchSession(session)
  forgetSession(session)                               -- a character switch keeps the session, not its tree
  sessionSubscriptions[session] = session:ui():on("@Makewindow", "Added", function(window)
    decorate(session, window)
  end)
end

hafen.event():on("SessionEnteredWorld", watchSession)
hafen.event():on("SessionRemoved", forgetSession)

-- Enabled while characters are already in the world: no event announces them. (A :reload does announce them,
-- and watchSession replaces its own subscription, so the two never double up.)
for _, session in ipairs(hafen.session():list()) do
  if session:character() ~= nil then watchSession(session) end
end
