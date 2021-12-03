local ns = select(2, ...) ---@type ChatEmotesNamespace @The addon namespace.

local L = ns:NewLocale()

L.LOCALE_NAME = "enUS"

L.CHAT_EMOTES = "Chat Emotes"
L.YOU_HAVE_NO_EMOTES_INSTALLED = "You have no emotes installed."
L.SEARCH_RESULTS = "Results: %d"
L.CHAT_EMOTES_OPTIONS = "Chat Emotes • Options"
L.OPTIONS = "Options"
L.EMOTE_SCALE = "% Emote Scale"
L.EMOTE_HOVER = "Show Emote Tooltip"
L.MISSING_EMOTE_PACK = "|cffFF8844You are missing emote packages. You need to install at least one before Chat Emotes can be of service.|r\r\n\r\nCheck the addon description for links to suggested packages that you can download.\r\n\r\nAlternatively, perform a search for \"|cffFFFFFFChat Emotes|r\" and see what other addons appear amongst the results."

ns.L = L
