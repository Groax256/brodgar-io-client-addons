-- Picking a player in one list of the Kith & Kin window picks the same player in every other list that has
-- them: the Kin list, and the member list of each Village and Realm tab.
--
-- A polity member's id is the buddy id of the same player (`Polity.Member.rname` looks the name up in the
-- Kin roster), so one id names a player across every list. Rows carry no id, though: a member reads the
-- kin's name as its text, the Kin row reads the same name, and a row is found by that name, skipped when two
-- kin share it. A member who is not your kin reads "???" and is never matched.
--
-- The click is read from the outbound stream, not from the list's `Changed`: a Kin row handles its own
-- mousedown and skips that seam. The Kin list sends `ch <id>` from the `BuddyWnd`, a member list
-- `sel <id>` from its polity. A list driven with `:value(row)` from inside the handler sends its own
-- message unreported (the stream is not re-entered for that character), so the lists do not echo.

local function rowNamed(list, name)
    local found = nil
    for _, row in ipairs(list:rows() or {}) do
        if row:text() == name then
            if found then
                return nil -- two rows with that name: neither is picked
            end
            found = row
        end
    end
    return found
end

local function pickIn(list, name)
    local row = rowNamed(list, name)
    if row then
        list:value(row)
    end
end

-- An outbound handler holds the sender's tree and may reach no other, so the window is found by walking up
-- from the sender (a polity: Category, PTab, Zergwnd; the Kin list: PTab, Zergwnd) rather than by looking
-- through every login's tree. The click came from the character on screen, whose roster names the id.
local function windowAbove(widget)
    local ancestor = widget:parent()
    while ancestor do
        if ancestor:type() == "Zergwnd" then
            return ancestor
        end
        ancestor = ancestor:parent()
    end
    return nil
end

local function pickEverywhere(window, buddyId, skipList)
    local session = hafen.session():current()
    if session == nil then
        return
    end
    local kin = session:kin():get(buddyId)
    local name = kin:exists() and kin:name() or nil
    if name == nil then
        return
    end
    local kinList = window:match("@BuddyList")
    if kinList and kinList ~= skipList then
        pickIn(kinList, name)
    end
    for _, memberList in ipairs(window:matchAll("@MemberList")) do
        if memberList ~= skipList then
            pickIn(memberList, name)
        end
    end
end

-- A Kin row: `ch <buddy id>` from the BuddyWnd. The colour row in a kin's panel sends `ch <group>` from its
-- own widget, which is not a BuddyWnd.
hafen.event():action():on("ch", function(event)
    local sender = event:widget()
    if sender:type() ~= "BuddyWnd" then
        return
    end
    local buddyId = event:args()[1]
    if type(buddyId) ~= "number" then
        return
    end
    local window = windowAbove(sender)
    if window then
        pickEverywhere(window, buddyId, window:match("@BuddyList"))
    end
end)

-- A member row: `sel <buddy id>` from the polity holding the list. No id is a cleared pick or your own row.
hafen.event():action():on("sel", function(event)
    local buddyId = event:args()[1]
    if type(buddyId) ~= "number" then
        return
    end
    local sender = event:widget()
    local memberList = sender:match("@MemberList")
    if memberList == nil then
        return
    end
    local window = windowAbove(sender)
    if window then
        pickEverywhere(window, buddyId, memberList)
    end
end)
