assert(type(LibStub) == "table", "ChatEmotesLib-1.0 requires LibStub")

local UTF8 = LibStub("ChatEmotesLibUTF8-1.0", true) ---@type UTF8

---@class ChatEmotesLib-1.0_PackageStruct @The raw data provided from external sources to register their emotes with the library.
---@field public name string
---@field public path string
---@field public emotes table<string, table<number, string>>

---@class ChatEmotesLib-1.0 @v1.0 of the library structure.

---@class ChatEmotesLib-1.0_Emote @v1.0 of the emote structure.
---@field public package string
---@field public folder string
---@field public name string
---@field public pattern string
---@field public file string
---@field public markup string
---@field public alias? string[]
---@field public ratio? number
---@field public ignoreSuggestion boolean
---@field public args any
---@field public fileWidth? number
---@field public fileHeight? number
---@field public offset? number[]
---@field public offsetL? number
---@field public offsetR? number
---@field public offsetT? number
---@field public offsetB? number
---@field public unicode? string

---@class ChatEmotesLib-1.0_SearchCache @v1.0 of the emote structure.
---@field public emotes ChatEmotesLib-1.0_Emote[]
---@field public weights table<ChatEmotesLib-1.0_Emote, boolean|number>

local MAJOR, MINOR = "ChatEmotesLib-1.0", 1
local CEL, OLDMINOR = LibStub:NewLibrary(MAJOR, MINOR) ---@type ChatEmotesLib-1.0
if not CEL then return end

local assert = assert
local format = format
local ipairs = ipairs
local pairs = pairs
local type = type
local strcmputf8i = strcmputf8i

---@type table<string, ChatEmotesLib-1.0_Emote[]>
CEL.packages = CEL.packages or {}

---@type string[]
CEL.packageNames = CEL.packageNames or { [0] = 0 }

---@type ChatEmotesLib-1.0_Emote[]
CEL.emotes = CEL.emotes or { [0] = 0 }

CEL.emoteWrapper = CEL.emoteWrapper or "#"

---@type string[]
CEL.emotePatterns = CEL.emotePatterns or {
	[0] = 1,
	"(%" .. CEL.emoteWrapper .. "%s*([^#%s]+)%s*%" .. CEL.emoteWrapper .. ")",
}

---@type string[]
CEL.emotePatternsAggressive = CEL.emotePatternsAggressive or {
	[0] = 4,
	"((%" .. CEL.emoteWrapper .. "%:[%w_]+%:%" .. CEL.emoteWrapper .. "))",
	"((%" .. CEL.emoteWrapper .. "[%w_]+%" .. CEL.emoteWrapper .. "))",
	"((%:[%w_]+%:))",
	"(([%w_]+))",
}

---@type table<string, function>
CEL.filter = {
	---@param emote ChatEmotesLib-1.0_Emote
	---@param name string
	sameName = function(emote, name)
		if emote.name == name then
			return true
		end
		if emote.alias then
			for i = 1, #emote.alias do
				if emote.alias[i] == name then
					return i
				end
			end
		end
	end,
	---@param emote ChatEmotesLib-1.0_Emote
	---@param name string
	sameNameCaseless = function(emote, name)
		if strcmputf8i(emote.name, name) == 0 then
			return true
		end
		if emote.alias then
			for i = 1, #emote.alias do
				if strcmputf8i(emote.alias[i], name) == 0 then
					return i
				end
			end
		end
	end,
	---@param emote ChatEmotesLib-1.0_Emote
	---@param name string
	nameFindText = function(emote, name)
		local startIndex = emote.name:find(name, nil, true)
		if startIndex then
			return startIndex
		end
		if emote.alias then
			for i = 1, #emote.alias do
				startIndex = emote.alias[i]:find(name, nil, true)
				if startIndex then
					return -startIndex
				end
			end
		end
	end,
	---@param emote ChatEmotesLib-1.0_Emote
	---@param name string
	nameFindTextCaseless = function(emote, name)
		local nameLC = name:lower()
		local startIndex = emote.name:lower():find(nameLC, nil, true)
		if startIndex then
			return startIndex
		end
		if emote.alias then
			for i = 1, #emote.alias do
				startIndex = emote.alias[i]:lower():find(nameLC, nil, true)
				if startIndex then
					return -startIndex
				end
			end
		end
	end,
	---@param emote ChatEmotesLib-1.0_Emote
	---@param name string
	nameFindTextStartsWith = function(emote, name)
		local startIndex = CEL.filter.nameFindText(emote, name)
		return startIndex and (startIndex == 1 or startIndex == -1)
	end,
	---@param emote ChatEmotesLib-1.0_Emote
	---@param name string
	nameFindTextStartsWithCaseless = function(emote, name)
		local startIndex = CEL.filter.nameFindTextCaseless(emote, name)
		return startIndex and (startIndex == 1 or startIndex == -1)
	end,
}

CEL.emoteLinkUnique = CEL.emoteLinkUnique or "chatemoteslib"
CEL.emoteLinkFormat = CEL.emoteLinkFormat or "|Hgarrmission:%s:%s|h%s|h"
CEL.emoteLinkPattern = CEL.emoteLinkPattern or "|Hgarrmission:([^:]+):([^|]+)|h([^|]+)|h"

---@param text string
local function SafePattern(text)
	return text
		:gsub("%%", "%%%%")
		:gsub("%.", "%%%.")
		:gsub("%?", "%%%?")
		:gsub("%+", "%%%+")
		:gsub("%-", "%%%-")
		:gsub("%(", "%%%(")
		:gsub("%)", "%%%)")
		:gsub("%[", "%%%[")
		:gsub("%]", "%%%]")
		:gsub("% ", "%% ")
end

local EMOJI_REPLACE = true
local EMOJI_ALLOW_LINKS = true
local EMOJI_MIN_BYTES = 3
local EMOJI_TONE = { ["🏻"] = 1, ["🏼"] = 2, ["🏽"] = 3, ["🏾"] = 4, ["🏿"] = 5 }
local EMOJI_TONE_PATTERN do
	local temp = {"["}
	local i = 1
	for chr, _ in pairs(EMOJI_TONE) do
		i = i + 1
		temp[i] = chr
	end
	i = i + 1
	temp[i] = "]"
	EMOJI_TONE_PATTERN = table.concat(temp, "")
end

---@param text string
local function EmojiIterator(text)
	return text:gmatch("[%z\1-\127\194-\244][\128-\191]+")
end

---@type table<string, ChatEmotesLib-1.0_Emote>
CEL.emoteUnicodeCache = CEL.emoteUnicodeCache or {}

---@param unicode string
local function GetUnicodeCache(unicode)
	return CEL.emoteUnicodeCache[unicode]
end

---@param unicode string
---@param emote ChatEmotesLib-1.0_Emote
local function SetUnicodeCache(unicode, emote)
	CEL.emoteUnicodeCache[unicode] = emote
end

---@param unicode string
local function GetEmoteByUnicode(unicode)
	local cache = GetUnicodeCache(unicode)
	if cache ~= nil then
		return cache
	end
	local result = false
	for i = 1, CEL.emotes[0] do
		local emote = CEL.emotes[i]
		if emote.unicode and emote.unicode == unicode then
			result = emote
			break
		end
	end
	SetUnicodeCache(unicode, result)
	return result
end

---@param text string
local function SafeSplit(text) end

---@param text string
---@param pattern string
---@param replacement string
local function SafeReplace(text, pattern, replacement) end

local function StringBuffer() end

do

	local sequences = {
		c = 10, r = 2,
		K = true, k = 2,
		H = true, h = 2,
		T = true, t = 2,
		A = true, a = 2,
	}

	local newbuffer
	local newsegments do

		local buffer = {
			__len = function(self)
				return self.length
			end,
			__concat = function(self, item)
				self.length = self.length + 1
				self[self.length] = item
				return self
			end,
			__call = function(self, item)
				return self .. item
			end,
		}

		local segments = {
			__len = buffer.__len,
			__concat = buffer.__concat,
			__call = function(self, segment)
				if not segment then
					segment = {}
				end
				segment.buffer = newbuffer()
				buffer.__concat(self, segment)
				return segment
			end,
		}

		function newbuffer()
			return setmetatable({ length = 0 }, buffer)
		end

		function newsegments()
			return setmetatable({ length = 0 }, segments)
		end

	end

	local strlen = UTF8 and UTF8.len or _G.strlenutf8 or _G.strlen
	local strsub = UTF8 and UTF8.sub or _G.strsub
	local strgsub = UTF8 and UTF8.gsub or _G.gsub

	local function createsegments(text)

		local segments = newsegments()
		local segment = segments()

		local i = 0
		local len = strlen(text)
		local skip = 0
		local level = 0

		if len ~= text:len() then
			text = strgsub(text, EMOJI_TONE_PATTERN, "")
		end

		while i < len do
			i = i + 1
			local chr = strsub(text, i, i)
			local chr2 = strsub(text, i + 1, i + 1)
			repeat
				if chr == "|" then
					local seq = sequences[chr2]
					if seq then
						if seq == true or chr2 == "c" then
							if chr2 == "H" then
								level = level + 2
							else
								level = level + 1
							end
						elseif level > 0 then
							level = level - 1
						end
						if seq ~= true then
							skip = seq
						end
						if level == 0 then
							segment = segments()
						end
					end
					break
				end
				if level > 0 then
					break
				end
				if skip > 0 then
					skip = skip - 1
					if skip == 0 then
						segment = segments()
					end
					break
				end
				if chr == " " then
					segment = segments()
					break
				end
			until true
			if EMOJI_REPLACE and chr:len() >= EMOJI_MIN_BYTES and GetEmoteByUnicode(chr) then
				segment = segments()
				segment.buffer(chr)
				segment = segments()
			else
				segment.buffer(chr)
			end
		end

		return segments

	end

	function StringBuffer()
		return newbuffer()
	end

	function SafeSplit(text)
		return createsegments(text)
	end

	function SafeReplace(text, pattern, replacement)
		local segments = createsegments(text)
		local result = newbuffer()
		for i = 1, segments.length do
			local segment = segments[i]
			local buffer = table.concat(segment.buffer, "")
			if segment.buffer[1] ~= "|" then
				buffer = buffer:gsub(pattern, replacement, 1)
			end
			result(buffer)
		end
		return table.concat(result, "")
	end

end

CEL.emoteMetatable = CEL.emoteMetatable or {
	__index = function(self, key)
		if key == "markup" then
			local file = self.file
			local fileWidth = self.fileWidth
			local fileHeight = self.fileHeight
			local offset = self.offset
			local offsetL = self.offsetL
			local offsetR = self.offsetR
			local offsetT = self.offsetT
			local offsetB = self.offsetB
			local markup
			if fileWidth and fileHeight and type(offset) == "table" then
				markup = format("|T%s:%d:%d:%d:%d:%d:%d:%d:%d:%d:%d|t", file, 0, 0, 0, 0, fileWidth, fileHeight, offset[1] * fileWidth, offset[2] * fileWidth, offset[3] * fileHeight, offset[4] * fileHeight)
			elseif fileWidth and fileHeight and offsetL and offsetR and offsetT and offsetB then
				markup = format("|T%s:%d:%d:%d:%d:%d:%d:%d:%d:%d:%d|t", file, 0, 0, 0, 0, fileWidth, fileHeight, offsetL * fileWidth, offsetR * fileWidth, offsetT * fileHeight, offsetB * fileHeight)
			else
				markup = format("|T%s:0:0|t", file)
			end
			rawset(self, key, markup)
			return markup
		end
	end,
}

---@type table<function, table<string, ChatEmotesLib-1.0_SearchCache>>
CEL.emoteSearchCache = CEL.emoteSearchCache or {}

---@param customFilter function
---@param name string
---@return ChatEmotesLib-1.0_SearchCache|nil
local function GetSearchFromCache(customFilter, name)
	local cache = CEL.emoteSearchCache[customFilter]
	if not cache then
		return
	end
	return cache[name]
end

---@param customFilter function
---@param name string
---@param emotes ChatEmotesLib-1.0_Emote[]
---@param weights table<ChatEmotesLib-1.0_Emote, boolean|number>
local function SetSearchCache(customFilter, name, emotes, weights)
	local cache = CEL.emoteSearchCache[customFilter]
	if not cache then
		cache = {}
		CEL.emoteSearchCache[customFilter] = cache
	end
	local nameCache = cache[name]
	if not nameCache then
		if emotes then
			nameCache = {}
		else
			nameCache = false
		end
		cache[name] = nameCache
	end
	if nameCache then
		nameCache.emotes = emotes
		nameCache.weights = weights
	end
	return nameCache
end

---@param package string
---@param path string
---@param folder string
---@param file any
---@return ChatEmotesLib-1.0_Emote
local function ProcessEmote(package, path, folder, file)
	local name
	local filePath
	local pattern
	local alias
	local ratio
	local ignoreSuggestion
	local args
	local fileWidth
	local fileHeight
	local offset
	local offsetL
	local offsetR
	local offsetT
	local offsetB
	local unicode
	if type(file) == "table" then
		name = file.name
		filePath = format("%s/%s/%s", path, folder, file.file or name)
		fileWidth = file.fileWidth
		fileHeight = file.fileHeight
		offset = file.offset
		offsetL = file.offsetL
		offsetR = file.offsetR
		offsetT = file.offsetT
		offsetB = file.offsetB
		pattern = SafePattern(name)
		alias = file.alias
		ratio = file.ratio
		ignoreSuggestion = file.ignoreSuggestion
		args = file.args
		unicode = file.unicode
	else
		name = file
		filePath = format("%s/%s/%s", path, folder, file)
		pattern = SafePattern(file)
	end
	return setmetatable({
		package = package,
		folder = folder,
		name = name,
		pattern = pattern,
		file = filePath,
		alias = alias,
		ratio = ratio,
		ignoreSuggestion = ignoreSuggestion,
		args = args,
		fileWidth = fileWidth,
		fileHeight = fileHeight,
		offset = offset,
		offsetL = offsetL,
		offsetR = offsetR,
		offsetT = offsetT,
		offsetB = offsetB,
		unicode = unicode,
	}, CEL.emoteMetatable)
end

---@param package string
---@param path string
---@param emotes table<string, table<number, any>>
---@return ChatEmotesLib-1.0_Emote[]
local function ProcessPackageEmotes(package, path, emotes)
	local allEmotes = CEL.emotes
	local icons
	for folder, files in pairs(emotes) do
		if type(files) == "table" then
			for _, file in ipairs(files) do
				if type(file) == "table" or type(file) == "string" then
					local emote = ProcessEmote(package, path, folder, file)
					allEmotes[0] = allEmotes[0] + 1
					allEmotes[allEmotes[0]] = emote
					if not icons then
						icons = { [0] = 0 }
					end
					icons[0] = icons[0] + 1
					icons[icons[0]] = emote
				end
			end
		end
	end
	return icons
end

---@param package ChatEmotesLib-1.0_PackageStruct
function CEL.RegisterPackage(package)
	assert(type(package.name) == "string", "Package name required.")
	assert(type(package.path) == "string", "Package path required.")
	assert(type(package.emotes) == "table", "Package emotes table required.")
	assert(CEL.packages[package.name] == nil, "Package already exists.")
	local icons = ProcessPackageEmotes(package.name, package.path, package.emotes)
	assert(icons ~= nil, "Package emotes table is malformed or empty.")
	CEL.packages[package.name] = icons
	CEL.packageNames[0] = CEL.packageNames[0] + 1
	CEL.packageNames[CEL.packageNames[0]] = package.name
	return icons
end

function CEL.GetPackages()
	return CEL.packages
end

function CEL.GetPackageNames()
	return CEL.packageNames
end

function CEL.GetEmotes()
	return CEL.emotes
end

---@param name string
---@param customFilter? function
function CEL.GetEmotesSearch(name, customFilter)
	customFilter = customFilter or CEL.filter.nameFindTextStartsWithCaseless
	local cache = GetSearchFromCache(customFilter, name)
	if cache ~= nil then
		if cache then
			return cache.emotes, cache.weights, true
		end
		return nil, nil, true
	end
	local emotes, weights
	for i = 1, CEL.emotes[0] do
		local emote = CEL.emotes[i]
		local result = customFilter(emote, name)
		if result then
			if not emotes then
				emotes = { [0] = 0 }
				weights = {}
			end
			emotes[0] = emotes[0] + 1
			emotes[emotes[0]] = emote
			weights[emote] = result
		end
	end
	SetSearchCache(customFilter, name, emotes, weights)
	return emotes, weights
end

---@param name string
---@param customFilter? function
---@return ChatEmotesLib-1.0_Emote
function CEL.GetEmoteSearch(name, customFilter)
	customFilter = customFilter or CEL.filter.nameFindTextStartsWithCaseless
	local emotes, weights, cached = CEL.GetEmotesSearch(name, customFilter)
	if not emotes then
		return
	end
	if emotes[2] and not cached then
		CEL.SortEmotes(emotes, weights)
	end
	return emotes[1]
end

---@param emotes ChatEmotesLib-1.0_Emote[]
---@param weights table<ChatEmotesLib-1.0_Emote, boolean|number>
function CEL.SortEmotes(emotes, weights)
	---@param a ChatEmotesLib-1.0_Emote
	---@param b ChatEmotesLib-1.0_Emote
	table.sort(emotes, function(a, b)
		local x = weights[a]
		local y = weights[b]
		local o = type(x)
		local p = type(y)
		if o == "boolean" then
			o, x = "number", x and 0 or -0xffff
		end
		if p == "boolean" then
			p, y = "number", y and 0 or -0xffff
		end
		if x >= 0 and y >= 0 then
			return x < y
		end
		return x > y
	end)
end

---@param text string
function CEL.TextToPattern(text)
	return SafePattern(text)
end

---@param text string
function CEL.EmojiIterator(text)
	return EmojiIterator(text)
end

---@param text string
function CEL.GetEmoteByUnicode(text)
	return GetEmoteByUnicode(text)
end

---@param text string
function CEL.SplitText(text)
	return SafeSplit(text)
end

---@param text string
---@param pattern string
---@param replacement string
function CEL.ReplaceText(text, pattern, replacement)
	return SafeReplace(text, pattern, replacement)
end

---@param text string
---@param height? number
---@param links? boolean
---@return string|nil, ChatEmotesLib-1.0_Emote|nil, ChatEmotesLib-1.0_Emote[]|nil
local function ReplaceEmotesInText(text, height, links)
	local unicodeEmotes
	for unicode in EmojiIterator(text) do
		local emote = GetEmoteByUnicode(unicode)
		if emote then
			if not unicodeEmotes then
				unicodeEmotes = { [0] = 0 }
			end
			unicodeEmotes[0] = unicodeEmotes[0] + 1
			unicodeEmotes[unicodeEmotes[0]] = emote
			text = CEL.SafeReplace(text, unicode, emote, height, (not EMOJI_REPLACE or EMOJI_ALLOW_LINKS) and links)
		end
	end
	for i = 1, CEL.emotePatterns[0] do
		local emotePattern = CEL.emotePatterns[i]
		for raw, emoteName in text:gmatch(emotePattern) do
			local emote = CEL.GetEmoteSearch(emoteName, CEL.filter.sameNameCaseless)
			if emote then
				return CEL.SafeReplace(text, raw, emote, height, links), emote, unicodeEmotes
			end
		end
	end
	for i = 1, CEL.emotePatternsAggressive[0] do
		local emotePattern = CEL.emotePatternsAggressive[i]
		for raw, emoteName in text:gmatch(emotePattern) do
			local emote = CEL.GetEmoteSearch(emoteName, CEL.filter.sameName)
			if emote then
				return CEL.SafeReplace(text, raw, emote, height, links), emote, unicodeEmotes
			end
		end
	end
	if unicodeEmotes then
		return text, nil, unicodeEmotes
	end
end

---@param text string
---@param height? number
---@param useLinks? boolean
---@param usedEmotes? boolean
---@return string|nil, ChatEmotesLib-1.0_Emote[]
function CEL.ReplaceEmotesInText(text, height, useLinks, usedEmotes)
	local segments = SafeSplit(text)
	local length = segments.length
	if length == 0 then
		return
	end
	local results = StringBuffer()
	local replaced
	local emotes
	for i = 1, length do
		local segment = segments[i]
		local buffer = table.concat(segment.buffer, "")
		if segment.buffer[1] ~= "|" then
			local replacement, replacementEmote, replacementUnicodeEmotes = ReplaceEmotesInText(buffer, height, useLinks)
			if replacement then
				replaced = true
				if usedEmotes then
					if not emotes then
						emotes = { [0] = 0 }
					end
					if replacementEmote then
						emotes[0] = emotes[0] + 1
						emotes[emotes[0]] = replacementEmote
					end
					if replacementUnicodeEmotes then
						for j = 1, replacementUnicodeEmotes[0] do
							emotes[0] = emotes[0] + 1
							emotes[emotes[0]] = replacementUnicodeEmotes[j]
						end
					end
				end
				buffer = replacement
			end
		end
		results(buffer)
	end
	if not replaced or results.length == 0 then
		return
	end
	return table.concat(results, ""), emotes
end

---@param text string
---@param raw string
---@param emote ChatEmotesLib-1.0_Emote
---@param height? number
---@param links? boolean
function CEL.SafeReplace(text, raw, emote, height, links)
	local pattern = CEL.TextToPattern(raw)
	local markup = emote.markup
	if height then
		markup = markup:gsub(":0:0", format(":%d:%d", height, height * (emote.ratio or 1)), 1)
	end
	return SafeReplace(text, pattern, links and format(CEL.emoteLinkFormat, CEL.emoteLinkUnique, emote.name, markup) or markup)
end

---@param link string
function CEL.GetEmoteFromLink(link)
	if type(link) ~= "string" then
		return
	end
	local linkType, arg1, arg2 = strsplit(":", link, 3)
	if linkType ~= "garrmission" or arg1 ~= CEL.emoteLinkUnique then
		return
	end
	return CEL.GetEmoteSearch(arg2, CEL.filter.sameName), arg2
end

--[=[

-- Run the test suite using:
-- /dump EmotesLibTest(1000)

-- Run specific test type using:
-- /dump EmotesLibTest(1000, 1)

local function randomString(maxLen, minLen)
	local len = random(minLen or 1, maxLen)
	local i = 0
	local buffer = {}
	while i < len do
		i = i + 1
		if UTF8 and random(1, 10) == 1 then
			buffer[i] = UTF8.char(random(127988, 128512))
		else
			buffer[i] = strchar(random(32, 122))
		end
	end
	return table.concat(buffer, "")
end

local function createPlain(numWords, maxWordLen)
	local n = random(1, numWords or 1)
	local buffer = {}
	for i = 1, n do
		buffer[i] = randomString(maxWordLen or 8)
	end
	return table.concat(buffer, " ")
end

local atlas = {
	"worldstate-capturebar-frame-factions",
	"worldstate-capturebar-arrow",
	"worldstate-capturebar-frame-separater",
	"worldstate-capturebar-frame-lfd",
	"worldstate-capturebar-leftfill-factions",
	"worldstate-capturebar-leftfill-lfd",
	"worldstate-capturebar-rightfill-factions",
	"worldstate-capturebar-rightfill-lfd",
	"worldstate-capturebar-spark-factions",
	"worldstate-capturebar-spark-lfd",
	"worldstate-capturebar-leftfill-boss",
	"worldstate-capturebar-rightfill-boss",
	"worldstate-capturebar-spark-boss",
	"worldstate-capturebar-frame-boss",
	"worldstate-capturebar-leftglow-boss",
	"worldstate-capturebar-leftglow-factions",
	"worldstate-capturebar-leftglow-lfd",
	"worldstate-capturebar-rightglow-factions",
	"worldstate-capturebar-rightglow-lfd",
	"worldstate-capturebar-neutralfill-boss",
	"worldstate-capturebar-neutralfill-factions",
	"worldstate-capturebar-neutralfill-lfd",
	"worldstate-capturebar-frame-target",
	"worldstate-capturebar-leftfill-target",
	"worldstate-capturebar-neutralfill-target",
	"worldstate-capturebar-rightfill-target",
	"worldstate-capturebar-spark-target",
	"worldstate-capturebar-neutralglow-target",
	"worldstate-capturebar-arrow-bastionarmor",
	"worldstate-capturebar-frame-separater-bastionarmor",
	"worldstate-capturebar-neutralfill-bastionarmor",
	"worldstate-capturebar-neutralglow-bastionarmor",
	"worldstate-capturebar-spark-bastionarmor",
	"worldstate-capturebar-spark-neutral-bastionarmor",
	"worldstate-capturebar-leftfill-white",
	"worldstate-capturebar-neutralfill-white",
	"worldstate-capturebar-rightfill-white",
	"worldstate-capturebar-spark-white",
	"worldstate-capturebar-arrow-embercourt",
	"worldstate-capturebar-frame-casualformal-embercourt",
	"worldstate-capturebar-frame-humbledecadent-embercourt",
	"worldstate-capturebar-frame-messyclean-embercourt",
	"worldstate-capturebar-frame-relaxingexciting-embercourt",
	"worldstate-capturebar-frame-safedangerous-embercourt",
	"worldstate-capturebar-leftfill-casualformal-embercourt",
	"worldstate-capturebar-leftfill-humbledecadent-embercourt",
	"worldstate-capturebar-leftfill-messyclean-embercourt",
	"worldstate-capturebar-leftfill-relaxingexciting-embercourt",
	"worldstate-capturebar-leftfill-safedangerous-embercourt",
	"worldstate-capturebar-leftfill-shadow-casualformal-embercourt",
	"worldstate-capturebar-leftfill-shadow-humbledecadent-embercourt",
	"worldstate-capturebar-leftfill-shadow-messyclean-embercourt",
	"worldstate-capturebar-leftfill-shadow-relaxingexciting-embercourt",
	"worldstate-capturebar-leftfill-shadow-safedangerous-embercourt",
	"worldstate-capturebar-leftglow-casualformal-embercourt",
	"worldstate-capturebar-leftglow-humbledecadent-embercourt",
	"worldstate-capturebar-leftglow-messyclean-embercourt",
	"worldstate-capturebar-leftglow-relaxingexciting-embercourt",
	"worldstate-capturebar-leftglow-safedangerous-embercourt",
	"worldstate-capturebar-rightfill-casualformal-embercourt",
	"worldstate-capturebar-rightfill-humbledecadent-embercourt",
	"worldstate-capturebar-rightfill-messyclean-embercourt",
	"worldstate-capturebar-rightfill-relaxingexciting-embercourt",
	"worldstate-capturebar-rightfill-safedangerous-embercourt",
	"worldstate-capturebar-rightfill-shadow-casualformal-embercourt",
	"worldstate-capturebar-rightfill-shadow-humbledecadent-embercourt",
	"worldstate-capturebar-rightfill-shadow-messyclean-embercourt",
	"worldstate-capturebar-rightfill-shadow-relaxingexciting-embercourt",
	"worldstate-capturebar-rightfill-shadow-safedangerous-embercourt",
	"worldstate-capturebar-rightglow-casualformal-embercourt",
	"worldstate-capturebar-rightglow-humbledecadent-embercourt",
	"worldstate-capturebar-rightglow-messyclean-embercourt",
	"worldstate-capturebar-rightglow-relaxingexciting-embercourt",
	"worldstate-capturebar-rightglow-safedangerous-embercourt",
	"worldstate-capturebar-spark-casualformal-embercourt",
	"worldstate-capturebar-spark-humbledecadent-embercourt",
	"worldstate-capturebar-spark-messyclean-embercourt",
	"worldstate-capturebar-spark-relaxingexciting-embercourt",
	"worldstate-capturebar-spark-safedangerous-embercourt",
	"worldstate-capturebar-divider-casualformal-embercourt",
	"worldstate-capturebar-divider-humbledecadent-embercourt",
	"worldstate-capturebar-divider-messyclean-embercourt",
	"worldstate-capturebar-divider-relaxingexciting-embercourt",
	"worldstate-capturebar-divider-safedangerous-embercourt",
	"worldstate-capturebar-framebar-bastionarmor",
}

local links = {
	function()
		return format("|cff0070dd|Hitem:80921:4721:::::::36:103::1:::::::|h[%s]|h|r", createPlain(3, 6):gsub("[%[%]]", ""))
	end,
	function()
		local r = random(0, 255)
		local g = random(0, 255)
		local b = random(0, 255)
		local hex = format("%02x%02x%02x", r, g, b)
		return format("|cFF%s[ Color %s ]|r", hex, hex)
	end,
	function()
		return format("|T%d:0:0|t", random(100000, 999999))
	end,
	function()
		return format("|A:%d:0:0|a", atlas[random(1, #atlas)])
	end,
	function()
		local n = random(1, 3)
		local p
		if n == 1 then
			p = "q"
		elseif n == 2 then
			p = "r"
		else
			p = "v"
		end
		return format("|Kq%d|k", p, random(1, 100))
	end,
}

local function createHyperlink()
	return links[random(1, #links)]()
end

local factories = {
	function()
		return createPlain(2, 6)
	end,
	function()
		return createPlain(6, 18)
	end,
	function()
		return createHyperlink()
	end,
	function()
		return format("%s %s", createPlain(2, 6), createHyperlink())
	end,
	function()
		return format("%s %s", createPlain(6, 18), createHyperlink())
	end,
	function()
		return format("%s %s %s %s", createHyperlink(), createHyperlink(), createHyperlink(), createHyperlink())
	end,
	function()
		return format("|cffffff00|Hworldmap:84:%d:%d|h[|A:Waypoint-MapPin-ChatIcon:13:13:0:0|a Map Pin Location]|h|r", random(7000, 7200), random(2400, 2600))
	end,
	function()
		local buffer = {}
		for i = 1, 3 do
			buffer[i] = format("|cffffff00|Hworldmap:84:%d:%d|h[|A:Waypoint-MapPin-ChatIcon:13:13:0:0|a Map Pin Location]|h|r", random(7000, 7200), random(2400, 2600))
		end
		return table.concat(buffer, " ")
	end,
}

local factoryNames = {
	"text(2:6)",
	"text(6:18)",
	"link(1)",
	"text(2:6) link(1)",
	"text(6:18) link(1)",
	"link(4)",
	"waypoint(1)",
	"waypoint(4)",
}

local function createTest(i)
	i = i or random(1, #factories)
	return i, factories[i]()
end

local function createTests(numTests, specificTestIndex)
	local tests = {}
	local i = 0
	while i < numTests do
		for j = 1, #factories do
			if not specificTestIndex or specificTestIndex == j then
				i = i + 1
				tests[i] = { createTest(j) }
			end
		end
	end
	return tests, i
end

local function printResults(results, totalDiff)
	local grouped = {}
	for i = 1, #factories do
		grouped[i] = { index = i, count = 0, total = 0 }
	end
	for _, result in ipairs(results) do
		local group = grouped[result.index]
		group.count = group.count + 1
		group.total = group.total + result.diff
		group[#group + 1] = result
	end
	for _, group in ipairs(grouped) do
		if group.count > 0 then
			group.average = group.total/group.count
		end
		group.percentile = group.total/totalDiff
	end
	table.sort(grouped, function(a, b)
		return a.percentile > b.percentile
	end)
	local buffer = {}
	for i, group in ipairs(grouped) do
		if group.count > 0 then
			buffer[i + 1] = format("[%s] %d (%.1f ms) => %.1f%% // %s", group.index, group.count, group.total/group.count, group.total/totalDiff*100, factoryNames[group.index])
		end
	end
	buffer[#buffer + 1] = format("[%s] %d (%.1f ms) => %.1f%%", "*", #results, totalDiff, 100)
	return buffer
end

_G.EmotesLibTest = function(numTests, specificTestIndex)
	if type(numTests) ~= "number" then
		return
	end
	local debugprofilestop = _G.debugprofilestop
	local EL_ReplaceEmotesInText = CEL.ReplaceEmotesInText
	local tests, numTests = createTests(numTests, specificTestIndex)
	local results = {}
	local totalStarted = debugprofilestop()
	for i = 1, numTests do
		local test = tests[i]
		local testIndex, testText = test[1], test[2]
		local testStarted = debugprofilestop()
		local result = EL_ReplaceEmotesInText(testText)
		local testDiff = debugprofilestop() - testStarted
		results[i] = { index = testIndex, text = testText, result = result, diff = testDiff }
	end
	local totalDiff = debugprofilestop() - totalStarted
	return printResults(results, totalDiff)
end

--]=]
