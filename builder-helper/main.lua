-- Builder helper: remembers what each building site still needs and shows it over the site.
-- Toggled with the hotkey assigned in Options > Game > Keybindings > Builder helper.
--
-- A building site (gfx/terobjs/consobj) carries no material data; that is in the window the server
-- opens for it, one @ISBox per material with a "have/total" figure. Nothing links that window to the
-- site, so the addon pairs them itself: a build window that opens after a right-click on a site is that
-- site's; a window already open (a site just placed, or open before the addon loaded) is taken once the
-- character has stood still for a few seconds without one opening. A claimed window is read whole into
-- the site's row and re-read on every change while it stays open.

local SITE = "gfx/terobjs/consobj"
local OVERLAY_KEY = "materials"

local ICON = 16                    -- material icon size, design pixels
local GAP = 4                      -- between the icon and the figure
local ROW = 18                     -- height of one material row
local PAD = 3                      -- plate margin round the column
local PLATE = {30, 30, 30, 160}    -- translucent dark plate behind the column

local ADOPT_AFTER = 3              -- seconds standing still with no window opened before the open one is taken
local PLACED_RADIUS = 22           -- world units: a site arriving this close to the dropped ghost is the one placed
local PLACED_TIMEOUT = 10          -- seconds a placement waits for its site to arrive
local RETRY = 0.5                  -- seconds between retries of anything not resolved yet
local READ_DELAY = 0.25            -- seconds to let a burst of box updates finish before the window is read

local FONT = hafen.font():get("sans"):derive():size(11):bold(true):outline{0, 0, 0}
local PENDING_TEXT = {font = FONT, color = {255, 255, 255}}
local DONE_TEXT = {font = FONT, color = {140, 230, 140}}

-- One row per site, keyed by the ground it stands on (grid id + offset in the grid, rounded).
-- materials: {{res = "gfx/invobjs/...", text = "2/150", have = 2, total = 150}, ...} in window order.
local sitesTable = hafen.store():table("sites")
  :column("grid", "text"):column("x", "integer"):column("y", "integer")
  :column("materials", "json")
  :key("grid", "x", "y")
  :create()

local function placeKey(place)
  return place.grid .. ":" .. place.x .. ":" .. place.y
end

local sites = {}                   -- [placeKey] = row; the painter reads it every frame
for _, row in ipairs(sitesTable:list()) do
  sites[placeKey(row)] = row
end

local options = hafen.client():options():addon()
local showLabelsOption = options:boolean("show-labels"):default(false):add()
local hideCompletedOption = options:boolean("hide-done"):default(false):add()
local showing = showLabelsOption:value()
local hideCompleted = hideCompletedOption:value()

local labelled = {}                -- [placeKey] = the gob wearing that site's label
local layouts = {}                 -- [placeKey] = what its label draws; rebuilt only when the record or an option changes
local claims = {}                  -- [Window] = {gob = Gob, place = {grid, x, y}}: the site a build window is about
local reading = {}                 -- [Window] = true while a read of it is scheduled
local expected = nil               -- {gob, session, stillFor, timer}: the site whose window should open next
local placed = nil                 -- {position, session}: a building just placed, until its site arrives
local watched = {}                 -- [account] = the @ISBox subscriptions on that character's tree

local function retry(fn)
  hafen.timer():after(RETRY, fn)
end

-- The ground a gob stands on, as the row key. nil while its position is not durable yet.
local function placeOf(gob)
  local position = gob:position()
  local info = position and position:info()
  if not info then return nil end
  return {grid = info.gridId, x = math.floor(info.x + 0.5), y = math.floor(info.y + 0.5)}
end

-- Every loaded object once: the same Gob is handed to every session that sees it.
local function eachGob(fn)
  local seen = {}
  for _, session in ipairs(hafen.session():list()) do
    for _, gob in ipairs(session:world():gob():list()) do
      if not seen[gob] then
        seen[gob] = true
        fn(gob)
      end
    end
  end
end

-- ---- labels ----

local function isDone(material)
  return material.have ~= nil and material.total ~= nil and material.have >= material.total
end

local function isComplete(site)
  if #site.materials == 0 then return false end
  for _, material in ipairs(site.materials) do
    if not isDone(material) then return false end
  end
  return true
end

-- Lays out a site's label: one row per material and the plate behind them, as offsets from the ground
-- point. Done here, once per change, so the painter computes and allocates nothing per frame.
local function layoutSite(key)
  local site = sites[key]
  if not site then
    layouts[key] = nil
    return
  end
  local rows = {}
  for _, material in ipairs(site.materials) do
    if not (hideCompleted and isDone(material)) then
      rows[#rows + 1] = {
        res = material.res,
        text = material.text,
        width = ICON + GAP + hafen.ui():measure(material.text, {font = FONT}).w,
        textOptions = isDone(material) and DONE_TEXT or PENDING_TEXT,
      }
    end
  end
  if #rows == 0 then
    layouts[key] = nil
    return
  end
  local widest = 0
  for _, row in ipairs(rows) do
    widest = math.max(widest, row.width)
  end
  local top = -#rows * ROW
  for index, row in ipairs(rows) do
    row.x = -row.width / 2
    row.y = top + (index - 1) * ROW
  end
  layouts[key] = {
    rows = rows,
    plate = {x = -widest / 2 - PAD, y = top - PAD, width = widest + 2 * PAD, height = #rows * ROW + 2 * PAD},
  }
end

-- Runs every frame for every labelled site on screen (a draw overlay is a callback), so it only blits
-- the layout. The icon and the text are cached by the client.
local function paintLabel(key)
  return function(graphics, _, screenX, screenY)
    local layout = layouts[key]
    if not layout then return end
    local plate = layout.plate
    graphics:color(PLATE)
    graphics:frect(screenX + plate.x, screenY + plate.y, plate.width, plate.height)
    graphics:color()
    for _, row in ipairs(layout.rows) do
      local rowX, rowY = screenX + row.x, screenY + row.y
      if row.res then graphics:resource(row.res, rowX, rowY, ICON, ICON) end
      graphics:text(row.text, rowX + ICON + GAP, rowY + 1, row.textOptions)
    end
  end
end

-- The client refuses an overlay while the gob's drawing is still resolving, so retry until it takes.
local function attachLabel(gob, key)
  if gob:overlay():get(OVERLAY_KEY) then return end
  if not layouts[key] then layoutSite(key) end
  local attached = pcall(function()
    gob:overlay():add(OVERLAY_KEY):draw(paintLabel(key)):height(0)
  end)
  if attached then
    labelled[key] = gob
  else
    retry(function()
      if showing and gob:exists() then attachLabel(gob, key) end
    end)
  end
end

local function hideAll()
  for _, gob in pairs(labelled) do
    gob:overlay():remove(OVERLAY_KEY)
  end
  labelled = {}
end

-- ---- the record ----

local function forget(key)
  local site = sites[key]
  if not site then return end
  sites[key] = nil
  layouts[key] = nil
  sitesTable:remove(site.grid, site.x, site.y)
  if labelled[key] then
    labelled[key]:overlay():remove(OVERLAY_KEY)
    labelled[key] = nil
  end
end

local function forgetAll()
  for key in pairs(sites) do
    forget(key)
  end
end

-- ---- build windows ----

local function windowOf(widget)
  local parent = widget:parent()
  while parent and parent:role() ~= "window" do
    parent = parent:parent()
  end
  return parent
end

-- Every window in the session with a material box in it.
local function buildWindows(session)
  local windows, seen = {}, {}
  for _, box in ipairs(session:ui():matchAll("@ISBox")) do
    local window = windowOf(box)
    if window and not seen[window] then
      seen[window] = true
      windows[#windows + 1] = window
    end
  end
  return windows
end

local scheduleRead

-- Reads a claimed window whole: its boxes, in tree order, are the site's materials.
local function readWindow(window)
  reading[window] = nil
  local claim = claims[window]
  if not claim then return end
  if not window:exists() then
    claims[window] = nil
    return
  end
  if not claim.place then
    if not claim.gob:exists() then
      claims[window] = nil
      return
    end
    claim.place = placeOf(claim.gob)
    if not claim.place then                       -- ground under the site not durable yet
      scheduleRead(window, RETRY)
      return
    end
  end
  local boxes = window:matchAll("@ISBox")
  if #boxes == 0 then return end
  local materials, resolving = {}, false
  for index, box in ipairs(boxes) do
    local text = box:text() or ""
    local have, total = text:match("^(%d+)/(%d+)")
    local res = box:res()                         -- nil while the material's resource is still loading
    if not res then resolving = true end
    materials[index] = {res = res, text = text, have = tonumber(have), total = tonumber(total)}
  end
  local key = placeKey(claim.place)
  local site = {grid = claim.place.grid, x = claim.place.x, y = claim.place.y, materials = materials}
  if isComplete(site) then
    forget(key)
    return
  end
  sites[key] = site
  sitesTable:put(site)
  layoutSite(key)
  if showing then attachLabel(claim.gob, key) end
  if resolving then scheduleRead(window, RETRY) end
end

-- One read per window per burst: a window's boxes arrive together, and a transfer is one update per item.
scheduleRead = function(window, delay)
  if reading[window] then return end
  reading[window] = true
  hafen.timer():after(delay or READ_DELAY, function() readWindow(window) end)
end

-- ---- pairing a window with its site ----

local function stopExpecting()
  if expected then
    expected.timer:cancel()
    expected = nil
  end
end

local function claimWindow(window, gob)
  claims[window] = {gob = gob}
  window:on("Removed", function() claims[window] = nil end)
  scheduleRead(window)
end

-- Claims the newest build window in the session nothing has claimed yet: server widget ids grow, so
-- the highest id is the one opened last. Answers whether there was one.
local function claimOpenWindow(session, gob)
  local newest, newestId
  for _, window in ipairs(buildWindows(session)) do
    local id = window:id()
    if not claims[window] and id and (not newestId or id > newestId) then
      newest, newestId = window, id
    end
  end
  if not newest then return false end
  claimWindow(newest, gob)
  return true
end

-- After a right-click on a site: the next build window to open in that session is the site's. If none
-- has opened once the character has stood still for ADOPT_AFTER seconds, the window was already open
-- (the click reached a site whose window stands), so the open one is taken.
local function expectWindow(gob, session)
  stopExpecting()
  local expectation = {gob = gob, session = session, stillFor = 0}
  expectation.timer = hafen.timer():every(RETRY, function()
    if not gob:exists() or not session:exists() then
      stopExpecting()
      return
    end
    local player = session:player():gob()
    if player and player:moving() then
      expectation.stillFor = 0
    else
      expectation.stillFor = expectation.stillFor + RETRY
    end
    if expectation.stillFor >= ADOPT_AFTER then
      stopExpecting()
      claimOpenWindow(session, gob)
    end
  end)
  expected = expectation
end

-- A material box appeared: in a claimed window, re-read it; in an unclaimed one while a site's window
-- is expected in that session, the window is that site's.
local function boxAdded(session, box)
  local window = windowOf(box)
  if not window then return end
  if claims[window] then
    scheduleRead(window)
  elseif expected and expected.session == session then
    claimWindow(window, expected.gob)
    stopExpecting()
  end
end

-- A box left a window that stayed open, so its list changed. A removed box no longer knows its window,
-- so every claimed window is re-read.
local function boxRemoved()
  for window in pairs(claims) do
    scheduleRead(window)
  end
end

-- A session that picks another character gets a new tree, so subscribe again on every entry.
local function watch(session)
  local account = session:user()
  for _, subscription in ipairs(watched[account] or {}) do
    subscription:off()
  end
  watched[account] = {
    session:ui():on("@ISBox", "Added", function(box) boxAdded(session, box) end),
    session:ui():on("@ISBox", "Removed", boxRemoved),
  }
end

-- ---- gobs ----

-- Looks at a gob for what the addon wants of it: a site arriving where a building was just placed, a site
-- standing on a remembered place (labelled), and anything else standing on one (the site was finished or
-- replaced, so its record is dropped). A gob that just loaded may have no durable position or name yet,
-- so this retries until it has what it needs.
local function checkGob(gob)
  if not gob:exists() or (not placed and not showing) then return end
  local place = placeOf(gob)
  if not place then
    retry(function() checkGob(gob) end)
    return
  end
  local key = placeKey(place)
  local justPlaced = placed ~= nil and (gob:position():distance(placed.position) or math.huge) < PLACED_RADIUS
  local remembered = showing and sites[key] ~= nil
  if not justPlaced and not remembered then return end
  local name = gob:name()
  if not name then
    retry(function() checkGob(gob) end)
    return
  end
  if name ~= SITE then
    if remembered then forget(key) end             -- something else stands on the site's place: finished or replaced
    return
  end
  if justPlaced then
    local session = placed.session
    placed = nil
    if not claimOpenWindow(session, gob) then expectWindow(gob, session) end
  end
  if remembered then attachLabel(gob, key) end
end

local function showAll()
  eachGob(checkGob)
end

-- ---- events ----

-- Stream handlers run inside the character's tree; the work runs on the next step.
hafen.event():action():on("click", function(event)
  if event:widget():type() ~= "MapView" then return end
  local gob = event:gob()
  if not gob then return end                          -- a ground click steers the walk; the expectation stands
  local button, session = event:args()[3], event:widget():session()
  hafen.timer():after(0, function()
    if button == 3 and gob:name() == SITE then
      expectWindow(gob, session)
      checkGob(gob)                                   -- a remembered site is labelled whether or not a window comes
      return
    end
    stopExpecting()
    -- Right-clicking what now stands on a remembered place: the site was finished or replaced.
    if button == 3 then
      local place = placeOf(gob)
      if place then forget(placeKey(place)) end
    end
  end)
end)

-- Placing a building: the server puts the site where the ghost was dropped and opens its window with
-- no click on the site. The place is kept until the site arrives (checkGob) or the timeout passes.
hafen.event():action():on("place", function(event)
  if event:widget():type() ~= "MapView" then return end
  local position, session = event:position(1), event:widget():session()
  hafen.timer():after(0, function()
    stopExpecting()
    placed = {position = position, session = session}
    local thisPlacement = placed
    hafen.timer():after(PLACED_TIMEOUT, function()
      if placed == thisPlacement then placed = nil end
    end)
  end)
end)

-- A figure moved in an open window (materials put in or taken out). The box applies the update after
-- this handler, so the window is re-read on the next step.
hafen.event():message():on("chnum", function(event)
  local window = windowOf(event:widget())
  if window and claims[window] then scheduleRead(window) end
end)

hafen.event():on("GobAdded", checkGob)

hafen.event():on("SessionEnteredWorld", function(session)
  watch(session)
  if showing then
    for _, gob in ipairs(session:world():gob():list()) do
      checkGob(gob)
    end
  end
end)

-- ---- options and hotkey ----

showLabelsOption:on("Changed", function(value)
  hafen.timer():after(0, function()
    showing = value
    if showing then showAll() else hideAll() end
  end)
end)

hideCompletedOption:on("Changed", function(value)
  hideCompleted = value
  for key in pairs(layouts) do
    layoutSite(key)
  end
end)

hafen.client():options():keybindings():on("toggle", function()
  showLabelsOption:value(not showLabelsOption:value())
end)

options:panel(function(root)
  root:gap(4)
  hafen.ui():check():parent(root):text("Show materials over building sites"):bind(showLabelsOption)
  hafen.ui():check():parent(root):text("Hide completed materials")
    :tooltip("Leave out a material the site already has all of, instead of drawing it green")
    :bind(hideCompletedOption)
  hafen.ui():button():parent(root):size(160):text("Forget all sites"):on("Pressed", function()
    hafen.timer():after(0, forgetAll)
  end)
end)

for _, session in ipairs(hafen.session():list()) do
  watch(session)
end
if showing then showAll() end
