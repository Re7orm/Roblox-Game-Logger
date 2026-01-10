-- Join/Leave + Chat Logger (separated) for Discord
-- + Playtime across sessions (DataStore)
-- Location: ServerScriptService > Script

local Players             = game:GetService("Players")
local HttpService         = game:GetService("HttpService")
local RunService          = game:GetService("RunService")
local LocalizationService = game:GetService("LocalizationService")
local TextChatService     = game:GetService("TextChatService")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local DataStoreService    = game:GetService("DataStoreService")

-- ========= WEBHOOKS =========
local WEBHOOK_JOINLEAVE = "Discord webhook"
local WEBHOOK_CHAT      = "Webhook chat"

-- ========= ASSETS / META =========
local imageURL  = "Image"
local avatarURL = "Avatar"

-- ========= DATASTORE (Playtime) =========
local PlaytimeStore = DataStoreService:GetDataStore("Playtime_v1") -- key: tostring(UserId) -> totalSeconds (number)

local function dsRetry(fn, tries)
	tries = tries or 5
	local lastErr
	for i = 1, tries do
		local ok, res = pcall(fn)
		if ok then return true, res end
		lastErr = res
		task.wait(math.min(1.5 * i, 6))
	end
	return false, lastErr
end

local function loadPlaytime(userId)
	local ok, res = dsRetry(function()
		return PlaytimeStore:GetAsync(tostring(userId))
	end)
	if not ok then
		warn("[Playtime] GetAsync failed:", res)
		return 0
	end
	local n = tonumber(res)
	return (n and n >= 0) and n or 0
end

local function savePlaytime(userId, totalSeconds)
	totalSeconds = math.max(0, math.floor(totalSeconds or 0))
	local ok, err = dsRetry(function()
		return PlaytimeStore:SetAsync(tostring(userId), totalSeconds)
	end)
	if not ok then
		warn(string.format("[Playtime] SetAsync failed for %d: %s", userId, tostring(err)))
	end
end

local function fmtHMS(seconds)
	seconds = math.max(0, math.floor(seconds or 0))
	local h = math.floor(seconds / 3600)
	local m = math.floor((seconds % 3600) / 60)
	local s = seconds % 60
	return string.format("%02d:%02d:%02d", h, m, s)
end

local function fmtHoursShort(seconds)
	local hours = math.max(0, (seconds or 0)) / 3600
	return string.format("%.1f h", hours)
end


local playerState = {}

-- ========= REMOTES =========
local ReportClientInfo  = ReplicatedStorage:FindFirstChild("ReportClientInfo") or Instance.new("RemoteEvent")
ReportClientInfo.Name   = "ReportClientInfo"
ReportClientInfo.Parent = ReplicatedStorage

-- ========= HTTP SENDER =========
local function postJSON(webhookUrl, payload)
	if RunService:IsStudio() then return end -- never post from Studio
	local data = table.clone(payload)
	data["avatar_url"] = avatarURL
	local ok, err = pcall(function()
		HttpService:PostAsync(webhookUrl, HttpService:JSONEncode(data), Enum.HttpContentType.ApplicationJson)
	end)
	if not ok then
		warn("Discord webhook failed:", err)
	end
end

-- ========= HELPERS =========
local function getCountryFor(player)
	local ok, region = pcall(function()
		return LocalizationService:GetCountryRegionForPlayerAsync(player)
	end)
	return ok and region or "Unknown"
end

-- >>>>>>>>>>> PREMIUM ADD: helper
local function getPremiumLabel(player)
	local ok, mt = pcall(function() return player.MembershipType end)
	if not ok or mt == nil then
		return "Unknown"
	end
	if mt == Enum.MembershipType.Premium then
		return "✅ "
	elseif mt == Enum.MembershipType.None then
		return "❌ "
	else
		-- Legacy/edge cases (old BC tiers show as Classic/Turbo/Outrageous)
		return tostring(mt):gsub("Enum%.MembershipType%.","")
	end
end
-- <<<<<<<<<<<< PREMIUM ADD end

-- ========= FORMATTERS =========
local function formatJoinEmbed(player, state)
	local device       = (state.deviceInfo and state.deviceInfo.hint) or "Unknown"
	local country      = state.country or "Unknown"
	local totalSeconds = (state.baseTotalSeconds or 0) + (state.sessionAccum or 0)
	local premiumLabel = state.premiumLabel or getPremiumLabel(player) -- safety

	return {
		username = "Game Logger",
		embeds = { {
			title = player.Name .. " joined the game",
			description = string.format(
				"User **%s** (ID **%d**) joined.\n[Profile](https://www.roblox.com/users/%d/profile) | [Game](https://www.roblox.com/games/%d/)",
				player.Name, player.UserId, player.UserId, game.PlaceId
			),
			color = tonumber("0x6AA84F"),
			fields = {
				{ name = "Country",        value = country,      inline = true },
				{ name = "Device",         value = device,       inline = true },
				{ name = "Premium",        value = premiumLabel, inline = true }, -- << PREMIUM ADD
				{ name = "Total Playtime", value = fmtHoursShort(totalSeconds), inline = true },
				{ name = "Update",         value = "Studio sessions are not logged.", inline = false },
				{ name = "Made for jumpstyle hangout", value = "by Re7orm", inline = false },
			},
			thumbnail = { url = imageURL }
		} }
	}
end

local function formatLeaveEmbed(player, state, sessionSeconds, remainingNames)
	local device       = (state.deviceInfo and state.deviceInfo.hint) or "Unknown"
	local country      = state.country or "Unknown"
	local newTotal     = (state.baseTotalSeconds or 0) + math.max(0, sessionSeconds or 0)
	local premiumLabel = state.premiumLabel or getPremiumLabel(player) -- << PREMIUM ADD

	return {
		username = "Game Logger",
		embeds = { {
			title = player.Name .. " left the game",
			description = string.format(
				"User **%s** (ID **%d**) left.\n[Profile](https://www.roblox.com/users/%d/profile) | [Game](https://www.roblox.com/games/%d/)",
				player.Name, player.UserId, player.UserId, game.PlaceId
			),
			color = tonumber("0xFF0000"),
			fields = {
				{ name = "Country",        value = country,      inline = true },
				{ name = "Device",         value = device,       inline = true },
				{ name = "Premium",        value = premiumLabel, inline = true }, -- << PREMIUM ADD
				{ name = "Session Time",   value = "**"..fmtHMS(sessionSeconds).."**", inline = true },
				{ name = "Total Playtime", value = fmtHoursShort(newTotal), inline = true },
				{ name = "Remaining Players", value = (#remainingNames > 0) and table.concat(remainingNames, ", ") or "None", inline = false },
				{ name = "Update",         value = "Studio sessions are not logged.", inline = false },
				{ name = "Made for jumpstyle hangout", value = "by Re7orm", inline = false },
			},
			thumbnail = { url = imageURL }
		} }
	}
end

local function formatChatEmbed(authorName, authorId, channelName, msgText)
	if #msgText > 1800 then msgText = msgText:sub(1, 1800) .. "…" end
	return {
		username = "Chat Logger",
		embeds = { {
			title = "Chat Message",
			color = tonumber("0x5865F2"),
			fields = {
				{ name = "Author",  value = string.format("**%s** (ID: %s)", authorName or "System", authorId or "N/A"), inline = true },
				{ name = "Channel", value = channelName or "Default", inline = true },
				{ name = "Message", value = "```" .. msgText .. "```", inline = false },
			},
			footer = { text = string.format("PlaceId: %d • %s", game.PlaceId, os.date("!%Y-%m-%d %H:%M:%SZ")) }
		} }
	}
end

-- ========= DEVICE REPORT (from client) =========
ReportClientInfo.OnServerEvent:Connect(function(player, info)
	local state = playerState[player.UserId]
	if not state then return end
	state.deviceInfo = {
		platform = info and info.platform or "Unknown",
		hint     = info and info.hint or "Unknown",
		raw      = info
	}
end)

-- ========= HEARTBEAT ACCUMULATOR (fixes session time precision) =========
RunService.Heartbeat:Connect(function(dt)
	for userId, st in pairs(playerState) do
		st.sessionAccum = (st.sessionAccum or 0) + math.max(0, dt)
	end
end)

-- ========= PLAYER JOIN =========
Players.PlayerAdded:Connect(function(player)
	local baseSeconds = loadPlaytime(player.UserId)

	playerState[player.UserId] = {
		startTime        = os.time(),                            -- anchor (for sanity)
		baseTotalSeconds = baseSeconds,                          -- persisted total before this session
		sessionAccum     = 0,                                    -- live seconds this session
		country          = getCountryFor(player),
		deviceInfo       = { platform = "Unknown", hint = "Waiting for client…" },
		premiumLabel     = getPremiumLabel(player),              -- << PREMIUM ADD
	}

	postJSON(WEBHOOK_JOINLEAVE, formatJoinEmbed(player, playerState[player.UserId]))
end)

-- ========= PLAYER LEAVE =========
Players.PlayerRemoving:Connect(function(player)
	local state = playerState[player.UserId]
	if not state then return end

	-- compute session first (robust)
	local now = os.time()
	local anchorDelta = math.max(0, now - (state.startTime or now))
	local sessionSeconds = math.max( math.floor(state.sessionAccum or 0), anchorDelta )

	local newTotal = (state.baseTotalSeconds or 0) + sessionSeconds
	savePlaytime(player.UserId, newTotal)

	-- remaining names *before* state cleanup
	local remaining = {}
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= player then table.insert(remaining, p.Name) end
	end

	postJSON(WEBHOOK_JOINLEAVE, formatLeaveEmbed(player, state, sessionSeconds, remaining))

	playerState[player.UserId] = nil
end)

-- ========= CHAT LOGGING (SEPARATE WEBHOOK) =========
if TextChatService and TextChatService.MessageReceived then
	TextChatService.MessageReceived:Connect(function(message)
		if RunService:IsStudio() then return end
		local text = message.Text or ""
		local channelName = (message.TextChannel and message.TextChannel.Name) or "Default"
		local authorName, authorId = "System", "N/A"
		local src = message.TextSource
		if src then
			authorId = tostring(src.UserId)
			local plr = Players:GetPlayerByUserId(src.UserId)
			authorName = (plr and plr.Name) or src.Name or ("User_"..authorId)
		end
		postJSON(WEBHOOK_CHAT, formatChatEmbed(authorName, authorId, channelName, text))
	end)
end

-- Classic Chat fallback
Players.PlayerAdded:Connect(function(plr)
	plr.Chatted:Connect(function(text)
		if RunService:IsStudio() then return end
		postJSON(WEBHOOK_CHAT, formatChatEmbed(plr.Name, tostring(plr.UserId), "Ingame main chat", text or ""))
	end)
end)

-- ========= AUTOSAVE (every 5 min) =========
task.spawn(function()
	while true do
		task.wait(300) -- 5 minutes (was 2s → DS throttle + wobbling totals)
		for _, plr in ipairs(Players:GetPlayers()) do
			local st = playerState[plr.UserId]
			if st then
				local now = os.time()
				local anchorDelta = math.max(0, now - (st.startTime or now))
				local sessionSeconds = math.max( math.floor(st.sessionAccum or 0), anchorDelta )
				local total = (st.baseTotalSeconds or 0) + sessionSeconds
				savePlaytime(plr.UserId, total)

				-- roll the anchor & reset accumulator to avoid double-counting
				st.baseTotalSeconds = total
				st.startTime = now
				st.sessionAccum = 0
			end
		end
	end
end)

-- ========= SHUTDOWN SAVE =========
game:BindToClose(function()
	for _, plr in ipairs(Players:GetPlayers()) do
		local st = playerState[plr.UserId]
		if st then
			local now = os.time()
			local anchorDelta = math.max(0, now - (st.startTime or now))
			local sessionSeconds = math.max( math.floor(st.sessionAccum or 0), anchorDelta )
			local total = (st.baseTotalSeconds or 0) + sessionSeconds
			savePlaytime(plr.UserId, total)
		end
	end
end)
## thanks
