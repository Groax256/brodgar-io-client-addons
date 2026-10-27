local metrics = StudyMetrics
local ui = hafen.ui()
local options = hafen.client():options():addon()
local efficiency = options:boolean("efficiency-badges"):default(true):add()
local timers = options:boolean("remaining-time"):default(true):add()
local memory = options:boolean("slot-memory"):default(true):add()
local locked = options:boolean("lock-study-clicks"):default(false):add()
local completion = options:boolean("completion-log"):default(false):add()
local sessions = {}
local face = hafen.font():get("serif"):derive():size(11)
local labelStock = {font = face, color = {190, 220, 255}}
local scale = ui:scale()
-- Inventory's pitch is UI.scale(32) + one device pixel, not UI.scale(33).
local pitch = (math.floor(32 * scale + 0.5) + 1) / scale

options:panel(function(root)
  root:gap(5)
  ui:label():parent(root):text("Study Helper — weight means mental weight")
  ui:check():parent(root):text("Efficiency details in native curiosity tooltips"):bind(efficiency)
  ui:check():parent(root):text("Estimated remaining time in native study item tooltips"):bind(timers)
  ui:check():parent(root):text("Remember study slots with dim icons"):bind(memory)
  ui:check():parent(root):text("Block left clicks on study items (including Shift/Ctrl)"):bind(locked)
  ui:check():parent(root):text("Log inferred completions (>99% when removed)"):bind(completion)
  ui:label():parent(root):text("Rates use full study durations, not LP actually earned.")
end)

local function profile(item)
  local curiosity = item:curiosity()
  return curiosity and curiosity:info() or nil
end

local function richTooltip(text)
  -- Plain widget tooltips are single-line. Rich text preserves newlines and wraps at the client's
  -- tooltip width; quote item names so resource text cannot be interpreted as markup.
  return "$b{}" .. text:gsub("[${}]", function(character) return "$" .. character end)
end

local function footprint(icon, item)
  local parent, size, cell = icon:parent(), icon:size(), item:cell()
  if not parent or parent:type() ~= "Inventory" or not size or not cell then return nil end
  return {x = cell.x, y = cell.y, w = math.max(1, math.floor(size.w / pitch + 0.5)),
          h = math.max(1, math.floor(size.h / pitch + 0.5))}
end

local function details(values, area, remaining)
  local rate = metrics.rate(values)
  local lines = {}
  local function number(label, value)
    lines[#lines + 1] = label .. ": $col[192,192,255]{" .. metrics.number(value) .. "}"
  end
  -- LP, LP/hour, full study time, mental weight and experience cost are already in the vanilla tooltip.
  if efficiency:value() then
    number("LP/mental weight", metrics.ratio(values.lp, values.attention))
    number("LP/hour/mental weight", metrics.ratio(rate, values.attention))
    number("LP/experience", metrics.ratio(values.lp, values.cost))
    if area then number("LP/hour/cell", metrics.ratio(rate, area.w * area.h)) end
  end
  if remaining then
    lines[#lines + 1] = "Time remaining: $col[192,255,192]{~" .. metrics.duration(remaining) .. "}"
  end
  return #lines > 0 and table.concat(lines, "\n") or nil
end

local function forgetIcon(state, icon)
  local record = state.icons[icon]
  if not record then return end
  -- Unlink first: ending a subscription may re-enter this function, and it must then find nothing to do.
  state.icons[icon] = nil
  for _, sub in ipairs(record.subs) do sub:off() end
  -- The note belongs to the item, not to this icon. Another icon drawing it keeps it up to date.
  for _, other in pairs(state.icons) do
    if other.item == record.item then return end
  end
  record.item:note(nil)
end

local function refreshIcon(state, icon, record)
  -- A stale item refuses a non-empty note, so stop decorating it as soon as either side is gone.
  if not icon:exists() or not record.item:exists() then forgetIcon(state, icon); return end
  local values = profile(record.item)
  local remaining = timers:value() and icon:parent() == state.inventory
      and metrics.remaining(values, record.item:progress()) or nil
  local note = values and details(values, footprint(icon, record.item), remaining) or nil
  if record.item:note() ~= note then record.item:note(note) end
end

local function decorate(state, icon)
  if state.icons[icon] or not icon:exists() then return end
  local item = icon:item()
  if not item then return end
  local record = {item = item, subs = {}}
  state.icons[icon] = record
  refreshIcon(state, icon, record)
  if state.icons[icon] ~= record then return end
  record.subs[#record.subs + 1] = item:on("Changed", function()
    if state.icons[icon] == record then refreshIcon(state, icon, record) end
  end)
  record.subs[#record.subs + 1] = icon:on("MouseDown", function(event)
    if locked:value() and event:button() == 1 and state.studying[item] then event:preventDefault() end
  end)
  -- Removed fires at once on a widget that is already gone, so the record may be forgotten by now.
  local removed = icon:on("Removed", function() forgetIcon(state, icon) end)
  if state.icons[icon] == record then record.subs[#record.subs + 1] = removed else removed:off() end
end

-- The native StudyInfo already prints LP, attention/Intelligence and EXP cost. Use its empty vertical
-- gap for the extra rate, rather than growing the character window or covering those native readings.
local function placeStudyLabel(panel, label)
  local box, size = panel:size(), label:size()
  if not box or not size then return end
  local occupied = {}
  for _, child in ipairs(panel:children():list()) do
    if not child:owned() then
      local pos, childSize = child:position(), child:size()
      if pos and childSize then occupied[#occupied + 1] = {top = pos.y, bottom = pos.y + childSize.h} end
    end
  end
  table.sort(occupied, function(left, right) return left.top < right.top end)
  local bottom, gap, top = 0, 0, 0
  for _, row in ipairs(occupied) do
    if row.top - bottom > gap then gap, top = row.top - bottom, bottom end
    bottom = math.max(bottom, row.bottom)
  end
  if box.h - bottom > gap then gap, top = box.h - bottom, bottom end
  label:position(2, top + math.max(0, math.floor((gap - size.h) / 2)))
  label:visible(gap >= size.h)
end

local function addStudy(state, panel)
  if state.panels[panel] or not panel:exists() then return end
  local label = ui:label():parent(panel):position(2, 65):name("study-rate"):stock(labelStock):text("? LP/h")
  state.panels[panel] = {label = label}
end

local refreshDesk
local function scheduleDesk(window, desk)
  if desk.dead or desk.pending or not window:exists() then return end
  desk.pending = hafen.timer():after(0, function()
    desk.pending = nil
    if desk.dead or not window:exists() then return end
    refreshDesk(window, desk)
  end)
end

local function forgetDesk(state, window)
  local desk = state.desks[window]
  if not desk then return end
  desk.dead = true
  if desk.pending then desk.pending:cancel(); desk.pending = nil end
  for _, sub in pairs(desk.itemSubs) do sub:off() end
  for _, sub in ipairs(desk.windowSubs) do sub:off() end
  if desk.column:exists() then desk.column:destroy() end
  if window:exists() then window:size(nil) end
  state.desks[window] = nil
end

local function addDesk(state, window)
  if state.desks[window] or not window:exists() then return end
  local column = ui:column():parent(window):position(0, 0):gap(2):name("desk-summary")
  local desk = {column = column, rows = {}, windowSubs = {}, itemSubs = {}}
  state.desks[window] = desk
  desk.windowSubs[#desk.windowSubs + 1] = window:on("ItemAdded", function() scheduleDesk(window, desk) end)
  desk.windowSubs[#desk.windowSubs + 1] = window:on("ItemRemoved", function() scheduleDesk(window, desk) end)
  desk.windowSubs[#desk.windowSubs + 1] = window:on("Removed", function() forgetDesk(state, window) end)
  desk.windowSubs[#desk.windowSubs + 1] = column:on("Resized", function() scheduleDesk(window, desk) end)
  scheduleDesk(window, desk)
end

refreshDesk = function(window, desk)
  if not window:exists() then return false end
  local total, unresolved, groups = 0, 0, {}
  local items, present = window:items():list(), {}
  for _, item in ipairs(items) do
    present[item] = true
    if not desk.itemSubs[item] then
      desk.itemSubs[item] = item:on("Changed", function() scheduleDesk(window, desk) end)
    end
    local ready = item:ready()
    local values = ready and profile(item) or nil
    if values then
      total = total + values.lp
      local name = item:name() or item:res() or "Unknown curiosity"
      local group = groups[name] or {time = 0, count = 0}
      groups[name] = group
      group.time, group.count = group.time + values.time, group.count + 1
    elseif not ready then
      unresolved = unresolved + 1
    end
  end
  for item, sub in pairs(desk.itemSubs) do
    if not present[item] then sub:off(); desk.itemSubs[item] = nil end
  end
  desk.unresolved = unresolved > 0
  local names = {}
  for name in pairs(groups) do names[#names + 1] = name end
  table.sort(names, function(left, right)
    if groups[left].time == groups[right].time then return left < right end
    return groups[left].time < groups[right].time
  end)
  local lines
  if unresolved > 0 then
    -- Do not present a partial total and a few rows as the finished summary while the rest is loading.
    lines = {{text = "Loading study information (" .. unresolved .. " remaining)...", color = {190, 220, 255}}}
  else
    lines = {{text = "Total LP: " .. metrics.number(total), color = {190, 220, 255}}}
    for _, name in ipairs(names) do
      local group = groups[name]
      lines[#lines + 1] = {text = name .. " x" .. group.count .. ": " .. metrics.duration(group.time) .. " stock",
                          color = group.time >= 86400 and {130, 220, 140} or {240, 155, 125}}
    end
  end
  local signatureParts = {}
  for _, line in ipairs(lines) do
    signatureParts[#signatureParts + 1] = line.text .. ":" .. table.concat(line.color, ",")
  end
  local signature = table.concat(signatureParts, "\n")
  if signature ~= desk.signature then
    desk.signature = signature
    for index, line in ipairs(lines) do
      if not desk.rows[index] then desk.rows[index] = ui:label():parent(desk.column):name("desk-row") end
      desk.rows[index]:text(line.text)
        :tooltip("Stock is the sum of full study durations, not time remaining. Green means at least 24 hours.")
      -- These colours encode stock sufficiency, not a theme default.
      desk.rows[index]:rule():color(line.color)
    end
    for index = #desk.rows, #lines + 1, -1 do desk.rows[index]:destroy(); desk.rows[index] = nil end
  end
  -- Recompute from native content, never from our previous packed height. Decorations are not content.
  local bottom = 0
  for _, child in ipairs(window:children():list()) do
    local kind = child:type() or ""
    if child ~= desk.column and not kind:find("Deco", 1, true) and child:visible() then
      local pos, size = child:position(), child:size()
      if pos and size then bottom = math.max(bottom, pos.y + size.h) end
    end
  end
  local size = desk.column:size()
  local changed = size and (desk.bottom ~= bottom or desk.height ~= size.h or desk.width ~= size.w)
  if changed then
    desk.bottom, desk.height, desk.width = bottom, size.h, size.w
    desk.column:position(0, bottom + 6)
    window:pack()
  end
  return true
end

local function refreshStudy(state)
  local slots = state.session:study():curiosity():list()
  local profiles, studying, current, occupied = {}, {}, {}, {}
  for _, slot in ipairs(slots) do
    local widget = slot:widget()
    local parent = widget and widget:parent()
    if parent then state.inventory = parent end
  end
  -- The slot's widget is the GItem, not its WItem depiction. Associate via the inventory's interned Items.
  local inventory = state.inventory
  if not inventory or not inventory:exists() then
    state.studying, state.previous = {}, {}
    return
  end
  local byItem = {}
  for icon, record in pairs(state.icons) do
    if icon:exists() and icon:parent() == inventory then byItem[record.item] = icon end
  end
  for _, item in ipairs(inventory:items():list()) do
    local values, progress = profile(item), item:progress()
    local name = item:name()
    studying[item] = true
    -- Like the native report, sum only resolved curiosity profiles. Profile-less items may be
    -- non-curiosities (including nameless ones), not missing study work. StudyChanged announces resolution.
    if values then
      profiles[#profiles + 1] = values
    end
    current[item] = {lp = values and values.lp, progress = progress, name = name or item:res() or "Curiosity"}
    local icon = byItem[item]
    if icon then
      local area = footprint(icon, item)
      if area then
        occupied[#occupied + 1] = area
        local resource = item:res()
        if memory:value() and resource then
          local key = tostring(area.x) .. ":" .. tostring(area.y)
          local old = state.history[key]
          if not old or old.res ~= resource or old.w ~= area.w or old.h ~= area.h then
            for savedKey, saved in pairs(state.history) do
              if metrics.overlap(saved, area) then state.history[savedKey] = nil end
            end
            state.history[key] = {x = area.x, y = area.y, w = area.w, h = area.h, res = resource}
          end
        end
      end
    end
  end
  if completion:value() then
    for item, previous in pairs(state.previous) do
      if not current[item] and previous.progress and previous.progress > 0.99 and previous.lp then
        hafen.log():write("[" .. (state.session:character() or state.session:user()) .. "] " .. previous.name
          .. " removed above 99%: likely completed (" .. metrics.number(previous.lp) .. " LP).")
      end
    end
  end
  state.studying, state.previous = studying, current
  local total = metrics.total(profiles)
  local summary = state.session:study():summary()
  local native = summary and summary:info() or total
  local attribute = state.session:char():attr():get("int")
  local intelligence = attribute and attribute:composite()
  local rate = total.known == 0 and total.unknown > 0 and "?" or metrics.number(total.rate)
  -- Every summary field is optional, so a total can be missing while the tab builds.
  local tip = "Nominal LP/hour: " .. rate .. "\nTotal LP: " .. metrics.number(native.lp)
      .. "\nAttention: " .. metrics.number(native.attention) .. "/" .. metrics.number(intelligence)
      .. "\nExperience cost: " .. metrics.number(native.cost)
      .. "\nSum of each resolved curiosity's LP / full duration."
      .. (total.unknown > 0 and "\nCuriosities without a study duration: " .. total.unknown .. "." or "")
  local caption = (rate == "?" and "?" or metrics.compact(total.rate) .. (total.unknown > 0 and "+" or "")) .. " LP/h"
  for panel, view in pairs(state.panels) do
    if panel:exists() then
      if view.caption ~= caption then view.label:text(caption); view.caption = caption end
      if view.tip ~= tip then view.label:tooltip(richTooltip(tip)); view.tip = tip end
      placeStudyLabel(panel, view.label)
    else state.panels[panel] = nil end
  end
  local ghosts = {}
  if memory:value() then
    for _, saved in pairs(state.history) do
      local empty = true
      for _, area in ipairs(occupied) do if metrics.overlap(saved, area) then empty = false; break end end
      if empty then ghosts[#ghosts + 1] = saved end
    end
  end
  state.ghosts = ghosts
  if state.memoryGrid ~= inventory then
    if state.memoryGrid and state.memoryGrid:exists() then state.memoryGrid:overlay():remove("memory") end
    state.memoryGrid = inventory
    inventory:overlay():add("memory"):draw(function(graphics)
      graphics:color(180, 160, 70, 90)
      for _, saved in ipairs(state.ghosts) do
        graphics:resource(saved.res, (saved.x - 1) * pitch + 1 / scale, (saved.y - 1) * pitch + 1 / scale,
                          saved.w * pitch - 1 / scale, saved.h * pitch - 1 / scale)
      end
      graphics:color()
    end)
  end
end

local function forgetSession(session)
  local state = sessions[session]
  if not state then return end
  for _, subscription in ipairs(state.subs) do subscription:off() end
  for icon in pairs(state.icons) do forgetIcon(state, icon) end
  for _, view in pairs(state.panels) do view.label:destroy() end
  for window in pairs(state.desks) do forgetDesk(state, window) end
  if state.memoryGrid and state.memoryGrid:exists() then state.memoryGrid:overlay():remove("memory") end
  sessions[session] = nil
end

local function watchSession(session)
  forgetSession(session)
  if not session:character() then return end
  local state = {session = session, icons = {}, panels = {}, desks = {}, studying = {}, previous = {},
                 ghosts = {}, subs = {}, history = session:store():var("study-slots")}
  sessions[session] = state
  local tree = session:ui()
  state.subs[#state.subs + 1] = tree:on("item", "Added", function(icon) decorate(state, icon) end)
  state.subs[#state.subs + 1] = tree:on("@StudyInfo", "Added", function(panel)
    addStudy(state, panel)
    local parent = panel:parent()
    if parent then state.inventory = parent:matchAll("inventory")[1] end
    refreshStudy(state)
    for icon, record in pairs(state.icons) do refreshIcon(state, icon, record) end
  end)
  state.subs[#state.subs + 1] = tree:on("window[title=Study Desk]", "Added", function(window) addDesk(state, window) end)
end

hafen.event():on("SessionEnteredWorld", watchSession)
hafen.event():on("SessionRemoved", forgetSession)
hafen.event():on("StudyChanged", function(_, session)
  local state = sessions[session]
  if state then
    refreshStudy(state)
    for icon, record in pairs(state.icons) do refreshIcon(state, icon, record) end
  end
end)
hafen.event():on("Load", function()
  for _, session in ipairs(hafen.session():list()) do watchSession(session) end
end)
hafen.event():on("Disable", function()
  for session in pairs(sessions) do forgetSession(session) end
end)

-- Only known icons/windows are revisited, once a second: progress, Intelligence and native geometry do
-- not publish revision events. Item tooltip changes update their notes immediately through Changed.
hafen.timer():every(1, function()
  for session, state in pairs(sessions) do
    if not session:exists() then forgetSession(session)
    else
      refreshStudy(state)
      for icon, record in pairs(state.icons) do refreshIcon(state, icon, record) end
      for window, desk in pairs(state.desks) do
        if not window:exists() then forgetDesk(state, window)
        elseif desk.unresolved then scheduleDesk(window, desk) end
      end
    end
  end
end)
