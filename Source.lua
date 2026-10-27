-- Check for table that is shared between executions.
if not shared then
	return warn("No shared, no script.")
end

-- Initialize Luraph globals if they do not exist.
loadstring("getfenv().LPH_NO_VIRTUALIZE = function(...) return ... end")()
getfenv().PP_SCRAMBLE_NUM = function(...) return ... end
getfenv().PP_SCRAMBLE_STR = function(...) return ... end
getfenv().PP_SCRAMBLE_RE_NUM = function(...) return ... end

local Suite = { aimEnabled = true, running = true, cleaned = false, entries = {}, connections = {} }

-- Constants.
local LIBRARY_REPO = "https://raw.githubusercontent.com/violin-suzutsuki/LinoriaLib/main/"
local CONFIG_FOLDER = "Suite"

local ESP_CONFIG = {
	ENABLED = true,
	MAX_DISTANCE = 2500,
	TEAM_CHECK = true,
	SHOW_BOX = true,
	SHOW_NAME = true,
	SHOW_HEALTH = true,
	SHOW_TRACER = true,
	BOX_COLOR = Color3.fromRGB(255, 70, 70),
	TEAM_COLOR = Color3.fromRGB(80, 255, 120),
	TEXT_COLOR = Color3.fromRGB(255, 255, 255),
	TOP_OFFSET = Vector3.new(0, 2.8, 0),
	BOTTOM_OFFSET = Vector3.new(0, 3.2, 0),
	BOX_ASPECT = 0.6,
	TEXT_SIZE = 13,
}

local AIM_CONFIG = {
	TARGET_FUNCTION = "Get3DPosition",
	SOURCE_MATCH = "GunScript_Local",
	RESCAN_INTERVAL = 1,
	FOV_RADIUS = 300,
	SHOW_FOV = true,
	FOV_COLOR = Color3.fromRGB(255, 255, 255),
	FOV_THICKNESS = 1,
	FOV_SIDES = 64,
	HIT_CHANCE = 0.85,
	HEAD_CHANCE = 0.35,
	HEAD_PART = "Head",
	BODY_PART = "UpperTorso",
	AIM_JITTER = 0.55,
	PREDICTION_TIME = 0.04,
	VISIBLE_CHECK = true,
}

-- Services.
local playersService = game:GetService("Players")
local userInputService = game:GetService("UserInputService")
local runService = game:GetService("RunService")

-- State.
local localPlayer = playersService.LocalPlayer
local fovCircle = nil
local hookedFunctions = setmetatable({}, { __mode = "k" })

---Create a Drawing object with the given properties applied.
---@param drawingType string
---@param properties table
local function newDrawing(drawingType, properties)
	local drawing = Drawing.new(drawingType)

	for property, value in next, properties do
		drawing[property] = value
	end

	return drawing
end

---Hide every drawing in an entry.
---@param entry table
local function hideEntry(entry)
	for _, drawing in next, entry do
		drawing.Visible = false
	end
end

---Create the ESP drawing set for a player.
---@param player Player
local function createEntry(player)
	if player == localPlayer or Suite.entries[player] then
		return
	end

	Suite.entries[player] = {
		box = newDrawing("Square", { Thickness = 1, Filled = false, Visible = false, ZIndex = 2 }),
		name = newDrawing("Text", { Size = ESP_CONFIG.TEXT_SIZE, Center = true, Outline = true, Color = ESP_CONFIG.TEXT_COLOR, Visible = false, ZIndex = 3 }),
		tracer = newDrawing("Line", { Thickness = 1, Visible = false, ZIndex = 1 }),
		healthBack = newDrawing("Square", { Thickness = 1, Filled = true, Color = Color3.new(0, 0, 0), Visible = false, ZIndex = 2 }),
		healthFill = newDrawing("Square", { Thickness = 1, Filled = true, Visible = false, ZIndex = 3 }),
	}
end

---Destroy the ESP drawing set for a player.
---@param player Player
local function removeEntry(player)
	local entry = Suite.entries[player]

	if not entry then
		return
	end

	for _, drawing in next, entry do
		drawing:Remove()
	end

	Suite.entries[player] = nil
end

---Update a single player's ESP drawings for this frame.
---@param player Player
---@param entry table
---@param camera Camera
local function updateEntry(player, entry, camera)
	if not ESP_CONFIG.ENABLED then
		return hideEntry(entry)
	end

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")

	if not (humanoid and rootPart and humanoid.Health > 0) then
		return hideEntry(entry)
	end

	local sameTeam = player.Team ~= nil and player.Team == localPlayer.Team

	if ESP_CONFIG.TEAM_CHECK and sameTeam then
		return hideEntry(entry)
	end

	local rootPosition = rootPart.Position
	local distance = (camera.CFrame.Position - rootPosition).Magnitude

	if distance > ESP_CONFIG.MAX_DISTANCE then
		return hideEntry(entry)
	end

	-- Drawing library elements use WorldToViewportPoint.
	local _, onScreen = camera:WorldToViewportPoint(rootPosition)

	if not onScreen then
		return hideEntry(entry)
	end

	local topPoint = camera:WorldToViewportPoint(rootPosition + ESP_CONFIG.TOP_OFFSET)
	local bottomPoint = camera:WorldToViewportPoint(rootPosition - ESP_CONFIG.BOTTOM_OFFSET)

	local height = math.abs(bottomPoint.Y - topPoint.Y)
	local width = height * ESP_CONFIG.BOX_ASPECT
	local boxX = topPoint.X - width / 2
	local boxY = topPoint.Y
	local color = sameTeam and ESP_CONFIG.TEAM_COLOR or ESP_CONFIG.BOX_COLOR

	entry.box.Visible = ESP_CONFIG.SHOW_BOX
	entry.box.Color = color
	entry.box.Size = Vector2.new(width, height)
	entry.box.Position = Vector2.new(boxX, boxY)

	entry.name.Visible = ESP_CONFIG.SHOW_NAME
	entry.name.Text = string.format("%s [%d]", player.DisplayName, math.floor(distance))
	entry.name.Position = Vector2.new(topPoint.X, boxY - ESP_CONFIG.TEXT_SIZE - 3)

	local healthRatio = math.clamp(humanoid.Health / math.max(humanoid.MaxHealth, 1), 0, 1)

	entry.healthBack.Visible = ESP_CONFIG.SHOW_HEALTH
	entry.healthBack.Size = Vector2.new(4, height + 2)
	entry.healthBack.Position = Vector2.new(boxX - 7, boxY - 1)

	entry.healthFill.Visible = ESP_CONFIG.SHOW_HEALTH
	entry.healthFill.Color = Color3.fromRGB(255, 60, 60):Lerp(Color3.fromRGB(60, 255, 60), healthRatio)
	entry.healthFill.Size = Vector2.new(2, height * healthRatio)
	entry.healthFill.Position = Vector2.new(boxX - 6, boxY + height * (1 - healthRatio))

	local viewport = camera.ViewportSize

	entry.tracer.Visible = ESP_CONFIG.SHOW_TRACER
	entry.tracer.Color = color
	entry.tracer.From = Vector2.new(viewport.X / 2, viewport.Y)
	entry.tracer.To = Vector2.new(topPoint.X, boxY + height)
end

---Collect the players that count as enemies, using the match folder the game maintains.
---@return Player[]
local function getEnemyPlayers()
	local enemies = {}
	local dataFolder = localPlayer:FindFirstChild("Data")
	local matchFolder = dataFolder and dataFolder:FindFirstChild("Match")
	local enemiesFolder = matchFolder and matchFolder:FindFirstChild("Enemies")

	if enemiesFolder then
		for _, marker in next, enemiesFolder:GetChildren() do
			local player = playersService:FindFirstChild(marker.Name)

			if player and player ~= localPlayer then
				table.insert(enemies, player)
			end
		end

		return enemies
	end

	-- Fallback for modes without a match folder.
	for _, player in next, playersService:GetPlayers() do
		if player == localPlayer then
			continue
		end

		if player.Team and player.Team == localPlayer.Team then
			continue
		end

		table.insert(enemies, player)
	end

	return enemies
end

---Check that nothing solid sits between the camera and the part.
---@param camera Camera
---@param targetPart BasePart
---@return boolean
local function isVisible(camera, targetPart)
	local origin = camera.CFrame.Position
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { localPlayer.Character, camera }
	params.IgnoreWater = true

	local result = workspace:Raycast(origin, targetPart.Position - origin, params)

	if not result then
		return true
	end

	return result.Instance:IsDescendantOf(targetPart.Parent)
end

---Get the aim cursor position, which is the screen center while the mouse is locked.
---@param camera Camera
---@return Vector2
local function getCursorPosition(camera)
	if userInputService.MouseBehavior == Enum.MouseBehavior.LockCenter then
		local viewport = camera.ViewportSize
		return Vector2.new(viewport.X / 2, viewport.Y / 2)
	end

	return userInputService:GetMouseLocation()
end

---Pick the enemy part closest to the cursor inside the FOV circle.
---@param camera Camera
---@return BasePart?
local function getTargetPart(camera)
	local cursor = getCursorPosition(camera)
	local partName = math.random() < AIM_CONFIG.HEAD_CHANCE and AIM_CONFIG.HEAD_PART or AIM_CONFIG.BODY_PART
	local bestPart, bestDistance = nil, AIM_CONFIG.FOV_RADIUS

	for _, player in next, getEnemyPlayers() do
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local part = character and (character:FindFirstChild(partName) or character:FindFirstChild("HumanoidRootPart"))

		if not (humanoid and part and humanoid.Health > 0) then
			continue
		end

		-- Drawing-space projection so it matches the cursor coordinates.
		local screenPosition, onScreen = camera:WorldToViewportPoint(part.Position)

		if not onScreen then
			continue
		end

		local distance = (Vector2.new(screenPosition.X, screenPosition.Y) - cursor).Magnitude

		if distance >= bestDistance then
			continue
		end

		if AIM_CONFIG.VISIBLE_CHECK and not isVisible(camera, part) then
			continue
		end

		bestPart, bestDistance = part, distance
	end

	return bestPart
end

---Resolve the world position the next shot should be aimed at, or nil to defer to the game.
---@return Vector3?
function Suite.getAimPosition()
	if not Suite.aimEnabled or math.random() > AIM_CONFIG.HIT_CHANCE then
		return nil
	end

	local camera = workspace.CurrentCamera

	if not camera then
		return nil
	end

	local targetPart = getTargetPart(camera)

	if not targetPart then
		return nil
	end

	-- Offset inside the part so shots never land on the exact centre, which the game reports.
	local half = targetPart.Size * AIM_CONFIG.AIM_JITTER * 0.5
	local jitter = Vector3.new(math.random() * 2 - 1, math.random() * 2 - 1, math.random() * 2 - 1) * half

	return targetPart.Position + jitter + targetPart.AssemblyLinearVelocity * AIM_CONFIG.PREDICTION_TIME
end

---Build the replacement closure for one Get3DPosition instance.
---@param originalBox table
local function makeReplacement(originalBox)
	return function(...)
		local aimPosition = Suite.getAimPosition()

		if aimPosition then
			return aimPosition
		end

		return originalBox.callback(...)
	end
end

---Find unhooked aim resolvers that belong to the gun script and hook them.
local function scanAndHook()
	local success, candidates = pcall(filtergc, "function", { Name = AIM_CONFIG.TARGET_FUNCTION, IgnoreExecutor = true }, false)

	if not success or typeof(candidates) ~= "table" then
		return
	end

	for _, candidate in next, candidates do
		if hookedFunctions[candidate] then
			continue
		end

		local source = debug.info(candidate, "s")

		if not (source and source:find(AIM_CONFIG.SOURCE_MATCH, 1, true)) then
			continue
		end

		hookedFunctions[candidate] = true

		local originalBox = {}
		originalBox.callback = hookfunction(candidate, makeReplacement(originalBox))
	end
end

---Keep the FOV circle on the cursor and hide it while the aim is off.
---@param camera Camera
local function updateFovCircle(camera)
	if not fovCircle then
		return
	end

	fovCircle.Visible = AIM_CONFIG.SHOW_FOV and Suite.aimEnabled

	if not fovCircle.Visible then
		return
	end

	fovCircle.Color = AIM_CONFIG.FOV_COLOR
	fovCircle.Position = getCursorPosition(camera)
	fovCircle.Radius = AIM_CONFIG.FOV_RADIUS
end

---Run the per-frame update for the ESP and the FOV circle.
local function onRenderStepped()
	local camera = workspace.CurrentCamera

	if not camera then
		return
	end

	for player, entry in next, Suite.entries do
		updateEntry(player, entry, camera)
	end

	updateFovCircle(camera)
end

---Download and run a Linoria module.
---@param path string
local function loadRemote(path)
	local response = request({ Url = LIBRARY_REPO .. path, Method = "GET" })

	return loadstring(response.Body)()
end

---Add a toggle that writes straight into a config table.
---@param group table
---@param id string
---@param text string
---@param config table
---@param key string
local function addConfigToggle(group, id, text, config, key)
	return group:AddToggle(id, {
		Text = text,
		Default = config[key],
		Callback = function(value)
			config[key] = value
		end,
	})
end

---Add a slider that writes straight into a config table.
---@param group table
---@param id string
---@param text string
---@param config table
---@param key string
---@param minimum number
---@param maximum number
---@param rounding number
local function addConfigSlider(group, id, text, config, key, minimum, maximum, rounding)
	group:AddSlider(id, {
		Text = text,
		Default = config[key],
		Min = minimum,
		Max = maximum,
		Rounding = rounding,
		Callback = function(value)
			config[key] = value
		end,
	})
end

---Add a color picker that writes straight into a config table.
---@param group table
---@param id string
---@param text string
---@param config table
---@param key string
local function addConfigColor(group, id, text, config, key)
	group:AddLabel(text):AddColorPicker(id, {
		Default = config[key],
		Title = text,
		Callback = function(value)
			config[key] = value
		end,
	})
end

---Build the Linoria menu and bind its controls to the config tables.
local function buildMenu()
	local Library = loadRemote("Library.lua")
	local ThemeManager = loadRemote("addons/ThemeManager.lua")
	local SaveManager = loadRemote("addons/SaveManager.lua")
	local Options = Library.Options or getgenv().Options

	Suite.library = Library
	Library:OnUnload(Suite.cleanup)

	local Window = Library:CreateWindow({ Title = "Suite", Center = true, AutoShow = true, TabPadding = 8, MenuFadeTime = 0.2 })
	local Tabs = { Aim = Window:AddTab("Aim"), Visuals = Window:AddTab("Visuals"), Settings = Window:AddTab("UI Settings") }

	-- Aim tab.
	local aimGroup = Tabs.Aim:AddLeftGroupbox("Silent aim")

	aimGroup:AddToggle("AimEnabled", {
		Text = "Enabled",
		Default = Suite.aimEnabled,
		Callback = function(value)
			Suite.aimEnabled = value
		end,
	}):AddKeyPicker("AimKey", { Default = "E", SyncToggleState = true, Mode = "Toggle", Text = "Silent aim", NoUI = false })

	addConfigToggle(aimGroup, "VisibleCheck", "Visible check", AIM_CONFIG, "VISIBLE_CHECK")
	addConfigSlider(aimGroup, "FovRadius", "FOV radius", AIM_CONFIG, "FOV_RADIUS", 30, 900, 0)

	aimGroup:AddSlider("HitChance", {
		Text = "Hit chance",
		Default = AIM_CONFIG.HIT_CHANCE * 100,
		Min = 1,
		Max = 100,
		Rounding = 0,
		Suffix = "%",
		Callback = function(value)
			AIM_CONFIG.HIT_CHANCE = value / 100
		end,
	})

	aimGroup:AddSlider("HeadChance", {
		Text = "Head chance",
		Default = AIM_CONFIG.HEAD_CHANCE * 100,
		Min = 0,
		Max = 100,
		Rounding = 0,
		Suffix = "%",
		Callback = function(value)
			AIM_CONFIG.HEAD_CHANCE = value / 100
		end,
	})

	local tuningGroup = Tabs.Aim:AddRightGroupbox("Tuning")

	tuningGroup:AddDropdown("BodyPart", {
		Text = "Body part",
		Values = { "UpperTorso", "HumanoidRootPart", "LowerTorso" },
		Default = 1,
		Multi = false,
		Callback = function(value)
			AIM_CONFIG.BODY_PART = value
		end,
	})

	addConfigSlider(tuningGroup, "AimJitter", "Aim jitter", AIM_CONFIG, "AIM_JITTER", 0.1, 1, 2)
	addConfigSlider(tuningGroup, "Prediction", "Prediction time", AIM_CONFIG, "PREDICTION_TIME", 0, 0.15, 3)
	addConfigToggle(tuningGroup, "ShowFov", "Show FOV circle", AIM_CONFIG, "SHOW_FOV")
	addConfigColor(tuningGroup, "FovColor", "FOV color", AIM_CONFIG, "FOV_COLOR")

	-- Visuals tab.
	local espGroup = Tabs.Visuals:AddLeftGroupbox("ESP")

	addConfigToggle(espGroup, "EspEnabled", "Enabled", ESP_CONFIG, "ENABLED")
	addConfigToggle(espGroup, "EspBox", "Box", ESP_CONFIG, "SHOW_BOX")
	addConfigToggle(espGroup, "EspName", "Name", ESP_CONFIG, "SHOW_NAME")
	addConfigToggle(espGroup, "EspHealth", "Health bar", ESP_CONFIG, "SHOW_HEALTH")
	addConfigToggle(espGroup, "EspTracer", "Tracer", ESP_CONFIG, "SHOW_TRACER")
	addConfigToggle(espGroup, "EspTeamCheck", "Team check", ESP_CONFIG, "TEAM_CHECK")
	addConfigSlider(espGroup, "EspDistance", "Max distance", ESP_CONFIG, "MAX_DISTANCE", 100, 5000, 0)

	local colorGroup = Tabs.Visuals:AddRightGroupbox("Colors")

	addConfigColor(colorGroup, "EspBoxColor", "Enemy color", ESP_CONFIG, "BOX_COLOR")
	addConfigColor(colorGroup, "EspTeamColor", "Team color", ESP_CONFIG, "TEAM_COLOR")

	-- Settings tab.
	local menuGroup = Tabs.Settings:AddLeftGroupbox("Menu")

	menuGroup:AddButton("Unload", function()
		Suite.detach()
	end)

	menuGroup:AddLabel("Menu bind"):AddKeyPicker("MenuKeybind", { Default = "End", NoUI = true, Text = "Menu keybind" })
	Library.ToggleKeybind = Options.MenuKeybind

	ThemeManager:SetLibrary(Library)
	SaveManager:SetLibrary(Library)
	SaveManager:IgnoreThemeSettings()
	SaveManager:SetIgnoreIndexes({ "MenuKeybind" })
	ThemeManager:SetFolder(CONFIG_FOLDER)
	SaveManager:SetFolder(CONFIG_FOLDER .. "/config")
	SaveManager:BuildConfigSection(Tabs.Settings)
	ThemeManager:ApplyToTab(Tabs.Settings)
	SaveManager:LoadAutoloadConfig()
end

---This is called when initialization errors.
---@param error string
local function onInitializeError(error)
	warn("Failed to initialize.")
	warn(error)
	warn(debug.traceback())
	Suite.detach()
end

---Tear down everything except the menu; hooked closures fall through to the original from here on.
function Suite.cleanup()
	if Suite.cleaned then
		return
	end

	Suite.cleaned = true
	Suite.aimEnabled = false
	Suite.running = false

	for _, connection in next, Suite.connections do
		connection:Disconnect()
	end

	for player in next, Suite.entries do
		removeEntry(player)
	end

	Suite.connections = {}

	if fovCircle then
		fovCircle:Remove()
		fovCircle = nil
	end
end

---Detach everything, including the menu.
function Suite.detach()
	Suite.cleanup()

	local library = Suite.library
	Suite.library = nil

	if library and not library.Unloaded then
		pcall(library.Unload, library)
	end
end

---Initialize the ESP, the silent aim and the menu.
function Suite.init()
	fovCircle = newDrawing("Circle", {
		Color = AIM_CONFIG.FOV_COLOR,
		Thickness = AIM_CONFIG.FOV_THICKNESS,
		NumSides = AIM_CONFIG.FOV_SIDES,
		Filled = false,
		Visible = false,
	})

	for _, player in next, playersService:GetPlayers() do
		createEntry(player)
	end

	table.insert(Suite.connections, playersService.PlayerAdded:Connect(createEntry))
	table.insert(Suite.connections, playersService.PlayerRemoving:Connect(removeEntry))
	table.insert(Suite.connections, runService.RenderStepped:Connect(onRenderStepped))

	-- Guns are recreated on equip, so keep rescanning for fresh closures.
	task.spawn(function()
		while Suite.running do
			pcall(scanAndHook)
			task.wait(AIM_CONFIG.RESCAN_INTERVAL)
		end
	end)

	buildMenu()
end

-- Detach the previous instance so re-execution starts clean.
if shared.Suite then
	shared.Suite.detach()
end

shared.Suite = Suite

-- Safely initialize the script as well as handle errors.
xpcall(Suite.init, onInitializeError)

return Suite
