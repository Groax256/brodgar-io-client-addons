-- Stack Quality -- a stack has no quality of its own, only the qualities of what it holds. This states their
-- mean twice: as a number on the stack's icon, in the corner picked in Options ▸ AddOns, and as a line in the
-- stack's tooltip.
--
-- Nothing polls. Every icon is announced as it is built, and a stack announces the moment its tooltip is
-- rebuilt -- which is also what happens when a part's own tooltip lands, or a part leaves.

-- ------------------------------------------------------------------ the look of ui/tt/q/quality
--
-- The number is drawn the way the game draws a single item's quality: the stock face, the digits in
-- (64, 192, 255) inside a one-pixel edge of that colour's contrast -- Utils.contrast quarters a bright
-- colour -- on a box of black at half strength, flush with the corner. A stack carries no quality of its
-- own, so the corner the game would use for one is free on a stack.
--
-- The colour is markup rather than a tint: a label's tint multiplies the whole raster, edge included, so
-- tinting would darken the edge as well; `$col` colours the glyphs alone, and the edge is baked round them.

local LABEL_KEY  = "stack-quality"
local LABEL_FONT = hafen.font():get("sans"):derive():outline{16, 48, 63}
local LABEL_BG   = {0, 0, 0, 128}

local function labelText(mean)
  return "$col[64,192,255]{" .. math.floor(mean + 0.5) .. "}"
end

-- ------------------------------------------------------------------ the corner

local CORNERS = {
  ["Top right"]    = {1, 0},
  ["Top left"]     = {0, 0},
  ["Bottom left"]  = {0, 1},
  ["Bottom right"] = {1, 1},       -- where the stack's own count is drawn: the two overlap
}

local options = hafen.client():options():addon()
local corner = options:choice("corner")
    :choices{"Top right", "Top left", "Bottom left", "Bottom right"}
    :default("Top right")
    :add()

options:panel(function(root)
  root:gap(4)
  hafen.ui():label():parent(root):text("Show the average quality in the corner:")
  hafen.ui():radio():parent(root):bind(corner)
end)

-- ------------------------------------------------------------------ state

local sessionSubscriptions = {}                      -- Session -> the one subscription that watches its icons
local labels = setmetatable({}, {__mode = "k"})      -- every label standing, to move when the corner does

local function place(label)
  local at = CORNERS[corner:value()]
  label:anchor(at[1], at[2])
end

corner:on("Changed", function()
  for label in pairs(labels) do
    if label:exists() then place(label) else labels[label] = nil end
  end
end)

-- ------------------------------------------------------------------ what the stack holds

-- The mean over the parts that can state a quality yet, and how many those are. A part whose tooltip has not
-- landed is left out rather than counted as a zero; a stack none of whose parts have landed answers nil.
-- An item holding nothing, and a liquid container -- which states what it holds and carries no items -- are
-- not stacks, and answer nil too.
local function meanQuality(item)
  local held = item:contents()
  if held == nil then return nil end
  local total, counted = 0, 0
  for _, part in ipairs(held:items():list()) do
    local quality = part:quality()
    if quality ~= nil then
      total = total + quality
      counted = counted + 1
    end
  end
  if counted == 0 then return nil end
  return total / counted, counted
end

-- ------------------------------------------------------------------ one icon

local function decorateIcon(icon)
  local item = icon:item()
  if item == nil then return end
  if item:handle() == nil then return end              -- a depiction: drawn, not held, holds nothing

  local label                                          -- built on the first stack reading, not before

  -- Read on the tooltip's arrival rather than every frame. The label is drawn by the client, so a stack that
  -- sits still costs nothing at all.
  local function refresh()
    local mean, counted = meanQuality(item)

    -- The note belongs to the item, which outlives this icon; a stale item refuses a non-empty one.
    if item:exists() then
      local note = (mean ~= nil)
          and string.format("Average quality: %.1f (%d items)", mean, counted)
          or nil
      if item:note() ~= note then item:note(note) end
    end

    -- An icon is destroyed the moment its item moves, possibly between two lines here; its replacement
    -- arrives in decorateIcon on its own.
    if not icon:exists() then return end
    if mean == nil then
      if label ~= nil then
        icon:overlay():remove(LABEL_KEY)
        labels[label] = nil
        label = nil
      end
      return
    end
    if label == nil then
      label = icon:overlay():add(LABEL_KEY):font(LABEL_FONT):background(LABEL_BG)
      place(label)
      labels[label] = true
    end
    label:text(labelText(mean))
  end

  refresh()                                            -- a stack whose tooltip beat the icon here
  if not icon:exists() then return end

  -- The item outlives the icon, so its subscription is ended with the icon: the icon that replaces this one
  -- takes its own.
  local revisions
  icon:on("Removed", function()
    if label ~= nil then labels[label] = nil end
    if revisions ~= nil then revisions:off() end
  end)
  revisions = item:on("Changed", refresh)
end

-- ------------------------------------------------------------------ lifecycle

local function forgetSession(session)
  local subscription = sessionSubscriptions[session]
  if subscription == nil then return end
  subscription:off()
  sessionSubscriptions[session] = nil
end

-- "item" reaches every icon an item is drawn as, the ones already on screen as well as those built later.
local function watchSession(session)
  forgetSession(session)                               -- a character switch keeps the session, not its tree
  sessionSubscriptions[session] = session:ui():on("item", "Added", decorateIcon)
end

hafen.event():on("SessionEnteredWorld", watchSession)
hafen.event():on("SessionRemoved", forgetSession)
