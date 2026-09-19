-- ╔══════════════════════════════════════════════════════════════╗
-- ║         BEE GAME WORKED - AUTO FARM v1.0                    ║
-- ║         Estrutura baseada na análise real do jogo            ║
-- ╚══════════════════════════════════════════════════════════════╝

-- ═══════════════════════════════════════════════════════════════
--                         SETUP INICIAL
-- ═══════════════════════════════════════════════════════════════

-- Encerra sessão anterior se existir
local previousSession = rawget(_G, "BeeGameSession")
if previousSession then
	previousSession.StopRequested = true
end

local SESSION = { StopRequested = false }
_G.BeeGameSession = SESSION

local function isCurrentSession()
	return not SESSION.StopRequested and rawget(_G, "BeeGameSession") == SESSION
end

if not game:IsLoaded() then game.Loaded:Wait() end
task.wait(1)

-- Remove GUIs antigas
pcall(function()
	for _, name in ipairs({"BeeGameFarm", "Rayfield"}) do
		local cg = game:GetService("CoreGui"):FindFirstChild(name)
		if cg then cg:Destroy() end
	end
end)

-- ═══════════════════════════════════════════════════════════════
--                         SERVIÇOS
-- ═══════════════════════════════════════════════════════════════

local Players            = game:GetService("Players")
local RunService         = game:GetService("RunService")
local UserInputService   = game:GetService("UserInputService")
local PathfindingService = game:GetService("PathfindingService")
local TweenService       = game:GetService("TweenService")

local player    = Players.LocalPlayer
local workspace = game:GetService("Workspace")

-- ═══════════════════════════════════════════════════════════════
--                     CARREGA RAYFIELD
-- ═══════════════════════════════════════════════════════════════

local RayfieldOk, Rayfield = pcall(function()
	return loadstring(game:HttpGet("https://sirius.menu/rayfield"))()
end)

if not RayfieldOk or not Rayfield then
	local stub = setmetatable({}, {
		__index = function() return function() return setmetatable({}, {__index = function() return function() end end}) end end
	})
	Rayfield = stub
	warn("[BeeGame] Rayfield falhou - UI indisponível")
end

local function safeNotify(title, content, duration)
	pcall(function()
		if Rayfield and Rayfield.Notify then
			Rayfield:Notify({ Title = title, Content = content, Duration = duration or 3, Image = 4483362458 })
		end
	end)
end

-- ═══════════════════════════════════════════════════════════════
--                     REFERÊNCIAS DO JOGO
-- ═══════════════════════════════════════════════════════════════

-- Estrutura confirmada via análise do Studio
local flowerZones    = workspace:WaitForChild("FlowerZones", 30)
local hivePlatforms  = workspace:WaitForChild("HivePlatforms", 30)
local collectibles   = workspace:WaitForChild("Collectibles", 30)
local treasureFolder = workspace:FindFirstChild("TreasureCollectibles")

if not flowerZones or not hivePlatforms then
	warn("[BeeGame] FlowerZones ou HivePlatforms não encontrados!")
end

-- ═══════════════════════════════════════════════════════════════
--                 MÓDULO DE EVENTOS (REDE)
-- ═══════════════════════════════════════════════════════════════

-- Descoberto via análise: ReplicatedStorage.Shared.Network.Events
-- Tem 216 filhos: 190 RemoteEvents, 22 RemoteFunctions, 3 UnreliableRemoteEvents
local EVENTS_MODULE = nil

local function getEvents()
	if EVENTS_MODULE then return EVENTS_MODULE end
	pcall(function()
		EVENTS_MODULE = require(
			game:GetService("ReplicatedStorage")
			:WaitForChild("Shared", 5)
			:WaitForChild("Network", 5)
			:WaitForChild("Events", 5)
		)
	end)
	return EVENTS_MODULE
end

-- ClientCall dispara FireServer com nome do evento
local function fireEvent(eventName, ...)
	local evts = getEvents()
	if evts and evts.ClientCall then
		pcall(function() evts.ClientCall(eventName, ...) end)
	end
end

-- ═══════════════════════════════════════════════════════════════
--                         CONFIGURAÇÃO
-- ═══════════════════════════════════════════════════════════════

local CONFIG = {
	Enabled        = false,
	SelectedField  = nil,
	ConvertAt      = 95,       -- % de pólen para converter
	AutoConvert    = true,
	TeleportToField = true,    -- Teleporta até o campo
	TeleportInField = false,   -- Teleporta dentro do campo
	CollectTokens  = true,
	TokenRadius    = 60,
	MoveSpeed      = 28,
	FieldRadius    = 20,
	WaitAtHive     = 2,
}

local RUNTIME = {
	Active   = false,
	PollLen  = 0,
	Honey    = 0,
	Tokens   = 0,
	Start    = 0,
}

-- ═══════════════════════════════════════════════════════════════
--                     STATS DO PLAYER
-- ═══════════════════════════════════════════════════════════════

-- CoreStats: confirmado existir no player pelo jogo
-- Estrutura: player.CoreStats.Pollen, .Capacity, .Honey
local coreStats    = nil
local pollenValue  = nil
local capacityValue = nil
local honeyValue   = nil

local function initStats()
	-- Tenta CoreStats primeiro (BSS padrão)
	local ok = pcall(function()
		coreStats   = player:WaitForChild("CoreStats", 10)
		pollenValue = coreStats:WaitForChild("Pollen", 10)
		capacityValue = coreStats:WaitForChild("Capacity", 10)
		honeyValue  = coreStats:WaitForChild("Honey", 10)
	end)
	if not ok then
		-- Fallback: leaderstats
		pcall(function()
			local ls = player:WaitForChild("leaderstats", 5)
			honeyValue  = ls:FindFirstChild("Honey")
			pollenValue = ls:FindFirstChild("Pollen")
		end)
		warn("[BeeGame] CoreStats não encontrado, usando leaderstats como fallback")
	end
end

task.spawn(initStats)

local function getPollen()
	if pollenValue then
		local ok, v = pcall(function() return pollenValue.Value end)
		return ok and v or 0
	end
	return 0
end

local function getCapacity()
	if capacityValue then
		local ok, v = pcall(function() return capacityValue.Value end)
		return ok and v or 1
	end
	return 1
end

local function getPollenPercent()
	local cap = getCapacity()
	return cap > 0 and (getPollen() / cap * 100) or 0
end

-- ═══════════════════════════════════════════════════════════════
--                     FUNÇÕES DE PERSONAGEM
-- ═══════════════════════════════════════════════════════════════

local CHAR_CACHE = { root = nil, humanoid = nil, t = 0, interval = 0.5 }

local function getRoot()
	local now = tick()
	if CHAR_CACHE.root and CHAR_CACHE.root.Parent and now - CHAR_CACHE.t < CHAR_CACHE.interval then
		return CHAR_CACHE.root
	end
	local char = player.Character
	if not char then return nil end
	CHAR_CACHE.root     = char:FindFirstChild("HumanoidRootPart")
	CHAR_CACHE.humanoid = char:FindFirstChildOfClass("Humanoid")
	CHAR_CACHE.t        = now
	return CHAR_CACHE.root
end

local function getHumanoid()
	getRoot()
	return CHAR_CACHE.humanoid
end

-- Teleporte CFrame (instantâneo)
local function teleportTo(pos)
	local root = getRoot()
	if not root then return false end
	local rot = root.CFrame - root.CFrame.Position
	root.CFrame = CFrame.new(pos) * rot
	task.wait(0.05)
	return true
end

-- Movimento andando via Humanoid:MoveTo
local function walkTo(destination, arrivalDist)
	local root = getRoot()
	local hum  = getHumanoid()
	if not root or not hum then return false end

	arrivalDist = arrivalDist or 5
	if (root.Position - destination).Magnitude <= arrivalDist then return true end

	hum:MoveTo(destination)

	local start   = tick()
	local lastPos = root.Position
	local stuck   = 0

	while isCurrentSession() and CONFIG.Enabled and tick() - start < 8 do
		if not root.Parent then return false end
		if (root.Position - destination).Magnitude <= arrivalDist then return true end
		local moved = (root.Position - lastPos).Magnitude
		if moved < 0.3 then
			stuck = stuck + 0.1
			if stuck >= 2 then break end
		else
			stuck = 0
			lastPos = root.Position
		end
		task.wait(0.1)
	end
	return (root.Position - destination).Magnitude <= arrivalDist + 4
end

-- Ir até destino: teleporta se CONFIG.TeleportToField, senão usa pathfinding
local function goTo(destination, useTeleport)
	if useTeleport or CONFIG.TeleportToField then
		return teleportTo(destination)
	end

	-- Pathfinding para distâncias longas
	local root = getRoot()
	local hum  = getHumanoid()
	if not root or not hum then return false end

	if (root.Position - destination).Magnitude <= 8 then return true end

	local waypoints = nil
	pcall(function()
		local path = PathfindingService:CreatePath({
			AgentHeight = 5, AgentRadius = 2,
			AgentCanJump = true, WaypointSpacing = 4,
		})
		path:ComputeAsync(root.Position, destination)
		if path.Status == Enum.PathStatus.Success then
			waypoints = path:GetWaypoints()
		end
	end)

	if waypoints and #waypoints > 1 then
		for i = 2, #waypoints do
			if not isCurrentSession() or not CONFIG.Enabled then return false end
			local wp = waypoints[i]
			if wp.Action == Enum.PathWaypointAction.Jump then
				hum:ChangeState(Enum.HumanoidStateType.Jumping)
			end
			if not walkTo(wp.Position, 4) then break end
		end
	else
		walkTo(destination, 8)
	end

	root = getRoot()
	return root and (root.Position - destination).Magnitude <= 12
end

-- ═══════════════════════════════════════════════════════════════
--                     INPUT DE COLETA (MOUSE)
-- ═══════════════════════════════════════════════════════════════

-- Descoberto: ToolCollect é o RemoteEvent real para coleta
-- Também há mouse1press/release nativos em executores
local INPUT = { held = false, method = nil }

local hasMouse1Press  = type(mouse1press)  == "function"
local hasMouse1Click  = type(mouse1click)  == "function"
local hasMouse1Release = type(mouse1release) == "function"

local VIM = nil
pcall(function() VIM = game:GetService("VirtualInputManager") end)

local function releaseInput()
	if not INPUT.held then return end
	pcall(function()
		if INPUT.method == "native" and hasMouse1Release then
			mouse1release()
		elseif INPUT.method == "vim" and VIM then
			VIM:SendMouseButtonEvent(0, 0, 0, false, game, 0)
		end
	end)
	INPUT.held   = false
	INPUT.method = nil
end

local function pressCollect()
	if INPUT.held then return true end

	-- Método 1: mouse1press nativo (Delta, Wave, etc.)
	if hasMouse1Press then
		local ok = pcall(mouse1press)
		if ok then
			INPUT.held   = true
			INPUT.method = "native"
			return true
		end
	end

	-- Método 2: mouse1click simples (Xeno)
	if hasMouse1Click then
		return pcall(mouse1click)
	end

	-- Método 3: VirtualInputManager fallback
	if VIM then
		local cam = workspace.CurrentCamera
		if cam then
			local vp = cam.ViewportSize
			local x, y = math.floor(vp.X * 0.5), math.floor(vp.Y * 0.5)
			local ok = pcall(function()
				VIM:SendMouseButtonEvent(x, y, 0, true, game, 0)
			end)
			if ok then
				INPUT.held   = true
				INPUT.method = "vim"
				return true
			end
		end
	end

	return false
end

-- ═══════════════════════════════════════════════════════════════
--             LOOP DE COLETA (mantém botão pressionado)
-- ═══════════════════════════════════════════════════════════════

local COLLECT_LOOP = { running = false, enabled = false }

local function startCollectLoop()
	if COLLECT_LOOP.running then return end
	COLLECT_LOOP.running = true

	task.spawn(function()
		while COLLECT_LOOP.enabled and isCurrentSession() do
			if CONFIG.Enabled and CONFIG.SelectedField then
				-- Só coleta se estiver no campo
				local root = getRoot()
				local fp   = CONFIG.SelectedField
				local fieldPos = fp:IsA("BasePart") and fp.Position or
					(fp:IsA("Model") and fp.PrimaryPart and fp.PrimaryPart.Position)

				if root and fieldPos then
					local dist = (root.Position - fieldPos).Magnitude
					local radius = CONFIG.FieldRadius + 15
					if dist <= radius then
						pressCollect()
					else
						releaseInput()
					end
				else
					releaseInput()
				end
			else
				releaseInput()
			end
			task.wait(0.08)
		end
		releaseInput()
		COLLECT_LOOP.running = false
	end)
end

-- ═══════════════════════════════════════════════════════════════
--                 COLETA DE TOKENS (Workspace.Collectibles)
-- ═══════════════════════════════════════════════════════════════

-- Tokens têm: atributo DebugName, TreasureID, CollectibleID
-- Estrutura: BasePart com CanTouch=false, então precisamos nos mover até eles

-- Prioridades por DebugName (descoberto via análise)
local TOKEN_PRIORITY = {
	-- Alta prioridade
	["MythicEgg"]        = 100,
	["GiftedMythicEgg"]  = 100,
	["RoyalJelly"]       = 90,
	["StarJelly"]        = 85,
	["Ticket"]           = 80,
	["MicroConverter"]   = 78,
	["FestiveBean"]      = 75,
	["JellyBean"]        = 70,
	-- Média
	["Inspire"]          = 60,
	["Boost"]            = 55,
	["Honeystorm"]       = 52,
	["CloudVial"]        = 50,
	["Mark"]             = 45,
	["Treat"]            = 40,
	-- Baixa
	["Honey"]            = 25,
	["Pollen"]           = 20,
}

local function getTokenPriority(token)
	-- Usa DebugName (mais confiável - confirmado no Studio)
	local dbg = token:GetAttribute("DebugName")
	if dbg then
		-- Remove espaços e faz match
		local clean = dbg:gsub("%s+", "")
		if TOKEN_PRIORITY[clean] then return TOKEN_PRIORITY[clean] end
		-- TreasureSparkles = item especial
		if token:FindFirstChild("TreasureSparkles") then return 50 end
		-- TreasureID com MapTreasure = item raro
		local tid = token:GetAttribute("TreasureID")
		if tid and tid:find("MapTreasure") then return 75 end
	end
	return 15 -- padrão
end

local function getObjectPos(obj)
	if not obj or not obj.Parent then return nil end
	if obj:IsA("BasePart") then return obj.Position end
	if obj:IsA("Model") then
		local p = obj.PrimaryPart or obj:FindFirstChildWhichIsA("BasePart", true)
		return p and p.Position
	end
	return nil
end

local collectingToken = false

local function getBestToken(maxDist)
	local root = getRoot()
	if not root then return nil end

	local best, bestScore = nil, -math.huge

	local sources = { collectibles, treasureFolder }

	for _, folder in ipairs(sources) do
		if folder and folder.Parent then
			for _, token in ipairs(folder:GetChildren()) do
				local pos = getObjectPos(token)
				if pos then
					local dist = (root.Position - pos).Magnitude
					if dist <= (maxDist or CONFIG.TokenRadius) then
						local priority = getTokenPriority(token)
						-- TreasureCollectibles tem prioridade máxima
						if folder == treasureFolder then priority = 100 end
						local score = priority - (dist * 0.4)
						if score > bestScore then
							best      = token
							bestScore = score
						end
					end
				end
			end
		end
	end

	return best
end

local function collectToken(token)
	if collectingToken or not token or not token.Parent then return false end
	collectingToken = true

	local pos = getObjectPos(token)
	if not pos then collectingToken = false; return false end

	local root = getRoot()
	if not root then collectingToken = false; return false end

	local dist     = (root.Position - pos).Magnitude
	local priority = getTokenPriority(token)

	-- Tokens valiosos (>=75): vai buscar independente da distância
	-- Tokens médios (>=40): só se estiver a menos de 25 studs
	-- Tokens comuns: só se estiver a menos de 12 studs
	local shouldChase = false
	if priority >= 75 then
		shouldChase = true
	elseif priority >= 40 and dist <= 25 then
		shouldChase = true
	elseif dist <= 12 then
		shouldChase = true
	end

	if not shouldChase then
		collectingToken = false
		return false
	end

	-- Move até o token
	if CONFIG.TeleportInField then
		teleportTo(pos + Vector3.new(0, 3, 0))
	else
		walkTo(pos + Vector3.new(0, 2, 0), 3)
	end

	-- Aguarda coleta (token some ao tocar)
	local waited = 0
	while token.Parent and waited < 1 do
		task.wait(0.1)
		waited = waited + 0.1
	end

	local collected = not token.Parent
	if collected then
		RUNTIME.Tokens = RUNTIME.Tokens + 1
		if priority >= 75 then
			safeNotify("💎 Token Valioso!", string.format("%s coletado!", token:GetAttribute("DebugName") or token.Name), 3)
		end
	end

	collectingToken = false
	return collected
end

-- Loop de coleta de tokens (roda em paralelo ao farm)
local TOKEN_LOOP = { running = false, enabled = false }

local function startTokenLoop()
	if TOKEN_LOOP.running then return end
	TOKEN_LOOP.running = true

	task.spawn(function()
		while TOKEN_LOOP.enabled and isCurrentSession() do
			if CONFIG.CollectTokens and CONFIG.Enabled and not collectingToken then
				local token = getBestToken(CONFIG.TokenRadius)
				if token then
					collectToken(token)
					task.wait(0.1)
				else
					task.wait(0.3)
				end
			else
				task.wait(0.3)
			end
		end
		TOKEN_LOOP.running = false
	end)
end

-- ═══════════════════════════════════════════════════════════════
--             COLMEIA (HivePlatforms)
-- ═══════════════════════════════════════════════════════════════

-- Estrutura confirmada: HivePlatforms > Hive1..6 > PlayerRef (ObjectValue)
--                                                 > HiveRespawnPoint (Part)
local function getHive()
	if not hivePlatforms then return nil end
	for _, hive in ipairs(hivePlatforms:GetChildren()) do
		local playerRef = hive:FindFirstChild("PlayerRef")
		local respawn   = hive:FindFirstChild("HiveRespawnPoint")
		if playerRef and respawn and respawn:IsA("BasePart") then
			local owner = playerRef:IsA("ObjectValue") and playerRef.Value
			if owner == player then return respawn end
		end
	end
	return nil
end

-- Converte pólen usando o evento ToggleHoneyMaking (confirmado via Events module)
local function convertAtHive()
	local hive = getHive()
	if not hive then
		warn("[BeeGame] Colmeia não encontrada!")
		safeNotify("⚠️ Colmeia", "Colmeia não encontrada! Verifique se você tem uma.", 5)
		task.wait(3)
		return false
	end

	-- Vai até a colmeia
	local ok = goTo(hive.Position + Vector3.new(0, 3, 0), true)
	if not ok then task.wait(1) end

	task.wait(0.5)

	-- Dispara ToggleHoneyMaking (mesmo evento do BSS original)
	fireEvent("PlayerHiveCommand", "ToggleHoneyMaking")

	safeNotify("🍯 Convertendo...", string.format("Convertendo %.0f%% de pólen em mel!", getPollenPercent()), 3)

	-- Aguarda atributo ConvertingAtHive ficar true
	local waitStart = tick()
	while tick() - waitStart < 5 do
		if player:GetAttribute("ConvertingAtHive") then break end
		task.wait(0.25)
	end

	-- Aguarda conversão terminar
	local convertStart = tick()
	while isCurrentSession() and tick() - convertStart < 120 do
		local pct = getPollenPercent()
		if pct < 1 then break end
		if not player:GetAttribute("ConvertingAtHive") then
			if pct > 1 then
				fireEvent("PlayerHiveCommand", "ToggleHoneyMaking")
			else
				break
			end
		end
		task.wait(1)
	end

	-- Para conversão se ainda ativa
	if player:GetAttribute("ConvertingAtHive") then
		fireEvent("PlayerHiveCommand", "ToggleHoneyMaking")
	end

	task.wait(CONFIG.WaitAtHive)
	safeNotify("✅ Conversão OK!", "Mel produzido! Voltando ao campo...", 3)
	return true
end

-- ═══════════════════════════════════════════════════════════════
--                    FARM PRINCIPAL
-- ═══════════════════════════════════════════════════════════════

-- Grade 3x3 de pontos dentro do campo para cobrir toda a área
local function getFieldSweepPoints(fieldPart, radius, height)
	local pos    = fieldPart:IsA("BasePart") and fieldPart.Position
		or (fieldPart.PrimaryPart and fieldPart.PrimaryPart.Position)
	if not pos then return {pos} end

	radius = radius or CONFIG.FieldRadius
	height = height or 3

	local step = radius * 0.65
	local points = {}

	for x = -1, 1 do
		for z = -1, 1 do
			table.insert(points, Vector3.new(
				pos.X + x * step,
				pos.Y + height,
				pos.Z + z * step
			))
		end
	end

	return points
end

local function farmField()
	if not CONFIG.SelectedField or not CONFIG.SelectedField.Parent then return end

	local field  = CONFIG.SelectedField
	local points = getFieldSweepPoints(field)
	local ptIdx  = 1

	-- Vai para o campo
	local fieldPos = field:IsA("BasePart") and field.Position
		or (field.PrimaryPart and field.PrimaryPart.Position)

	if not fieldPos then return end

	goTo(Vector3.new(fieldPos.X, fieldPos.Y + 3, fieldPos.Z))

	-- Varre os pontos do campo
	while isCurrentSession() and CONFIG.Enabled
		and CONFIG.SelectedField == field
		and getPollenPercent() < CONFIG.ConvertAt do

		local target = points[ptIdx]
		ptIdx = (ptIdx % #points) + 1

		if CONFIG.TeleportInField then
			teleportTo(target)
			task.wait(0.3)
		else
			walkTo(target, 4)
		end

		task.wait(0.2)
	end
end

-- ═══════════════════════════════════════════════════════════════
--             LOOP DE VELOCIDADE (mantém WalkSpeed correto)
-- ═══════════════════════════════════════════════════════════════

local SPEED_LOOP = { running = false }

local function startSpeedLoop()
	if SPEED_LOOP.running then return end
	SPEED_LOOP.running = true
	task.spawn(function()
		while isCurrentSession() do
			if CONFIG.Enabled then
				local hum = getHumanoid()
				if hum and hum.WalkSpeed ~= CONFIG.MoveSpeed then
					hum.WalkSpeed = CONFIG.MoveSpeed
				end
			end
			task.wait(0.1)
		end
		SPEED_LOOP.running = false
	end)
end

-- ═══════════════════════════════════════════════════════════════
--                    LOOP PRINCIPAL
-- ═══════════════════════════════════════════════════════════════

local MAIN_LOOP = { running = false }

local function stopAll()
	CONFIG.Enabled     = false
	COLLECT_LOOP.enabled = false
	TOKEN_LOOP.enabled   = false
	releaseInput()
	-- Restaura WalkSpeed
	pcall(function()
		local hum = getHumanoid()
		if hum then hum.WalkSpeed = 16 end
	end)
end

local function startMainLoop()
	if MAIN_LOOP.running then return end
	MAIN_LOOP.running = true

	-- Inicia subsistemas
	COLLECT_LOOP.enabled = true
	startCollectLoop()

	TOKEN_LOOP.enabled = true
	startTokenLoop()

	startSpeedLoop()

	RUNTIME.Start  = tick()
	RUNTIME.Active = true

	task.spawn(function()
		while CONFIG.Enabled and isCurrentSession() do
			if not CONFIG.SelectedField or not CONFIG.SelectedField.Parent then
				task.wait(0.5)
				continue
			end

			local pct = getPollenPercent()

			-- Converte se atingiu o limite e AutoConvert está ligado
			if CONFIG.AutoConvert and pct >= CONFIG.ConvertAt then
				releaseInput()
				convertAtHive()
			else
				farmField()
			end

			task.wait(0.1)
		end

		stopAll()
		MAIN_LOOP.running = false
		RUNTIME.Active    = false
		print("[BeeGame] Farm parado.")
	end)
end

-- ═══════════════════════════════════════════════════════════════
--                         UI (RAYFIELD)
-- ═══════════════════════════════════════════════════════════════

local Window = Rayfield:CreateWindow({
	Name              = "🐝 Bee Game Auto Farm v1.0",
	LoadingTitle      = "Bee Swarm Simulator",
	LoadingSubtitle   = "Carregando...",
	ConfigurationSaving = { Enabled = false },
	Discord           = { Enabled = false },
	KeySystem         = false,
})

-- ── TAB FARM ──────────────────────────────────────────────────

local FarmTab = Window:CreateTab("🌻 Farm", 4483362458)
FarmTab:CreateSection("⚙️ Configuração")

-- Dropdown de campos
local fieldNames = {}
if flowerZones then
	for _, zone in ipairs(flowerZones:GetChildren()) do
		if zone:IsA("BasePart") or zone:IsA("Model") then
			table.insert(fieldNames, zone.Name)
		end
	end
	table.sort(fieldNames)
end

FarmTab:CreateDropdown({
	Name           = "📍 Selecionar Campo",
	Options        = fieldNames,
	CurrentOption  = { fieldNames[1] or "Nenhum" },
	MultipleOptions = false,
	Flag           = "FieldDropdown",
	Callback       = function(opt)
		local name = opt[1]
		if not flowerZones then return end
		for _, zone in ipairs(flowerZones:GetChildren()) do
			if zone.Name == name then
				CONFIG.SelectedField = zone
				safeNotify("📍 Campo", "Campo selecionado: " .. name, 3)
				break
			end
		end
	end,
})

-- Inicializa campo padrão
if fieldNames[1] and flowerZones then
	for _, zone in ipairs(flowerZones:GetChildren()) do
		if zone.Name == fieldNames[1] then
			CONFIG.SelectedField = zone
			break
		end
	end
end

-- Toggle principal
FarmTab:CreateToggle({
	Name         = "🟢 Auto Farm",
	CurrentValue = false,
	Flag         = "AutoFarmToggle",
	Callback     = function(v)
		CONFIG.Enabled = v
		if v then
			if not CONFIG.SelectedField then
				safeNotify("⚠️ Erro", "Selecione um campo primeiro!", 3)
				CONFIG.Enabled = false
				return
			end
			safeNotify("🐝 Farm ON", "Farmando: " .. CONFIG.SelectedField.Name, 3)
			startMainLoop()
		else
			stopAll()
			safeNotify("⛔ Farm OFF", "Farm pausado.", 2)
		end
	end,
})

FarmTab:CreateSection("🔧 Opções de Farm")

FarmTab:CreateToggle({
	Name         = "🚀 Teleportar até o Campo",
	CurrentValue = true,
	Flag         = "TeleportToField",
	Callback     = function(v)
		CONFIG.TeleportToField = v
		safeNotify(v and "🚀 Teleporte Ligado" or "🚶 Andando até campo", "", 2)
	end,
})

FarmTab:CreateToggle({
	Name         = "⚡ Teleportar Dentro do Campo",
	CurrentValue = false,
	Flag         = "TeleportInField",
	Callback     = function(v)
		CONFIG.TeleportInField = v
		safeNotify(v and "⚡ Teleporte no campo ON" or "🚶 Andar no campo ON", "", 2)
	end,
})

FarmTab:CreateToggle({
	Name         = "🔄 Auto Converter",
	CurrentValue = true,
	Flag         = "AutoConvert",
	Callback     = function(v)
		CONFIG.AutoConvert = v
		safeNotify(v and "🔄 Auto Convert ON" or "🔄 Auto Convert OFF", "", 2)
	end,
})

FarmTab:CreateSlider({
	Name         = "Converter em % de Pólen",
	Range        = { 50, 100 },
	Increment    = 5,
	Suffix       = "%",
	CurrentValue = 95,
	Flag         = "ConvertAt",
	Callback     = function(v) CONFIG.ConvertAt = v end,
})

FarmTab:CreateSlider({
	Name         = "Velocidade de Movimento",
	Range        = { 16, 100 },
	Increment    = 2,
	Suffix       = " ws",
	CurrentValue = 28,
	Flag         = "MoveSpeed",
	Callback     = function(v) CONFIG.MoveSpeed = v end,
})

FarmTab:CreateSlider({
	Name         = "Raio do Campo",
	Range        = { 10, 50 },
	Increment    = 2,
	Suffix       = " studs",
	CurrentValue = 20,
	Flag         = "FieldRadius",
	Callback     = function(v) CONFIG.FieldRadius = v end,
})

-- ── TAB TOKENS ────────────────────────────────────────────────

local TokenTab = Window:CreateTab("💎 Tokens", 4483362458)
TokenTab:CreateSection("Coleta de Tokens")

TokenTab:CreateToggle({
	Name         = "💎 Coletar Tokens",
	CurrentValue = true,
	Flag         = "CollectTokens",
	Callback     = function(v)
		CONFIG.CollectTokens = v
		safeNotify(v and "💎 Tokens ON" or "💎 Tokens OFF", "", 2)
	end,
})

TokenTab:CreateSlider({
	Name         = "Raio de Coleta",
	Range        = { 20, 150 },
	Increment    = 5,
	Suffix       = " studs",
	CurrentValue = 60,
	Flag         = "TokenRadius",
	Callback     = function(v) CONFIG.TokenRadius = v end,
})

TokenTab:CreateSection("ℹ️ Prioridades de Tokens")

TokenTab:CreateButton({
	Name = "📋 Ver Prioridades",
	Callback = function()
		print("\n═══════ PRIORIDADES DE TOKENS ═══════")
		print("ALTA (>=75): MythicEgg, GiftedMythicEgg, RoyalJelly, StarJelly, Ticket, MicroConverter, FestiveBean, JellyBean")
		print("MÉDIA (40-74): Inspire, Boost, Honeystorm, CloudVial, Mark, Treat")
		print("BAIXA (<40): Honey, Pollen")
		print("TESOUROS: TreasureCollectibles = prioridade 100 (sempre coletados)")
		print("═══════════════════════════════════════")
		safeNotify("📋 Prioridades", "Veja o console (F9) para detalhes!", 4)
	end,
})

-- ── TAB STATS ─────────────────────────────────────────────────

local StatsTab = Window:CreateTab("📊 Stats", 4483362458)
StatsTab:CreateSection("Estatísticas da Sessão")

StatsTab:CreateButton({
	Name = "📊 Atualizar Stats",
	Callback = function()
		local uptime = tick() - RUNTIME.Start
		local mins   = math.floor(uptime / 60)
		local secs   = math.floor(uptime % 60)
		local pct    = getPollenPercent()

		local msg = string.format(
			"Tempo: %dm %ds\nPólen: %.1f%%\nTokens: %d\nFarmando: %s",
			mins, secs, pct, RUNTIME.Tokens,
			CONFIG.SelectedField and CONFIG.SelectedField.Name or "Nenhum"
		)

		safeNotify("📊 Stats", msg, 8)
		print("\n═══════ STATS ═══════")
		print(msg)
		print("═════════════════════")
	end,
})

StatsTab:CreateButton({
	Name = "🔍 Escanear Tokens Próximos",
	Callback = function()
		local root = getRoot()
		if not root then safeNotify("⚠️ Erro", "Personagem não encontrado!", 3) return end

		local found = 0
		print("\n═══════ TOKENS PRÓXIMOS ═══════")

		if collectibles then
			for _, token in ipairs(collectibles:GetChildren()) do
				local pos = getObjectPos(token)
				if pos then
					local dist = (root.Position - pos).Magnitude
					if dist <= 200 then
						local dbg = token:GetAttribute("DebugName") or "?"
						local tid = token:GetAttribute("TreasureID") or "?"
						local pri = getTokenPriority(token)
						print(string.format("  [%.0f studs] %s | %s | P:%d", dist, dbg, tid, pri))
						found = found + 1
					end
				end
			end
		end

		print(string.format("Total: %d tokens em 200 studs", found))
		print("═══════════════════════════════")
		safeNotify("🔍 Scan", string.format("%d tokens em 200 studs - veja o console!", found), 4)
	end,
})

-- ── TAB INFO / UNLOAD ─────────────────────────────────────────

local InfoTab = Window:CreateTab("ℹ️ Info", 4483362458)
InfoTab:CreateSection("Informações")

InfoTab:CreateButton({
	Name = "🔎 Verificar Estrutura do Jogo",
	Callback = function()
		local info = {
			"FlowerZones: " .. (flowerZones and tostring(#flowerZones:GetChildren()) .. " campos" or "NÃO ENCONTRADO"),
			"HivePlatforms: " .. (hivePlatforms and tostring(#hivePlatforms:GetChildren()) .. " colmeias" or "NÃO ENCONTRADO"),
			"Collectibles: " .. (collectibles and tostring(#collectibles:GetChildren()) .. " tokens" or "NÃO ENCONTRADO"),
			"CoreStats: " .. (coreStats and "OK" or "NÃO ENCONTRADO"),
			"Events Module: " .. (getEvents() and "OK" or "NÃO ENCONTRADO"),
			"Campo atual: " .. (CONFIG.SelectedField and CONFIG.SelectedField.Name or "Nenhum"),
			"Pólen: " .. string.format("%.1f%%", getPollenPercent()),
		}
		print("\n═══════ ESTRUTURA DO JOGO ═══════")
		for _, l in ipairs(info) do print("  " .. l) end
		print("══════════════════════════════════")
		safeNotify("🔎 Jogo OK", table.concat(info, "\n"), 8)
	end,
})

InfoTab:CreateSection("⚠️ Controle")

InfoTab:CreateButton({
	Name = "🗑️ Unload Script",
	Callback = function()
		safeNotify("⚠️ Unloading...", "Parando todos os sistemas em 2 segundos...", 2)
		task.wait(2)

		-- Para tudo
		SESSION.StopRequested = true
		stopAll()
		MAIN_LOOP.running  = false
		SPEED_LOOP.running = false
		_G.BeeGameSession  = nil

		-- Remove GUI
		pcall(function()
			local gui = game:GetService("CoreGui"):FindFirstChild("Rayfield")
			if gui then gui:Destroy() end
		end)

		print("[BeeGame] ✅ Script descarregado com sucesso!")
		pcall(function()
			game.StarterGui:SetCore("SendNotification", {
				Title = "BeeGame Unloaded"; Text = "Script removido com sucesso!"; Duration = 5;
			})
		end)
	end,
})

-- ═══════════════════════════════════════════════════════════════
--                         INICIALIZAÇÃO
-- ═══════════════════════════════════════════════════════════════

print("═══════════════════════════════════════════════════")
print("[BeeGame] 🐝 Auto Farm v1.0 carregado!")
print("[BeeGame] Campos disponíveis: " .. #fieldNames)
print("[BeeGame] Tokens ativos: " .. (collectibles and #collectibles:GetChildren() or 0))
print("[BeeGame] mouse1press: " .. (hasMouse1Press and "✓" or "✗"))
print("[BeeGame] mouse1click: " .. (hasMouse1Click and "✓" or "✗"))
print("[BeeGame] VirtualInputManager: " .. (VIM and "✓" or "✗"))
print("═══════════════════════════════════════════════════")

safeNotify("🐝 BeeGame Farm", "Script carregado! Selecione um campo e ative o Auto Farm.", 5)
