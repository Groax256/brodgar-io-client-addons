-- Kith & Kin Side by Side: the Kith & Kin window shows its Kin, Village and Realm tabs next to each other,
-- a vertical line between two neighbours, instead of one at a time behind the tab buttons.
--
-- The window is the client's `Zergwnd`. Each tab is a `PTab` child at 0,0 holding one widget (the Kin list,
-- a `BuddyWnd`, or a polity `Category`); the client hides every tab but its current one, and the `TButton`s
-- under them switch which one that is. Every frame this addon shows every tab, places them in a row, hides
-- the buttons and keeps one divider of its own per gap. The window packs only around visible children, so
-- `window:pack()` after a change fits the frame round the whole row.
--
-- `widget:visible(true)` on a tab the client hid records no restore, so `Disable` hides again every tab
-- but the client's current one before the teardown gives back the places, the buttons and the size.

local GAP = 10                                  -- design px between a tab and a divider
local DIVIDER_WIDTH = 1
local DIVIDER_COLOUR = {150, 130, 100, 200}

local layoutByUser = {}                         -- user -> {window, dividers, currentTab, signature}

local function log(message)
    hafen.log():write("[kith-kin-side-by-side] " .. message)
end

-- The tabs in the order they are drawn: Kin first, then the polities in the order the server sent them.
local function tabsOf(window)
    local kinTab, polityTabs, tabButtons = nil, {}, {}
    for _, child in ipairs(window:children():list()) do
        local childType = child:type()
        if childType == "PTab" then
            local content = child:children():list()[1]
            if content and content:type() == "BuddyWnd" then
                kinTab = child
            else
                table.insert(polityTabs, child)
            end
        elseif childType == "TButton" then
            table.insert(tabButtons, child)
        end
    end
    local tabs = {}
    if kinTab then
        table.insert(tabs, kinTab)
    end
    for _, polityTab in ipairs(polityTabs) do
        table.insert(tabs, polityTab)
    end
    return tabs, kinTab, tabButtons
end

local function differs(first, second)
    return math.abs(first - second) > 0.5
end

local function newDivider(window)
    local divider = hafen.ui():widget():parent(window):size(DIVIDER_WIDTH, 1)
    divider:on("Draw", function(drawEvent)
        local graphics = drawEvent:g()
        graphics:color(DIVIDER_COLOUR[1], DIVIDER_COLOUR[2], DIVIDER_COLOUR[3], DIVIDER_COLOUR[4])
        graphics:frect(0, 0, drawEvent:w(), drawEvent:h())
    end)
    return divider
end

local function layOut(layout)
    local window = layout.window
    local tabs, _, tabButtons = tabsOf(window)

    -- The client's current tab is the one already showing the first time it is seen, before any is shown here.
    if layout.currentTab and not layout.currentTab:exists() then
        layout.currentTab = nil
    end
    if layout.currentTab == nil and not layout.touched then
        for _, tab in ipairs(tabs) do
            if tab:visible() then
                layout.currentTab = tab
                break
            end
        end
    end

    local moved = false
    for _, tabButton in ipairs(tabButtons) do
        if tabButton:visible() then
            tabButton:visible(false)
            moved = true
        end
    end

    local tallest = 0
    for _, tab in ipairs(tabs) do
        tallest = math.max(tallest, tab:size().h)
    end

    local x = 0
    for index, tab in ipairs(tabs) do
        if not tab:visible() then
            tab:visible(true)
            moved = true
        end
        local place = tab:position()
        if differs(place.x, x) or differs(place.y, 0) then
            tab:position(x, 0)
            moved = true
        end
        x = x + tab:size().w
        if index < #tabs then
            local divider = layout.dividers[index]
            if divider == nil or not divider:exists() then
                divider = newDivider(window)
                layout.dividers[index] = divider
            end
            local dividerPlace, dividerSize = divider:position(), divider:size()
            if differs(dividerPlace.x, x + GAP) or differs(dividerSize.h, tallest) then
                divider:position(x + GAP, 0):size(DIVIDER_WIDTH, tallest)
                moved = true
            end
            x = x + GAP + DIVIDER_WIDTH + GAP
        end
    end
    for index = math.max(#tabs, 1), #layout.dividers do
        local divider = layout.dividers[index]
        if divider then
            divider:destroy()
            layout.dividers[index] = nil
            moved = true
        end
    end
    layout.touched = layout.touched or #tabs > 0

    -- The client packs the window itself when a tab changes size; a move of ours it does not see.
    if moved then
        window:pack()
    end
end

local function watchWindow(session)
    local window = session:ui():match("@Zergwnd")
    if window == nil then
        log("no Kith & Kin window for " .. session:user())
        return
    end
    local previous = layoutByUser[session:user()]
    if previous and previous.window == window then
        return
    end
    layoutByUser[session:user()] = {window = window, dividers = {}}
end

hafen.event():on("SessionEnteredWorld", watchWindow)
hafen.event():on("SessionRemoved", function(session)
    layoutByUser[session:user()] = nil
end)

-- A character already in the world when the addon loads.
for _, session in ipairs(hafen.session():list()) do
    if session:ui():match("@GameUI") then
        watchWindow(session)
    end
end

hafen.event():on("Update", function()
    for user, layout in pairs(layoutByUser) do
        if layout.window:exists() then
            layOut(layout)
        else
            layoutByUser[user] = nil
        end
    end
end)

-- Back to one tab at a time: the client's current one stays, or Kin when that one has gone.
hafen.event():on("Disable", function()
    for _, layout in pairs(layoutByUser) do
        if layout.window:exists() then
            local tabs, kinTab = tabsOf(layout.window)
            local currentTab = layout.currentTab
            if currentTab == nil or not currentTab:exists() then
                currentTab = kinTab
            end
            for _, tab in ipairs(tabs) do
                if tab ~= currentTab then
                    tab:visible(false)
                end
            end
        end
    end
end)
