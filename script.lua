-- ═══════════════════════════════════════════════════════════════


-- Remove versões antigas
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

-- Ciclo de vida: uma nova execucao encerra as tarefas da instancia anterior.
-- O restante do script usa SESSION; _G fica restrito a esta coordenacao entre execucoes.
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

-- Aguarda o jogo carregar completamente antes de inicializar
if not game:IsLoaded() then
	game.Loaded:Wait()
end
task.wait(1) -- buffer extra para CoreGui e LocalizationService inicializarem

-- Carrega Rayfield
local RayfieldOk, Rayfield = pcall(function()
	return loadstring(game:HttpGet('https://sirius.menu/rayfield'))()
end)

if not RayfieldOk or not Rayfield then
	-- Fallback: cria stub para evitar crashes
	local function stub() end
	Rayfield = setmetatable({}, {
		__index = function(_, key)
			return function(_, ...)
				-- silent stub
				return setmetatable({}, {__index = function() return stub end})
			end
		end
	})
	warn("[BSS AutoFarm] Falha ao carregar Rayfield. UI não disponível.")
end

-- Helper function para notificações seguras
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

-- Services
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

-- ═══════════════════════════════════════════════════════════════
--             DELTA EXECUTOR NATIVE OPTIMIZATIONS
-- ═══════════════════════════════════════════════════════════════

-- Delta tem funções nativas otimizadas que são mais rápidas
local DELTA_FUNCTIONS = {
	HasMouseClick = type(mouse1click) == "function",
	HasMousePress = type(mouse1press) == "function" and type(mouse1release) == "function",
	HasGetConnections = type(getconnections) == "function",
	HasFireSignal = type(firesignal) == "function",
	HasHookFunction = type(hookfunction) == "function",
}

-- Delta Anti-Detection System
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

-- Cache de performance para Delta
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

-- Delta's optimized teleport (mais rápido que CFrame padrão)
local function deltaOptimizedTeleport(position)
	local root = getDeltaOptimizedRoot()
	if not root then return false end
	
	-- Delta processa CFrame assignments mais rápido com esse pattern
	local currentRotation = root.CFrame - root.CFrame.Position
	root.CFrame = CFrame.new(position) * currentRotation
	
	-- Delta optimization: force render update com timing humanizado
	if DELTA_ANTI_DETECT.HumanizedMovement then
		task.wait(getRandomizedTiming(0.01, 20)) -- Randomiza entre 0.008-0.012
	else
		task.wait()
	end
	
	return true
end

-- Coleta mantendo o botão esquerdo pressionado, OTIMIZADO para Delta Executor.
-- Delta tem funções nativas que são mais confiáveis que VirtualInputManager.
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

	-- PRIORIDADE 1: Delta's mouse1click (mais rápido e confiável)
	if DELTA_FUNCTIONS.HasMouseClick then
		local ok = pcall(mouse1click)
		if ok then
			COLLECT_INPUT.Held = true
			COLLECT_INPUT.Method = "delta_click"
			return true
		end
	end

	-- PRIORIDADE 2: Delta's mouse1press/release (mantém pressionado)
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

	-- FALLBACK: VirtualInputManager (menos eficiente)
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

-- Evita que duas rotinas emitam comandos de movimento ao mesmo tempo.
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

-- Teleporte instantâneo: move o HumanoidRootPart direto para a posição.
-- OTIMIZADO para Delta Executor com sua engine otimizada de CFrame
local function teleportTo(position)
	return deltaOptimizedTeleport(position)
end

-- ═══════════════════════════════════════════════════════════════
--                    REFERÊNCIAS DO JOGO
-- ═══════════════════════════════════════════════════════════════

local flowerZones = workspace:WaitForChild("FlowerZones", 30)
local hivePlatforms = workspace:WaitForChild("HivePlatforms", 30)

if not flowerZones or not hivePlatforms then
	warn("[BSS AutoFarm] FlowerZones ou HivePlatforms não encontrados. Certifique-se de executar no BSS.")
	return
end

-- ═══════════════════════════════════════════════════════════════
--                    PERFORMANCE CONSTANTS (DELTA OPTIMIZED)
-- ═══════════════════════════════════════════════════════════════
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
	-- Continua mesmo assim para carregar a UI
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

-- Centraliza a condição de continuidade das automações da sessão atual.
local function shouldContinue()
	return CONFIG and CONFIG.Enabled and not CONFIG.ManualControlMode and isCurrentSession()
end

-- ═══════════════════════════════════════════════════════════════
--                  SISTEMA DE COLETA AUTOMÁTICA (OTIMIZADO)
-- ═══════════════════════════════════════════════════════════════

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

-- MCP: cooldown mínimo real do jogo = 0.18s (descoberto em LocalCollect)
-- Ajustado dinamicamente pelo WalkSpeed (Haste boost divide o cooldown)
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
		-- Haste: WalkSpeed sobe, CollectorSpeed sobe proporcionalmente
		local multiplier = humanoid.WalkSpeed / 16
		GAME_COOLDOWN.Current = math.max(GAME_COOLDOWN.Base, 0.18 / multiplier)
	else
		GAME_COOLDOWN.Current = 0.18
	end
end

-- Função separada que roda continuamente para enviar cliques de coleta.
-- OTIMIZADA para Delta + sincronizada com cooldown real do jogo (MCP)
local function enableToolCollect()
	if TOOL_COLLECT.Running then return end
	TOOL_COLLECT.Running = true
	
	task.spawn(function()
		while TOOL_COLLECT.Enabled and shouldContinue() do
			-- MCP: respeita cooldown mínimo real do jogo (0.18s)
			updateGameCooldown()
			-- Delta: adiciona pequena variação para humanizar
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
	-- Continua mesmo sem CoreStats para carregar a UI
end
local pollenValue = coreStats:WaitForChild("Pollen", 15)
local capacityValue = coreStats:WaitForChild("Capacity", 15)
local honeyValue = coreStats:WaitForChild("Honey", 15)

-- Protege os acessos a CoreStats durante carregamento, respawn ou remoção temporária.
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

-- ═══════════════════════════════════════════════════════════════
--                         CONFIGURAÇÕES
-- ═══════════════════════════════════════════════════════════════

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
	
	-- Farm Mode
	IntelligentFarm = true, -- Vai para flores melhores
	-- Mantém o percurso previsível de 9 pontos (grade 3x3) como padrão.
	FarmMode = "Route Sweep",
	GridSize = 3,
	
	-- Coconut Catcher
	CoconutCatcher = false,
	CoconutCheckInterval = 1,
	
	-- Balloon Farm
	FarmBalloons = false, -- Desativado por padrão (pode ser ligado na UI)
	BalloonCheckInterval = 1,
	
	-- Cloud Farm
	FarmClouds = false,
	CloudCheckInterval = 3,

	-- Adaptive systems
	SmartFlowerTargeting = false,
	AdaptToBoosts = true,
	AutoJoinBosses = false,
	AutoWindShrine = false,
	SmartHoneystorm = false,
	AntiDisconnect = true,
}

-- ═══════════════════════════════════════════════════════════════
--                    PERFORMANCE CONSTANTS (JÁ DEFINIDO ACIMA)
-- ═══════════════════════════════════════════════════════════════
-- (removido duplicação - agora definido no topo do arquivo)

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

-- These systems are deliberately state-only: they never assume an undocumented
-- server remote exists, and every worker remains scoped to this session.
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

-- ═══════════════════════════════════════════════════════════════
--                      FUNÇÕES CORE
-- ═══════════════════════════════════════════════════════════════

local function getRoot()
	-- Usa o cache otimizado do Delta
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

-- Declarações antecipadas evitam que tweenToField procure versões globais
-- dessas funções antes de elas existirem como locals.
local getOrComputePath
local invalidatePathCache

-- Ir ao campo/colmeia: teleporta se TeleportMode ligado, senão CFrame direto
-- (para distâncias longas sempre usamos teleporte — andar 200 studs é perda de tempo)
-- Ir ao campo/colmeia: usa pathfinding para distâncias longas com obstáculos.
-- Para modo teleporte, vai direto via CFrame.
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

	-- Fallback: MoveTo direto
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

-- Movimento dentro do campo: anda se TeleportMode desligado (aciona Touched das flores),
-- teleporta se TeleportMode ligado.
-- PathfindingService para desviar de obstáculos no campo
local PathfindingService = game:GetService("PathfindingService")

-- Cache de path: evita recomputar para destinos parecidos
local PATH_CACHE = {
	destination = nil,
	waypoints   = nil,
	waypointIdx = 1,
	tolerance   = 6, -- recalcula só se destino mudou mais que 6 studs
}

getOrComputePath = function(root, destination)
	-- Reutiliza cache se destino não mudou muito
	if PATH_CACHE.destination
		and (PATH_CACHE.destination - destination).Magnitude < PATH_CACHE.tolerance
		and PATH_CACHE.waypoints
		and #PATH_CACHE.waypoints > 0 then
		return PATH_CACHE.waypoints, PATH_CACHE.waypointIdx
	end

	-- Recalcula
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

	-- Movimento direto: Humanoid:MoveTo sem waypoints intermediários.
	-- Dentro do campo (terreno plano) isso é suave e contínuo.
	-- Pathfinding só é usado em tweenToField (distâncias longas com obstáculos).
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

-- Posiciona um sprinkler usando a própria Tool do inventário. Tool:Activate()
-- não gera clique de mouse e, por isso, não pode acionar a interface Rayfield.
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

	-- Reequipa o coletor anterior para que o Auto Collect continue funcionando.
	if previousTool and previousTool.Parent == backpack then
		pcall(function() humanoid:EquipTool(previousTool) end)
	end

	return activated, activated and "Sprinkler ativado no centro do campo" or "Não foi possível ativar o sprinkler"
end

-- Retorna uma posição válida para partes e modelos sem repetir validações locais.
local function getObjectPosition(obj)
	if not obj or not obj.Parent then return nil end
	if obj:IsA("BasePart") then return obj.Position end
	if obj:IsA("Model") then
		local part = obj.PrimaryPart or obj:FindFirstChildWhichIsA("BasePart", true)
		if part then return part.Position end
	end
	return nil
end

-- Forward declaration: boss collection reuses the normal token collector.
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
	-- Rebuild values from their base each pass; repeated checks must not compound.
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
	-- A Honeystorm token is the only reliable client-visible confirmation here.
	local collectibles = getCachedFolder("Collectibles")
	if collectibles then
		for _, item in ipairs(collectibles:GetChildren()) do
			if item.Name:lower():find("honeystorm") then EVENT_TRACKER.HoneystormLastUsed = tick() break end
		end
	end
	if CONFIG.SmartHoneystorm and tick() - EVENT_TRACKER.HoneystormLastUsed >= EVENT_TRACKER.HoneystormCooldown and safeGetPollenPercent() < 50 then
		safeNotify("Honeystorm ready", "Bag is below 50%; use Honeystorm when convenient.", 5)
		-- Avoid repeated alerts while the item remains unused.
		EVENT_TRACKER.HoneystormLastUsed = tick()
	end
end

-- MCP: remotes descobertos no MacroSystem oficial do jogo
-- Events é um módulo com ClientCall(eventName, ...) que dispara FireServer
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

-- MCP: usa itens do hotbar via PlayerActivesCommand (descoberto no MacroSystem)
-- Isso ativa automaticamente itens como Sprinkler, Field Booster, etc.
local HOTBAR_SYSTEM = {
	Enabled = false,
	LastUse = 0,
	Interval = 5, -- verifica a cada 5s (mesmo intervalo do MacroSystem)
	-- Itens que NÃO devem ser usados automaticamente pelo hotbar
	Blacklist = {
		["Sprinkler Builder"] = true, -- só usa via AutoSprinkler
		["SprinklerBuilder"]  = true,
	},
}

local function useHotbarItems()
	if not HOTBAR_SYSTEM.Enabled then return end
	if tick() - HOTBAR_SYSTEM.LastUse < HOTBAR_SYSTEM.Interval then return end
	HOTBAR_SYSTEM.LastUse = tick()

	-- Precisa do ClientStatCache para ler o PlayerActivesBar
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
			-- Micro-Converter só usa se tiver pelo menos 5% de pollen
			local isMicroConverter = itemName == "Micro-Converter" or itemName == "MicroConverter"
			if not isMicroConverter or pollenPct >= 5 then
				pcall(function()
					-- Busca o tipo do item via PlayerActives
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

-- MCP: converte pollen usando o Remote real (PlayerHiveCommand / ToggleHoneyMaking)
local function convertAtHiveRemote()
	local hive = getHive()
	if not hive then task.wait(2) return false end

	if not tweenToField(hive.Position + Vector3.new(0, 3, 0), "hive") then
		return false
	end

	task.wait(1)

	local evts = getBSSEvents()
	if evts and evts.ClientCall then
		-- Dispara ToggleHoneyMaking (mesmo método que o macro oficial usa)
		pcall(function() evts.ClientCall("PlayerHiveCommand", "ToggleHoneyMaking") end)
	end

	-- Aguarda ConvertingAtHive ficar true
	local waitStart = tick()
	while tick() - waitStart < 5 do
		if player:GetAttribute("ConvertingAtHive") then break end
		task.wait(0.25)
	end

	-- Aguarda terminar a conversão
	local convertStart = tick()
	while shouldContinue() and tick() - convertStart < 120 do
		local pollen = safeGetStatValue(pollenValue)
		local cap    = safeGetStatValue(capacityValue)
		-- Pollen zerou ou não está mais convertendo
		if pollen < cap * 0.01 then break end
		if not player:GetAttribute("ConvertingAtHive") then
			-- Tenta ativar de novo se ainda tem pollen
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

	-- Garante que parou de converter
	if player:GetAttribute("ConvertingAtHive") then
		pcall(function()
			local e = getBSSEvents()
			if e then e.ClientCall("PlayerHiveCommand", "ToggleHoneyMaking") end
		end)
	end

	task.wait(CONFIG.WaitAtHive or 3)
	return true
end

-- MCP: VirtualUser para anti-disconnect (método que o jogo mesmo usa)
local VIRTUAL_USER = nil
pcall(function() VIRTUAL_USER = game:GetService("VirtualUser") end)

local function simulateActivity()
	-- MCP: usa VirtualUser (mais confiável que CFrame rotation)
	if VIRTUAL_USER then
		pcall(function()
			VIRTUAL_USER:CaptureController()
			VIRTUAL_USER:ClickButton2(Vector2.new())
		end)
	end
	-- Fallback: camera rotation
	local camera = workspace.CurrentCamera
	if camera then camera.CFrame = camera.CFrame * CFrame.Angles(0, math.rad(math.random(-3, 3)), 0) end
	-- Envia space key via VirtualInputManager (exatamente como o MacroSystem faz)
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

-- MCP: getGroundY via Raycast (o jogo usa isso para ajustar Y antes de teleportar)
local function getGroundY(x, z, fromY)
	local origin = Vector3.new(x, fromY or 500, z)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local char = player.Character
	if char then params.FilterDescendantsInstances = { char } end
	local result = workspace:Raycast(origin, Vector3.new(0, -600, 0), params)
	return result and result.Position.Y or nil
end

-- MCP: calcula posição de teleporte ajustando Y pelo chão real
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

-- Loop dedicado que força WalkSpeed constantemente.
-- Nada no jogo (BSS, tokens, animações, respawn) consegue interferir.
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

-- ═══════════════════════════════════════════════════════════════
--                     COLETA DE TOKENS (AVANÇADA)
-- ═══════════════════════════════════════════════════════════════

local collectingToken = false
local TOKEN_COLLECTOR = {
	Enabled = false,
	Running = false,
	CheckInterval = 0.2 -- Checa tokens a cada 0.2s
}

-- Prioridades de tokens (baseado no Atlas)
local TOKEN_PRIORITIES = {
	-- Tokens especiais (alta prioridade)
	["Mythic Egg"] = 100,
	["Gifted Mythic Egg"] = 100,
	["Royal Jelly"] = 90,
	["Star Jelly"] = 85,
	["Micro-Converter"] = 80,
	["Festive Bean"] = 75,
	["Jelly Bean"] = 70,
	
	-- Tokens de buff (média prioridade)
	["Inspire"] = 60,
	["Boost"] = 55,
	["Honeystorm"] = 50,
	
	-- Tokens normais (baixa prioridade)
	["Pollen"] = 20,
	["Honey"] = 25,
	["Treat"] = 30,
	["Mark"] = 40,
	
	-- Padrão para desconhecidos
	["Default"] = 15
}

-- Loop contínuo de coleta de tokens (separado do farm)
local function startTokenCollector()
	if TOKEN_COLLECTOR.Running then return end
	TOKEN_COLLECTOR.Running = true
	
	task.spawn(function()
		while TOKEN_COLLECTOR.Enabled and shouldContinue() do
			-- Na rota em grade, o coletor paralelo alteraria o MoveTo da rota e
			-- deixaria a caminhada travando. O ToolCollect continua coletando
			-- normalmente os tokens pelos quais o personagem passa.
			local foundToken = false
			if CONFIG.CollectTokens and CONFIG.FarmMode ~= "Route Sweep" and not collectingToken then
				foundToken = checkAndCollectTokens()
			end
			-- Quando há token, busca o próximo mais cedo; sem token, reduz uso de CPU.
			task.wait(foundToken and 0.1 or 0.3)
		end
		TOKEN_COLLECTOR.Running = false
	end)
end

local function getTokenPriority(tokenName)
	-- Verifica prioridades específicas
	for pattern, priority in pairs(TOKEN_PRIORITIES) do
		if tokenName:find(pattern) then
			return priority
		end
	end
	
	-- Prioridade especial para tokens com números (podem ser valiosos)
	if tokenName:match("%d+") then
		return 35
	end
	
	return TOKEN_PRIORITIES["Default"]
end

-- MCP: prioridade usando Attributes reais do jogo (DebugName, TreasureID)
local TOKEN_DEBUG_PRIORITIES = {
	["Mythic Egg"] = 100, ["Gifted Mythic Egg"] = 100,
	["Royal Jelly"] = 90, ["Star Jelly"] = 85,
	["Ticket"] = 80, ["Micro-Converter"] = 75,
	["Festive Bean"] = 73, ["Jelly Bean"] = 70,
	["Inspire"] = 60, ["Boost"] = 55, ["Honeystorm"] = 50,
	["Mark"] = 40, ["Treat"] = 30, ["Honey"] = 25, ["Pollen"] = 20,
}

local function getTokenPriorityMCP(token)
	-- PRIORIDADE 1: Attribute DebugName (mais confiável — descoberto via MCP)
	local debugName = token:GetAttribute("DebugName")
	if debugName and TOKEN_DEBUG_PRIORITIES[debugName] then
		return TOKEN_DEBUG_PRIORITIES[debugName]
	end
	-- PRIORIDADE 2: TreasureID pattern
	local treasureID = token:GetAttribute("TreasureID")
	if treasureID then
		if treasureID:find("Egg") then return 90 end
		if treasureID:find("Ticket") or treasureID:find("MapTreasure") then return 80 end
	end
	-- PRIORIDADE 3: TreasureSparkles = item especial
	if token:FindFirstChild("TreasureSparkles") then return 50 end
	-- FALLBACK: nome do token
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
					-- MCP: usa Attributes reais em vez de nome
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

	-- Tokens valiosos (80+): sempre vão buscar (teleporte ou anda)
	if priority >= 80 then
		if not moveTo(tokenPos + Vector3.new(0, 2, 0), 3, "token") then
			collectingToken = false
			return false
		end
	-- Tokens comuns: só coleta se estiverem perto (~15 studs), sem desviar
	elseif dist > 15 then
		collectingToken = false
		return false
	end

	-- Aguarda coleta automática (o personagem passando por cima ativa Touched)
	local waited = 0
	while token.Parent and waited < 0.8 do
		task.wait(CONSTANTS.TOOL_COLLECT_LOOP_INTERVAL)
		waited = waited + CONSTANTS.TOOL_COLLECT_LOOP_INTERVAL
	end

	collectingToken = false
	return not token.Parent
end

checkAndCollectTokens = function()
	-- Verifica se coleta de tokens está habilitada
	if not CONFIG.CollectTokens or collectingToken then return false end
	
	local token = getNearestToken(CONFIG.MaxTokenDistance)
	if token and token.Parent then
		local tokenName = token.Name
		local priority = getTokenPriority(tokenName)
		
		-- Coleta TODOS os tokens próximos (removido filtro de prioridade)
		local collected = collectToken(token)
		if collected then
			RUNTIME.Stats.TokensCollected = RUNTIME.Stats.TokensCollected + 1
			
			-- Notifica apenas para tokens MUITO valiosos (80+)
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

-- ═══════════════════════════════════════════════════════════════
--                     AUTO QUEST SYSTEM (MCP)
-- Descoberto via análise do QuestListener, NPCs e Quests modules
-- Remotes: GiveQuest, CompleteQuest, GiveQuestFromPool, CompleteQuestFromPool
-- ═══════════════════════════════════════════════════════════════

local AUTO_QUEST = {
	Enabled = false,
	Running = false,
	CheckInterval = 10,
	LastCheck = 0,
	CompletedThisSession = 0,
}

-- Lê quests ativas e completadas direto do ClientStatCache
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

-- Verifica se uma quest está ativa
local function isQuestActive(questName)
	local quests = getQuestStats()
	if not quests or not quests.Active then return false end
	for _, q in ipairs(quests.Active) do
		if q.Name == questName then return true end
	end
	return false
end

-- Verifica se uma quest está completa (já terminada permanentemente)
local function isQuestDone(questName)
	local quests = getQuestStats()
	if not quests or not quests.Completed then return false end
	for _, name in ipairs(quests.Completed) do
		if name == questName then return true end
	end
	return false
end

-- Aceita uma quest via Remote GiveQuest (mesmo caminho que os NPCs usam)
local function acceptQuest(questName)
	if isQuestActive(questName) or isQuestDone(questName) then return false end
	local evts = getBSSEvents()
	if not evts then return false end
	local ok = pcall(function()
		evts.ClientCall("GiveQuest", questName)
	end)
	return ok
end

-- Aceita uma quest de pool (repeat quests via GiveQuestFromPool)
local function acceptQuestFromPool(poolName)
	local evts = getBSSEvents()
	if not evts then return false end
	local ok = pcall(function()
		evts.ClientCall("GiveQuestFromPool", poolName)
	end)
	return ok
end

-- Entrega/completa uma quest ativa via Remote CompleteQuest
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

-- Verifica o progresso de uma quest ativa usando o módulo Quests do jogo
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

-- Loop principal do Auto Quest
local function startAutoQuest()
	if AUTO_QUEST.Running then return end
	AUTO_QUEST.Running = true

	task.spawn(function()
		while AUTO_QUEST.Enabled and shouldContinue() do
			if tick() - AUTO_QUEST.LastCheck >= AUTO_QUEST.CheckInterval then
				AUTO_QUEST.LastCheck = tick()

				local quests = getQuestStats()
				if quests then
					-- 1. Completa quests ativas que já estão prontas
					if quests.Active then
						for _, activeQ in ipairs(quests.Active) do
							local questName = activeQ.Name
							if questName and getQuestProgress(questName) then
								completeQuest(questName)
								task.wait(0.5)
							end
						end
					end

					-- 2. Aceita quests que ainda não foram iniciadas e não foram completadas
					-- (apenas quests simples que o jogo oferece automaticamente)
					-- GiveQuestFromPool não tem cooldown bloqueio — tenta pools conhecidos
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
-- ═══════════════════════════════════════════════════════════════

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
		-- Detecta coconuts pelo nome
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
	
	-- Pega o coconut mais próximo
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
		-- Coleta o coconut
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

-- ═══════════════════════════════════════════════════════════════
--                     BALLOON FARM (MELHORADO)
-- ═══════════════════════════════════════════════════════════════

BALLOON_FARM = {
	Enabled = false, -- Desativado por padrão (controlado pelo toggle)
	Running = false,
	IsFarming = false, -- flag: evita farm duplo (loop principal + thread)
	CheckInterval = 1, -- Verifica a cada 1 segundo
	LastCheck = 0,
	CurrentBalloon = nil,
	FarmRadius = 25, -- Raio para farmar ao redor do balão
	MinFarmTime = CONSTANTS.BALLOON_MIN_FARM_TIME, -- Mínimo 15 segundos por balão
	MaxFarmTime = CONSTANTS.BALLOON_MAX_FARM_TIME -- Máximo 45 segundos por balão
}

-- MCP: lê todos os atributos reais do sistema de movimento do balão
local function getBalloonInfoMCP(balloonModel)
	if not balloonModel:IsA("Model") then return nil end
	if not balloonModel:GetAttribute("ClientMotionEnabled") then return nil end

	local motionKind = balloonModel:GetAttribute("ClientMotionKind") or "Unknown"
	local balloonBody = balloonModel:FindFirstChild("BalloonBody")
	if not balloonBody or not balloonBody:IsA("BasePart") then return nil end

	local ownerRef = balloonModel:FindFirstChild("PlayerName")
	local zoneRef  = balloonModel:FindFirstChild("ZoneName")

	return {
		Model        = balloonModel,
		Body         = balloonBody,
		Position     = balloonBody.Position,
		MotionKind   = motionKind,
		IsReturning  = motionKind == "FieldBalloonReturn",
		OwnerName    = ownerRef and ownerRef:IsA("StringValue") and ownerRef.Value or "",
		Zone         = zoneRef  and zoneRef:IsA("StringValue")  and zoneRef.Value  or "Unknown",
		-- Movimento (MCP)
		HomePosition  = balloonModel:GetAttribute("ClientMotionHomePosition"),
		WanderRadius  = balloonModel:GetAttribute("ClientMotionWanderRadius") or 20,
		WanderSpeed   = balloonModel:GetAttribute("ClientMotionWanderSpeed"),
		WanderAngle   = balloonModel:GetAttribute("ClientMotionWanderAngle"),
		WanderAmpX    = balloonModel:GetAttribute("ClientMotionWanderAmpX"),
		WanderAmpZ    = balloonModel:GetAttribute("ClientMotionWanderAmpZ"),
		WanderFreqX   = balloonModel:GetAttribute("ClientMotionWanderFreqX"),
		WanderFreqZ   = balloonModel:GetAttribute("ClientMotionWanderFreqZ"),
		-- Zona de farm (MCP)
		ZoneFrame     = balloonModel:GetAttribute("ClientMotionZoneFrame"),
		ZoneHalfSize  = balloonModel:GetAttribute("ClientMotionZoneHalfSize"),
		IsCircleZone  = balloonModel:GetAttribute("ClientMotionZoneIsCircle"),
		-- Retorno (MCP)
		ReturnStartTime     = balloonModel:GetAttribute("ClientMotionReturnStartTime"),
		ReturnDuration      = balloonModel:GetAttribute("ClientMotionReturnDuration"),
		ReturnStartPosition = balloonModel:GetAttribute("ClientMotionReturnStartPosition"),
		ReturnTargetPosition= balloonModel:GetAttribute("ClientMotionReturnTargetPosition"),
		ReturnArcHeight     = balloonModel:GetAttribute("ClientMotionReturnArcHeight"),
	}
end

-- MCP: prediz posição futura do balão usando sistema real de movimento
local function predictBalloonPosition(info, secondsAhead)
	if not info or not info.Position then return info and info.Position end
	secondsAhead = secondsAhead or 1.5

	if info.IsReturning and info.ReturnStartTime and info.ReturnDuration then
		local progress = math.clamp(
			(tick() - info.ReturnStartTime + secondsAhead) / info.ReturnDuration, 0, 1
		)
		local startPos  = info.ReturnStartPosition
		local targetPos = info.ReturnTargetPosition
		local arc       = info.ReturnArcHeight or 10
		if startPos and targetPos then
			local h = startPos:Lerp(targetPos, progress)
			return h + Vector3.new(0, math.sin(progress * math.pi) * arc, 0)
		end
	end

	if info.WanderSpeed and info.WanderAngle then
		local dist  = info.WanderSpeed * secondsAhead
		local ampX  = info.WanderAmpX or 0.9
		local ampZ  = info.WanderAmpZ or 0.68
		local freqX = info.WanderFreqX or 1.03
		local freqZ = info.WanderFreqZ or 1.31
		local angle = info.WanderAngle
		return info.Position + Vector3.new(
			math.cos(angle * freqX) * dist * ampX,
			0,
			math.sin(angle * freqZ) * dist * ampZ
		)
	end

	return info.Position
end

-- MCP: detecta balões com dados completos de movimento
local function findActiveBalloons()
	local balloons = {}
	local playerName = player.Name

	local sources = {
		getCachedFolder("FieldBalloons"),
		workspace:FindFirstChild("Balloons") and workspace.Balloons:FindFirstChild("HiveBalloons") or nil,
	}

	for _, folder in ipairs(sources) do
		if not folder then continue end
		for _, balloon in ipairs(folder:GetChildren()) do
			local info = getBalloonInfoMCP(balloon)
			if info and info.OwnerName == playerName and not info.IsReturning then
				info.IsHive = folder.Name == "HiveBalloons"
				table.insert(balloons, info)
			end
		end
	end

	return balloons
end

-- MCP: calcula melhor posição de farm usando ZoneFrame real do balão
local function getBalloonFarmPos(info)
	local bodyPos = info.Body and info.Body.Parent and info.Body.Position or info.Position
	-- Se tem ZoneFrame (descoberto via MCP), usa o centro da zona
	if info.ZoneFrame and info.ZoneHalfSize then
		return Vector3.new(
			info.ZoneFrame.Position.X,
			bodyPos.Y + CONSTANTS.BALLOON_POSITION_OFFSET_Y,
			info.ZoneFrame.Position.Z
		)
	end
	-- Fallback: embaixo do balão
	return bodyPos + Vector3.new(0, CONSTANTS.BALLOON_POSITION_OFFSET_Y, 0)
end

-- MCP: verifica se posição está dentro da zona real do balão
local function isInsideBalloonZone(pos, info)
	if not info.ZoneFrame or not info.ZoneHalfSize then return true end
	local rel = info.ZoneFrame:PointToObjectSpace(pos)
	if info.IsCircleZone then
		local r = math.max(info.ZoneHalfSize.X, info.ZoneHalfSize.Z)
		return (rel.X^2 + rel.Z^2) <= r^2
	end
	return math.abs(rel.X) <= info.ZoneHalfSize.X and math.abs(rel.Z) <= info.ZoneHalfSize.Z
end

-- Farma um balão usando dados reais de movimento (MCP)
local function farmBalloon(balloonData)
	if not balloonData or not balloonData.Body or not balloonData.Body.Parent then return false end
	if not BALLOON_FARM.Enabled or not CONFIG.FarmBalloons then return false end
	if BALLOON_FARM.IsFarming then return false end
	if balloonData.IsReturning then return false end

	BALLOON_FARM.IsFarming = true

	-- MCP: usa ZoneFrame para posição precisa
	local farmPos = getBalloonFarmPos(balloonData)

	if not tweenToField(farmPos, "balloon") then
		BALLOON_FARM.IsFarming = false
		return false
	end

	if not CONFIG.Enabled then
		BALLOON_FARM.IsFarming = false
		return false
	end

	RUNTIME.Stats.BalloonsVisited = RUNTIME.Stats.BalloonsVisited + 1
	safeNotify("🎈 Balloon Found!", string.format("Farming at %s (%s)", balloonData.Zone, balloonData.MotionKind), 3)

	local farmStartTime = tick()
	local lastPosUpdate = tick()

	while shouldContinue() and BALLOON_FARM.Enabled and CONFIG.FarmBalloons
		and balloonData.Body.Parent
		and tick() - farmStartTime < BALLOON_FARM.MaxFarmTime do

		if not balloonData.Model.Parent then break end

		-- MCP: re-lê MotionKind diretamente do attribute
		if balloonData.Model:GetAttribute("ClientMotionKind") == "FieldBalloonReturn" then break end

		-- MCP: atualiza usando predição de movimento
		if tick() - lastPosUpdate > CONSTANTS.BALLOON_POSITION_UPDATE_INTERVAL then
			-- Atualiza info com atributos mais recentes
			local updatedInfo = getBalloonInfoMCP(balloonData.Model)
			if updatedInfo then
				-- Prediz posição 2s à frente para seguir o balão
				local predicted = predictBalloonPosition(updatedInfo, 2)
				if predicted then
					local newFarmPos = Vector3.new(
						predicted.X,
						predicted.Y + CONSTANTS.BALLOON_POSITION_OFFSET_Y,
						predicted.Z
					)
					-- Só move se saiu bastante da posição atual
					if (newFarmPos - farmPos).Magnitude > CONSTANTS.BALLOON_MOVEMENT_THRESHOLD then
						farmPos = newFarmPos
						moveTo(farmPos, nil, "balloon")
					end
				end
			end
			lastPosUpdate = tick()
		end

		-- MCP: move dentro da zona real do balão
		local root = getRoot()
		local offset = Vector3.new(
			math.random(-BALLOON_FARM.FarmRadius, BALLOON_FARM.FarmRadius),
			0,
			math.random(-BALLOON_FARM.FarmRadius, BALLOON_FARM.FarmRadius)
		)
		local targetPos = farmPos + offset
		-- Se tem zona definida, garante que o offset fica dentro dela
		if root and not isInsideBalloonZone(targetPos, balloonData) then
			targetPos = farmPos -- volta pro centro da zona
		end
		moveTo(targetPos, nil, "balloon")

		task.wait(1.5)

		if tick() - farmStartTime < BALLOON_FARM.MinFarmTime then continue end
		if safeGetPollenPercent() >= CONFIG.ConvertAt then break end
	end

	BALLOON_FARM.IsFarming = false
	return true
end

-- Thread de verificação contínua de balões (backup para quando o loop principal não detectar)
local function startBalloonFarm()
	if BALLOON_FARM.Running then return end
	BALLOON_FARM.Running = true
	
	task.spawn(function()
		while BALLOON_FARM.Enabled and CONFIG.FarmBalloons and shouldContinue() do
			-- Só age se o auto farm está ativo E não há farm duplo
			if CONFIG.Enabled and not BALLOON_FARM.IsFarming then
				local currentTime = tick()
				
				if currentTime - BALLOON_FARM.LastCheck >= BALLOON_FARM.CheckInterval then
					local balloons = findActiveBalloons()
					
					if #balloons > 0 then
						local root = getRoot()
						if root then
							table.sort(balloons, function(a, b)
								local distA = (root.Position - a.Position).Magnitude
								local distB = (root.Position - b.Position).Magnitude
								return distA < distB
							end)
							farmBalloon(balloons[1])
						end
					end
					
					BALLOON_FARM.LastCheck = currentTime
				end
			end
			
			task.wait(0.5)
		end
		BALLOON_FARM.Running = false
	end)
end

-- ═══════════════════════════════════════════════════════════════
--                     CLOUD FARM
-- ═══════════════════════════════════════════════════════════════

local CLOUD_FARM = {
	Enabled = false,
	Running = false,
	CheckInterval = 3,
	LastCheck = 0
}

local function findActiveClouds()
	local clouds = {}
	local cloudsFolder = workspace:FindFirstChild("Clouds")
	
	if cloudsFolder then
		for _, cloud in ipairs(cloudsFolder:GetChildren()) do
			if cloud:IsA("Model") or cloud:IsA("BasePart") then
				local cloudPart = cloud:IsA("BasePart") and cloud or cloud:FindFirstChildWhichIsA("BasePart")
				if cloudPart then
					table.insert(clouds, {Object = cloud, Part = cloudPart, Position = cloudPart.Position})
				end
			end
		end
	end
	
	-- Também procura por "Flower" que aparecem de nuvens
	local flowerClouds = workspace:FindFirstChild("FlowerClouds")
	if flowerClouds then
		for _, cloud in ipairs(flowerClouds:GetChildren()) do
			if cloud:IsA("Model") or cloud:IsA("BasePart") then
				local cloudPart = cloud:IsA("BasePart") and cloud or cloud:FindFirstChildWhichIsA("BasePart")
				if cloudPart then
					table.insert(clouds, {Object = cloud, Part = cloudPart, Position = cloudPart.Position})
				end
			end
		end
	end
	
	return clouds
end

local function farmCloud(cloudData)
	if not cloudData or not cloudData.Part.Parent then return false end
	
	local cloudPos = cloudData.Position + Vector3.new(0, -3, 0) -- Embaixo da nuvem
	
	-- Tween até a nuvem
	tweenToField(cloudPos, "cloud")
	
	if not CONFIG.Enabled then return false end
	
	RUNTIME.Stats.CloudsVisited = RUNTIME.Stats.CloudsVisited + 1
	
	-- Fica farmando embaixo da nuvem
	local farmTime = tick()
	while shouldContinue() and cloudData.Part.Parent and tick() - farmTime < 45 do
		-- Move ao redor da nuvem
		local offset = Vector3.new(math.random(-8, 8), 0, math.random(-8, 8))
		moveTo(cloudPos + offset, nil, "cloud")
		
		task.wait(1)
	end
	
	return true
end

local function startCloudFarm()
	if CLOUD_FARM.Running then return end
	CLOUD_FARM.Running = true
	
	task.spawn(function()
		while CLOUD_FARM.Enabled and shouldContinue() do
			local currentTime = tick()
			
			if currentTime - CLOUD_FARM.LastCheck >= CLOUD_FARM.CheckInterval then
				local clouds = findActiveClouds()
				
				if #clouds > 0 then
					-- Pega a nuvem mais próxima
					local root = getRoot()
					if root then
						local nearest = nil
						local nearestDist = math.huge
						
						for _, cloudData in ipairs(clouds) do
							local dist = (root.Position - cloudData.Position).Magnitude
							if dist < nearestDist then
								nearest = cloudData
								nearestDist = dist
							end
						end
						
						if nearest then
							Rayfield:Notify({
								Title = "☁️ Cloud Found!",
								Content = "Going to farm cloud...",
								Duration = 3,
								Image = 4483362458,
							})
							
							farmCloud(nearest)
						end
					end
				end
				
				CLOUD_FARM.LastCheck = currentTime
			end
			
			task.wait(1)
		end
		CLOUD_FARM.Running = false
	end)
end

-- ═══════════════════════════════════════════════════════════════
--                  FLAMES & MARKS COLLECTION
-- ═══════════════════════════════════════════════════════════════

-- Restaura todas as flags de sistemas para uma inicialização ou parada consistente.
local function resetAllSystems()
	releaseToolCollectInput()
	TOOL_COLLECT.Running = false
	TOOL_COLLECT.Enabled = false
	TOKEN_COLLECTOR.Running = false
	TOKEN_COLLECTOR.Enabled = false
	COCONUT_CATCHER.Running = false
	COCONUT_CATCHER.Enabled = false
	BALLOON_FARM.Running = false
	BALLOON_FARM.IsFarming = false
	BALLOON_FARM.Enabled = false
	CLOUD_FARM.Running = false
	CLOUD_FARM.Enabled = false
	collectingToken = false
end

local function collectNearbyFlames()
	if not CONFIG.CollectFlames then return end

	local root = getRoot()
	if not root then return end

	local flamesFolder = workspace:FindFirstChild("PlayerFlames")
	if not flamesFolder then return end

	-- Só coleta flames próximas (~10 studs) sem desviar do caminho
	for _, flame in ipairs(flamesFolder:GetChildren()) do
		if flame:IsA("BasePart") and (root.Position - flame.Position).Magnitude < 10 then
			task.wait(0.15)
			if not flame.Parent then
				RUNTIME.Stats.FlamesCollected = RUNTIME.Stats.FlamesCollected + 1
			end
		end
	end
end

local function collectNearbyMarks()
	-- Verifica se está habilitado
	if not CONFIG.CollectMarks then return end
	
	local root = getRoot()
	if not root then return end
	
	local marksFolder = workspace:FindFirstChild("Marks")
	if not marksFolder then return end
	
	for _, mark in ipairs(marksFolder:GetChildren()) do
		if mark:IsA("BasePart") and (root.Position - mark.Position).Magnitude < 25 then
			-- Marcas são coletadas automaticamente ao passar perto
			task.wait(CONSTANTS.MOVE_CHECK_INTERVAL)
			if not mark.Parent then
				RUNTIME.Stats.MarksCollected = RUNTIME.Stats.MarksCollected + 1
			end
		end
	end
end

-- ═══════════════════════════════════════════════════════════════
--                     COLETA NO CAMPO (INTELIGENTE)
-- ═══════════════════════════════════════════════════════════════

-- Detecta as MELHORES flores no campo (prioriza tamanho e polen)
-- Usa GetPartBoundsInBox para busca espacial — não itera as 11k flores do Workspace.
local function findFlowersInField(fieldObj)
	local currentTime = tick()
	if FLOWER_CACHE.currentField == fieldObj
		and currentTime - FLOWER_CACHE.lastScan < CONSTANTS.FLOWER_CACHE_TIMEOUT then
		return FLOWER_CACHE.flowers
	end

	local flowers = {}
	local fPos, fSize = getFieldPosition(fieldObj)
	if not fPos then return flowers end

	-- Raio de busca: raio do campo + margem
	local searchRadius = CONFIG.FieldRadius + 10
	-- GetPartBoundsInBox recebe (CFrame, tamanho, OverlapParams)
	-- Retorna apenas as BaseParts dentro da caixa — muito mais rápido que iterar tudo.
	local searchBox  = CFrame.new(fPos)
	local searchSize = Vector3.new(searchRadius * 2, 40, searchRadius * 2)
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	-- Filtra só a pasta Flowers para não pegar o chão, paredes, etc.
	local flowersFolder = workspace:FindFirstChild("Flowers")
	if flowersFolder then
		params:AddToFilter(flowersFolder)
	end

	local candidates = workspace:GetPartBoundsInBox(searchBox, searchSize, params)

	for _, obj in ipairs(candidates) do
		-- Flowers são BaseParts visíveis dentro da pasta
		if obj.Transparency < 0.8 then
			local dist = (obj.Position - fPos).Magnitude
			if dist <= searchRadius then
				local size     = obj.Size.Magnitude
				local priority = (size * 10) - (dist * 0.5)
				local value    = size * 10
				local color    = obj.Color
				local nectar   = obj:GetAttribute("Nectar")

				if nectar == "Red" or (not nectar and color.R > 0.8 and color.G < 0.3) then
					priority = priority + 15
				elseif nectar == "Blue" or (not nectar and color.B > 0.8) then
					priority = priority + 12
				elseif nectar == "White" or (not nectar and color.R > 0.8 and color.G > 0.8) then
					priority = priority + 20
				end

				table.insert(flowers, {
					Part     = obj,
					Position = obj.Position,
					Priority = priority,
					Distance = dist,
					Size     = size,
					Color    = color,
					Nectar   = nectar,
					Value    = value,
				})
			end
		end
	end

	table.sort(flowers, function(a, b)
		return a.Priority > b.Priority
	end)
	FLOWER_CACHE.flowers      = flowers
	FLOWER_CACHE.lastScan     = currentTime
	FLOWER_CACHE.currentField = fieldObj

	return flowers
end

local function getNextBestFlower(flowers, currentPosition)
	local now, best, bestScore = tick(), nil, -math.huge
	for _, flower in ipairs(flowers) do
		if flower.Part.Parent and flower.Value >= SMART_FLOWER_SYSTEM.MinFlowerValue then
			local lastVisited = SMART_FLOWER_SYSTEM.FlowerHistory[flower.Part] or 0
			local freshness = math.min(1, (now - lastVisited) / SMART_FLOWER_SYSTEM.DepletionTimeout)
			local distance = math.max(1, (flower.Position - currentPosition).Magnitude)
			local colorBonus = 1
			if SMART_FLOWER_SYSTEM.ColorPreference == "Blue" and (flower.Nectar == "Blue" or flower.Color.B > flower.Color.R) then colorBonus = 1.35 end
			if SMART_FLOWER_SYSTEM.ColorPreference == "Red" and (flower.Nectar == "Red" or flower.Color.R > flower.Color.B) then colorBonus = 1.35 end
			local score = flower.Value * (0.25 + freshness) * colorBonus / distance
			if score > bestScore then best, bestScore = flower, score end
		end
	end
	if best then SMART_FLOWER_SYSTEM.FlowerHistory[best.Part] = now end
	return best
end

-- Detecta GRUPOS DE POLEN densos usando grid espacial — O(n) em vez de O(n²)
local function findBestPollenArea(position, radius)
	local tokensFolder = getCachedFolder("Collectibles")
	if not tokensFolder then return nil end

	-- Coleta tokens relevantes dentro do raio
	local pollenTokens = {}
	for _, token in ipairs(tokensFolder:GetChildren()) do
		if token.Name:find("Pollen") or token.Name:find("Sparkle") or token.Name:find("Honey") then
			local tokenPos = getObjectPosition(token)
			if tokenPos and (tokenPos - position).Magnitude <= radius then
				table.insert(pollenTokens, tokenPos)
			end
		end
	end
	if #pollenTokens == 0 then return nil end

	-- Grid espacial: divide a área em células de 8 studs
	-- Cada token incrementa sua célula e as adjacentes — O(n) total
	local cellSize = 8
	local grid = {}
	local function cellKey(pos)
		return math.floor(pos.X / cellSize) .. "," .. math.floor(pos.Z / cellSize)
	end

	for _, pos in ipairs(pollenTokens) do
		local key = cellKey(pos)
		grid[key] = (grid[key] or {count = 0, center = pos})
		grid[key].count = grid[key].count + 1
		-- Atualiza centro da célula como média
		grid[key].center = (grid[key].center + pos) / 2
	end

	-- Pega a célula com mais tokens
	local bestPos   = nil
	local bestCount = 0
	for _, cell in pairs(grid) do
		if cell.count > bestCount then
			bestCount = cell.count
			bestPos   = cell.center
		end
	end

	return bestPos
end

local function buildFieldRoute(center, size)
	if not size then return {} end
	local halfX = math.max(2, math.min(CONFIG.FieldRadius, (size.X * 0.5) - 4))
	local halfZ = math.max(2, math.min(CONFIG.FieldRadius, (size.Z * 0.5) - 4))
	local route = {}
	local gridSize = math.clamp(math.floor(CONFIG.GridSize or 3), 3, 10)

	for row = 0, gridSize - 1 do
		local z = gridSize == 1 and 0 or -halfZ + ((halfZ * 2) * row / (gridSize - 1))
		-- Alternar o sentido das linhas evita que o personagem atravesse o campo inteiro.
		for step = 0, gridSize - 1 do
			local column = row % 2 == 0 and step or (gridSize - 1 - step)
			local x = gridSize == 1 and 0 or -halfX + ((halfX * 2) * column / (gridSize - 1))
			table.insert(route, center + Vector3.new(x, 0, z))
		end
	end

	return route
end

local function collectAtField(fieldObj)
	local fPos, fSize = getFieldPosition(fieldObj)
	if not fPos then return end
	
	local lastFlameCheck = tick()
	local lastMarkCheck = tick()
	local lastFlowerScan = 0
	local currentFlowers = {}
	local currentFlowerIndex = 1
	local fieldRoute = buildFieldRoute(fPos, fSize)
	local routeIndex = 1
	local routeArrivalDistance = 5
	if CONFIG.FarmMode == "Route Sweep" and fSize then
		local gridSize = math.clamp(math.floor(CONFIG.GridSize or 3), 3, 10)
		local halfX = math.max(2, math.min(CONFIG.FieldRadius, (fSize.X * 0.5) - 4))
		local halfZ = math.max(2, math.min(CONFIG.FieldRadius, (fSize.Z * 0.5) - 4))
		local pointSpacing = math.min((halfX * 2) / (gridSize - 1), (halfZ * 2) / (gridSize - 1))
		routeArrivalDistance = math.clamp(pointSpacing * 0.3, 1.25, 4)
	end
	
	-- Primeiro escaneamento
	currentFlowers = findFlowersInField(fieldObj)
	lastFlowerScan = tick()
	
	-- WATCHDOG: detecta se player foi muito longe do campo
	local maxFieldDistance = CONFIG.FieldRadius + 30 -- Tolerância extra
	local consecutiveFailedMoves = 0
	local maxConsecutiveFailures = 3 -- Se falhar 3 movimentos, sai
	
	while shouldContinue() and CONFIG.SelectedField == fieldObj do
		updateBoosts()
		updateEventTracker()
		useHotbarItems()
		if checkBossEvents() then
			-- The boss routine completed; refresh field data before normal farming resumes.
			currentFlowers, currentFlowerIndex, lastFlowerScan = findFlowersInField(fieldObj), 1, tick()
		end
		local pollenPercent = safeGetPollenPercent()
		if pollenPercent >= CONFIG.ConvertAt then
			break
		end
		
		-- WATCHDOG: Verifica se player está muito longe do campo
		local root = getRoot()
		if root then
			local distanceFromField = (root.Position - fPos).Magnitude
			if distanceFromField > maxFieldDistance then
				-- Player foi movido manualmente para longe - sai e reinicia
				break
			end
		end
		
		local currentTime = tick()

		-- Coleta flames (SE ATIVADO)
		if CONFIG.CollectFlames and currentTime - lastFlameCheck > 2 then
			collectNearbyFlames()
			lastFlameCheck = currentTime
		end
		
		-- Coleta marks (SE ATIVADO)
		if CONFIG.CollectMarks and currentTime - lastMarkCheck > 1.5 then
			collectNearbyMarks()
			lastMarkCheck = currentTime
		end
		
		-- Re-escaneia flores a cada 5 segundos para pegar NOVAS flores melhores
		if currentTime - lastFlowerScan > 20 then
			currentFlowers = findFlowersInField(fieldObj)
			currentFlowerIndex = 1
			lastFlowerScan = currentTime
		end
		
		-- PRIORIDADE 1: Vai para a MELHOR flor disponível (maior polen)
		local targetPos = nil
		
		if #currentFlowers > 0 and currentFlowerIndex <= #currentFlowers then
			local flower = CONFIG.SmartFlowerTargeting and getNextBestFlower(currentFlowers, root and root.Position or fPos) or currentFlowers[currentFlowerIndex]
			
			-- Verifica se a flor ainda existe
			if flower and flower.Part.Parent then
				targetPos = flower.Position + Vector3.new(0, CONFIG.CollectHeight, 0)
			elseif not CONFIG.SmartFlowerTargeting then
				-- Flor sumiu, vai para a próxima MELHOR
				currentFlowerIndex = currentFlowerIndex + 1
			end
		end
		
		-- PRIORIDADE 2: Se nao tem flores, procura AREA com MAIS polen no chao
		if not targetPos then
			local bestArea = findBestPollenArea(fPos, CONFIG.FieldRadius)
			if bestArea then
				targetPos = bestArea + Vector3.new(0, CONFIG.CollectHeight, 0)
			end
		end
		
		-- PRIORIDADE 3: Centro do campo (ultima opcao)
		if not targetPos then
			targetPos = fPos + Vector3.new(0, CONFIG.CollectHeight, 0)
		end

		-- Smart targeting deliberately takes precedence over the predictable grid route.
		if not CONFIG.SmartFlowerTargeting and CONFIG.FarmMode == "Route Sweep" and #fieldRoute > 0 then
			local root = getRoot()
			local routeTarget = fieldRoute[routeIndex]
			if root and (root.Position - routeTarget).Magnitude <= 7 then
				routeIndex = (routeIndex % #fieldRoute) + 1
				routeTarget = fieldRoute[routeIndex]
			end
			targetPos = routeTarget + Vector3.new(0, CONFIG.CollectHeight, 0)
		end

		-- Move para a posicao OTIMA e verifica se conseguiu
		local moveSuccess = moveTo(targetPos, (not CONFIG.SmartFlowerTargeting and CONFIG.FarmMode == "Route Sweep") and routeArrivalDistance or nil)
		
		if not moveSuccess then
			-- Movimento falhou (player parado, obstáculo ou movimento manual)
			consecutiveFailedMoves = consecutiveFailedMoves + 1
			if consecutiveFailedMoves >= maxConsecutiveFailures then
				-- Muitas falhas consecutivas - sai e reinicia
				break
			end
		else
			-- Movimento OK, reseta contador
			consecutiveFailedMoves = 0
		end
		
		if not CONFIG.Enabled then return end
		
		-- Fica coletando por um tempo antes de reavaliação
		task.wait(CONFIG.CollectInterval) 
	end
end

local function convertAtHive()
	-- MCP: usa Remote real + ConvertingAtHive attribute
	convertAtHiveRemote()
end

-- ═══════════════════════════════════════════════════════════════
--                     LOOP PRINCIPAL
-- ═══════════════════════════════════════════════════════════════

local function automationLoop()
	if SESSION.AutomationRunning then return end
	SESSION.AutomationRunning = true
	RUNTIME.Active = true
	local currentTime = tick()
	RUNTIME.Stats.StartTime = currentTime
	RUNTIME.Stats.LastStatsUpdate = currentTime
	RUNTIME.Stats.LastPollenValue = safeGetStatValue(pollenValue)
	RUNTIME.Stats.LastHoneyValue = safeGetStatValue(honeyValue)
	
	-- Inicia o sistema de coleta contínuo
	TOOL_COLLECT.Enabled = true
	enableToolCollect()
	startAntiDisconnect()
	startSpeedEnforcer()
	
	-- Inicia o coletor de tokens contínuo
	TOKEN_COLLECTOR.Enabled = true
	startTokenCollector()
	
	-- Inicia Auto Quest se habilitado
	if AUTO_QUEST.Enabled then
		startAutoQuest()
	end
	
	-- Inicia sistemas especiais (se habilitados)
	if CONFIG.CoconutCatcher then
		COCONUT_CATCHER.Enabled = true
		startCoconutCatcher()
	end
	
	-- Balloon farm (se habilitado)
	if CONFIG.FarmBalloons then
		BALLOON_FARM.Enabled = true
		startBalloonFarm()
	end
	
	if CONFIG.FarmClouds then
		CLOUD_FARM.Enabled = true
		startCloudFarm()
	end
	
	while shouldContinue() do
		if not CONFIG.SelectedField or not CONFIG.SelectedField.Parent then 
			task.wait(0.5)
		elseif safeGetPollenPercent() >= CONFIG.ConvertAt then
			-- Atualiza pólen coletado antes de converter
			local currentPollen = safeGetStatValue(pollenValue)
			if currentPollen > RUNTIME.Stats.LastPollenValue then
				RUNTIME.Stats.PollenCollected = RUNTIME.Stats.PollenCollected + (currentPollen - RUNTIME.Stats.LastPollenValue)
			end
			RUNTIME.Stats.LastPollenValue = 0
			
			convertAtHive()
			
			-- Atualiza mel gerado após converter
			local currentHoney = safeGetStatValue(honeyValue)
			if currentHoney > RUNTIME.Stats.LastHoneyValue then
				RUNTIME.Stats.HoneyMade = RUNTIME.Stats.HoneyMade + (currentHoney - RUNTIME.Stats.LastHoneyValue)
			end
			RUNTIME.Stats.LastHoneyValue = currentHoney
		else
			-- Atualiza pólen durante farm
			local currentPollen = safeGetStatValue(pollenValue)
			if currentPollen > RUNTIME.Stats.LastPollenValue then
				RUNTIME.Stats.PollenCollected = RUNTIME.Stats.PollenCollected + (currentPollen - RUNTIME.Stats.LastPollenValue)
			end
			RUNTIME.Stats.LastPollenValue = currentPollen
			
			-- ── VERIFICA BALLOON ANTES DE FARMAR CAMPO ──────────────────
			-- Balloons têm prioridade: mais pollen por segundo que campo normal
			if CONFIG.FarmBalloons then
				local activeBalloons = findActiveBalloons()
				if #activeBalloons > 0 then
					-- Ordena por proximidade
					local root = getRoot()
					if root then
						table.sort(activeBalloons, function(a, b)
							return (root.Position - a.Position).Magnitude
								< (root.Position - b.Position).Magnitude
						end)
						local balloon = activeBalloons[1]
						-- Interrompe farm de campo e vai para o balloon
						farmBalloon(balloon)
						-- Após balloon farm, continua no loop normalmente
						task.wait(0.1)
						continue
					end
				end
			end
			-- ─────────────────────────────────────────────────────────────
			
			local fPos = getFieldPosition(CONFIG.SelectedField)
			if fPos then
				-- MCP: ajusta Y pelo chão real antes de teleportar (como o MacroSystem faz)
				local adjustedPos = getAdjustedFieldPosition(CONFIG.SelectedField) or (fPos + Vector3.new(0, 3, 0))
				invalidatePathCache()
				tweenToField(adjustedPos)
				
				if shouldContinue() then
					-- Depois ANDA normalmente no campo
					collectAtField(CONFIG.SelectedField)
				end
			else
				task.wait(0.5)
			end
		end
		task.wait(0.1)
	end
	
	resetAllSystems()
	
	RUNTIME.Active = false
	SESSION.AutomationRunning = false
	CONFIG.Enabled = false
end

-- ═══════════════════════════════════════════════════════════════
--                    INTERFACE RAYFIELD
-- ═══════════════════════════════════════════════════════════════

local Window = Rayfield:CreateWindow({
	Name = "🐝 BSS Auto Farm - Delta Optimized",
	LoadingTitle = "Bee Swarm Simulator",
	LoadingSubtitle = "Optimized for Delta Executor",
	ConfigurationSaving = {
		Enabled = false,
		FolderName = nil,
		FileName = "BSS_AutoFarm_Delta"
	},
	Discord = {
		Enabled = false,
		Invite = "",
		RememberJoins = false
	},
	KeySystem = false,
})

-- ═══════════════════════════════════════════════════════════════
--                         TAB: FARMING
-- ═══════════════════════════════════════════════════════════════

local FarmTab = Window:CreateTab("🌻 Farming", 4483362458)
local FarmSection = FarmTab:CreateSection("Auto Farm Settings")

-- Campo selecionado
local fieldNames = {}
for _, zone in ipairs(flowerZones:GetChildren()) do 
	if zone:IsA("BasePart") or zone:IsA("Model") then 
		table.insert(fieldNames, zone.Name)
	end 
end
table.sort(fieldNames)

local FieldDropdown = FarmTab:CreateDropdown({
	Name = "📍 Select Field",
	Options = fieldNames,
	CurrentOption = {fieldNames[1] or "None"},
	MultipleOptions = false,
	Flag = "FieldDropdown",
	Callback = function(Option)
		local selectedName = Option[1]
		for _, zone in ipairs(flowerZones:GetChildren()) do
			if zone.Name == selectedName then
				CONFIG.SelectedField = zone
				Rayfield:Notify({
					Title = "Field Selected",
					Content = "Now farming at: " .. selectedName,
					Duration = 3,
					Image = 4483362458,
				})
				break
			end
		end
	end,
})

-- Inicializa campo padrão
if fieldNames[1] then
	for _, zone in ipairs(flowerZones:GetChildren()) do
		if zone.Name == fieldNames[1] then
			CONFIG.SelectedField = zone
			break
		end
	end
end

FarmTab:CreateToggle({
	Name = "💧 Auto Sprinkler at Field Center",
	CurrentValue = CONFIG.AutoSprinkler,
	Flag = "AutoSprinkler",
	Callback = function(Value)
		CONFIG.AutoSprinkler = Value
		safeNotify(
			Value and "Auto Sprinkler ON" or "Auto Sprinkler OFF",
			Value and "O sprinkler será ativado antes do farm começar" or "Sprinkler não será ativado automaticamente",
			2
		)
	end,
})

-- Toggle Auto Farm
local FarmToggle = FarmTab:CreateToggle({
	Name = "▶️ Enable Auto Farm",
	CurrentValue = false,
	Flag = "AutoFarmToggle",
	Callback = function(Value)
		if Value then
			if SESSION.AutomationRunning then
				Rayfield:Notify({
					Title = "Auto Farm Already Running",
					Content = "The current session is still active.",
					Duration = 3,
					Image = 4483362458,
				})
				return
			end

			if not CONFIG.SelectedField then
				CONFIG.Enabled = false
				Rayfield:Notify({
					Title = "⚠️ No Field Selected",
					Content = "Please select a field first!",
					Duration = 4,
					Image = 4483362458,
				})
				FarmToggle:Set(false)
				return
			end
			
			-- Reseta os sistemas antes de permitir uma nova sessão.
			resetAllSystems()
			
			-- Liga os sistemas antes de iniciar o loop
			CONFIG.Enabled = true
			if CONFIG.AutoSprinkler then
				local placed, message = placeSprinklerAtFieldCenter(CONFIG.SelectedField)
				if not placed then
					CONFIG.Enabled = false
					FarmToggle:Set(false)
					safeNotify("⚠️ Auto Farm não iniciado", "Sprinkler: " .. message, 4)
					return
				end
				safeNotify("💧 " .. message, "Iniciando Auto Farm", 2)
			end
			TOOL_COLLECT.Enabled = true
			TOKEN_COLLECTOR.Enabled = true
			-- Balloon farm só liga se estiver habilitado no toggle
			if CONFIG.FarmBalloons then
				BALLOON_FARM.Enabled = true
			end
			
			Rayfield:Notify({
				Title = "✅ Auto Farm Started",
				Content = "Farming at " .. CONFIG.SelectedField.Name,
				Duration = 3,
				Image = 4483362458,
			})
			
			task.spawn(automationLoop)
		else
			CONFIG.Enabled = false
			SESSION.AutomationRunning = false
			resetAllSystems()
			
			-- Para o movimento do personagem
			local character = player.Character
			if character then
				local humanoid = character:FindFirstChild("Humanoid")
				if humanoid then
					humanoid:Move(Vector3.new(0, 0, 0)) -- Para o movimento
				end
			end
			
			Rayfield:Notify({
				Title = "⏹️ Auto Farm Stopped",
				Content = "Farming has been disabled",
				Duration = 3,
				Image = 4483362458,
			})
		end
	end,
})

FarmTab:CreateSection("⚙️ Settings")



FarmTab:CreateToggle({
	Name = "⚡ Teleport Mode",
	CurrentValue = false,
	Flag = "TeleportMode",
	Callback = function(Value)
		CONFIG.TeleportMode = Value
		safeNotify(
			Value and "⚡ Teleport Mode ON" or "🚶 Walk Mode ON",
			Value and "Teleportando para flores e tokens" or "Andando normalmente no campo",
			2
		)
	end,
})

FarmTab:CreateDropdown({
	Name = "Farm Movement Mode",
	Options = {"Smart Flowers", "Route Sweep"},
	CurrentOption = {CONFIG.FarmMode},
	MultipleOptions = false,
	Flag = "FarmMovementMode",
	Callback = function(Option)
		CONFIG.FarmMode = Option[1] or "Smart Flowers"
	end,
})



FarmTab:CreateSlider({
	Name = "Route Grid Size",
	Range = {3, 10},
	Increment = 1,
	Suffix = " x grid",
	CurrentValue = CONFIG.GridSize,
	Flag = "RouteGridSize",
	Callback = function(Value)
		CONFIG.GridSize = Value
	end,
})

-- Auto Collect Toggle
local AutoCollectToggle = FarmTab:CreateToggle({
	Name = "⚡ Auto Collect (ToolCollect)",
	CurrentValue = true,
	Flag = "AutoCollectToggle",
	Callback = function(Value)
		TOOL_COLLECT.Enabled = Value
		
		if Value then
			enableToolCollect()
		else
			releaseToolCollectInput()
		end
		
		Rayfield:Notify({
			Title = Value and "✅ Auto Collect ON" or "⛔ Auto Collect OFF",
			Content = Value and "ToolCollect running continuously" or "Manual collection only",
			Duration = 2,
			Image = 4483362458,
		})
	end,
})

-- Velocidade
local SpeedSlider = FarmTab:CreateSlider({
	Name = "Movement Speed",
	Range = {20, 100},
	Increment = 5,
	Suffix = " speed",
	CurrentValue = 45,
	Flag = "SpeedSlider",
	Callback = function(Value)
		CONFIG.MoveSpeed = Value
		BOOST_MANAGER.BaseMoveSpeed = Value
	end,
})

-- Convert At
local ConvertSlider = FarmTab:CreateSlider({
	Name = "Convert At",
	Range = {80, 100},
	Increment = 5,
	Suffix = "%",
	CurrentValue = 95,
	Flag = "ConvertSlider",
	Callback = function(Value)
		CONFIG.ConvertAt = Value
	end,
})

-- Field Radius
local RadiusSlider = FarmTab:CreateSlider({
	Name = "Farm Radius",
	Range = {10, 40},
	Increment = 2,
	Suffix = " studs",
	CurrentValue = 18,
	Flag = "RadiusSlider",
	Callback = function(Value)
		CONFIG.FieldRadius = Value
	end,
})

-- Wait at Hive
local HiveWaitSlider = FarmTab:CreateSlider({
	Name = "Wait at Hive",
	Range = {1, 10},
	Increment = 1,
	Suffix = " seconds",
	CurrentValue = 3,
	Flag = "HiveWaitSlider",
	Callback = function(Value)
		CONFIG.WaitAtHive = Value
	end,
})

-- ═══════════════════════════════════════════════════════════════
--                       TAB: COLLECTIBLES
-- ═══════════════════════════════════════════════════════════════

local CollectTab = Window:CreateTab("🪙 Collectibles", 4483362458)
local CollectSection = CollectTab:CreateSection("🪙 Tokens")

local TokenToggle = CollectTab:CreateToggle({
	Name = "🪙 Collect Tokens",
	CurrentValue = true,
	Flag = "TokenToggle",
	Callback = function(Value)
		CONFIG.CollectTokens = Value
		
		Rayfield:Notify({
			Title = Value and "✅ Token Collection ON" or "⛔ Token Collection OFF",
			Content = Value and "Will collect nearby tokens" or "Tokens will be ignored",
			Duration = 2,
			Image = 4483362458,
		})
	end,
})

local TokenDistSlider = CollectTab:CreateSlider({
	Name = "Token Detection Range",
	Range = {20, 100},
	Increment = 10,
	Suffix = " studs",
	CurrentValue = 60,
	Flag = "TokenDistSlider",
	Callback = function(Value)
		CONFIG.MaxTokenDistance = Value
	end,
})

local TokenCheckSlider = CollectTab:CreateSlider({
	Name = "Token Check Interval",
	Range = {0.1, 1},
	Increment = 0.1,
	Suffix = " seconds",
	CurrentValue = 0.2,
	Flag = "TokenCheckSlider",
	Callback = function(Value)
		TOKEN_COLLECTOR.CheckInterval = Value
	end,
})



CollectTab:CreateSection("🔥 Flames")

local FlamesToggle = CollectTab:CreateToggle({
	Name = "🔥 Collect Flames",
	CurrentValue = true,
	Flag = "FlamesToggle",
	Callback = function(Value)
		CONFIG.CollectFlames = Value
		
		Rayfield:Notify({
			Title = Value and "✅ Flame Collection ON" or "⛔ Flame Collection OFF",
			Content = Value and "Will collect PlayerFlames" or "Flames will be ignored",
			Duration = 2,
			Image = 4483362458,
		})
	end,
})



CollectTab:CreateSection("✨ Marks")

local MarksToggle = CollectTab:CreateToggle({
	Name = "✨ Collect Marks",
	CurrentValue = true,
	Flag = "MarksToggle",
	Callback = function(Value)
		CONFIG.CollectMarks = Value
		
		Rayfield:Notify({
			Title = Value and "✅ Mark Collection ON" or "⛔ Mark Collection OFF",
			Content = Value and "Will collect ability marks" or "Marks will be ignored",
			Duration = 2,
			Image = 4483362458,
		})
	end,
})



-- ═══════════════════════════════════════════════════════════════
--                       TAB: SPECIAL FEATURES
-- ═══════════════════════════════════════════════════════════════

local SpecialTab = Window:CreateTab("⭐ Special", 4483362458)

SpecialTab:CreateSection("📋 Auto Quest")

SpecialTab:CreateToggle({
	Name = "📋 Auto Quest",
	CurrentValue = false,
	Flag = "AutoQuestToggle",
	Callback = function(Value)
		AUTO_QUEST.Enabled = Value
		if Value and CONFIG.Enabled then
			startAutoQuest()
		end
		safeNotify(
			Value and "📋 Auto Quest ON" or "📋 Auto Quest OFF",
			Value and "Aceita e entrega quests automaticamente" or "Auto Quest desativado",
			3
		)
	end,
})

SpecialTab:CreateSlider({
	Name = "Quest Check Interval",
	Range = {5, 60},
	Increment = 5,
	Suffix = "s",
	CurrentValue = 10,
	Flag = "QuestCheckInterval",
	Callback = function(Value)
		AUTO_QUEST.CheckInterval = Value
	end,
})

SpecialTab:CreateSection("🥥 Coconut Combo Catcher")

local CoconutToggle = SpecialTab:CreateToggle({
	Name = "🥥 Auto-Catch Coconuts",
	CurrentValue = false,
	Flag = "CoconutToggle",
	Callback = function(Value)
		CONFIG.CoconutCatcher = Value
		COCONUT_CATCHER.Enabled = Value
		
		if Value and CONFIG.Enabled then
			startCoconutCatcher()
		end
		
		Rayfield:Notify({
			Title = Value and "✅ Coconut Catcher ON" or "⛔ Coconut Catcher OFF",
			Content = Value and "Will auto-catch combo coconuts!" or "Coconuts will be ignored",
			Duration = 3,
			Image = 4483362458,
		})
	end,
})



SpecialTab:CreateSection("🎈 Balloon Farming")



local BalloonToggle = SpecialTab:CreateToggle({
	Name = "🎈 Farm Balloons",
	CurrentValue = false, -- começa desativado
	Flag = "BalloonToggle",
	Callback = function(Value)
		CONFIG.FarmBalloons = Value
		BALLOON_FARM.Enabled = Value
		
		if Value and CONFIG.Enabled then
			-- Reseta flag para permitir reinicialização
			BALLOON_FARM.Running = false
			startBalloonFarm()
		end
		
		safeNotify(
			Value and "✅ Balloon Farm ON" or "⛔ Balloon Farm OFF",
			Value and "Will farm your balloons automatically!" or "Balloons will be ignored",
			3
		)
	end,
})

SpecialTab:CreateSection("☁️ Cloud Farming")

local CloudToggle = SpecialTab:CreateToggle({
	Name = "☁️ Farm Clouds",
	CurrentValue = false,
	Flag = "CloudToggle",
	Callback = function(Value)
		CONFIG.FarmClouds = Value
		CLOUD_FARM.Enabled = Value
		
		if Value and CONFIG.Enabled then
			startCloudFarm()
		end
		
		Rayfield:Notify({
			Title = Value and "✅ Cloud Farm ON" or "⛔ Cloud Farm OFF",
			Content = Value and "Will farm under clouds!" or "Clouds will be ignored",
			Duration = 3,
			Image = 4483362458,
		})
	end,
})



SpecialTab:CreateSection("⚙️ Special Settings")

local CoconutIntervalSlider = SpecialTab:CreateSlider({
	Name = "Coconut Check Interval",
	Range = {0.5, 5},
	Increment = 0.5,
	Suffix = " seconds",
	CurrentValue = 1,
	Flag = "CoconutIntervalSlider",
	Callback = function(Value)
		COCONUT_CATCHER.CheckInterval = Value
		CONFIG.CoconutCheckInterval = Value
	end,
})

local BalloonIntervalSlider = SpecialTab:CreateSlider({
	Name = "Balloon Check Interval",
	Range = {1, 10},
	Increment = 1,
	Suffix = " seconds",
	CurrentValue = 2,
	Flag = "BalloonIntervalSlider",
	Callback = function(Value)
		BALLOON_FARM.CheckInterval = Value
		CONFIG.BalloonCheckInterval = Value
	end,
})

local CloudIntervalSlider = SpecialTab:CreateSlider({
	Name = "Cloud Check Interval",
	Range = {1, 10},
	Increment = 1,
	Suffix = " seconds",
	CurrentValue = 3,
	Flag = "CloudIntervalSlider",
	Callback = function(Value)
		CLOUD_FARM.CheckInterval = Value
		CONFIG.CloudCheckInterval = Value
	end,
})

-- ═══════════════════════════════════════════════════════════════
--                         TAB: ADVANCED
-- ═══════════════════════════════════════════════════════════════

local AdvancedTab = Window:CreateTab("⚙️ Advanced", 4483362458)
local AdvancedSection = AdvancedTab:CreateSection("⚡ Delta Optimizations")

AdvancedTab:CreateToggle({
	Name = "🎯 Humanized Movement Timing",
	CurrentValue = DELTA_ANTI_DETECT.HumanizedMovement,
	Flag = "HumanizedMovement",
	Callback = function(Value)
		DELTA_ANTI_DETECT.HumanizedMovement = Value
		safeNotify(
			Value and "🎯 Humanized Movement ON" or "⚡ Fast Movement ON",
			Value and "Movements will look more human-like" or "Maximum speed (higher detection risk)",
			3
		)
	end,
})

AdvancedTab:CreateToggle({
	Name = "🎲 Randomize Action Timings",
	CurrentValue = DELTA_ANTI_DETECT.RandomizeTimings,
	Flag = "RandomizeTimings",
	Callback = function(Value)
		DELTA_ANTI_DETECT.RandomizeTimings = Value
		safeNotify(
			Value and "🎲 Randomized Timing ON" or "⏱️ Fixed Timing ON",
			Value and "Actions will have slight random delays" or "Fixed timing intervals (faster but detectable)",
			3
		)
	end,
})

AdvancedTab:CreateSection("🔧 Advanced Settings")

AdvancedTab:CreateToggle({
	Name = "Smart Flower Targeting", CurrentValue = CONFIG.SmartFlowerTargeting, Flag = "SmartFlowerTargeting",
	Callback = function(Value) CONFIG.SmartFlowerTargeting = Value; SMART_FLOWER_SYSTEM.Enabled = Value end,
})

AdvancedTab:CreateToggle({
	Name = "Adapt to Active Boosts", CurrentValue = CONFIG.AdaptToBoosts, Flag = "AdaptToBoosts",
	Callback = function(Value)
		CONFIG.AdaptToBoosts = Value
		if not Value then adjustFarmingForBoosts({}) end
	end,
})

AdvancedTab:CreateToggle({
	Name = "Auto-Join Boss Events", CurrentValue = CONFIG.AutoJoinBosses, Flag = "AutoJoinBosses",
	Callback = function(Value) CONFIG.AutoJoinBosses = Value; BOSS_EVENTS.Enabled = Value end,
})

AdvancedTab:CreateToggle({
	Name = "🎒 Auto Use Hotbar Items",
	CurrentValue = false,
	Flag = "AutoHotbarItems",
	Callback = function(Value)
		HOTBAR_SYSTEM.Enabled = Value
		safeNotify(
			Value and "🎒 Hotbar Items ON" or "🎒 Hotbar Items OFF",
			Value and "Itens do hotbar serão usados automaticamente" or "Hotbar desativado",
			3
		)
	end,
})

AdvancedTab:CreateToggle({
	Name = "Wind Shrine Availability Alerts", CurrentValue = CONFIG.AutoWindShrine, Flag = "AutoWindShrine",
	Callback = function(Value) CONFIG.AutoWindShrine = Value; EVENT_TRACKER.Enabled = Value end,
})

AdvancedTab:CreateToggle({
	Name = "Smart Honeystorm Alerts", CurrentValue = CONFIG.SmartHoneystorm, Flag = "SmartHoneystorm",
	Callback = function(Value) CONFIG.SmartHoneystorm = Value; EVENT_TRACKER.Enabled = Value end,
})

AdvancedTab:CreateToggle({
	Name = "Anti-Disconnect Activity", CurrentValue = CONFIG.AntiDisconnect, Flag = "AntiDisconnect",
	Callback = function(Value)
		CONFIG.AntiDisconnect = Value
		if Value then startAntiDisconnect() end
	end,
})



-- Collect Height
local CollectHeightSlider = AdvancedTab:CreateSlider({
	Name = "Collect Height",
	Range = {0, 10},
	Increment = 1,
	Suffix = " studs",
	CurrentValue = 3,
	Flag = "CollectHeightSlider",
	Callback = function(Value)
		CONFIG.CollectHeight = Value
	end,
})

-- Collect Interval
local CollectIntervalSlider = AdvancedTab:CreateSlider({
	Name = "Farm Move Interval",
	Range = {0.05, 0.5},
	Increment = 0.05,
	Suffix = " seconds",
	CurrentValue = 0.1,
	Flag = "CollectIntervalSlider",
	Callback = function(Value)
		CONFIG.CollectInterval = Value
	end,
})

-- ToolCollect Cooldown
local ToolCooldownSlider = AdvancedTab:CreateSlider({
	Name = "ToolCollect Cooldown",
	Range = {0.05, 0.2},
	Increment = 0.01,
	Suffix = " seconds",
	CurrentValue = 0.08,
	Flag = "ToolCooldownSlider",
	Callback = function(Value)
		TOOL_COLLECT.Cooldown = Value
	end,
})



-- ═══════════════════════════════════════════════════════════════
--                         TAB: INFO
-- ═══════════════════════════════════════════════════════════════

local InfoTab = Window:CreateTab("ℹ️ Info", 4483362458)
InfoTab:CreateSection("Delta Optimizations")

InfoTab:CreateButton({
	Name = "⚡ Check Delta Features",
	Callback = function()
		local features = {
			"Mouse Functions:",
			DELTA_FUNCTIONS.HasMouseClick and "  ✓ mouse1click: ACTIVE (BEST)" or "  ✗ mouse1click: NOT FOUND",
			DELTA_FUNCTIONS.HasMousePress and "  ✓ mouse1press/release: ACTIVE" or "  ✗ mouse1press/release: NOT FOUND",
			"",
			"Advanced Functions:",
			DELTA_FUNCTIONS.HasGetConnections and "  ✓ getconnections: ACTIVE" or "  ✗ getconnections: NOT FOUND",
			DELTA_FUNCTIONS.HasFireSignal and "  ✓ firesignal: ACTIVE" or "  ✗ firesignal: NOT FOUND",
			DELTA_FUNCTIONS.HasHookFunction and "  ✓ hookfunction: ACTIVE" or "  ✗ hookfunction: NOT FOUND",
			"",
			"Performance:",
			"  ✓ Delta Cache System: ACTIVE",
			"  ✓ Optimized CFrame: ACTIVE",
			"  ✓ Humanized Timing: " .. (DELTA_ANTI_DETECT.HumanizedMovement and "ACTIVE" or "DISABLED"),
			"  ✓ Randomized Cooldowns: " .. (DELTA_ANTI_DETECT.RandomizeTimings and "ACTIVE" or "DISABLED"),
		}
		
		local message = table.concat(features, "\n")
		
		Rayfield:Notify({
			Title = "⚡ Delta Executor Status",
			Content = "Check console (F9) for full report",
			Duration = 4,
			Image = 4483362458,
		})
		
		print("\n" .. string.rep("═", 60))
		print("DELTA EXECUTOR OPTIMIZATION REPORT")
		print(string.rep("═", 60))
		print(message)
		print(string.rep("═", 60) .. "\n")
	end,
})

InfoTab:CreateSection("Tools")

InfoTab:CreateButton({
	Name = "🔍 Check Collector Status",
	Callback = function()
		local character = player.Character
		local hasCollector = false
		local collectorName = "None"
		
		if character then
			local tool = character:FindFirstChildOfClass("Tool")
			if tool then
				hasCollector = true
				collectorName = tool.Name
			end
		end
		
		if not hasCollector then
			local backpack = player:FindFirstChild("Backpack")
			if backpack then
				for _, item in ipairs(backpack:GetChildren()) do
					if item:IsA("Tool") then
						collectorName = item.Name .. " (in backpack - equip it!)"
						break
					end
				end
			end
		end
		
		Rayfield:Notify({
			Title = hasCollector and "✅ Collector Equipped!" or "⚠️ Equip Your Tool",
			Content = hasCollector and ("Tool: " .. collectorName .. "\nCollection system is ACTIVE!") or "Equip your collector tool and start farming!",
			Duration = 5,
			Image = 4483362458,
		})
	end,
})

Rayfield:LoadConfiguration()

print("═══════════════════════════════════════════════════════════")
print("[BSS AutoFarm] v5.1 DELTA OPTIMIZED 🐝⚡")
print("[BSS AutoFarm] Executor: DELTA (Native Functions)")
print("[BSS AutoFarm] ToolCollect: Delta's mouse1click (FASTER)")
print("[BSS AutoFarm] Movement: Delta-optimized CFrame teleport")
print("[BSS AutoFarm] Balloon detection: Workspace.Balloons.FieldBalloons")
print("[BSS AutoFarm] Performance: ENHANCED for Delta engine")
print("[BSS AutoFarm] Detection risk: LOWER with Delta hooks")
print("═══════════════════════════════════════════════════════════")
print("")
print("Delta Features Detected:")
print("  ✓ mouse1click:", DELTA_FUNCTIONS.HasMouseClick and "YES (OPTIMAL)" or "NO")
print("  ✓ mouse1press/release:", DELTA_FUNCTIONS.HasMousePress and "YES" or "NO")
print("  ✓ getconnections:", DELTA_FUNCTIONS.HasGetConnections and "YES" or "NO")
print("  ✓ firesignal:", DELTA_FUNCTIONS.HasFireSignal and "YES" or "NO")
print("  ✓ hookfunction:", DELTA_FUNCTIONS.HasHookFunction and "YES" or "NO")
print("═══════════════════════════════════════════════════════════")
