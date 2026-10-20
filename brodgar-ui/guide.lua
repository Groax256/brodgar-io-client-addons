-- The setup guide's window: one page of steps.lua at a time, with Back, Next and Skip; a step marked centred
-- stands in the middle of the page. It opens by itself the first time a character enters the world, and the
-- store remembers once it has been finished, skipped or closed; :brodgarui and the button on Options > AddOns >
-- Brodgar UI open it again.

local Steps = BrodgarUI.Steps

local Guide = {}
BrodgarUI.Guide = Guide

local PAGE_WIDTH = 400
local PAGE_HEIGHT = 320
local PAGE_MARGIN = 4        -- between the scrolling box's edge and the page; a surface with no place starts at (100, 100)
local FOOTER_GAP = 10
local BUTTON_WIDTH = 90

local progress = hafen.store():var("guide")   -- done: true once the guide was finished, skipped or closed

-- The window stands in the middle of the screen, and stays there when the game window is resized.
local sheet = hafen.ui():sheet()
sheet:rule("[name=brodgar-ui/guide]"):anchor{to = "screen", at = "center"}
sheet:install()

local guideWindow = nil
local pageBox = nil          -- the scrolling box every page is built into
local pageColumn = nil       -- the page on show, rebuilt on every turn
local stepLabel = nil
local backButton = nil
local nextButton = nil
local steps = {}
local currentStep = 1

local function markDone()
  progress.done = true
  hafen.store():flush()
end

local function show(index)
  currentStep = index
  local step = steps[index]
  if pageColumn ~= nil and pageColumn:exists() then pageColumn:destroy() end
  pageColumn = hafen.ui():column():gap(6):parent(pageBox):position(PAGE_MARGIN, PAGE_MARGIN)
  local built, failure = pcall(step.build, pageColumn)
  if not built then
    hafen.ui():label():parent(pageColumn):text("This page could not be shown.")
    hafen.log():write("setup guide: the page '" .. step.title .. "' failed -- " .. tostring(failure))
  end
  if step.centred then
    local size = pageColumn:size()
    pageColumn:position(math.max(PAGE_MARGIN, math.floor((PAGE_WIDTH - size.w) / 2)),
                        math.max(PAGE_MARGIN, math.floor((PAGE_HEIGHT - size.h) / 2)))
  end
  guideWindow:title("Brodgar UI: " .. step.title)
  stepLabel:text("Step " .. index .. " of " .. #steps)
  backButton:enabled(index > 1)
  if index == #steps then
    nextButton:text("Finish")
  else
    nextButton:text("Next")
  end
end

-- Closed by Finish or Skip: remembered as done, then taken down on the next step, since the press that asked
-- for it runs inside the window.
local function close()
  markDone()
  hafen.timer():after(0, function()
    if guideWindow ~= nil and guideWindow:exists() then guideWindow:destroy() end
  end)
end

function Guide.open()
  if guideWindow ~= nil and guideWindow:exists() then return end
  steps = Steps.list()

  guideWindow = hafen.ui():window():name("guide"):title("Brodgar UI")
  pageBox = hafen.ui():scroll():parent(guideWindow):position(0, 0):size(PAGE_WIDTH, PAGE_HEIGHT)

  local footer = hafen.ui():row():gap(8):parent(guideWindow):position(0, PAGE_HEIGHT + FOOTER_GAP)
  backButton = hafen.ui():button():parent(footer):size(BUTTON_WIDTH):text("Back")
  nextButton = hafen.ui():button():parent(footer):size(BUTTON_WIDTH):text("Next")
  local skipButton = hafen.ui():button():parent(footer):size(BUTTON_WIDTH):text("Skip")
  stepLabel = hafen.ui():label():parent(footer):text("")

  backButton:on("Pressed", function()
    if currentStep > 1 then show(currentStep - 1) end
  end)
  nextButton:on("Pressed", function()
    if currentStep < #steps then
      show(currentStep + 1)
    else
      close()
    end
  end)
  skipButton:on("Pressed", close)
  guideWindow:on("Close", markDone)       -- the window's own X: left alone, it destroys the window

  guideWindow:pack()
  show(1)
end

-- The first character to enter the world on a client that has not been through the guide opens it.
function Guide.openFirstTime()
  if progress.done then return end
  hafen.timer():after(0, Guide.open)
end
