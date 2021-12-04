if WOW_PROJECT_ID ~= WOW_PROJECT_MAINLINE then return end

local CEL = LibStub and LibStub("ChatEmotesLib-1.0", true) ---@type ChatEmotesLib-1.0
if not CEL then return end

local _G = _G
local strlenutf8 = _G.strlenutf8

---@class ChatEmotesLocale
---@field public LOCALE_NAME string
---@field public CHAT_EMOTES string
---@field public YOU_HAVE_NO_EMOTES_INSTALLED string
---@field public MISSING_EMOTE_PACK string
---@field public SEARCH_RESULTS string
---@field public CHAT_EMOTES_OPTIONS string
---@field public OPTIONS string
---@field public EMOTE_SCALE string
---@field public EMOTE_HOVER string

---@class ChatEmotesNamespace
---@field public NewLocale function
---@field public IsSameLocale function
---@field public L ChatEmotesLocale

local addonName = ... ---@type string @The name of the addon.
local ns = select(2, ...) ---@type ChatEmotesNamespace @The addon namespace.
local L = ns.L

local addon = CreateFrame("Frame")
local addonFrame ---@type ChatEmotesUIMixin
local addonButton ---@type ChatEmotesUIButton
local addonConfigFrame ---@type ChatEmotesUIConfigMixin

local NO_EMOTE_MARKUP_FALLBACK = format("|T%s:%d:%d:%d:%d:%d:%d:%d:%d:%d:%d|t", 132048, 16, 10, -1, 0, 16, 16, 4, 13, 0, 16)

---@class ChatEmoteStatistics
---@field public sent? number|nil
---@field public received? number|nil

---@class ChatEmotesDB_Options
---@field public emoteScale number
---@field public emoteHover boolean

---@class ChatEmotesDB_Position
---@field public point string
---@field public relativeTo? string|nil
---@field public relativePoint string
---@field public x number
---@field public y number
---@field public width number
---@field public height number

---@class ChatEmotesDB
---@field public options ChatEmotesDB_Options
---@field public position ChatEmotesDB_Position
---@field public favorites table<string, boolean|nil>
---@field public statistics table<string, ChatEmoteStatistics>

local DB ---@type ChatEmotesDB
local defaults = {
	options = {
		emoteScale = 1.25,
		emoteHover = true,
	},
	position = {
		point = "LEFT",
		relativeTo = nil,
		relativePoint = "LEFT",
		x = 15,
		y = -175,
		width = 335,
		height = 345,
	},
	favorites = {},
	statistics = {},
}

---@type table<string, number>
local activeChannels = {}

---@type table<number, boolean>
local ignoreChannels = {
	-- [1] = true, -- General (General - %s)
	-- [2] = true, -- Trade (Trade - %s)
	-- [22] = true, -- LocalDefense (LocalDefense - %s)
	-- [26] = true, -- LookingForGroup (LookingForGroup)
	-- [27] = true, -- BigfootWorldChannel (BigfootWorldChannel)
	-- [28] = true, -- MeetingStone (MeetingStone)
	-- [32] = true, -- NewcomerChat (Newcomer Chat)
	-- [33] = true, -- ShadowlandsBetaDiscussion (zzOLD Shadowlands Beta Discussion)
	-- [34] = true, -- ShadowlandsPTRDiscussion (zzOLD Shadowlands PTR Discussion)
	-- [35] = true, -- ShadowlandsTestDiscussion (Shadowlands Test Discussion)
	-- [36] = true, -- ChromieTime (Chromie Time - Cataclysm)
	-- [37] = true, -- ChromieTime (Chromie Time - Burning Crusade)
	-- [38] = true, -- ChromieTime (Chromie Time - Wrath of the Lich King)
	-- [39] = true, -- ChromieTime (Chromie Time - Mists of Pandaria)
	-- [40] = true, -- ChromieTime (Chromie Time - Warlords of Draenor)
	-- [41] = true, -- ChromieTime (Chromie Time - Legion)
}

---@class ScrollingMessageFrame : FontString, Frame

---@class ChatFrameEditBox : EditBox
---@field public autoCompleteSource? function|nil
---@field public customAutoCompleteFunction? function|nil

---@class ChatFrame : ScrollingMessageFrame
---@field public editBox ChatFrameEditBox

local supportedChatEvents = {
	"CHAT_MSG_BN_CONVERSATION",
	"CHAT_MSG_BN_WHISPER",
	"CHAT_MSG_BN_WHISPER_INFORM",
	"CHAT_MSG_CHANNEL",
	"CHAT_MSG_GUILD",
	"CHAT_MSG_INSTANCE_CHAT",
	"CHAT_MSG_OFFICER",
	"CHAT_MSG_PARTY",
	"CHAT_MSG_PARTY_GUIDE",
	"CHAT_MSG_PARTY_LEADER",
	"CHAT_MSG_RAID",
	"CHAT_MSG_RAID_LEADER",
	"CHAT_MSG_RAID_WARNING",
	"CHAT_MSG_SAY",
	"CHAT_MSG_WHISPER",
	"CHAT_MSG_WHISPER_INFORM",
	"CHAT_MSG_YELL",
}

local function ChatInsert(text, noPadding)
	if not noPadding then
		text = format("%s ", text)
	end
	if ChatEdit_GetActiveWindow() then
		ChatEdit_InsertLink(text)
	else
		ChatFrame_OpenChat(text)
	end
end

---@param emote ChatEmotesLib-1.0_Emote
local function GetEmoteUniqueKey(emote)
	return format("%s %s", emote.package, emote.name)
end

---@param emote ChatEmotesLib-1.0_Emote
local function IsFavorite(emote)
	local unique = GetEmoteUniqueKey(emote)
	return DB.favorites[unique]
end

---@param emote ChatEmotesLib-1.0_Emote
---@param noUpdates? boolean
local function AddToFavorites(emote, noUpdates)
	local unique = GetEmoteUniqueKey(emote)
	DB.favorites[unique] = true
	if not noUpdates then
		addonFrame:UpdateEmoteFrames(emote)
	end
end

---@param emote ChatEmotesLib-1.0_Emote
---@param noUpdates? boolean
local function RemoveFromFavorites(emote, noUpdates)
	local unique = GetEmoteUniqueKey(emote)
	DB.favorites[unique] = nil
	if not noUpdates then
		addonFrame:UpdateEmoteFrames(emote)
	end
end

---@param emote ChatEmotesLib-1.0_Emote
---@param noUpdates? boolean
local function ToggleFavorite(emote, noUpdates)
	if IsFavorite(emote) then
		RemoveFromFavorites(emote, noUpdates)
	else
		AddToFavorites(emote, noUpdates)
	end
end

---@param emote ChatEmotesLib-1.0_Emote
local function GetStatistics(emote, createIfMissing)
	local unique = GetEmoteUniqueKey(emote)
	local emoteStats = DB.statistics[unique]
	if createIfMissing and not emoteStats then
		emoteStats = {}
		DB.statistics[unique] = emoteStats
	end
	return emoteStats
end

---@param emotes ChatEmotesLib-1.0_Emote[]
---@param guid string
local function LogEmoteStatistics(emotes, guid)
	local isPlayer = guid == UnitGUID("player")
	for _, emote in ipairs(emotes) do
		local emoteStats = GetStatistics(emote, true)
		if isPlayer then
			emoteStats.sent = (emoteStats.sent or 0) + 1
		else
			emoteStats.received = (emoteStats.received or 0) + 1
			-- if not emoteStats.receivedFrom then
			-- 	emoteStats.receivedFrom = {}
			-- end
			-- emoteStats.receivedFrom[guid] = (emoteStats.receivedFrom[guid] or 0) + 1
		end
	end
end

---@param chatFrame ChatFrame
---@param forceScale? number|nil
---@param heightOffset? number|nil
---@return number
local function GetHeightForChatFrame(chatFrame, forceScale, heightOffset)
	local _, height = chatFrame:GetFont()
	if not height or height < 1 then
		height = CHAT_FRAME_DEFAULT_FONT_SIZE or 14 ---@diagnostic disable-line: undefined-global
	end
	if heightOffset then
		height = height + heightOffset
	end
	return height * (forceScale or DB.options.emoteScale)
end

local prevLineID

---@param self ChatFrame
---@param event string
---@param text string
local function ChatMessageFilter(self, event, text, playerName, languageName, channelName, playerName2, specialFlags, zoneChannelID, channelIndex, channelBaseName, unused, lineID, guid, ...)
	local isIgnored = zoneChannelID and zoneChannelID ~= 0 and ignoreChannels[zoneChannelID]
	if isIgnored then
		return
	end
	local isActive = not zoneChannelID or zoneChannelID == 0 or activeChannels[zoneChannelID]
	if not isActive then
		return
	end
	local height = GetHeightForChatFrame(self)
	local newText, usedEmotes = CEL.ReplaceEmotesInText(text, height, DB.options.emoteHover, true)
	if newText then
		if prevLineID ~= lineID then
			prevLineID = lineID
			LogEmoteStatistics(usedEmotes, guid)
		end
		return false, newText, playerName, languageName, channelName, playerName2, specialFlags, zoneChannelID, channelIndex, channelBaseName, unused, lineID, guid, ...
	end
end

local autoCompleteCache = {}

local function GetPosition(text, pos)
	local from = 1
	local to = strlenutf8(text)
	local sfrom
	local sto
	for i = pos, 1, -1 do
		local chr = text:sub(i, i)
		if chr == " " then
			from = i + 1
			break
		elseif chr == CEL.emoteWrapper then
			sfrom = i
			from = i + 1
			break
		end
	end
	for i = from, to do
		local chr = text:sub(i, i)
		if chr == " " then
			to = i - 1
			break
		elseif chr == CEL.emoteWrapper then
			sto = i
			to = i - 1
			break
		end
	end
	return from, to, sfrom or from, sto or to
end

local function SortAutoCompleteCache(a, b)
	if a.priority == b.priority then
		return a.name < b.name
	end
	return a.priority < b.priority
end

---@param text string
---@param maxResults number
---@param utf8Position number
---@param allowFullMatch boolean
---The varargs contain the include/exclude or other provided arguments.
local function AutoCompleteSource(text, maxResults, utf8Position, allowFullMatch, ...)
	wipe(autoCompleteCache)
	local from, to, sfrom, sto = GetPosition(text, utf8Position)
	local aggressiveMatched = sfrom - from == 0
	if aggressiveMatched then
		return autoCompleteCache
	end
	local len = to - from
	if len < 1 then
		return autoCompleteCache
	end
	local query = text:sub(from, to)
	local emotes, weights = CEL.GetEmotesSearch(query, aggressiveMatched and CEL.filter.nameFindTextStartsWithCaseless or CEL.filter.nameFindTextCaseless)
	if not emotes then
		return autoCompleteCache
	end
	if emotes[2] then
		CEL.SortEmotes(emotes, weights)
	end
	local index = 0
	for i = 1, emotes[0] do
		local emote = emotes[i]
		if not emote.ignoreSuggestion then
			local priority = emote.name:find(query) or (100 + (emote.name:lower():find(query:lower()) or 99))
			index = index + 1
			autoCompleteCache[index] = {
				name = emote.name,
				priority = priority,
				chatemote = emote,
				chatemotefrom = sfrom,
				chatemoteto = sto,
			}
		end
	end
	if not autoCompleteCache[1] then
		return autoCompleteCache
	elseif autoCompleteCache[2] then
		table.sort(autoCompleteCache, SortAutoCompleteCache)
	end
	for i = 1, #autoCompleteCache do
		local result = autoCompleteCache[i]
		result.priority = 1
	end
	for i = maxResults + 1, #autoCompleteCache do
		autoCompleteCache[i] = nil
	end
	return autoCompleteCache
end

---@param self ChatFrameEditBox
---@param newText string
---@param result table
---@param name string
local function AutoCompleteAccept(self, newText, result, name)
	local emote = result.chatemote ---@type ChatEmotesLib-1.0_Emote
	if not emote then
		return true
	end
	local text = self:GetText()
	local prefix = text:sub(1, result.chatemotefrom - 1)
	local suffix = text:sub(result.chatemoteto + 1)
	local updatedText = format("%s%s%s", prefix, emote.name, suffix)
	self:SetText(updatedText)
	self:SetCursorPosition(strlenutf8(updatedText) - strlenutf8(suffix))
	return true
end

local origAutoCompletFuncs = {}

---@param self ChatFrameEditBox
local function CacheOrigAutoCompletFuncs(self)
	local cache = origAutoCompletFuncs[self]
	if not cache then
		cache = {}
		origAutoCompletFuncs[self] = cache
	end
	if self.autoCompleteSource ~= AutoCompleteSource then
		cache.autoCompleteSource = self.autoCompleteSource
	end
	if self.customAutoCompleteFunction ~= AutoCompleteAccept then
		cache.customAutoCompleteFunction = self.customAutoCompleteFunction
	end
	if cache.autoCompleteSource then
		return cache
	end
	self.autoCompleteSource = AutoCompleteSource
	self.customAutoCompleteFunction = AutoCompleteAccept
	return cache
end

---@param self ChatFrameEditBox
local function CacheOrigAutoCompletFuncsRestore(self)
	local cache = CacheOrigAutoCompletFuncs(self)
	self.autoCompleteSource = cache.autoCompleteSource
	self.customAutoCompleteFunction = cache.customAutoCompleteFunction
end

---@param self ChatFrameEditBox
local function AutoCompleteEditBox_SetAutoCompleteSource(self, source)
	CacheOrigAutoCompletFuncs(self)
end

---@param self ChatFrameEditBox
local function AutoCompleteEditBox_SetCustomAutoCompleteFunction(self)
	CacheOrigAutoCompletFuncs(self)
end

---@param autoCompleteBox Frame
---@param results table
---@param context? string
local function AutoComplete_UpdateResults(autoCompleteBox, results, context)
	local self = autoCompleteBox.parent ---@diagnostic disable-line
	local first = results[1]
	if not first or not first.chatemote then
		CacheOrigAutoCompletFuncsRestore(self)
		return
	end
	local totalReturns = #results
	local numReturns = min(totalReturns, AUTOCOMPLETE_MAX_BUTTONS) ---@diagnostic disable-line: undefined-global
	for i = 1, numReturns do
		local button = _G["AutoCompleteButton" .. i] ---@type Button
		if button:IsEnabled() then
			local result = button.nameInfo ---@diagnostic disable-line
			local emote = result.chatemote ---@type ChatEmotesLib-1.0_Emote
			if emote then
				button:SetText(format("%s %s", emote.markup, emote.name))
			end
		end
	end
end

---@param self ChatFrameEditBox
---@param userInput boolean
local function ChatEditBoxOnTextChanged(self, userInput)
	if not userInput then
		return
	end
	local text = self:GetText()
	if not text then
		return
	end
	CacheOrigAutoCompletFuncs(self)
	if not self.autoCompleteSource or self.autoCompleteSource == AutoCompleteSource then
		_G.AutoCompleteEditBox_SetAutoCompleteSource(self, AutoCompleteSource, "chatemote") ---@diagnostic disable-line
		_G.AutoCompleteEditBox_SetCustomAutoCompleteFunction(self, AutoCompleteAccept) ---@diagnostic disable-line
		_G.AutoComplete_Update(self, text, self:GetUTF8CursorPosition()) ---@diagnostic disable-line
	end
end

---@param self ChatFrame
---@param link string
---@param text string
---@param button string
local function ChatFrameOnHyperlinkClick(self, link, text, button)
	if not DB.options.emoteHover then
		return
	end
	local emote = CEL.GetEmoteFromLink(link)
	if not emote then
		return
	end
	if button == "RightButton" then
		addon:TogglePicker(emote)
	else
		ChatInsert(emote.name)
	end
end

---@param self ChatFrame
---@param link string
---@param text string
local function ChatFrameOnHyperlinkEnter(self, link, text)
	if not DB.options.emoteHover then
		return
	end
	local emote = CEL.GetEmoteFromLink(link)
	if not emote then
		return
	end
	GameTooltip:SetOwner(self, "ANCHOR_CURSOR", 0, 0)
	GameTooltip:AddLine(tostring(emote.name), 1, 1, 1)
	GameTooltip:AddLine(emote.markup:gsub(":0:0", format(":%d:%d", 32, 32 * (emote.ratio or 1)), 1), 1, 1, 1)
	GameTooltip:AddLine(tostring(emote.package), 0.5, 0.5, 0.5)
	GameTooltip:AddLine(tostring(emote.folder), 0.5, 0.5, 0.5)
	GameTooltip:Show()
end

---@param self ChatFrame
---@param link string
---@param text string
local function ChatFrameOnHyperlinkLeave(self, link, text)
	if not DB.options.emoteHover then
		return
	end
	GameTooltip:Hide()
end

local function GetRandomEmote()
	local emotes = CEL.GetEmotes()
	local index = random(1, min(100, max(1, emotes[0])))
	return emotes[index]
end

local function CreateUI(frameName) end ---@return ChatEmotesUIMixin
local function CreateButton(frameName) end ---@return ChatEmotesUIButton
local function CreateConfig(frameName) end ---@return ChatEmotesUIConfigMixin

do

	---@class CallbackRegistryMixin : Frame
	---@field public GenerateCallbackEvents function
	---@field public TriggerEvent function

	---@class ScrollBoxListViewMixin : CallbackRegistryMixin
	---@field public FindFrame function(elementData)
	---@field public HasScrollableExtent function
	---@field public ScrollToEnd function(noInterpolation)
	---@field public GetScrollPercentage function
	---@field public GetVisibleExtentPercentage function
	---@field public IsScrollAllowed function
	---@field public GetView function
	---@field public Init function(view)
	---@field public SetView function(view)
	---@field public Flush function
	---@field public ForEachFrame function(func)
	---@field public EnumerateFrames function
	---@field public FindElementDataByPredicate function(predicate)
	---@field public FindElementDataIndexByPredicate function(predicate)
	---@field public FindByPredicate function(predicate)
	---@field public Find function(index)
	---@field public FindIndex function(elementData)
	---@field public InsertElementData function(...)
	---@field public InsertElementDataTable function(tbl)
	---@field public InsertElementDataTableRange function(tbl, indexBegin, indexEnd)
	---@field public ContainsElementDataByPredicate function(predicate)
	---@field public GetDataProvider function
	---@field public HasDataProvider function
	---@field public ClearDataProvider function
	---@field public GetDataIndexBegin function
	---@field public GetDataIndexEnd function
	---@field public IsVirtualized function
	---@field public GetElementExtent function(dataIndex)
	---@field public GetExtentUntil function(dataIndex)
	---@field public SetDataProvider function(dataProvider, retainScrollPosition)
	---@field public GetDataProviderSize function
	---@field public OnViewDataChanged function
	---@field public Rebuild function
	---@field public OnViewAcquiredFrame function(frame, elementData, new)
	---@field public OnViewReleasedFrame function(frame, oldElementData)
	---@field public IsAcquireLocked function
	---@field public FullUpdateInternal function
	---@field public Update function(forceLayout)
	---@field public ScrollToNearest function(dataIndex, noInterpolation)
	---@field public ScrollToElementDataIndex function(dataIndex, alignment, noInterpolation)
	---@field public ScrollToElementData function(elementData, alignment, noInterpolation)
	---@field public ScrollToElementDataByPredicate function(predicate, alignment, noInterpolation)

	---@class WowScrollBoxList : ScrollBoxListViewMixin

	---@class ChatEmotesUIScrollCollectionMixin : CallbackRegistryMixin

	local function SetScrollBoxButtonAlternateState(scrollBox)
		local index = scrollBox:GetDataIndexBegin()
		scrollBox:ForEachFrame(function(button)
			button:SetAlternateOverlayShown(index % 2 == 1)
			index = index + 1
		end)
	end

	---@type ChatEmotesUIScrollCollectionMixin
	local UIScrollCollectionMixin = CreateFromMixins(CallbackRegistryMixin)

	UIScrollCollectionMixin:GenerateCallbackEvents({
		"OnHide",
		"OnShow",
		"OnSizeChanged",
		"OnScroll", -- WowScrollBoxList
		"OnAllowScrollChanged", -- WowScrollBoxList
	})

	function UIScrollCollectionMixin:OnLoad()
		CallbackRegistryMixin.OnLoad(self)
	end

	function UIScrollCollectionMixin:OnHide()
		self:TriggerEvent("OnHide")
	end

	function UIScrollCollectionMixin:OnShow()
		self:TriggerEvent("OnShow")
	end

	function UIScrollCollectionMixin:OnSizeChanged(width, height)
		self:TriggerEvent("OnSizeChanged", width, height)
	end

	---@class ChatEmotesUIScrollBoxEmoteButtonMixin : Button

	---@type ChatEmotesUIScrollBoxEmoteButtonMixin
	local UIScrollBoxEmoteButtonMixin = {}

	local ScrollBoxEmoteButtonSize = 30

	function UIScrollBoxEmoteButtonMixin:OnLoad()
		-- self:SetHeight(ButtonSize)
		self:SetSize(ScrollBoxEmoteButtonSize, ScrollBoxEmoteButtonSize) -- grid
		-- self.RightLabel = self:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		-- self.RightLabel:SetJustifyH("RIGHT")
		-- self.RightLabel:SetHeight(ButtonSize)
		-- self.RightLabel:SetPoint("RIGHT", -5, 0)
		-- self.RightLabel:SetScale(2)
		-- self.LeftLabel = self:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		-- self.LeftLabel:SetJustifyH("LEFT")
		-- self.LeftLabel:SetHeight(ButtonSize)
		-- self.LeftLabel:SetPoint("LEFT", 5, 0)
		-- self.LeftLabel:SetPoint("RIGHT", self.RightLabel, "LEFT", -5, 0)
		self.Label = self:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall", 1)
		self.Label:SetJustifyH("CENTER")
		self.Label:SetJustifyV("MIDDLE")
		self.Label:SetAllPoints()
		self.Label:SetScale(2)
		self.Background = self:CreateTexture(nil, "BACKGROUND", nil, 1)
		self.Background:SetAllPoints()
		self.Background:SetColorTexture(0.1, 0.1, 0.1, 1)
		self.MouseoverOverlay = self:CreateTexture(nil, "ARTWORK", 2)
		self.MouseoverOverlay:SetAllPoints()
		self.MouseoverOverlay:SetColorTexture(0.5, 0.5, 0.5, 1)
		self.MouseoverOverlay:Hide()
		self.Alternate = self:CreateTexture(nil, "BACKGROUND", nil, 2)
		self.Alternate:SetAllPoints()
		self.Alternate:SetColorTexture(0.2, 0.2, 0.2, 1)
		self.Alternate:Hide()
		-- self.Star = self:CreateTexture(nil, "OVERLAY", nil, 1)
		-- self.Star:SetTexture(2923258)
		-- self.Star:SetTexCoord(2/32, 16/32, 2/32, 16/32)
		-- self.Star:SetSize(16, 16)
		-- self.Star:SetPoint("TOPRIGHT", 1, 1)
		-- self.Star:Hide()
		self:SetScript("OnEnter", self.OnEnter)
		self:SetScript("OnLeave", self.OnLeave)
		self:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		self:SetScript("OnClick", self.OnClick)
	end

	---@param emote ChatEmotesLib-1.0_Emote
	function UIScrollBoxEmoteButtonMixin:Init(emote)
		-- self.LeftLabel:SetText(emote.name)
		-- self.RightLabel:SetText(emote.markup)
		self.emote = emote
		self.Label:SetText(emote.markup)
		self:Update()
	end

	function UIScrollBoxEmoteButtonMixin:OnEnter()
		self.MouseoverOverlay:Show()
		local emote = self.emote
		GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT", 0, 0)
		GameTooltip:AddLine(tostring(emote.name), 1, 1, 1)
		-- GameTooltip:AddLine(emote.markup:gsub(":0:0", format(":%d:%d", 32, 32 * (emote.ratio or 1)), 1), 1, 1, 1)
		GameTooltip:AddLine(tostring(emote.package), 0.5, 0.5, 0.5)
		GameTooltip:AddLine(tostring(emote.folder), 0.5, 0.5, 0.5)
		GameTooltip:Show()
	end

	function UIScrollBoxEmoteButtonMixin:OnLeave()
		self.MouseoverOverlay:Hide()
		GameTooltip:Hide()
	end

	function UIScrollBoxEmoteButtonMixin:OnClick(button)
		local emote = self.emote
		if button == "LeftButton" then
			ChatInsert(emote.name)
		elseif button == "RightButton" then
			ToggleFavorite(emote)
		end
	end

	function UIScrollBoxEmoteButtonMixin:SetAlternateOverlayShown(alternate)
		self.Alternate:SetShown(alternate)
	end

	function UIScrollBoxEmoteButtonMixin:Update()
		-- local emote = self.emote
		-- if IsFavorite(emote) then
		-- 	self.Background:SetColorTexture(0.2, 0.2, 0, 1)
		-- 	self.MouseoverOverlay:SetColorTexture(0.6, 0.6, 0.4, 1)
		-- else
		-- 	self.Background:SetColorTexture(0.1, 0.1, 0.1, 1)
		-- 	self.MouseoverOverlay:SetColorTexture(0.4, 0.4, 0.4, 1)
		-- end
	end

	local MinPanelWidth = 380
	local MinPanelHeight = 320
	local MaxPanelWidth = MinPanelWidth * 1.8421
	local MaxPanelHeight = MinPanelHeight * 2
	local DefaultPanelWidth = MinPanelWidth
	local DefaultPanelHeight = MinPanelHeight
	local isGridView = true
	local SearchMaxResults = 200

	---@class ChatEmotesUIMixin : Frame
	---@field public Inset Frame

	---@type ChatEmotesUIMixin
	local UIMixin = {}

	function UIMixin:OnLoad()
		self:SetToplevel(true)
		self:SetMovable(true)
		self:SetResizable(true)
		self:EnableMouse(true)
		self:SetClampedToScreen(true)
		self:SetSize(DefaultPanelWidth, DefaultPanelHeight)
		ButtonFrameTemplate_HidePortrait(self) ---@diagnostic disable-line: undefined-global
		self.Inset:SetPoint("TOPLEFT", 4, -24) -- -60
		self.TitleBar:Init(self) ---@diagnostic disable-line: undefined-field
		self.ResizeButton:Init(self, MinPanelWidth, MinPanelHeight, MaxPanelWidth, MaxPanelHeight) ---@diagnostic disable-line: undefined-field
		self.TitleText:SetText(L.CHAT_EMOTES) ---@diagnostic disable-line: undefined-field
		self.showingArguments = false
		self.filterDataProvider = CreateDataProvider()
		self.logDataProvider = CreateDataProvider()
		self.searchDataProvider = CreateDataProvider()
		self.searchDataProvider:RegisterCallback(DataProviderMixin.Event.OnSizeChanged, self.OnSearchDataProviderChanged, self)
		self:InitializeLog()
		self:HookScript("OnShow", self.OnShow)
		self:HookScript("OnHide", self.OnHide)
		self.ConfigButton:SetScript("OnClick", function()
			PlaySound(SOUNDKIT.IG_CHAT_EMOTE_BUTTON) ---@diagnostic disable-line: undefined-global
			addon:ToggleConfig()
		end)
		self.ConfigButton:SetScript("OnEnter", function()
			GameTooltip:SetOwner(self.ConfigButton, "ANCHOR_RIGHT")
			GameTooltip_SetTitle(GameTooltip, L.OPTIONS) ---@diagnostic disable-line: undefined-global
			GameTooltip:Show()
		end)
		self.ConfigButton:SetScript("OnLeave", function()
			GameTooltip:Hide()
		end)
	end

	function UIMixin:OnShow()
		local position = DB.position
		local width, height = position.width, position.height
		if not width then
			width, height = DefaultPanelWidth, DefaultPanelHeight
		end
		local point, relativeTo, relativePoint, x, y = position.point, position.relativeTo, position.relativePoint, position.x, position.y
		if not point then
			point, relativeTo, relativePoint, x, y = "CENTER", nil, "CENTER", 0, 0
		end
		self:SetSize(width, height)
		self:ClearAllPoints()
		self:SetPoint(point, relativeTo, relativePoint, x, y)
		self.MissingEmotePackage:SetShown(self.logDataProvider:GetSize() == 0)
	end

	function UIMixin:OnHide()
		local point, relativeTo, relativePoint, x, y = self:GetPoint()
		if not point then
			return
		end
		local position = DB.position
		position.width, position.height = self:GetSize()
		position.point, position.relativeTo, position.relativePoint, position.x, position.y = point, relativeTo and relativeTo:GetName() or nil, relativePoint, x, y
	end

	function UIMixin:OnSearchDataProviderChanged(hasSortComparator)
		local size = self.searchDataProvider:GetSize()
		local text = L.SEARCH_RESULTS:format(size)
		self.Log.Bar.Label:SetText(text)
	end

	---@param elementData ChatEmotesLib-1.0_Emote
	---@param search string
	function UIMixin:TryAddToSearch(elementData, search)
		if not search or search:len() == 0 then
			return false
		end
		if search:trim():len() < 2 then ---@diagnostic disable-line: undefined-field
			return false
		end
		local searchLC = search:lower()
		local found
		if elementData.name:lower():find(searchLC) then
			found = true
		elseif elementData.alias then
			for _, alias in ipairs(elementData.alias) do
				if alias:lower():find(searchLC) then
					found = true
					break
				end
			end
		end
		if found then
			---@diagnostic disable-next-line: redundant-parameter
			self.searchDataProvider:Insert(elementData)
			-- self.searchDataProvider:Insert(CopyTable(elementData, true)) -- shallow
			return true
		end
		return false
	end

	function UIMixin:DisplayEvents()
		self.Log.Bar.Label:SetText()
		self.Log.Search:Hide()
		self.Log.Events:Show()
	end

	function UIMixin:DisplaySearch()
		self.Log.Events:Hide()
		self.Log.Search:Show()
	end

	---@param elementData ChatEmotesLib-1.0_Emote
	function UIMixin:RemoveFromDataProvider(dataProvider, elementData)
		local index = dataProvider:GetSize()
		while index >= 1 do
			local _elementData = dataProvider:Find(index) ---@type ChatEmotesLib-1.0_Emote
			if _elementData == elementData then
				dataProvider:RemoveIndex(index)
			end
			index = index - 1
		end
	end

	function UIMixin:InitializeLog()
		self.Log.Bar.Label:SetText()
		self.Log.Bar.SearchBox:HookScript("OnTextChanged", function()
			self.searchDataProvider:Flush()
			local text = self.Log.Bar.SearchBox:GetText()
			local empty = not text or text:len() == 0 or text:trim():len() < 2 -- min length requirement before searching
			if empty then
				self:DisplayEvents()
				return
			end
			self:DisplaySearch()
			local found = 0
			text = text:trim()
			---@param elementData ChatEmotesLib-1.0_Emote
			for index, elementData in self.logDataProvider:Enumerate() do
				if self:TryAddToSearch(elementData, text) then
					found = found + 1
				end
				if found >= SearchMaxResults then
					break
				end
			end
			-- self.Log.Search.ScrollBox:ScrollToElementDataIndex(1)
			local pendingSearch = self.pendingSearch
			if pendingSearch then
				self.pendingSearch = nil
				---@param elementData ChatEmotesLib-1.0_Emote
				local found = self.Log.Search.ScrollBox:ScrollToElementDataByPredicate(
					function(elementData)
						return elementData == pendingSearch
					end,
					ScrollBoxConstants.AlignCenter,
					ScrollBoxConstants.NoScrollInterpolation
				)
				if found then
					local button = self.Log.Search.ScrollBox:FindFrame(found)
					if button then
						button:Flash()
					end
				end
			elseif self.Log.Search.ScrollBox:HasScrollableExtent() then
				-- self.Log.Search.ScrollBox:ScrollToEnd(ScrollBoxConstants.NoScrollInterpolation)
			end
		end)
		local function SetOnDataRangeChanged(scrollBox)
			local function OnDataRangeChanged(sortPending)
				SetScrollBoxButtonAlternateState(scrollBox)
			end
			scrollBox:RegisterCallback(ScrollBoxListMixin.Event.OnDataRangeChanged, OnDataRangeChanged, self)
		end
		if not isGridView then
			SetOnDataRangeChanged(self.Log.Events.ScrollBox)
		end
		---@param elementData ChatEmotesLib-1.0_Emote
		-- local function AddEventToFilter(scrollBox, elementData)
		-- 	local found = self.filterDataProvider:FindElementDataByPredicate(
		-- 		function(filterData)
		-- 			return filterData == elementData
		-- 		end
		-- 	)
		-- 	if found then
		-- 		found.enabled = true
		-- 		local button = scrollBox:FindFrame(elementData)
		-- 		if button then
		-- 			button:UpdateEnabledState()
		-- 		end
		-- 	else
		-- 		self.filterDataProvider:Insert(elementData)
		-- 	end
		-- 	self:RemoveFromDataProvider(self.logDataProvider, elementData)
		-- 	self:RemoveFromDataProvider(self.searchDataProvider, elementData)
		-- end
		do
			---@param elementData ChatEmotesLib-1.0_Emote
			---@param text string
			-- local function LocateInSearch(elementData, text)
			-- 	self.pendingSearch = elementData
			-- 	self.Log.Bar.SearchBox:SetText(text)
			-- end
			local view = CreateScrollBoxListGridView() -- CreateScrollBoxListLinearView()
			view:SetElementExtent(ScrollBoxEmoteButtonSize)
			---@param factory function
			---@param emote ChatEmotesLib-1.0_Emote
			view:SetElementFactory(function(factory, emote)
				local button, isNew = factory("Button") ---@type ChatEmotesUIScrollBoxEmoteButtonMixin
				if isNew then
					Mixin(button, UIScrollBoxEmoteButtonMixin)
					button:OnLoad()
					-- button.HideButton:SetScript("OnMouseDown", function(button, buttonName) AddEventToFilter(self.Filter.ScrollBox, emote) end)
					-- button:SetScript("OnDoubleClick", function(button, buttonName) LocateInSearch(emote, emote.name) end)
				end
				button:Init(emote)
			end)
			local pad = 2
			local spacing = 2
			view:SetPadding(pad, pad, pad, pad, spacing, spacing)
			view:SetHorizontal(false)
			view:SetStride(ScrollBoxEmoteButtonSize)
			view:SetStrideExtent(ScrollBoxEmoteButtonSize)
			ScrollUtil.InitScrollBoxWithScrollBar(self.Log.Events.ScrollBox, self.Log.Events.ScrollBar, view)
			self.Log.Events.ScrollBox:SetDataProvider(self.logDataProvider)
		end
		do
			---@param elementData ChatEmotesLib-1.0_Emote
			-- local function LocateInLog(elementData)
			-- 	self.Log.Bar.SearchBox:SetText()
			-- 	self:DisplayEvents()
			-- 	local found = self.Log.Events.ScrollBox:ScrollToElementDataByPredicate(
			-- 		function(data)
			-- 			return data == elementData
			-- 		end,
			-- 		ScrollBoxConstants.AlignCenter,
			-- 		ScrollBoxConstants.NoScrollInterpolation
			-- 	)
			-- 	local button = found and self.Log.Events.ScrollBox:FindFrame(found)
			-- 	if button then
			-- 		button:Flash()
			-- 	end
			-- end
			local view = CreateScrollBoxListGridView() -- CreateScrollBoxListLinearView()
			view:SetElementExtent(ScrollBoxEmoteButtonSize)
			---@param factory function
			---@param emote ChatEmotesLib-1.0_Emote
			view:SetElementFactory(function(factory, emote)
				local button, isNew = factory("Button") ---@type ChatEmotesUIScrollBoxEmoteButtonMixin
				if isNew then
					Mixin(button, UIScrollBoxEmoteButtonMixin)
					button:OnLoad()
					-- button.HideButton:SetScript("OnMouseDown", function(button, buttonName) LocateInLog(emote) end)
					-- button:SetScript("OnDoubleClick", function(button, buttonName) LocateInLog(emote) end)
				end
				button:Init(emote)
			end)
			local pad = 2
			local spacing = 2
			view:SetPadding(pad, pad, pad, pad, spacing, spacing)
			view:SetHorizontal(false)
			view:SetStride(ScrollBoxEmoteButtonSize)
			view:SetStrideExtent(ScrollBoxEmoteButtonSize)
			ScrollUtil.InitScrollBoxWithScrollBar(self.Log.Search.ScrollBox, self.Log.Search.ScrollBar, view)
			self.Log.Search.ScrollBox:SetDataProvider(self.searchDataProvider)
		end
	end

	---@param emotes ChatEmotesLib-1.0_Emote[]
	function UIMixin:SetEmotes(emotes)
		self.logDataProvider:Flush()
		if not emotes or not emotes[1] then
			return
		end
		self.logDataProvider:InsertTableRange(emotes, 1, emotes[0])
	end

	---@param emote ChatEmotesLib-1.0_Emote
	function UIMixin:ShowEmote(emote)
		self:Show() -- TODO: find emote and scroll to where it is located and highlight the frame
	end

	---@param emote ChatEmotesLib-1.0_Emote
	function UIMixin:UpdateEmoteFrames(emote)
		local scrollBox = self.Log.Events:IsShown() and self.Log.Events.ScrollBox or self.Log.Search.ScrollBox
		scrollBox:ForEachFrame(function(button)
			if not emote or emote == button.emote then
				button:Update()
			end
		end)
	end

	function CreateUI(frameName)
		local frame = CreateFrame("Frame", frameName, UIParent, "ButtonFrameTemplate") ---@type ChatEmotesUIMixin
		Mixin(frame, UIMixin)
		frame.TitleBar = CreateFrame("Frame", nil, frame, "PanelDragBarTemplate")
		frame.TitleBar:SetHeight(32)
		frame.TitleBar:SetPoint("TOPLEFT")
		frame.TitleBar:SetPoint("TOPRIGHT")
		frame.ResizeButton = CreateFrame("Button", nil, frame, "PanelResizeButtonTemplate")
		frame.ResizeButton:SetPoint("BOTTOMRIGHT", -4, 4)
		frame.ConfigButton = CreateFrame("Button", nil, frame)
		frame.ConfigButton:SetSize(16, 16)
		frame.ConfigButton:SetPoint("BOTTOMLEFT", 6, 6)
		frame.ConfigButton.Texture = frame.ConfigButton:CreateTexture(nil, "ARTWORK")
		frame.ConfigButton.Texture:SetAllPoints()
		frame.ConfigButton.Texture:SetTexture(851903)
		frame.StatusText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		frame.StatusText:SetJustifyH("LEFT")
		frame.StatusText:SetHeight(18)
		frame.StatusText:SetPoint("BOTTOMLEFT", frame.ConfigButton, "BOTTOMRIGHT", 2, 0)
		frame.StatusText:SetPoint("BOTTOMRIGHT", frame.ResizeButton, "BOTTOMLEFT", -2, 0)
		frame.Log = CreateFrame("Frame", nil, frame)
		frame.Log:SetPoint("TOPLEFT", frame.TitleBar, "BOTTOMLEFT", 8, 4) -- -32
		frame.Log:SetPoint("BOTTOMRIGHT", -9, 28)
		frame.Log.Bar = CreateFrame("Frame", nil,frame.Log)
		frame.Log.Bar:SetHeight(24)
		frame.Log.Bar:SetPoint("TOPLEFT")
		frame.Log.Bar:SetPoint("TOPRIGHT")
		frame.Log.Bar.Label = frame.Log.Bar:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		frame.Log.Bar.Label:SetJustifyH("RIGHT")
		frame.Log.Bar.Label:SetSize(135, 10)
		frame.Log.Bar.Label:SetPoint("RIGHT", -12*2, 0)
		frame.Log.Bar.SearchBox = CreateFrame("EditBox", nil, frame.Log.Bar, "SearchBoxTemplate")
		frame.Log.Bar.SearchBox:SetAutoFocus(false)
		frame.Log.Bar.SearchBox:SetHistoryLines(1)
		frame.Log.Bar.SearchBox:SetMaxBytes(64)
		frame.Log.Bar.SearchBox:SetSize(180, 22)
		frame.Log.Bar.SearchBox:SetPoint("LEFT", 6, 0)
		frame.Log.Bar.SearchBox:SetPoint("RIGHT", -2, 0)
		frame.Log.Events = CreateFrame("Frame", nil, frame.Log)
		frame.Log.Events:SetPoint("TOPLEFT", frame.Log.Bar, "BOTTOMLEFT", 0, -2)
		frame.Log.Events:SetPoint("BOTTOMRIGHT")
		frame.Log.Events.ScrollBox = CreateFrame("Frame", nil, frame.Log.Events, "WowScrollBoxList") ---@type WowScrollBoxList
		frame.Log.Events.ScrollBox:SetPoint("TOPLEFT")
		frame.Log.Events.ScrollBox:SetPoint("BOTTOMRIGHT", -25, 0)
		frame.Log.Events.ScrollBox.Background = frame.Log.Events.ScrollBox:CreateTexture(nil, "BACKGROUND")
		frame.Log.Events.ScrollBox.Background:SetAllPoints()
		frame.Log.Events.ScrollBox.Background:SetColorTexture(0.03, 0.03, 0.03, 1)
		frame.Log.Events.ScrollBar = CreateFrame("Frame", nil, frame.Log.Events, "WowTrimScrollBar") ---@type ChatEmotesUIScrollCollectionMixin
		frame.Log.Events.ScrollBar:SetPoint("TOPLEFT", frame.Log.Events.ScrollBox, "TOPRIGHT", 0, -3)
		frame.Log.Events.ScrollBar:SetPoint("BOTTOMLEFT", frame.Log.Events.ScrollBox, "BOTTOMRIGHT", 0, 0)
		Mixin(frame.Log.Events.ScrollBar, UIScrollCollectionMixin)
		frame.Log.Events.ScrollBar:OnLoad()
		frame.Log.Search = CreateFrame("Frame", nil, frame.Log)
		frame.Log.Search:SetPoint("TOPLEFT", frame.Log.Bar, "BOTTOMLEFT", 0, -2)
		frame.Log.Search:SetPoint("BOTTOMRIGHT")
		frame.Log.Search.ScrollBox = CreateFrame("Frame", nil, frame.Log.Search, "WowScrollBoxList") ---@type WowScrollBoxList
		frame.Log.Search.ScrollBox:SetPoint("TOPLEFT")
		frame.Log.Search.ScrollBox:SetPoint("BOTTOMRIGHT", -25, 0)
		frame.Log.Search.ScrollBox.Background = frame.Log.Search.ScrollBox:CreateTexture(nil, "BACKGROUND")
		frame.Log.Search.ScrollBox.Background:SetAllPoints()
		frame.Log.Search.ScrollBox.Background:SetColorTexture(0.03, 0.03, 0.03, 1)
		frame.Log.Search.ScrollBar = CreateFrame("Frame", nil, frame.Log.Search, "WowTrimScrollBar") ---@type ChatEmotesUIScrollCollectionMixin
		frame.Log.Search.ScrollBar:SetPoint("TOPLEFT", frame.Log.Search.ScrollBox, "TOPRIGHT", 0, -3)
		frame.Log.Search.ScrollBar:SetPoint("BOTTOMLEFT", frame.Log.Search.ScrollBox, "BOTTOMRIGHT", 0, 0)
		Mixin(frame.Log.Search.ScrollBar, UIScrollCollectionMixin)
		frame.Log.Search.ScrollBar:OnLoad()
		frame.MissingEmotePackage = CreateFrame("Frame", nil, frame)
		frame.MissingEmotePackage:SetFrameStrata("HIGH")
		frame.MissingEmotePackage:SetAllPoints(frame.Log)
		frame.MissingEmotePackage.Background = frame.MissingEmotePackage:CreateTexture(nil, "BACKGROUND")
		frame.MissingEmotePackage.Background:SetAllPoints()
		frame.MissingEmotePackage.Background:SetColorTexture(0, 0, 0)
		frame.MissingEmotePackage.Text = frame.MissingEmotePackage:CreateFontString(nil, "OVERLAY", "GameFontNormalLargeOutline")
		frame.MissingEmotePackage.Text:SetPoint("TOPLEFT", 20, -20)
		frame.MissingEmotePackage.Text:SetPoint("BOTTOMRIGHT", -20, 20)
		frame.MissingEmotePackage.Text:SetJustifyH("CENTER")
		frame.MissingEmotePackage.Text:SetJustifyV("MIDDLE")
		frame.MissingEmotePackage.Text:SetText(L.MISSING_EMOTE_PACK)
		frame:OnLoad()
		frame:Hide()
		return frame
	end

	---@class ChatEmotesUIButton : Button

	function CreateButton(frameName)
		local button = CreateFrame("Button", frameName, UIParent) ---@type ChatEmotesUIButton
		button:SetFrameStrata("LOW")
		button:SetSize(32, 32)
		---@diagnostic disable-next-line: undefined-global
		button:SetPoint("TOP", ChatFrameMenuButton, "BOTTOM", 0, 0) -- ChatFrame1ButtonFrame
		button.Text = button:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		button.Text:SetJustifyH("CENTER")
		button.Text:SetJustifyV("MIDDLE")
		button.Text:SetAllPoints()
		button:SetNormalTexture(format("Interface\\AddOns\\%s\\textures\\chat-button-up", addonName))
		button:SetPushedTexture(format("Interface\\AddOns\\%s\\textures\\chat-button-down", addonName))
		button:SetDisabledTexture(format("Interface\\AddOns\\%s\\textures\\chat-button-disabled", addonName))
		button:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
		function button:UpdateTexture()
			local emotes = CEL.GetEmotes()
			local text
			if not emotes or not emotes[1] then
				text = NO_EMOTE_MARKUP_FALLBACK
			else
				local emote = GetRandomEmote()
				text = emote.markup
			end
			button.Text:SetText(text)
		end
		button:SetScript("OnClick", function()
			PlaySound(SOUNDKIT.IG_CHAT_EMOTE_BUTTON) ---@diagnostic disable-line: undefined-global
			addon:TogglePicker()
			button:UpdateTexture()
		end)
		button:SetScript("OnEnable", function() button.Text:Show() end)
		button:SetScript("OnDisable", function() button.Text:Hide() end)
		button:SetScript("OnEnter", function()
			GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
			GameTooltip_SetTitle(GameTooltip, L.CHAT_EMOTES) ---@diagnostic disable-line: undefined-global
			GameTooltip:Show()
		end)
		button:SetScript("OnLeave", function()
			GameTooltip:Hide()
		end)
		button:UpdateTexture()
		C_Timer.After(1, button.UpdateTexture)
		return button
	end

	---@class ChatEmotesUIConfigMixin : Frame
	---@field public Inset Frame

	---@type ChatEmotesUIConfigMixin
	local UIConfigMixin = {}

	function UIConfigMixin:OnLoad()
		self:SetToplevel(true)
		self:SetMovable(true)
		self:EnableMouse(true)
		self:SetClampedToScreen(true)
		self:SetSize(DefaultPanelWidth, DefaultPanelHeight)
		self:SetPoint("CENTER")
		ButtonFrameTemplate_HidePortrait(self) ---@diagnostic disable-line: undefined-global
		self.Inset:SetPoint("TOPLEFT", 4, -24) -- -60
		self.TitleBar:Init(self) ---@diagnostic disable-line: undefined-field
		self.TitleText:SetText(L.CHAT_EMOTES_OPTIONS) ---@diagnostic disable-line: undefined-field
		self:UpdateScrollFrame()
	end

	function UIConfigMixin:UpdateScrollFrame()
		local totalHeight = 0
		for _, widget in ipairs(self.Options) do
			totalHeight = totalHeight + widget:GetHeight()
		end
		local numToDisplay = 8
		local fakeItemHeight = 32
		local numItems = floor(totalHeight / fakeItemHeight + 0.5)
		local scrollFrame = self.ScrollFrame
		FauxScrollFrame_Update(scrollFrame, numItems, numToDisplay, fakeItemHeight, nil, nil, nil, nil, nil, nil, true) ---@diagnostic disable-line: undefined-global
		if numItems > numToDisplay then
			scrollFrame.ScrollBarTop:Show()
			scrollFrame.ScrollBarBottom:Show()
			scrollFrame.ScrollBarMiddle:Show()
			scrollFrame.ScrollBar:Show()
		else
			scrollFrame.ScrollBarTop:Hide()
			scrollFrame.ScrollBarBottom:Hide()
			scrollFrame.ScrollBarMiddle:Hide()
			scrollFrame.ScrollBar:Hide()
			scrollFrame.ScrollBar:SetValue(0)
		end
	end

	local InputFactory = {}

	do

		local function EditBox_OnEditFocusLost(self)
			local cvar = self.cvar
			if cvar.type ~= "number" then
				return
			end
			local key = cvar.key
			local options = DB.options
			local value = self.value
			if not value or value < 1 then
				local ovalue = defaults.options[key]
				value = floor(ovalue * 100 + 0.5)
			elseif value > 999 then
				value = 999
			end
			if cvar.percentile then
				options[key] = value / 100
			else
				options[key] = value
			end
			self:SetNumber(value)
		end

		local function EditBox_OnEnterPressed(self)
			local cvar = self.cvar
			if cvar.type == "number" then
				self.value = self:GetNumber()
			else
				self.value = self:GetText()
			end
			self:ClearFocus()
		end

		local function EditBox_OnTextChanged(self)
			if not self.Update then
				return
			end
			self:Update()
		end

		local function EditBox_OnShow(self)
			local cvar = self.cvar
			local options = DB.options
			if cvar.type == "number" then
				if cvar.percentile then
					self.value = floor(options[cvar.key] * 100 + 0.5)
				else
					self.value = options[cvar.key]
				end
				self:SetNumber(self.value)
			else
				self.value = options[cvar.key]
				self:SetText(self.value)
			end
		end

		local function EditBox_OnArrowPressed(self)
			if not self.Update then
				return
			end
			self:Update(true)
		end

		local function CheckButton_OnShow(self)
			self:SetChecked(DB.options[self.cvar.key])
		end

		local function CheckButton_OnClick(self, button, down)
			DB.options[self.cvar.key] = not not self:GetChecked()
		end

		function InputFactory:FinalizeOption(frame, widget, offsetX, offsetY)
			if widget.finalized then
				return widget
			end
			widget.finalized = true
			if widget.cvar then
				local widgetType = widget:GetObjectType()
				if widgetType == "EditBox" then
					widget:HookScript("OnEditFocusLost", EditBox_OnEditFocusLost)
					widget:SetScript("OnEnterPressed", EditBox_OnEnterPressed) -- override default
					widget:HookScript("OnTextChanged", EditBox_OnTextChanged)
					widget:HookScript("OnShow", EditBox_OnShow)
					widget:HookScript("OnArrowPressed", EditBox_OnArrowPressed)
				elseif widgetType == "CheckButton" then
					widget:HookScript("OnShow", CheckButton_OnShow)
					widget:HookScript("OnClick", CheckButton_OnClick)
				end
			end
			local index = #frame.Options
			local prevOption = frame.Options[index]
			if prevOption then
				widget:SetPoint("TOPLEFT", prevOption, "BOTTOMLEFT", offsetX or 0, offsetY or 0)
			else
				widget:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, 0)
			end
			frame.Options[index + 1] = widget
			return widget
		end

	end

	local function CreateLabel(frame, widget, label, offsetX, offsetY)
		widget.Label = widget:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
		widget.Label:SetPoint("LEFT", widget, "RIGHT", 4 + (offsetX or 0), offsetY or 0)
		widget.Label:SetPoint("RIGHT", frame, "RIGHT", -16, 0)
		widget.Label:SetJustifyH("LEFT")
		widget.Label:SetJustifyV("TOP")
		widget.Label:SetText(label)
	end

	function InputFactory:CreateEditBox(frame, cvar, label)
		local editBox = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
		editBox.cvar = cvar
		editBox:SetSize(48, 32)
		editBox:SetAutoFocus(false)
		editBox.Label = CreateLabel(frame, editBox, label)
		editBox:SetScript("OnTabPressed", EditBox_OnTabPressed) ---@diagnostic disable-line: undefined-global
		editBox:SetScript("OnEscapePressed", EditBox_ClearFocus) ---@diagnostic disable-line: undefined-global
		editBox:SetScript("OnEditFocusLost", EditBox_ClearHighlight) ---@diagnostic disable-line: undefined-global
		editBox:SetScript("OnEditFocusGained", EditBox_HighlightText) ---@diagnostic disable-line: undefined-global
		editBox:SetScript("OnEnterPressed", EditBox_ClearFocus) ---@diagnostic disable-line: undefined-global
		return InputFactory:FinalizeOption(frame, editBox)
	end

	function InputFactory:CreateEditBoxNumeric(frame, cvar, label)
		local editBox = self:CreateEditBox(frame, cvar, label)
		editBox:SetNumeric(true)
		editBox:SetNumber(100)
		editBox:SetMaxLetters(3)
		return InputFactory:FinalizeOption(frame, editBox)
	end

	function InputFactory:CreateFontString(frame)
		local fontString = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
		fontString:SetNonSpaceWrap(false)
		fontString:SetWordWrap(false) ---@diagnostic disable-line: redundant-parameter
		fontString:SetSize(0, 20)
		fontString:SetJustifyH("LEFT")
		fontString:SetJustifyV("TOP")
		return InputFactory:FinalizeOption(frame, fontString)
	end

	---@class UICheckButtonTemplate : CheckButton
	---@field public text FontString

	function InputFactory:CreateCheckBox(frame, cvar, label)
		local checkBox = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate") ---@type UICheckButtonTemplate
		checkBox.cvar = cvar
		checkBox:SetSize(32, 32)
		checkBox.Label = CreateLabel(frame, checkBox, label, -5, 0)
		return InputFactory:FinalizeOption(frame, checkBox, -10, 0)
	end

	function CreateConfig(frameName)
		local frame = CreateFrame("Frame", frameName, UIParent, "ButtonFrameTemplate") ---@type ChatEmotesUIConfigMixin
		Mixin(frame, UIConfigMixin)
		frame.TitleBar = CreateFrame("Frame", nil, frame, "PanelDragBarTemplate")
		frame.TitleBar:SetHeight(32)
		frame.TitleBar:SetPoint("TOPLEFT")
		frame.TitleBar:SetPoint("TOPRIGHT")
		do -- frame.Options
			frame.Options = {}
			frame.ScrollFrame = CreateFrame("ScrollFrame", "$parentScrollFrame", frame, "ListScrollFrameTemplate")
			frame.ScrollFrame.ScrollBarMiddle = _G[format("%s%s", frame.ScrollFrame:GetName(), "Middle")] ---@type Texture
			frame.ScrollFrame.ScrollChildFrame.Options = frame.Options -- alias
			frame.ScrollFrame.ScrollBar.scrollStep = 32
			frame.ScrollFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", 9, -29)
			frame.ScrollFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -34, 29)
			do -- emoteScale

				local emoteScale = InputFactory:CreateEditBoxNumeric(frame.ScrollFrame.ScrollChildFrame, { type = "number", key = "emoteScale", percentile = true }, L.EMOTE_SCALE)
				emoteScale.Preview = InputFactory:CreateFontString(frame.ScrollFrame.ScrollChildFrame)

				function emoteScale:RandomEmote()
					local emote = GetRandomEmote()
					self.emote = emote
					return emote
				end

				function emoteScale:UpdateEmote()
					local emote = self.emote
					local scale = self:GetNumber() / 100
					local height = GetHeightForChatFrame(DEFAULT_CHAT_FRAME, scale, 3) ---@diagnostic disable-line: undefined-global
					local text
					if emote then
						text = CEL.SafeReplace(emote.name, emote.name, emote, height, false)
					else
						text = NO_EMOTE_MARKUP_FALLBACK
					end
					self.Preview:SetText(text)
					local size = self.Preview:GetUnboundedStringWidth()
					self.Preview:SetSize(size, size * (emote and emote.ratio or 1))
					addonConfigFrame:UpdateScrollFrame()
				end

				---@param newEmote boolean
				function emoteScale:Update(newEmote)
					if newEmote or not self.emote then
						self:RandomEmote()
					end
					self:UpdateEmote()
				end

			end
			InputFactory:CreateCheckBox(frame.ScrollFrame.ScrollChildFrame, { key = "emoteHover" }, L.EMOTE_HOVER)
		end
		frame:OnLoad()
		frame:Hide()
		return frame
	end

end

local function CreateSlashCommand()
	local function CommandHandler(text, editBox)
		if text and (text:find("[Cc][Oo][Nn][Ff][Ii][Gg]") or text:find("[Oo][Pp][Tt][Ii][Oo][Nn][Ss]?")) then
			addon:ToggleConfig()
		else
			addon:TogglePicker()
		end
	end
	---@diagnostic disable-next-line: undefined-field
	_G.SlashCmdList[addonName] = CommandHandler
	_G[format("SLASH_%s1", addonName)] = "/vladschatemotes"
	_G[format("SLASH_%s2", addonName)] = "/vce"
	_G[format("SLASH_%s3", addonName)] = "/chatemotes"
	_G[format("SLASH_%s4", addonName)] = "/ce"
	return CommandHandler
end

local function UpdateChannels()
	wipe(activeChannels)
	for i = 1, NUM_CHAT_WINDOWS do ---@diagnostic disable-line: undefined-global
		local channels = { GetChatWindowChannels(i) }
		for j = 1, #channels, 2 do
			local channel, id = channels[j], channels[j + 1]
			activeChannels[channel] = id
			activeChannels[id] = channel
		end
	end
end

local function UpdateChannelsReduntant()
	UpdateChannels()
	C_Timer.After(3, UpdateChannels)
end

local function InitDB()
	ChatEmotesDB = type(ChatEmotesDB) == "table" and ChatEmotesDB or {}
	DB = setmetatable(ChatEmotesDB, { __index = defaults })
	for k, v in pairs(defaults) do
		if type(v) == "table" then
			local t = rawget(DB, k)
			if type(t) ~= "table" then
				t = {}
				DB[k] = t
			end
			setmetatable(t, { __index = v })
		end
	end
end

local function Init()
	UpdateChannelsReduntant()
	for _, event in ipairs(supportedChatEvents) do
		ChatFrame_AddMessageEventFilter(event, ChatMessageFilter) ---@diagnostic disable-line: undefined-global
	end
	for i = 1, NUM_CHAT_WINDOWS do ---@diagnostic disable-line: undefined-global
		local chatFrame = _G["ChatFrame" .. i] ---@type ChatFrame
		if chatFrame then
			local editBox = chatFrame.editBox
			editBox:HookScript("OnTextChanged", ChatEditBoxOnTextChanged)
			chatFrame:HookScript("OnHyperlinkClick", ChatFrameOnHyperlinkClick)
			chatFrame:HookScript("OnHyperlinkEnter", ChatFrameOnHyperlinkEnter)
			chatFrame:HookScript("OnHyperlinkLeave", ChatFrameOnHyperlinkLeave)
		end
	end
	hooksecurefunc("AutoCompleteEditBox_SetAutoCompleteSource", AutoCompleteEditBox_SetAutoCompleteSource)
	hooksecurefunc("AutoCompleteEditBox_SetCustomAutoCompleteFunction", AutoCompleteEditBox_SetCustomAutoCompleteFunction)
	hooksecurefunc("AutoComplete_UpdateResults", AutoComplete_UpdateResults)
	CreateSlashCommand()
	addonButton = CreateButton("VladsChatEmotesButton")
end

addon:SetScript("OnEvent", function(self, event, ...) self[event](self, event, ...) end)
addon:RegisterEvent("ADDON_LOADED")

local function InitChannelMonitor()
	hooksecurefunc("AddChatWindowChannel", UpdateChannelsReduntant)
	hooksecurefunc("RemoveChatWindowChannel", UpdateChannelsReduntant)
	addon.CHANNEL_UI_UPDATE = UpdateChannels
	addon.CHANNEL_FLAGS_UPDATED = UpdateChannels
	addon.CHANNEL_LEFT = UpdateChannels
	addon.CHAT_MSG_CHANNEL_JOIN = UpdateChannels
	addon.CHAT_MSG_CHANNEL_LEAVE = UpdateChannels
	addon.CHAT_MSG_CHANNEL_LIST = UpdateChannels
	addon.CHAT_MSG_CHANNEL_NOTICE = UpdateChannels
	addon:RegisterEvent("CHANNEL_UI_UPDATE")
	addon:RegisterEvent("CHANNEL_FLAGS_UPDATED")
	addon:RegisterEvent("CHANNEL_LEFT")
	addon:RegisterEvent("CHAT_MSG_CHANNEL_JOIN")
	addon:RegisterEvent("CHAT_MSG_CHANNEL_LEAVE")
	addon:RegisterEvent("CHAT_MSG_CHANNEL_LIST")
	addon:RegisterEvent("CHAT_MSG_CHANNEL_NOTICE")
end

function addon:ADDON_LOADED(event, name)
	if name ~= addonName then
		return
	end
	addon:UnregisterEvent(event)
	InitDB()
	Init()
	InitChannelMonitor()
end

function addon:TogglePicker(showEmote)
	if not addonFrame then
		addonFrame = CreateUI("VladsChatEmotesFrame")
		table.insert(UISpecialFrames, addonFrame:GetName()) ---@diagnostic disable-line: undefined-global
		addonFrame:SetEmotes(CEL.GetEmotes())
	end
	if showEmote then
		addonFrame:ShowEmote(showEmote)
	else
		addonFrame:SetShown(not addonFrame:IsShown())
	end
end

function addon:ToggleConfig()
	if not addonConfigFrame then
		addonConfigFrame = CreateConfig("VladsChatEmotesConfigFrame")
		table.insert(UISpecialFrames, addonConfigFrame:GetName()) ---@diagnostic disable-line: undefined-global
	end
	addonConfigFrame:SetShown(not addonConfigFrame:IsShown())
end
