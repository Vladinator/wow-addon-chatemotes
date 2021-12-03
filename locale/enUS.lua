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

ns.L = L
