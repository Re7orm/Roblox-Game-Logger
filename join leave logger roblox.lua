local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local webhook = "Your webhook link on discord please try it first without an API ^^"
local imageURL = "Your imageURL i prefer using the link from discord."

local playerData = {}

-- Function to send a message to Discord very cool ^^
local function sendToDiscord(data)
	local jsonData = HttpService:JSONEncode(data)
	HttpService:PostAsync(webhook, jsonData, Enum.HttpContentType.ApplicationJson)
end

-- Function to format the join message
local function formatJoinMessage(player)
	local data = {
		["username"] = "Game Logger",  -- Custom name for the webhook message sender
		["embeds"] = {{
			["title"] = player.Name .. " joined the Game",
			["description"] = "User: **" .. player.Name .. "** with ID: **" .. player.UserId .. "** has joined the game.\n[Profile](https://www.roblox.com/users/" .. player.UserId .. "/profile) | [Game](https://www.roblox.com/games/" .. game.PlaceId .. ")",
			["color"] = tonumber("0x6AA84F"),
			["fields"] = {
				{
					["name"] = "Update Logs",
					["value"] = "logs are here :D",  
					["inline"] = false
				}
			},
			["thumbnail"] = {
				["url"] = imageURL
			}
		}}
	}
	return data
end

-- Function to format the leave message
local function formatLeaveMessage(player, totalTime, remainingPlayers)
	local hours = math.floor(totalTime / 3600)
	local minutes = math.floor((totalTime % 3600) / 60)
	local seconds = totalTime % 60
	local timeString = string.format("%02d:%02d:%02d", hours, minutes, seconds)

	local remainingPlayersList = table.concat(remainingPlayers, ", ")
--- leave msg 
	local data = {
		["username"] = "Game Logger",  -- Custom name for the webhook message sender
		["embeds"] = {{
			["title"] = player.Name .. " left the Game",
			["description"] = "User: **" .. player.Name .. "** with ID: **" .. player.UserId .. "** left the game.\n[Profile](https://www.roblox.com/users/" .. player.UserId .. "/profile) | [Game](https://www.roblox.com/games/" .. game.PlaceId .. ")",
			["color"] = tonumber("0xFF0000"),
			["fields"] = {
				{
					["name"] = "Time Spent in Game",
					["value"] = "**" .. timeString .. "**",
					["inline"] = true
				},
				{
					["name"] = "Remaining Players",
					["value"] = remainingPlayersList,
					["inline"] = false
				},
				{
					["name"] = "Update Logs",
					["value"] = "logs are here :D",  
					["inline"] = false
				}
			},
			["thumbnail"] = {
				["url"] = imageURL
			}
		}}
	}
	return data
end

-- Handle Player Added event
Players.PlayerAdded:Connect(function(player)
	if RunService:IsStudio() then return end  -- Skip logging if in Roblox Studio

	playerData[player.UserId] = {startTime = os.time()}
	local joinData = formatJoinMessage(player)
	sendToDiscord(joinData)
end)

-- Handle Player Removing event
Players.PlayerRemoving:Connect(function(player)
	if RunService:IsStudio() then return end  -- Skip logging if in Roblox Studio

	local endTime = os.time()
	local startTime = playerData[player.UserId].startTime
	local totalTime = endTime - startTime
	playerData[player.UserId] = nil -- Clean up data after player leaves

	local remainingPlayers = {}
	for _, remainingPlayer in pairs(Players:GetPlayers()) do
		table.insert(remainingPlayers, remainingPlayer.Name)
	end

	local leaveData = formatLeaveMessage(player, totalTime, remainingPlayers)
	sendToDiscord(leaveData)
end)
