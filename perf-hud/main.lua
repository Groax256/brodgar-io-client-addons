-- Performance HUD displaying current FPS and JVM heap memory usage.

local UPDATE_INTERVAL_SECONDS = 0.5
local PADDING_X = 9
local PADDING_Y = 6

local HUD_FONT = hafen.font():get("sans"):derive():size(16):bold(true)

-- Window styling: transparent chrome to remove default title plate and close button,
-- with a child panel providing the standard themeable window frame (gfx/hud/wnd).
local BOX_LOOK = {
  bg = {res = "gfx/hud/wnd/lg/bg", mode = "tile"},
  border = {box = "gfx/hud/wnd", mode = "tile"},
}

local NO_CHROME = {
  bg = {color = {0, 0, 0, 0}},
  border = {color = {0, 0, 0, 0}, width = 1},
  closeButton = {at = "topleft", offset = {0, -200}},
}

-- Format the text showing frames per second and used memory in megabytes (at most XXX and YYYY).
local function format_display_text()
  local current_fps = hafen.client():fps()
  if not current_fps then
    current_fps = 0
  end

  local memory_table = hafen.client():memory()
  local used_megabytes = 0
  if memory_table and memory_table.heapUsed then
    used_megabytes = math.floor(memory_table.heapUsed / 1048576)
  end

  return string.format("FPS: %d - RAM: %d", current_fps, used_megabytes)
end

-- Measure the maximum string bounds ("FPS: 999 - RAM: 9999") to size the window tightly without clipping.
local text_width = 230
local text_height = 20

local measure_success, measured_size = pcall(function()
  return hafen.ui():measure("FPS: 999 - RAM: 9999", {font = HUD_FONT})
end)

if measure_success and measured_size and measured_size.w and measured_size.h then
  text_width = math.ceil(measured_size.w)
  text_height = math.ceil(measured_size.h)
end

local window_width = text_width + (PADDING_X * 2) + 6
local window_height = text_height + (PADDING_Y * 2)

-- Persistent addon settings storing window visibility state.
local addon_settings = hafen.store():var("settings")

-- Construct the window with transparent chrome, zero padding, and no title bar.
local performance_window = hafen.ui():window()
  :position(20, 20)
  :remember("perf_hud", hafen.store())
  :size(window_width, window_height)

performance_window:rule()
  :bg(NO_CHROME.bg)
  :border(NO_CHROME.border)
  :closeButton(NO_CHROME.closeButton)
  :padding(0)

if addon_settings.visible == false then
  performance_window:visible(false)
end

-- Themeable panel with the normal client window border, serving as the drag handle.
local background_panel = hafen.ui():widget()
  :parent(performance_window)
  :position(0, 0)
  :size(window_width, window_height)

background_panel:stock(BOX_LOOK)
performance_window:draggable(background_panel)

-- Label with larger font, positioned with tight padding inside the frame.
local status_label = hafen.ui():label()
  :parent(performance_window)
  :position(PADDING_X, PADDING_Y)
  :text(format_display_text())

status_label:rule():font(HUD_FONT)

-- Toggle window visibility between hidden and shown states and persist choice.
local function toggle_window_visibility()
  if performance_window and performance_window:exists() then
    local new_visibility = not performance_window:visible()
    performance_window:visible(new_visibility)
    addon_settings.visible = new_visibility
    hafen.store():flush()
  end
end

-- Register keybinding in Options > Game > Keybindings > Performance HUD.
hafen.client():options():keybindings():on("toggle", function()
  hafen.timer():after(0, toggle_window_visibility)
end)

-- Register console commands to toggle the window.
hafen.console():on("perf", function()
  hafen.timer():after(0, toggle_window_visibility)
end)

hafen.console():on("fps", function()
  hafen.timer():after(0, toggle_window_visibility)
end)

hafen.console():on("ram", function()
  hafen.timer():after(0, toggle_window_visibility)
end)

-- Periodically refresh the statistics while the window is visible.
hafen.timer():every(UPDATE_INTERVAL_SECONDS, function()
  if performance_window and performance_window:exists() and performance_window:visible() then
    status_label:text(format_display_text())
  end
end)
