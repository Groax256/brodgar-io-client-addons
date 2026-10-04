-- Side-by-side layout for the Kith & Kin window tabs (Kin, Village, Realm).

local GAP_DISTANCE = 10
local DIVIDER_WIDTH = 1
local DIVIDER_COLOR = {150, 130, 100, 200}

local layouts_by_user = {} -- username -> {window = zergwnd_window, dividers = {}, current_tab = tab_widget, touched = boolean}

local function collect_window_tabs(zergwnd_window)
    local kin_tab = nil
    local polity_tabs = {}
    local tab_buttons = {}

    for _, child_widget in ipairs(zergwnd_window:children():list()) do
        local widget_type = child_widget:type()
        if widget_type == "PTab" then
            local tab_content = child_widget:children():list()[1]
            if tab_content and tab_content:type() == "BuddyWnd" then
                kin_tab = child_widget
            else
                table.insert(polity_tabs, child_widget)
            end
        elseif widget_type == "TButton" then
            table.insert(tab_buttons, child_widget)
        end
    end

    local ordered_tabs = {}
    if kin_tab then
        table.insert(ordered_tabs, kin_tab)
    end
    for _, polity_tab in ipairs(polity_tabs) do
        table.insert(ordered_tabs, polity_tab)
    end

    return ordered_tabs, kin_tab, tab_buttons
end

local function coordinate_differs(first_coordinate, second_coordinate)
    return math.abs(first_coordinate - second_coordinate) > 0.5
end

local function create_divider_widget(parent_window)
    local divider_widget = hafen.ui():widget():parent(parent_window):size(DIVIDER_WIDTH, 1)
    divider_widget:on("Draw", function(draw_event)
        local graphics_context = draw_event:g()
        graphics_context:color(DIVIDER_COLOR[1], DIVIDER_COLOR[2], DIVIDER_COLOR[3], DIVIDER_COLOR[4])
        graphics_context:frect(0, 0, draw_event:w(), draw_event:h())
    end)
    return divider_widget
end

local function apply_side_by_side_layout(user_layout)
    local zergwnd_window = user_layout.window
    local ordered_tabs, _, tab_buttons = collect_window_tabs(zergwnd_window)

    if user_layout.current_tab and not user_layout.current_tab:exists() then
        user_layout.current_tab = nil
    end

    if user_layout.current_tab == nil and not user_layout.touched then
        for _, tab_widget in ipairs(ordered_tabs) do
            if tab_widget:visible() then
                user_layout.current_tab = tab_widget
                break
            end
        end
    end

    local layout_changed = false
    for _, tab_button in ipairs(tab_buttons) do
        if tab_button:visible() then
            tab_button:visible(false)
            layout_changed = true
        end
    end

    local tallest_tab_height = 0
    for _, tab_widget in ipairs(ordered_tabs) do
        tallest_tab_height = math.max(tallest_tab_height, tab_widget:size().h)
    end

    local current_horizontal_offset = 0
    for tab_index, tab_widget in ipairs(ordered_tabs) do
        if not tab_widget:visible() then
            tab_widget:visible(true)
            layout_changed = true
        end

        local current_position = tab_widget:position()
        if coordinate_differs(current_position.x, current_horizontal_offset) or coordinate_differs(current_position.y, 0) then
            tab_widget:position(current_horizontal_offset, 0)
            layout_changed = true
        end

        current_horizontal_offset = current_horizontal_offset + tab_widget:size().w

        if tab_index < #ordered_tabs then
            local divider_widget = user_layout.dividers[tab_index]
            if divider_widget == nil or not divider_widget:exists() then
                divider_widget = create_divider_widget(zergwnd_window)
                user_layout.dividers[tab_index] = divider_widget
            end

            local divider_position = divider_widget:position()
            local divider_size = divider_widget:size()
            if coordinate_differs(divider_position.x, current_horizontal_offset + GAP_DISTANCE)
                or coordinate_differs(divider_size.h, tallest_tab_height) then
                divider_widget:position(current_horizontal_offset + GAP_DISTANCE, 0):size(DIVIDER_WIDTH, tallest_tab_height)
                layout_changed = true
            end

            current_horizontal_offset = current_horizontal_offset + GAP_DISTANCE + DIVIDER_WIDTH + GAP_DISTANCE
        end
    end

    for divider_index = math.max(#ordered_tabs, 1), #user_layout.dividers do
        local excess_divider = user_layout.dividers[divider_index]
        if excess_divider then
            excess_divider:destroy()
            user_layout.dividers[divider_index] = nil
            layout_changed = true
        end
    end

    user_layout.touched = user_layout.touched or #ordered_tabs > 0

    if layout_changed then
        zergwnd_window:pack()
    end
end

local function register_window_layout(active_session, zergwnd_window)
    local username = active_session:user()
    local previous_layout = layouts_by_user[username]
    if previous_layout and previous_layout.window == zergwnd_window then
        return
    end
    layouts_by_user[username] = {window = zergwnd_window, dividers = {}}
end

local function watch_session_window(active_session)
    local zergwnd_window = active_session:ui():match("@Zergwnd")
    if zergwnd_window then
        register_window_layout(active_session, zergwnd_window)
    end
    active_session:ui():on("@Zergwnd", "Added", function(added_window)
        register_window_layout(active_session, added_window)
    end)
end

hafen.event():on("SessionEnteredWorld", watch_session_window)
hafen.event():on("SessionRemoved", function(removed_session)
    layouts_by_user[removed_session:user()] = nil
end)

for _, active_session in ipairs(hafen.session():list()) do
    if active_session:ui():match("@GameUI") then
        watch_session_window(active_session)
    end
end

hafen.event():on("Update", function()
    for username, user_layout in pairs(layouts_by_user) do
        if user_layout.window:exists() then
            apply_side_by_side_layout(user_layout)
        else
            layouts_by_user[username] = nil
        end
    end
end)

hafen.event():on("Disable", function()
    for _, user_layout in pairs(layouts_by_user) do
        if user_layout.window:exists() then
            local ordered_tabs, kin_tab = collect_window_tabs(user_layout.window)
            local current_tab = user_layout.current_tab
            if current_tab == nil or not current_tab:exists() then
                current_tab = kin_tab
            end
            for _, tab_widget in ipairs(ordered_tabs) do
                if tab_widget ~= current_tab then
                    tab_widget:visible(false)
                end
            end
        end
    end
end)
