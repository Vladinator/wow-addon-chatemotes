local CEL = LibStub and LibStub("ChatEmotesLib-1.0", true) ---@type ChatEmotesLib-1.0
if not CEL then return end

local _G = _G
local strlenutf8 = _G.strlenutf8

local addonName, ns = ...
local addon = CreateFrame("Frame")
local addonFrame ---@type VladsChatEmotesUIMixin
local addonButton ---@type VladsChatEmotesUIButton
local PanelTitle = "Chat Emotes"

local defaults = { point = "LEFT", relativePoint = "LEFT", x = 15, y = -175, width = 335, height = 345 }
ChatEmotesDB = setmetatable({}, { __index = defaults })
local DB = ChatEmotesDB

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

---@class ChatFrame : Frame
---@field public editBox EditBox

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

---@param self EditBox
---@param event string
---@param text string
local function ChatMessageFilter(self, event, text, playerName, languageName, channelName, playerName2, specialFlags, zoneChannelID, channelIndex, channelBaseName, ...)
	local isIgnored = zoneChannelID and zoneChannelID ~= 0 and ignoreChannels[zoneChannelID]
	if isIgnored then
		return
	end
	local isActive = not zoneChannelID or zoneChannelID == 0 or activeChannels[zoneChannelID]
	if not isActive then
		return
	end
	local _, height = self:GetFont()
	local newText = CEL.ReplaceEmotesInText(text, height)
	if newText then
		return false, newText, playerName, languageName, channelName, playerName2, specialFlags, zoneChannelID, channelIndex, channelBaseName, ...
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
				twitchemote = emote,
				twitchemotefrom = sfrom,
				twitchemoteto = sto,
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

---@param self EditBox
---@param newText string
---@param result table
---@param name string
local function AutoCompleteAccept(self, newText, result, name)
	local emote = result.twitchemote ---@type ChatEmotesLib-1.0_Emote
	if not emote then
		return true
	end
	local text = self:GetText()
	local prefix = text:sub(1, result.twitchemotefrom - 1)
	local suffix = text:sub(result.twitchemoteto + 1)
	local updatedText = format("%s%s%s", prefix, emote.name, suffix)
	self:SetText(updatedText)
	self:SetCursorPosition(strlenutf8(updatedText) - strlenutf8(suffix))
	return true
end

local origAutoCompletFuncs = {}

---@param self EditBox
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

local function CacheOrigAutoCompletFuncsRestore(self)
	local cache = CacheOrigAutoCompletFuncs(self)
	self.autoCompleteSource = cache.autoCompleteSource
	self.customAutoCompleteFunction = cache.customAutoCompleteFunction
end

---@param self EditBox
local function AutoCompleteEditBox_SetAutoCompleteSource(self, source)
	CacheOrigAutoCompletFuncs(self)
end

---@param self EditBox
local function AutoCompleteEditBox_SetCustomAutoCompleteFunction(self)
	CacheOrigAutoCompletFuncs(self)
end

---@param autoCompleteBox Frame
---@param results table
---@param context? string
local function AutoComplete_UpdateResults(autoCompleteBox, results, context)
	local self = autoCompleteBox.parent ---@diagnostic disable-line
	local first = results[1]
	if not first or not first.twitchemote then
		CacheOrigAutoCompletFuncsRestore(self)
		return
	end
	local totalReturns = #results
	local numReturns = min(totalReturns, AUTOCOMPLETE_MAX_BUTTONS) ---@diagnostic disable-line: undefined-global
	for i = 1, numReturns do
		local button = _G["AutoCompleteButton" .. i] ---@type Button
		if button:IsEnabled() then
			local result = button.nameInfo ---@diagnostic disable-line
			local emote = result.twitchemote ---@type ChatEmotesLib-1.0_Emote
			if emote then
				button:SetText(format("%s %s", emote.markup, emote.name))
			end
		end
	end
end

---@param self EditBox
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
		_G.AutoCompleteEditBox_SetAutoCompleteSource(self, AutoCompleteSource, "twitchemote") ---@diagnostic disable-line
		_G.AutoCompleteEditBox_SetCustomAutoCompleteFunction(self, AutoCompleteAccept) ---@diagnostic disable-line
		_G.AutoComplete_Update(self, text, self:GetUTF8CursorPosition()) ---@diagnostic disable-line
	end
end

---@param self ChatFrame
---@param link string
---@param text string
---@param button string
local function ChatFrameOnHyperlinkClick(self, link, text, button)
	local emote = CEL.GetEmoteFromLink(link)
	if not emote then
		return
	end
	if button == "RightButton" then
		addon:ToggleFrame(emote)
	else
		if ChatEdit_GetActiveWindow() then
			ChatEdit_InsertLink(emote.name)
		else
			ChatFrame_OpenChat(emote.name)
		end
	end
end

---@param self ChatFrame
---@param link string
---@param text string
local function ChatFrameOnHyperlinkEnter(self, link, text)
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
	GameTooltip:Hide()
end

local function CreateUI(frameName) end ---@return VladsChatEmotesUIMixin
local function CreateButton(frameName) end ---@return VladsChatEmotesUIButton

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

	---@class VladsChatEmotesUIScrollCollectionMixin : CallbackRegistryMixin

	local function SetScrollBoxButtonAlternateState(scrollBox)
		local index = scrollBox:GetDataIndexBegin()
		scrollBox:ForEachFrame(function(button)
			button:SetAlternateOverlayShown(index % 2 == 1)
			index = index + 1
		end)
	end

	---@type VladsChatEmotesUIScrollCollectionMixin
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

	---@class VladsChatEmotesUIEmoteButtonMixin : Button

	---@type VladsChatEmotesUIEmoteButtonMixin
	local UIEmoteButtonMixin = {}

	local ButtonSize = 30

	function UIEmoteButtonMixin:OnLoad()
		-- self:SetHeight(ButtonSize)
		self:SetSize(ButtonSize, ButtonSize) -- grid
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
		self.Label = self:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		self.Label:SetJustifyH("CENTER")
		self.Label:SetJustifyV("MIDDLE")
		self.Label:SetAllPoints()
		self.Label:SetScale(2)
		self.Background = self:CreateTexture(nil, "BACKGROUND", nil, 1)
		self.Background:SetAllPoints()
		self.Background:SetColorTexture(0.1, 0.1, 0.1, 1)
		self.MouseoverOverlay = self:CreateTexture(nil, "OVERLAY")
		self.MouseoverOverlay:SetAllPoints()
		self.MouseoverOverlay:SetColorTexture(0.5, 0.5, 0.5, 1)
		self.MouseoverOverlay:Hide()
		self.Alternate = self:CreateTexture(nil, "BACKGROUND", nil, 2)
		self.Alternate:SetAllPoints()
		self.Alternate:SetColorTexture(0.2, 0.2, 0.2, 1)
		self.Alternate:Hide()
		self:SetScript("OnEnter", self.OnEnter)
		self:SetScript("OnLeave", self.OnLeave)
		self:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		self:SetScript("OnClick", self.OnClick)
	end

	---@param emote ChatEmotesLib-1.0_Emote
	function UIEmoteButtonMixin:Init(emote)
		-- self.LeftLabel:SetText(emote.name)
		-- self.RightLabel:SetText(emote.markup)
		self.emote = emote
		self.Label:SetText(emote.markup)
	end

	function UIEmoteButtonMixin:OnEnter()
		self.MouseoverOverlay:Show()
		local emote = self.emote
		GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT", 0, 0)
		GameTooltip:AddLine(tostring(emote.name), 1, 1, 1)
		-- GameTooltip:AddLine(emote.markup:gsub(":0:0", format(":%d:%d", 32, 32 * (emote.ratio or 1)), 1), 1, 1, 1)
		GameTooltip:AddLine(tostring(emote.package), 0.5, 0.5, 0.5)
		GameTooltip:AddLine(tostring(emote.folder), 0.5, 0.5, 0.5)
		GameTooltip:Show()
	end

	function UIEmoteButtonMixin:OnLeave()
		self.MouseoverOverlay:Hide()
		GameTooltip:Hide()
	end

	function UIEmoteButtonMixin:OnClick(button)
		local emote = self.emote
		if button == "LeftButton" then
			if ChatEdit_GetActiveWindow() then
				ChatEdit_InsertLink(emote.name)
			else
				ChatFrame_OpenChat(emote.name)
			end
		elseif button == "RightButton" then
			-- TODO: favorites
		end
	end

	function UIEmoteButtonMixin:SetAlternateOverlayShown(alternate)
		self.Alternate:SetShown(alternate)
	end

	local SearchDataProviderResultsFormat = "Results: %d"
	local SearchMaxResults = 200
	local LoadingEmotesNothing = "You have no emotes installed."

	local MinPanelWidth = 380
	local MinPanelHeight = 320
	local MaxPanelWidth = MinPanelWidth * 1.8421
	local MaxPanelHeight = MinPanelHeight * 2
	local DefaultPanelWidth = MinPanelWidth
	local DefaultPanelHeight = MinPanelHeight
	local isGridView = true

	---@class VladsChatEmotesUIButton : Button

	---@class VladsChatEmotesUIMixin : Frame
	---@field public Inset Frame

	---@type VladsChatEmotesUIMixin
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
		self.TitleText:SetText(PanelTitle) ---@diagnostic disable-line: undefined-field
		self.showingArguments = false
		self.filterDataProvider = CreateDataProvider()
		self.logDataProvider = CreateDataProvider()
		self.searchDataProvider = CreateDataProvider()
		self.searchDataProvider:RegisterCallback(DataProviderMixin.Event.OnSizeChanged, self.OnSearchDataProviderChanged, self)
		self:InitializeLog()
		self:HookScript("OnShow", self.OnShow)
		self:HookScript("OnHide", self.OnHide)
	end

	function UIMixin:OnShow()
		local width, height = DB.width, DB.height
		if not width then
			width, height = DefaultPanelWidth, DefaultPanelHeight
		end
		local point, relativeTo, relativePoint, x, y = DB.point, DB.relativeTo, DB.relativePoint, DB.x, DB.y
		if not point then
			point, relativeTo, relativePoint, x, y = "CENTER", nil, "CENTER", 0, 0
		end
		self:SetSize(width, height)
		self:ClearAllPoints()
		self:SetPoint(point, relativeTo, relativePoint, x, y)
	end

	function UIMixin:OnHide()
		local point, relativeTo, relativePoint, x, y = self:GetPoint()
		if not point then
			return
		end
		DB.width, DB.height = self:GetSize()
		DB.point, DB.relativeTo, DB.relativePoint, DB.x, DB.y = point, relativeTo and relativeTo:GetName() or nil, relativePoint, x, y
	end

	function UIMixin:OnSearchDataProviderChanged(hasSortComparator)
		local size = self.searchDataProvider:GetSize()
		local text = SearchDataProviderResultsFormat:format(size)
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
		local function AddEventToFilter(scrollBox, elementData)
			local found = self.filterDataProvider:FindElementDataByPredicate(
				function(filterData)
					return filterData == elementData
				end
			)
			if found then
				found.enabled = true
				local button = scrollBox:FindFrame(elementData)
				if button then
					button:UpdateEnabledState()
				end
			else
				self.filterDataProvider:Insert(elementData)
			end
			self:RemoveFromDataProvider(self.logDataProvider, elementData)
			self:RemoveFromDataProvider(self.searchDataProvider, elementData)
		end
		do
			---@param elementData ChatEmotesLib-1.0_Emote
			---@param text string
			local function LocateInSearch(elementData, text)
				self.pendingSearch = elementData
				self.Log.Bar.SearchBox:SetText(text)
			end
			local view = CreateScrollBoxListGridView() -- CreateScrollBoxListLinearView()
			view:SetElementExtent(ButtonSize)
			---@param factory function
			---@param emote ChatEmotesLib-1.0_Emote
			view:SetElementFactory(function(factory, emote)
				local button, isNew = factory("Button") ---@type VladsChatEmotesUIEmoteButtonMixin
				if isNew then
					Mixin(button, UIEmoteButtonMixin)
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
			view:SetStride(ButtonSize)
			view:SetStrideExtent(ButtonSize)
			ScrollUtil.InitScrollBoxWithScrollBar(self.Log.Events.ScrollBox, self.Log.Events.ScrollBar, view)
			self.Log.Events.ScrollBox:SetDataProvider(self.logDataProvider)
		end
		do
			---@param elementData ChatEmotesLib-1.0_Emote
			local function LocateInLog(elementData)
				self.Log.Bar.SearchBox:SetText()
				self:DisplayEvents()
				local found = self.Log.Events.ScrollBox:ScrollToElementDataByPredicate(
					function(data)
						return data == elementData
					end,
					ScrollBoxConstants.AlignCenter,
					ScrollBoxConstants.NoScrollInterpolation
				)
				local button = found and self.Log.Events.ScrollBox:FindFrame(found)
				if button then
					button:Flash()
				end
			end
			local view = CreateScrollBoxListGridView() -- CreateScrollBoxListLinearView()
			view:SetElementExtent(ButtonSize)
			---@param factory function
			---@param emote ChatEmotesLib-1.0_Emote
			view:SetElementFactory(function(factory, emote)
				local button, isNew = factory("Button") ---@type VladsChatEmotesUIEmoteButtonMixin
				if isNew then
					Mixin(button, UIEmoteButtonMixin)
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
			view:SetStride(ButtonSize)
			view:SetStrideExtent(ButtonSize)
			ScrollUtil.InitScrollBoxWithScrollBar(self.Log.Search.ScrollBox, self.Log.Search.ScrollBar, view)
			self.Log.Search.ScrollBox:SetDataProvider(self.searchDataProvider)
		end
	end

	---@param emotes ChatEmotesLib-1.0_Emote[]
	---@param loadMax? number
	function UIMixin:SetEmotes(emotes, loadMax)
		self.logDataProvider:Flush()
		if not emotes then
			self.StatusText:SetText(LoadingEmotesNothing)
			return
		end
		self.logDataProvider:InsertTableRange(emotes, 1, emotes[0])
	end

	---@param emote ChatEmotesLib-1.0_Emote
	function UIMixin:ShowEmote(emote)
		self:Show() -- TODO: find emote and scroll to where it is located and highlight the frame
	end

	function CreateUI(frameName)
		local frame = CreateFrame("Frame", frameName, UIParent, "ButtonFrameTemplate") ---@type VladsChatEmotesUIMixin
		Mixin(frame, UIMixin)
		frame.TitleBar = CreateFrame("Frame", nil, frame, "PanelDragBarTemplate")
		frame.TitleBar:SetHeight(32)
		frame.TitleBar:SetPoint("TOPLEFT")
		frame.TitleBar:SetPoint("TOPRIGHT")
		frame.ResizeButton = CreateFrame("Button", nil, frame, "PanelResizeButtonTemplate")
		frame.ResizeButton:SetPoint("BOTTOMRIGHT", -4, 4)
		frame.StatusText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
		frame.StatusText:SetJustifyH("LEFT")
		frame.StatusText:SetHeight(30)
		frame.StatusText:SetPoint("BOTTOMLEFT", 10, 0)
		frame.StatusText:SetPoint("BOTTOMRIGHT", frame.ResizeButton, "BOTTOMLEFT", 0, 0)
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
		frame.Log.Events.ScrollBar = CreateFrame("Frame", nil, frame.Log.Events, "WowTrimScrollBar") ---@type VladsChatEmotesUIScrollCollectionMixin
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
		frame.Log.Search.ScrollBar = CreateFrame("Frame", nil, frame.Log.Search, "WowTrimScrollBar") ---@type VladsChatEmotesUIScrollCollectionMixin
		frame.Log.Search.ScrollBar:SetPoint("TOPLEFT", frame.Log.Search.ScrollBox, "TOPRIGHT", 0, -3)
		frame.Log.Search.ScrollBar:SetPoint("BOTTOMLEFT", frame.Log.Search.ScrollBox, "BOTTOMRIGHT", 0, 0)
		Mixin(frame.Log.Search.ScrollBar, UIScrollCollectionMixin)
		frame.Log.Search.ScrollBar:OnLoad()
		frame:OnLoad()
		frame:Hide()
		return frame
	end

	function CreateButton(frameName)
		local button = CreateFrame("Button", frameName, UIParent) ---@type VladsChatEmotesUIButton
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
				text = "|T134400:0:0|t"
			else
				local index = random(1, min(100, emotes[0]))
				local emote = emotes[index]
				text = emote.markup
			end
			button.Text:SetText(text)
		end
		button:SetScript("OnClick", function()
			PlaySound(SOUNDKIT.IG_CHAT_EMOTE_BUTTON) ---@diagnostic disable-line: undefined-global
			addon:ToggleFrame()
			button:UpdateTexture()
		end)
		button:SetScript("OnEnable", function() button.Text:Show() end)
		button:SetScript("OnDisable", function() button.Text:Hide() end)
		button:SetScript("OnEnter", function()
			GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
			GameTooltip_SetTitle(GameTooltip, PanelTitle) ---@diagnostic disable-line: undefined-global
			GameTooltip:Show()
		end)
		button:SetScript("OnLeave", function()
			GameTooltip:Hide()
		end)
		button:UpdateTexture()
		return button
	end

end

local function CreateSlashCommand()
	local function CommandHandler(text, editBox)
		addon:ToggleFrame()
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

local function Init()
	ChatEmotesDB = type(ChatEmotesDB) == "table" and ChatEmotesDB or {}
	DB = setmetatable(ChatEmotesDB, { __index = defaults })
	UpdateChannelsReduntant()
	for _, event in ipairs(supportedChatEvents) do
		ChatFrame_AddMessageEventFilter(event, ChatMessageFilter) ---@diagnostic disable-line: undefined-global
	end
	for i = 1, NUM_CHAT_WINDOWS do ---@diagnostic disable-line: undefined-global
		local chatFrame = _G["ChatFrame" .. i] ---@type ChatFrame
		if chatFrame then
			-----@diagnostic disable-next-line: undefined-field
			local editBox = chatFrame.editBox ---@type EditBox
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
	C_Timer.After(1, addonButton.UpdateTexture)
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
	Init()
	InitChannelMonitor()
end

function addon:ToggleFrame(showEmote)
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
