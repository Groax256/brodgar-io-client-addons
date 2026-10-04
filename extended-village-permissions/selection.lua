-- Synchronizes player selection across all tabs in the Kith & Kin window (Kin, Village, Realm).

local function find_row_by_name(target_list, player_name)
    local matching_row = nil
    for _, row_widget in ipairs(target_list:rows() or {}) do
        if row_widget:text() == player_name then
            if matching_row then
                return nil
            end
            matching_row = row_widget
        end
    end
    return matching_row
end

local function select_player_in_list(target_list, player_name)
    local matching_row = find_row_by_name(target_list, player_name)
    if matching_row then
        target_list:value(matching_row)
    end
end

local function find_enclosing_window(starting_widget)
    local ancestor_widget = starting_widget:parent()
    while ancestor_widget do
        if ancestor_widget:type() == "Zergwnd" then
            return ancestor_widget
        end
        ancestor_widget = ancestor_widget:parent()
    end
    return nil
end

local function synchronize_player_selection(zergwnd_window, buddy_identifier, excluded_list)
    local current_session = hafen.session():current()
    if current_session == nil then
        return
    end

    local kin_entry = current_session:kin():get(buddy_identifier)
    local player_name = kin_entry:exists() and kin_entry:name() or nil
    if player_name == nil then
        return
    end

    local buddy_list = zergwnd_window:match("@BuddyList")
    if buddy_list and buddy_list ~= excluded_list then
        select_player_in_list(buddy_list, player_name)
    end

    for _, member_list in ipairs(zergwnd_window:matchAll("@MemberList")) do
        if member_list ~= excluded_list then
            select_player_in_list(member_list, player_name)
        end
    end
end

-- Outbound action handler for Kin rows: "ch <buddy_identifier>" from BuddyWnd.
hafen.event():action():on("ch", function(action_event)
    local sender_widget = action_event:widget()
    if sender_widget:type() ~= "BuddyWnd" then
        return
    end

    local buddy_identifier = action_event:args()[1]
    if type(buddy_identifier) ~= "number" then
        return
    end

    local enclosing_window = find_enclosing_window(sender_widget)
    if enclosing_window then
        synchronize_player_selection(enclosing_window, buddy_identifier, enclosing_window:match("@BuddyList"))
    end
end)

-- Outbound action handler for member rows: "sel <buddy_identifier>" from polity category.
hafen.event():action():on("sel", function(action_event)
    local buddy_identifier = action_event:args()[1]
    if type(buddy_identifier) ~= "number" then
        return
    end

    local sender_widget = action_event:widget()
    local member_list = sender_widget:match("@MemberList")
    if member_list == nil then
        return
    end

    local enclosing_window = find_enclosing_window(sender_widget)
    if enclosing_window then
        synchronize_player_selection(enclosing_window, buddy_identifier, member_list)
    end
end)
