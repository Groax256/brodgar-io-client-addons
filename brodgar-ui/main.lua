-- Brodgar UI: a pack of Simple Minimap, Simple Chat, Quick Search, Actionbars, Themes, Hider, Hitboxes,
-- Stockpile Take and Multi-Session, set up to work together.
--
-- The manifest lists the nine as dependencies, so each one that is on has run by now. The player may turn any of
-- them off on its own and the bundle still loads, so each preset goes only to an addon that is on: :api() is nil
-- for one that is not. This file only says where two of them start and which theme the client starts in; what
-- the user changes afterwards stays each addon's own to remember. A preset's numbers are screen pixels, the same
-- on every interface scale.

local addons = hafen.client():addons()

-- The minimap: the screen's top-right corner, with the map 300 px square.
local simpleMinimap = addons:get("simple-minimap"):api()
if simpleMinimap then
  simpleMinimap.preset{
    place = {at = "topright", offset = {-8, 8}},
    mapSize = {width = 300, height = 300},
  }
end

-- The chat: the screen's bottom-left corner, at Simple Chat's own size.
local simpleChat = addons:get("simple-chat"):api()
if simpleChat then
  simpleChat.preset{
    place = {at = "bottomleft", offset = {8, -8}},
  }
end

-- The look: the Simple theme, the client's own without the blackletter. Themes acts on it once, for a player
-- who has picked no theme; a theme picked before or after is the player's.
local themes = addons:get("themes"):api()
if themes then
  themes.preset{
    theme = "simple",
  }
end

-- The rest take nothing: Quick Search opens its field in the middle of the screen, Actionbars starts its
-- first bar centred on the bottom edge, and Hider, Hitboxes, Stockpile Take and Multi-Session are as their
-- addons ship them.

-- ---------------------------------------------------------------- the setup guide

local Guide = BrodgarUI.Guide

hafen.event():on("SessionEnteredWorld", Guide.openFirstTime)

hafen.console():on("brodgarui", function()
  hafen.timer():after(0, Guide.open)
end)

-- Options > AddOns > Brodgar UI: a button that opens the guide. The page stands in the Options window, so the
-- guide is built on the next step.
hafen.client():options():addon():panel(function(root)
  root:gap(6)
  hafen.ui():label():parent(root):text("Set up the client and the addons of Brodgar UI, one page at a time.")
  local openButton = hafen.ui():button():parent(root):size(160):text("Open the setup guide")
  openButton:on("Pressed", function()
    hafen.timer():after(0, Guide.open)
  end)
end)
