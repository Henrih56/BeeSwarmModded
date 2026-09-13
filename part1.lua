print("[BSS AutoFarm] Script iniciado!")
pcall(function()
	game.StarterGui:SetCore("SendNotification", {
		Title = "BSS AutoFarm";
		Text = "Script carregado!";
		Duration = 5;
	})
end)
local guiNames = {"AtlasV3", "AtlasStyleMacro", "BSSAutoFarm", "BSS Auto Farm", "AtlasV2", "BSSMacro"}
for _, guiName in ipairs(guiNames) do
	pcall(function()
		if game:GetService("CoreGui"):FindFirstChild(guiName) then 
			game:GetService("CoreGui")[guiName]:Destroy() 
		end
		if game:GetService("Players").LocalPlayer.PlayerGui:FindFirstChild(guiName) then 
			game:GetService("Players").LocalPlayer.PlayerGui[guiName]:Destroy() 
		end
	end)
end
local previousSession = rawget(_G, "BSSAutoFarmSession")
if previousSession then
	previousSession.StopRequested = true
end
local SESSION = {
	StopRequested = false,
	AutomationRunning = false,
}
_G.BSSAutoFarmSession = SESSION
local function isCurrentSession()
	return not SESSION.StopRequested and rawget(_G, "BSSAutoFarmSession") == SESSION
end
if not game:IsLoaded() then
	game.Loaded:Wait()
end
task.wait(1) -- buffer extra para CoreGui e LocalizationService inicializarem
local RayfieldOk, Rayfield = pcall(function()
	return loadstring(game:HttpGet('https://sirius.menu/rayfield'))()
end)
game.StarterGui:SetCore("SendNotification", {
	Title = "BSS AutoFarm";
	Text = "Carregando Rayfield...";
	Duration = 3;
})
if not RayfieldOk or not Rayfield then
	local function stub() end
	Rayfield = setmetatable({}, {
		__index = function(_, key)
			return function(_, ...)
				return setmetatable({}, {__index = function() return stub end})
			end
		end
	})
	warn("[BSS AutoFarm] Falha ao carregar Rayfield. UI não disponível.")
	game.StarterGui:SetCore("SendNotification", {
		Title = "BSS AutoFarm - ERRO";
		Text = "Rayfield falhou. UI indisponível.";
		Duration = 10;
	})
end
local function safeNotify(title, content, duration)
	pcall(function()
		if Rayfield and Rayfield.Notify then
			Rayfield:Notify({
				Title = title,
				Content = content,
				Duration = duration or 3,
				Image = 4483362458,
			})
		end
	end)
end
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local VirtualInputManager = nil
pcall(function()
	VirtualInputManager = game:GetService("VirtualInputManager")
end)
local player = Players.LocalPlayer
local workspace = game:GetService("Workspace")
local DELTA_FUNCTIONS = {
	HasMouseClick = type(mouse1click) == "function",
	HasMousePress = type(mouse1press) == "function" and type(mouse1release) == "function",
	HasGetConnections = type(getconnections) == "function",
	HasFireSignal = type(firesignal) == "function",
	HasHookFunction = type(hookfunction) == "function",
}
local DELTA_ANTI_DETECT = {
	Enabled = true,
	RandomizeTimings = true,
	HumanizedMovement = true,
}
local function getRandomizedTiming(baseValue, variationPercent)
	if not DELTA_ANTI_DETECT.RandomizeTimings then return baseValue end
	local variation = baseValue * (variationPercent / 100)
	return baseValue + math.random(-variation * 100, variation * 100) / 100
end
local DELTA_CACHE = {
	Character = nil,
	Root = nil,
	Humanoid = nil,
	LastUpdate = 0,
	UpdateInterval = 0.5, -- Atualiza cache a cada 0.5s
}
local function getDeltaOptimizedRoot()
	local currentTime = tick()
	if DELTA_CACHE.Root and DELTA_CACHE.Root.Parent and currentTime - DELTA_CACHE.LastUpdate < DELTA_CACHE.UpdateInterval then
		return DELTA_CACHE.Root
	end
	local character = player.Character
	if not character then return nil end
	local root = character:FindFirstChild("HumanoidRootPart")
	local humanoid = character:FindFirstChild("Humanoid")
	DELTA_CACHE.Character = character
	DELTA_CACHE.Root = root
	DELTA_CACHE.Humanoid = humanoid
	DELTA_CACHE.LastUpdate = currentTime
	return root
end
local function deltaOptimizedTeleport(position)
	local root = getDeltaOptimizedRoot()
	if not root then return false end
	local currentRotation = root.CFrame - root.CFrame.Position
	root.CFrame = CFrame.new(position) * currentRotation
	if DELTA_ANTI_DETECT.HumanizedMovement then
		task.wait(getRandomizedTiming(0.01, 20)) -- Randomiza entre 0.008-0.012
	else
		task.wait()
	end
	return true
end
local COLLECT_INPUT = { Held = false, Method = nil, X = nil, Y = nil }
local function hasInteractiveUiAt(x, y)
	if UserInputService:GetFocusedTextBox() then return true end
	local ok, guiObjects = pcall(function()
		return GuiService:GetGuiObjectsAtPosition(x, y)
	end)
	if not ok then return true end -- em caso de dúvida, não clicar
	for _, guiObject in ipairs(guiObjects) do
		if guiObject.Visible and (guiObject:IsA("GuiButton") or guiObject:IsA("TextBox")) then
			return true
		end
	end
	return false
end
local function releaseToolCollectInput()
	if not COLLECT_INPUT.Held then return end
	pcall(function()
		if COLLECT_INPUT.Method == "delta_native" and DELTA_FUNCTIONS.HasMousePress then
			mouse1release()
		elseif COLLECT_INPUT.Method == "virtual" and VirtualInputManager then
			VirtualInputManager:SendMouseButtonEvent(COLLECT_INPUT.X, COLLECT_INPUT.Y, 0, false, game, 0)
		end
	end)
	COLLECT_INPUT.Held = false
	COLLECT_INPUT.Method = nil
	COLLECT_INPUT.X, COLLECT_INPUT.Y = nil, nil
end
local function fireToolCollect()
	if COLLECT_INPUT.Held then return true end
	if DELTA_FUNCTIONS.HasMouseClick then
		local ok = pcall(mouse1click)
		if ok then
			COLLECT_INPUT.Held = true
			COLLECT_INPUT.Method = "delta_click"
			return true
		end
	end
	local mousePosition = UserInputService:GetMouseLocation()
	if hasInteractiveUiAt(mousePosition.X, mousePosition.Y) then return false end
	if DELTA_FUNCTIONS.HasMousePress then
		local ok = pcall(mouse1press)
		if ok then
			COLLECT_INPUT.Held = true
			COLLECT_INPUT.Method = "delta_native"
			return true
		end
	end
	local camera = workspace.CurrentCamera
	if not VirtualInputManager or not camera then return false end
	local viewport = camera.ViewportSize
	local x, y = math.floor(viewport.X * 0.5), math.floor(viewport.Y * 0.5)
	if x <= 0 or y <= 0 or hasInteractiveUiAt(x, y) then return false end
	local ok = pcall(function()
		VirtualInputManager:SendMouseButtonEvent(x, y, 0, true, game, 0)
	end)
	if ok then
		COLLECT_INPUT.Held = true
		COLLECT_INPUT.Method = "virtual"
		COLLECT_INPUT.X, COLLECT_INPUT.Y = x, y
	end
	return ok
end
local MOVEMENT = { Busy = false, Owner = nil }
local function requestMovement(owner, action)
	if MOVEMENT.Busy then return false end
	MOVEMENT.Busy = true
	MOVEMENT.Owner = owner
	local ok, result = xpcall(action, debug.traceback)
	MOVEMENT.Busy = false
	MOVEMENT.Owner = nil
	if not ok then
		warn("[BSS AutoFarm] Movimento falhou: " .. tostring(result))
		return false
	end
	return result == true
end
local function teleportTo(position)
	return deltaOptimizedTeleport(position)
end
local flowerZones = workspace:WaitForChild("FlowerZones", 30)
local hivePlatforms = workspace:WaitForChild("HivePlatforms", 30)
if not flowerZones or not hivePlatforms then
	warn("[BSS AutoFarm] FlowerZones ou HivePlatforms não encontrados. Certifique-se de executar no BSS.")
	return
end
local CONSTANTS = {
	TOOL_COLLECT_COOLDOWN = 0.06, -- Delta pode processar clicks mais rápido
	TOOL_COLLECT_LOOP_INTERVAL = 0.04, -- Loop interval reduzido para Delta
	TOKEN_DEFAULT_MAX_DISTANCE = 60,
	TOKEN_SPEED_BOOST_NORMAL = 2.0, -- Delta teleport é mais rápido
	TOKEN_SPEED_BOOST_PRIORITY = 3.0, -- Tokens prioritários ainda mais rápidos
	TOKEN_PRIORITY_THRESHOLD = 70,
	TOKEN_COLLECT_TIMEOUT_BASE = 4, -- Timeout reduzido (Delta é mais eficiente)
	TOKEN_WAIT_AFTER_COLLECT = 0.6, -- Wait reduzido
	MOVE_CHECK_INTERVAL = 0.08, -- Check mais frequente no Delta
	STUCK_MOVEMENT_THRESHOLD = 0.5,
	BALLOON_MIN_FARM_TIME = 15,
	BALLOON_MAX_FARM_TIME = 45,
	BALLOON_POSITION_OFFSET_Y = -8,
	BALLOON_POSITION_UPDATE_INTERVAL = 1.5, -- Update mais frequente
	BALLOON_MOVEMENT_THRESHOLD = 15,
if not flowerZones or not hivePlatforms then
	warn("[BSS AutoFarm] FlowerZones ou HivePlatforms não encontrados. Certifique-se de executar no BSS.")
endART_FLOWER_SCAN_TIMEOUT = 1.5, -- Scan mais rápido
	BOSS_CHECK_INTERVAL = 1.5, -- Check mais frequente
}
local CACHED_REFS = {
	Collectibles = nil,
	Balloons = nil,
	FieldBalloons = nil,
	lastUpdate = 0
}
local function getCachedFolder(name)
	local currentTime = tick()
	if currentTime - CACHED_REFS.lastUpdate >= CONSTANTS.WORKSPACE_CACHE_TIMEOUT then
		CACHED_REFS.Collectibles = workspace:FindFirstChild("Collectibles")
		CACHED_REFS.Balloons = workspace:FindFirstChild("Balloons")
		CACHED_REFS.FieldBalloons = CACHED_REFS.Balloons
			and CACHED_REFS.Balloons:FindFirstChild("FieldBalloons") or nil
		CACHED_REFS.lastUpdate = currentTime
	end
	local folder = CACHED_REFS[name]
	if folder and folder.Parent then
		return folder
	end
	if name == "FieldBalloons" then
		local balloons = workspace:FindFirstChild("Balloons")
		folder = balloons and balloons:FindFirstChild("FieldBalloons") or nil
	else
		folder = workspace:FindFirstChild(name)
	end
	CACHED_REFS[name] = folder
	return folder
end
local FLOWER_CACHE = {
	flowers = {},
	lastScan = 0,
	currentField = nil
}
local CONFIG
local BALLOON_FARM
local function shouldContinue()
	return CONFIG and CONFIG.Enabled and not CONFIG.ManualControlMode and isCurrentSession()
end
local TOOL_COLLECT = {
	Enabled = false,
	Running = false,
	Cooldown = 0.08,
	LastCollect = 0,
	CollectCount = 0,
	LastError = nil
}
local function getEquippedCollector()
	local character = player.Character
	if not character then return nil end
	return character:FindFirstChildOfClass("Tool")
end
local GAME_COOLDOWN = {
	Base = 0.18,       -- mínimo absoluto do jogo
	Current = 0.18,
	LastSpeedCheck = 0,
}
local function updateGameCooldown()
	if tick() - GAME_COOLDOWN.LastSpeedCheck < 0.5 then return end
	GAME_COOLDOWN.LastSpeedCheck = tick()
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.WalkSpeed > 16 then
		local multiplier = humanoid.WalkSpeed / 16
		GAME_COOLDOWN.Current = math.max(GAME_COOLDOWN.Base, 0.18 / multiplier)
	else
		GAME_COOLDOWN.Current = 0.18
	end
end
local function enableToolCollect()
	if TOOL_COLLECT.Running then return end
	TOOL_COLLECT.Running = true
	task.spawn(function()
		while TOOL_COLLECT.Enabled and shouldContinue() do
			updateGameCooldown()
			local cooldown = getRandomizedTiming(
				math.max(GAME_COOLDOWN.Current, TOOL_COLLECT.Cooldown), 10
			)
			if tick() - TOOL_COLLECT.LastCollect >= cooldown then
				local clicked = fireToolCollect()
				TOOL_COLLECT.LastCollect = tick()
				if clicked then
					TOOL_COLLECT.CollectCount = TOOL_COLLECT.CollectCount + 1
					TOOL_COLLECT.LastError = nil
				else
					TOOL_COLLECT.LastError = "Cursor sobre UI ou simulação de mouse indisponível"
				end
			end
			local loopWait = getRandomizedTiming(CONSTANTS.TOOL_COLLECT_LOOP_INTERVAL, 20)
			task.wait(loopWait)
		end
		releaseToolCollectInput()
		TOOL_COLLECT.Running = false
	end)
end
local coreStats = player:WaitForChild("CoreStats", 30)
if not coreStats then
	warn("[BSS AutoFarm] CoreStats não encontrado. Tentando buscar...")
	coreStats = player.CoreStats or player:FindFirstChild("CoreStats")
	if not coreStats then
		task.wait(5)
		coreStats = player:WaitForChild("CoreStats", 15)
	end
end
local pollenValue = coreStats:WaitForChild("Pollen", 15)
local capacityValue = coreStats:WaitForChild("Capacity", 15)
local honeyValue = coreStats:WaitForChild("Honey", 15)
local function safeGetStatValue(stat, default)
	local success, value = pcall(function()
		return stat and stat.Value
	end)
	if success and type(value) == "number" then return value end
	return default or 0
end
local function safeGetPollenPercent()
	local pollenPercent = 0
	pcall(function()
		local capacity = safeGetStatValue(capacityValue)
		if capacity > 0 then
			pollenPercent = (safeGetStatValue(pollenValue) / capacity) * 100
		end
	end)
	return pollenPercent
end
CONFIG = {
	Enabled = false,
	ManualControlMode = false, -- NOVO: quando true, você pode controlar manualmente
	SelectedField = nil,
	MoveSpeed = 45,
	FieldRadius = 18,
	CollectHeight = 3,
	CollectInterval = 0.1,
	ConvertAt = 95,
	TeleportMode = false, -- quando true: teleporta em tudo (campo, tokens, colmeia)
	AutoSprinkler = false,
	CollectTokens = true,
	MaxTokenDistance = 60,
	CollectFlames = true,
	CollectMarks = true,
	WaitAtHive = 3,
	IntelligentFarm = true, -- Vai para flores melhores
	FarmMode = "Route Sweep",
	GridSize = 3,
	CoconutCatcher = false,
	CoconutCheckInterval = 1,
	FarmBalloons = false, -- Desativado por padrão (pode ser ligado na UI)
	BalloonCheckInterval = 1,
	FarmClouds = false,
	CloudCheckInterval = 3,
	SmartFlowerTargeting = false,
	AdaptToBoosts = true,
	AutoJoinBosses = false,
	AutoWindShrine = false,
	SmartHoneystorm = false,
	AntiDisconnect = true,
}
TOOL_COLLECT.Cooldown = CONSTANTS.TOOL_COLLECT_COOLDOWN
local RUNTIME = {
	Active = false,
	Stats = {
		PollenCollected = 0,
		LastPollenValue = 0,
		TokensCollected = 0,
		HoneyMade = 0,
		LastHoneyValue = 0,
		FlamesCollected = 0,
		MarksCollected = 0,
		CoconutsCaught = 0,
		BalloonsVisited = 0,
	CloudsVisited = 0,
	BossEventsParticipated = 0,
	BoostAdjustments = 0,
	WindShrineOpportunities = 0,
		Runtime = 0,
		StartTime = 0,
		LastStatsUpdate = 0
	}
}
local SMART_FLOWER_SYSTEM = {
	Enabled = false,
	FlowerHistory = {},
	DepletionTimeout = 15,
	MinFlowerValue = 5,
	ScanRadius = 50,
	ColorPreference = nil,
}
local BOOST_MANAGER = {ActiveBoosts = {}, LastCheck = 0, CheckInterval = 0.5, BaseMoveSpeed = CONFIG.MoveSpeed, BaseObservedWalkSpeed = nil}
local BOSS_EVENTS = {
	Enabled = false, Running = false, ActiveBoss = nil, LastCheck = 0,
	BossLocations = {
		["Stick Bug"] = {Zone = "Spider Field", Priority = 90},
		["Tunnel Bear"] = {Zone = "Tunnel", Priority = 85},
		["King Beetle"] = {Zone = "Clover Field", Priority = 80},
		["Coconut Crab"] = {Zone = "Coconut Field", Priority = 88},
	},
}
local EVENT_TRACKER = {
	Enabled = false, WindShrineLastDonation = 0, WindShrineCooldown = 3600,
	HoneystormLastUsed = 0, HoneystormCooldown = 1800, LastCheck = 0,
}
local ANTI_DISCONNECT = {Enabled = true, LastActivity = 0, ActivityInterval = 180, Running = false}
local function getRoot()
	return getDeltaOptimizedRoot()
end
local function getHive()
	for _, platform in ipairs(hivePlatforms:GetChildren()) do
		local playerRef = platform:FindFirstChild("PlayerRef")
		local respawn = platform:FindFirstChild("HiveRespawnPoint")
		if playerRef and respawn and respawn:IsA("BasePart") then
			local owner = nil
			if playerRef:IsA("ObjectValue") then 
				owner = playerRef.Value
			elseif playerRef:IsA("StringValue") then 
				owner = Players:FindFirstChild(playerRef.Value) 
			end
			if owner == player then return respawn end
		end
	end
	return nil
end
local getOrComputePath
local invalidatePathCache
local function tweenToFieldImpl(destination)
	if not shouldContinue() then return false end
	if CONFIG.TeleportMode then
		return teleportTo(destination)
	end
	local char = player.Character
	if not char then return false end
	local root     = char:FindFirstChild("HumanoidRootPart")
	local humanoid = char:FindFirstChild("Humanoid")
	if not root or not humanoid then return false end
	if (root.Position - destination).Magnitude <= 8 then return true end
	local waypoints, _ = getOrComputePath(root, destination)
	if waypoints and #waypoints > 1 then
		for i = 2, #waypoints do
			if not shouldContinue() or not root.Parent then return false end
			if (root.Position - destination).Magnitude <= 8 then return true end
			local wp = waypoints[i]
			if wp.Action == Enum.PathWaypointAction.Jump then
				humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
			end
			humanoid:MoveTo(wp.Position)
			local wpStart = tick()
			local lastPos = root.Position
			local stuckFor = 0
			while shouldContinue() and tick() - wpStart < 4 do
				if not root.Parent then return false end
				if (root.Position - wp.Position).Magnitude <= 5 then break end
				local moved = (root.Position - lastPos).Magnitude
				if moved < CONSTANTS.STUCK_MOVEMENT_THRESHOLD then
					stuckFor = stuckFor + CONSTANTS.MOVE_CHECK_INTERVAL
					if stuckFor >= 1.5 then invalidatePathCache() break end
				else
					stuckFor = 0
					lastPos = root.Position
				end
				task.wait(CONSTANTS.MOVE_CHECK_INTERVAL)
			end
		end
		return (root.Position - destination).Magnitude <= 12
	end
	humanoid:MoveTo(destination)
	local start = tick()
	while shouldContinue() and tick() - start < 10 do
		if not root.Parent then return false end
		if (root.Position - destination).Magnitude <= 8 then return true end
		task.wait(CONSTANTS.MOVE_CHECK_INTERVAL)
	end
	return false
end
local function tweenToField(destination, owner)
	return requestMovement(owner or "field", function()
		return tweenToFieldImpl(destination)
	end)
end
local PathfindingService = game:GetService("PathfindingService")
local PATH_CACHE = {
	destination = nil,
	waypoints   = nil,
	waypointIdx = 1,
	tolerance   = 6, -- recalcula só se destino mudou mais que 6 studs
}
getOrComputePath = function(root, destination)
	if PATH_CACHE.destination
		and (PATH_CACHE.destination - destination).Magnitude < PATH_CACHE.tolerance
		and PATH_CACHE.waypoints
		and #PATH_CACHE.waypoints > 0 then
		return PATH_CACHE.waypoints, PATH_CACHE.waypointIdx
	end
	local waypoints = nil
	pcall(function()
		local path = PathfindingService:CreatePath({
			AgentHeight     = 5,
			AgentRadius     = 2,
			AgentCanJump    = true,
			AgentCanClimb   = false,
			WaypointSpacing = 4,
		})
		path:ComputeAsync(root.Position, destination)
		if path.Status == Enum.PathStatus.Success then
			waypoints = path:GetWaypoints()
		end
	end)
	PATH_CACHE.destination = destination
	PATH_CACHE.waypoints   = waypoints
	PATH_CACHE.waypointIdx = 2 -- índice 1 é a posição atual, começa do 2
	return waypoints, 2
end
invalidatePathCache = function()
	PATH_CACHE.destination = nil
	PATH_CACHE.waypoints   = nil
end
local function moveToImpl(destination, arrivalDistance)
	local character = player.Character
	if not character then return false end
	local root     = character:FindFirstChild("HumanoidRootPart")
	local humanoid = character:FindFirstChild("Humanoid")
	if not root or not humanoid then return false end
	if CONFIG.TeleportMode then
		teleportTo(destination)
		return true
	end
	local arrived = arrivalDistance or 5
	if (root.Position - destination).Magnitude <= arrived then return true end
	humanoid:MoveTo(destination)
	local start    = tick()
	local lastPos  = root.Position
	local stuckFor = 0
	while shouldContinue() and tick() - start < 6 do
		if not root.Parent then return false end
		if (root.Position - destination).Magnitude <= arrived then return true end
		local moved = (root.Position - lastPos).Magnitude
		if moved < CONSTANTS.STUCK_MOVEMENT_THRESHOLD then
			stuckFor = stuckFor + CONSTANTS.MOVE_CHECK_INTERVAL
			if stuckFor >= 1.5 then return false end
		else
			stuckFor = 0
			lastPos  = root.Position
		end
		task.wait(CONSTANTS.MOVE_CHECK_INTERVAL)
	end
	return false
end
local function moveTo(destination, arrivalDistance, owner)
	return requestMovement(owner or "field", function()
		return moveToImpl(destination, arrivalDistance)
	end)
end
local function getFieldPosition(fieldObj)
	if fieldObj:IsA("BasePart") then
		return fieldObj.Position, fieldObj.Size
	elseif fieldObj:IsA("Model") then
		if fieldObj.PrimaryPart then
			return fieldObj.PrimaryPart.Position, fieldObj.PrimaryPart.Size
		else
			local part = fieldObj:FindFirstChildWhichIsA("BasePart", true)
			if part then return part.Position, part.Size end
		end
	end
	return nil, nil
end
local function placeSprinklerAtFieldCenter(fieldObj)
	local center = getFieldPosition(fieldObj)
	if not center then return false, "Campo sem posição válida" end
	local character = player.Character
	local backpack = player:FindFirstChildOfClass("Backpack")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not character or not backpack or not humanoid then
		return false, "Personagem ou inventário indisponível"
	end
	local previousTool = character:FindFirstChildOfClass("Tool")
	local sprinkler = nil
	for _, container in ipairs({character, backpack}) do
		for _, item in ipairs(container:GetChildren()) do
			if item:IsA("Tool") and string.find(string.lower(item.Name), "sprinkler", 1, true) then
				sprinkler = item
				break
			end
		end
		if sprinkler then break end
	end
	if not sprinkler then return false, "Nenhum sprinkler foi encontrado no inventário" end
	if not tweenToField(center + Vector3.new(0, CONFIG.CollectHeight, 0), "sprinkler") then
		return false, "Não foi possível chegar ao centro do campo"
	end
	local activated = pcall(function()
		if sprinkler.Parent == backpack then humanoid:EquipTool(sprinkler) end
		task.wait(0.15)
		sprinkler:Activate()
	end)
	if previousTool and previousTool.Parent == backpack then
		pcall(function() humanoid:EquipTool(previousTool) end)
	end
	return activated, activated and "Sprinkler ativado no centro do campo" or "Não foi possível ativar o sprinkler"
end
local function getObjectPosition(obj)
	if not obj or not obj.Parent then return nil end
	if obj:IsA("BasePart") then return obj.Position end
	if obj:IsA("Model") then
		local part = obj.PrimaryPart or obj:FindFirstChildWhichIsA("BasePart", true)
		if part then return part.Position end
	end
	return nil
end
local checkAndCollectTokens
local function readActiveBoosts()
	local boosts = {}
	local character = player.Character
	if not character then return boosts end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		BOOST_MANAGER.BaseObservedWalkSpeed = BOOST_MANAGER.BaseObservedWalkSpeed or humanoid.WalkSpeed
		boosts.Haste = humanoid.WalkSpeed > math.max(BOOST_MANAGER.BaseObservedWalkSpeed, BOOST_MANAGER.BaseMoveSpeed)
		boosts.HealthBoost = humanoid.MaxHealth > 100
	end
	for _, instance in ipairs(character:GetDescendants()) do
		local name = instance.Name:lower():gsub("%s+", "")
		local active = not instance:IsA("BoolValue") or instance.Value
		if active then
			if name:find("haste") then boosts.Haste = true end
			if name:find("blueboost") then boosts.BlueBoost = true end
			if name:find("redboost") then boosts.RedBoost = true end
			if name:find("melody") then boosts.Melody = true end
			if name:find("focus") then boosts.Focus = true end
		end
	end
	return boosts
end
local function adjustFarmingForBoosts(boosts)
	CONFIG.MoveSpeed = boosts.Haste and math.min(BOOST_MANAGER.BaseMoveSpeed * 1.5, 100) or BOOST_MANAGER.BaseMoveSpeed
	TOOL_COLLECT.Cooldown = boosts.Focus and (CONSTANTS.TOOL_COLLECT_COOLDOWN * 0.7) or CONSTANTS.TOOL_COLLECT_COOLDOWN
	SMART_FLOWER_SYSTEM.ColorPreference = boosts.BlueBoost and "Blue" or (boosts.RedBoost and "Red" or nil)
end
local function updateBoosts()
	if not CONFIG.AdaptToBoosts or tick() - BOOST_MANAGER.LastCheck < BOOST_MANAGER.CheckInterval then return end
	BOOST_MANAGER.LastCheck = tick()
	local boosts = readActiveBoosts()
	BOOST_MANAGER.ActiveBoosts = boosts
	adjustFarmingForBoosts(boosts)
	RUNTIME.Stats.BoostAdjustments = RUNTIME.Stats.BoostAdjustments + 1
end
local function detectActiveBoss()
	local npcs = workspace:FindFirstChild("NPCs")
	if not npcs then return nil end
	for _, npc in ipairs(npcs:GetChildren()) do
		local definition = BOSS_EVENTS.BossLocations[npc.Name]
		local position = getObjectPosition(npc)
		if definition and position then
			local humanoid = npc:FindFirstChildOfClass("Humanoid")
			local health = humanoid or npc:FindFirstChild("Health", true) or npc:FindFirstChild("HP", true)
			local alive = not health or (health:IsA("Humanoid") and health.Health > 0) or ((health:IsA("NumberValue") or health:IsA("IntValue")) and health.Value > 0)
			if alive then return {Name = npc.Name, Model = npc, Location = position, Priority = definition.Priority} end
		end
	end
	return nil
end
local function participateInBoss(boss)
	if BOSS_EVENTS.Running or not boss or not boss.Model.Parent then return false end
	BOSS_EVENTS.Running, BOSS_EVENTS.ActiveBoss = true, boss
	safeNotify("Boss detected", "Joining " .. boss.Name, 3)
	local reached = tweenToField(boss.Location + Vector3.new(0, CONFIG.CollectHeight, 0), "boss")
	local started = tick()
	while reached and shouldContinue() and boss.Model.Parent and tick() - started < 180 do
		local position = getObjectPosition(boss.Model)
		if position then moveTo(position + Vector3.new(0, CONFIG.CollectHeight, 0), 12, "boss") end
		checkAndCollectTokens()
		task.wait(0.5)
	end
	if shouldContinue() then
		task.wait(1)
		checkAndCollectTokens()
	end
	BOSS_EVENTS.Running, BOSS_EVENTS.ActiveBoss = false, nil
	RUNTIME.Stats.BossEventsParticipated = RUNTIME.Stats.BossEventsParticipated + 1
	return true
end
local function checkBossEvents()
	if not CONFIG.AutoJoinBosses or BOSS_EVENTS.Running or tick() - BOSS_EVENTS.LastCheck < CONSTANTS.BOSS_CHECK_INTERVAL then return false end
	BOSS_EVENTS.LastCheck = tick()
	local boss = detectActiveBoss()
	if boss then return participateInBoss(boss) end
	return false
end
local function checkWindShrine()
	if not CONFIG.AutoWindShrine or tick() - EVENT_TRACKER.WindShrineLastDonation < EVENT_TRACKER.WindShrineCooldown then return end
	local shrine = workspace:FindFirstChild("WindShrine")
	if shrine then
		local detector = shrine:FindFirstChildWhichIsA("ClickDetector", true)
		EVENT_TRACKER.WindShrineLastDonation = tick()
		RUNTIME.Stats.WindShrineOpportunities = RUNTIME.Stats.WindShrineOpportunities + 1
		safeNotify("Wind Shrine ready", detector and "Interaction detected; select the donation item in-game." or "Shrine found; interaction is not currently visible.", 5)
	end
end
local function updateEventTracker()
	if tick() - EVENT_TRACKER.LastCheck < 5 then return end
	EVENT_TRACKER.LastCheck = tick()
	checkWindShrine()
	local collectibles = getCachedFolder("Collectibles")
	if collectibles then
		for _, item in ipairs(collectibles:GetChildren()) do
			if item.Name:lower():find("honeystorm") then EVENT_TRACKER.HoneystormLastUsed = tick() break end
		end
	end
	if CONFIG.SmartHoneystorm and tick() - EVENT_TRACKER.HoneystormLastUsed >= EVENT_TRACKER.HoneystormCooldown and safeGetPollenPercent() < 50 then
		safeNotify("Honeystorm ready", "Bag is below 50%; use Honeystorm when convenient.", 5)
		EVENT_TRACKER.HoneystormLastUsed = tick()
	end
end
local BSS_EVENTS_MODULE = nil
local function getBSSEvents()
	if BSS_EVENTS_MODULE then return BSS_EVENTS_MODULE end
	pcall(function()
		BSS_EVENTS_MODULE = require(
			game:GetService("ReplicatedStorage")
			:WaitForChild("Shared", 5)
			:WaitForChild("Network", 5)
			:WaitForChild("Events", 5)
		)
	end)
	return BSS_EVENTS_MODULE
end
local HOTBAR_SYSTEM = {
	Enabled = false,
	LastUse = 0,
	Interval = 5, -- verifica a cada 5s (mesmo intervalo do MacroSystem)
	Blacklist = {
		["Sprinkler Builder"] = true, -- só usa via AutoSprinkler
		["SprinklerBuilder"]  = true,
	},
}
local function useHotbarItems()
	if not HOTBAR_SYSTEM.Enabled then return end
	if tick() - HOTBAR_SYSTEM.LastUse < HOTBAR_SYSTEM.Interval then return end
	HOTBAR_SYSTEM.LastUse = tick()
	local ok, statCache = pcall(function()
		return require(game:GetService("ReplicatedStorage")
			:WaitForChild("Client", 5)
			:WaitForChild("Systems", 5)
			:WaitForChild("ClientStatCache", 5))
	end)
	if not ok or not statCache then return end
	local stats = statCache:Get()
	if not stats or not stats.Settings or not stats.Settings.PlayerActivesBar then return end
	local evts = getBSSEvents()
	if not evts then return end
	local pollenPct = safeGetPollenPercent()
	for _, itemName in ipairs(stats.Settings.PlayerActivesBar) do
		if itemName and itemName ~= "nil" and not HOTBAR_SYSTEM.Blacklist[itemName] then
			local isMicroConverter = itemName == "Micro-Converter" or itemName == "MicroConverter"
			if not isMicroConverter or pollenPct >= 5 then
				pcall(function()
					local playerActives = require(game:GetService("ReplicatedStorage")
						:WaitForChild("Game", 5)
						:WaitForChild("ItemsAndEconomy", 5)
						:WaitForChild("PlayerActives", 5))
					local item = playerActives.Get(itemName)
					if item then
						evts.ClientCall("PlayerActivesCommand", item.Name, item.Type)
					end
				end)
			end
		end
	end
end
local function convertAtHiveRemote()
	local hive = getHive()
	if not hive then task.wait(2) return false end
	if not tweenToField(hive.Position + Vector3.new(0, 3, 0), "hive") then
		return false
	end
	task.wait(1)
	local evts = getBSSEvents()
	if evts and evts.ClientCall then
		pcall(function() evts.ClientCall("PlayerHiveCommand", "ToggleHoneyMaking") end)
	end
	local waitStart = tick()
	while tick() - waitStart < 5 do
		if player:GetAttribute("ConvertingAtHive") then break end
		task.wait(0.25)
	end
	local convertStart = tick()
	while shouldContinue() and tick() - convertStart < 120 do
		local pollen = safeGetStatValue(pollenValue)
		local cap    = safeGetStatValue(capacityValue)
		if pollen < cap * 0.01 then break end
		if not player:GetAttribute("ConvertingAtHive") then
			if pollen > cap * 0.01 then
				pcall(function()
					local e = getBSSEvents()
					if e then e.ClientCall("PlayerHiveCommand", "ToggleHoneyMaking") end
				end)
			else
				break
			end
		end
		task.wait(1)
	end
	if player:GetAttribute("ConvertingAtHive") then
		pcall(function()
			local e = getBSSEvents()
			if e then e.ClientCall("PlayerHiveCommand", "ToggleHoneyMaking") end
		end)
	end
	task.wait(CONFIG.WaitAtHive or 3)
	return true
end
local VIRTUAL_USER = nil
pcall(function() VIRTUAL_USER = game:GetService("VirtualUser") end)
local function simulateActivity()
	if VIRTUAL_USER then
		pcall(function()
			VIRTUAL_USER:CaptureController()
			VIRTUAL_USER:ClickButton2(Vector2.new())
		end)
	end
	local camera = workspace.CurrentCamera
	if camera then camera.CFrame = camera.CFrame * CFrame.Angles(0, math.rad(math.random(-3, 3)), 0) end
	if VirtualInputManager then
		pcall(function()
			VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.Space, false, nil)
			task.wait(0.05)
			VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.Space, false, nil)
		end)
		pcall(function()
			VirtualInputManager:SendMouseMoveEvent(0, 0, false, nil)
		end)
	end
end
local function getGroundY(x, z, fromY)
	local origin = Vector3.new(x, fromY or 500, z)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local char = player.Character
	if char then params.FilterDescendantsInstances = { char } end
	local result = workspace:Raycast(origin, Vector3.new(0, -600, 0), params)
	return result and result.Position.Y or nil
end
local function getAdjustedFieldPosition(fieldPart)
	local pos, size = getFieldPosition(fieldPart)
	if not pos then return nil end
	local groundY = getGroundY(pos.X, pos.Z, pos.Y + 100)
	if groundY then
		return Vector3.new(pos.X, groundY + 3, pos.Z)
	end
	return Vector3.new(pos.X, pos.Y + 3, pos.Z)
end
local function startAntiDisconnect()
	if ANTI_DISCONNECT.Running then return end
	ANTI_DISCONNECT.Running = true
	task.spawn(function()
		while ANTI_DISCONNECT.Enabled and isCurrentSession() do
			if CONFIG.AntiDisconnect and CONFIG.Enabled and tick() - ANTI_DISCONNECT.LastActivity >= ANTI_DISCONNECT.ActivityInterval then
				simulateActivity()
				ANTI_DISCONNECT.LastActivity = tick()
			end
			task.wait(30)
		end
		ANTI_DISCONNECT.Running = false
	end)
end
local SPEED_ENFORCER = {Running = false}
local function startSpeedEnforcer()
	if SPEED_ENFORCER.Running then return end
	SPEED_ENFORCER.Running = true
	task.spawn(function()
		while isCurrentSession() do
			if CONFIG.Enabled and not CONFIG.ManualControlMode then
				local char = player.Character
				if char then
					local humanoid = char:FindFirstChildOfClass("Humanoid")
					if humanoid and humanoid.WalkSpeed ~= CONFIG.MoveSpeed then
						humanoid.WalkSpeed = CONFIG.MoveSpeed
					end
				end
			end
			task.wait(0.1)
		end
		SPEED_ENFORCER.Running = false
	end)
end
local collectingToken = false
local TOKEN_COLLECTOR = {
	Enabled = false,
	Running = false,
	CheckInterval = 0.2 -- Checa tokens a cada 0.2s
}
local TOKEN_PRIORITIES = {
	["Mythic Egg"] = 100,
	["Gifted Mythic Egg"] = 100,
	["Royal Jelly"] = 90,
	["Star Jelly"] = 85,
	["Micro-Converter"] = 80,
	["Festive Bean"] = 75,
	["Jelly Bean"] = 70,
	["Inspire"] = 60,
	["Boost"] = 55,
	["Honeystorm"] = 50,
	["Pollen"] = 20,
	["Honey"] = 25,
	["Treat"] = 30,
	["Mark"] = 40,
	["Default"] = 15
}
local function startTokenCollector()
	if TOKEN_COLLECTOR.Running then return end
	TOKEN_COLLECTOR.Running = true
	task.spawn(function()
		while TOKEN_COLLECTOR.Enabled and shouldContinue() do
			local foundToken = false
			if CONFIG.CollectTokens and CONFIG.FarmMode ~= "Route Sweep" and not collectingToken then
				foundToken = checkAndCollectTokens()
			end
			task.wait(foundToken and 0.1 or 0.3)
		end
		TOKEN_COLLECTOR.Running = false
	end)
end
local function getTokenPriority(tokenName)
	for pattern, priority in pairs(TOKEN_PRIORITIES) do
		if tokenName:find(pattern) then
			return priority
		end
	end
	if tokenName:match("%d+") then
		return 35
	end
	return TOKEN_PRIORITIES["Default"]
end
local TOKEN_DEBUG_PRIORITIES = {
	["Mythic Egg"] = 100, ["Gifted Mythic Egg"] = 100,
	["Royal Jelly"] = 90, ["Star Jelly"] = 85,
	["Ticket"] = 80, ["Micro-Converter"] = 75,
	["Festive Bean"] = 73, ["Jelly Bean"] = 70,
	["Inspire"] = 60, ["Boost"] = 55, ["Honeystorm"] = 50,
	["Mark"] = 40, ["Treat"] = 30, ["Honey"] = 25, ["Pollen"] = 20,
}
local function getTokenPriorityMCP(token)
	local debugName = token:GetAttribute("DebugName")
	if debugName and TOKEN_DEBUG_PRIORITIES[debugName] then
		return TOKEN_DEBUG_PRIORITIES[debugName]
	end
	local treasureID = token:GetAttribute("TreasureID")
	if treasureID then
		if treasureID:find("Egg") then return 90 end
		if treasureID:find("Ticket") or treasureID:find("MapTreasure") then return 80 end
	end
	if token:FindFirstChild("TreasureSparkles") then return 50 end
	return getTokenPriority(token.Name)
end
local function getNearestToken(maxDistance)
	local root = getRoot()
	if not root then return nil end
	local bestToken = nil
	local bestScore = -math.huge
	local folders = {
		getCachedFolder("Collectibles"),
		workspace:FindFirstChild("TreasureCollectibles"),
	}
	for _, folder in ipairs(folders) do
		if not folder then continue end
		for _, token in ipairs(folder:GetChildren()) do
			local tokenPos = getObjectPosition(token)
			if tokenPos then
				local dist = (root.Position - tokenPos).Magnitude
				if dist < (maxDistance or 60) then
					local priority = getTokenPriorityMCP(token)
					if folder.Name == "TreasureCollectibles" then
						priority = 100
					end
					local score = priority - (dist * 0.5)
					if score > bestScore then
						bestToken = token
						bestScore = score
					end
				end
			end
		end
	end
	return bestToken
end
local function collectToken(token)
	if not token or not token.Parent then return false end
	collectingToken = true
	local tokenPos = getObjectPosition(token)
	if not tokenPos then
		collectingToken = false
		return false
	end
	local priority = getTokenPriority(token.Name)
	local root     = getRoot()
	if not root then
		collectingToken = false
		return false
	end
	local dist = (root.Position - tokenPos).Magnitude
	if priority >= 80 then
		if not moveTo(tokenPos + Vector3.new(0, 2, 0), 3, "token") then
			collectingToken = false
			return false
		end
	elseif dist > 15 then
		collectingToken = false
		return false
	end
	local waited = 0
	while token.Parent and waited < 0.8 do
		task.wait(CONSTANTS.TOOL_COLLECT_LOOP_INTERVAL)
		waited = waited + CONSTANTS.TOOL_COLLECT_LOOP_INTERVAL
	end
	collectingToken = false
	return not token.Parent
end
checkAndCollectTokens = function()
	if not CONFIG.CollectTokens or collectingToken then return false end
	local token = getNearestToken(CONFIG.MaxTokenDistance)
	if token and token.Parent then
		local tokenName = token.Name
		local priority = getTokenPriority(tokenName)
		local collected = collectToken(token)
		if collected then
			RUNTIME.Stats.TokensCollected = RUNTIME.Stats.TokensCollected + 1
			if priority >= 80 then
				Rayfield:Notify({
					Title = "💎 Valuable Token!",
					Content = "Collected: " .. tokenName,
					Duration = 2,
					Image = 4483362458,
				})
			end
		end
	end
	return token ~= nil
end
local AUTO_QUEST = {
	Enabled = false,
	Running = false,
	CheckInterval = 10,
	LastCheck = 0,
	CompletedThisSession = 0,
}
local function getQuestStats()
	local ok, statCache = pcall(function()
		return require(game:GetService("ReplicatedStorage")
			:WaitForChild("Client", 5)
			:WaitForChild("Systems", 5)
			:WaitForChild("ClientStatCache", 5))
	end)
	if not ok or not statCache then return nil end
	local stats = statCache:Get()
	if not stats or not stats.Quests then return nil end
	return stats.Quests -- { Active = {...}, Completed = {...} }
end
local function isQuestActive(questName)
	local quests = getQuestStats()
	if not quests or not quests.Active then return false end
	for _, q in ipairs(quests.Active) do
		if q.Name == questName then return true end
	end
	return false
end
local function isQuestDone(questName)
	local quests = getQuestStats()
	if not quests or not quests.Completed then return false end
	for _, name in ipairs(quests.Completed) do
		if name == questName then return true end
	end
	return false
end
local function acceptQuest(questName)
	if isQuestActive(questName) or isQuestDone(questName) then return false end
	local evts = getBSSEvents()
	if not evts then return false end
	local ok = pcall(function()
		evts.ClientCall("GiveQuest", questName)
	end)
	return ok
end
local function acceptQuestFromPool(poolName)
	local evts = getBSSEvents()
	if not evts then return false end
	local ok = pcall(function()
		evts.ClientCall("GiveQuestFromPool", poolName)
	end)
	return ok
end
local function completeQuest(questName)
	if not isQuestActive(questName) then return false end
	local evts = getBSSEvents()
	if not evts then return false end
	local ok = pcall(function()
		evts.ClientCall("CompleteQuest", questName)
	end)
	if ok then
		AUTO_QUEST.CompletedThisSession = AUTO_QUEST.CompletedThisSession + 1
		safeNotify("📋 Quest Complete!", questName, 4)
	end
	return ok
end
local function getQuestProgress(questName)
	local ok, QuestsModule = pcall(function()
		return require(game:GetService("ReplicatedStorage")
			:WaitForChild("Game", 5)
			:WaitForChild("Progression", 5)
			:WaitForChild("Quests", 5))
	end)
	if not ok or not QuestsModule then return nil end
	local ok2, statCache = pcall(function()
		return require(game:GetService("ReplicatedStorage")
			:WaitForChild("Client", 5)
			:WaitForChild("Systems", 5)
			:WaitForChild("ClientStatCache", 5))
	end)
	if not ok2 or not statCache then return nil end
	local stats = statCache:Get()
	if not stats then return nil end
	local canComplete = false
	pcall(function() canComplete = QuestsModule:CanComplete(questName, stats) end)
	return canComplete
end
local function startAutoQuest()
	if AUTO_QUEST.Running then return end
	AUTO_QUEST.Running = true
	task.spawn(function()
		while AUTO_QUEST.Enabled and shouldContinue() do
			if tick() - AUTO_QUEST.LastCheck >= AUTO_QUEST.CheckInterval then
				AUTO_QUEST.LastCheck = tick()
				local quests = getQuestStats()
				if quests then
					if quests.Active then
						for _, activeQ in ipairs(quests.Active) do
							local questName = activeQ.Name
							if questName and getQuestProgress(questName) then
								completeQuest(questName)
								task.wait(0.5)
							end
						end
					end
					local knownPools = {
						"BrownBear", "BlackBear", "MotherBear", "ScienceBear",
						"PolarBear", "PandaBear", "SpiritBear", "DapperBear",
					}
					for _, pool in ipairs(knownPools) do
						pcall(function() acceptQuestFromPool(pool) end)
						task.wait(0.1)
					end
				end
			end
			task.wait(2)
		end
		AUTO_QUEST.Running = false
	end)
end
local COCONUT_CATCHER = {
	Enabled = false,
	Running = false,
	CheckInterval = 1,
	LastCheck = 0
}
local function findCoconutCombos()
	local coconuts = {}
	local tokensFolder = workspace:FindFirstChild("Collectibles")
	if not tokensFolder then return coconuts end
	for _, token in ipairs(tokensFolder:GetChildren()) do
		if token.Name:find("Coconut") or token.Name:find("coconut") then
			local tokenPos = getObjectPosition(token)
			if tokenPos then
				table.insert(coconuts, {Token = token, Position = tokenPos})
			end
		end
	end
	return coconuts
end
local function catchCoconutCombos()
	if collectingToken then return end
	local coconuts = findCoconutCombos()
	if #coconuts == 0 then return end
	local root = getRoot()
	if not root then return end
	local nearest = nil
	local nearestDist = math.huge
	for _, coconutData in ipairs(coconuts) do
		local dist = (root.Position - coconutData.Position).Magnitude
		if dist < nearestDist and dist < CONSTANTS.COCONUT_MAX_DISTANCE then -- Max 200 studs
			nearest = coconutData
			nearestDist = dist
		end
	end
	if nearest then
		local success = collectToken(nearest.Token)
		if success then
			RUNTIME.Stats.CoconutsCaught = RUNTIME.Stats.CoconutsCaught + 1
			Rayfield:Notify({
				Title = "🥥 Coconut Caught!",
				Content = string.format("Collected coconut (%.0f studs away)", nearestDist),
				Duration = 2,
				Image = 4483362458,
			})
		end
	end
end
local function startCoconutCatcher()
	if COCONUT_CATCHER.Running then return end
	COCONUT_CATCHER.Running = true
	task.spawn(function()
		while COCONUT_CATCHER.Enabled and shouldContinue() do
			local currentTime = tick()
			if currentTime - COCONUT_CATCHER.LastCheck >= COCONUT_CATCHER.CheckInterval then
				catchCoconutCombos()
				COCONUT_CATCHER.LastCheck = currentTime
			end
			task.wait(0.5)
		end
		COCONUT_CATCHER.Running = false
	end)
end
BALLOON_FARM = {
	Enabled = false, -- Desativado por padrão (controlado pelo toggle)
	Running = false,
	IsFarming = false, -- flag: evita farm duplo (loop principal + thread)
	CheckInterval = 1, -- Verifica a cada 1 segundo
	LastCheck = 0,
	CurrentBalloon = nil,
	FarmRadius = 25, -- Raio para farmar ao redor do balão
	MinFarmTime = C