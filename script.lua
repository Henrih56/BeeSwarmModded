-- ═══════════════════════════════════════════════════════════════
--    🐝 BSS AUTO FARM v4.1 - RAYFIELD UI VERSION
--    Professional farming script with FULLY CUSTOMIZABLE features
--    + SPECIAL AUTO-FEATURES: Coconuts, Balloons, Clouds!
--    
--    MOVEMENT: Tween to field + natural walking (no noclip!)
--    COLLECTION: Separate continuous threads (0.08s cooldown)
--    TOKENS: Aggressive collection with priority system
--    BALLOONS: ALWAYS ACTIVE — uses Workspace.Balloons.FieldBalloons
--              + BalloonInflate event for instant detection
--              Priority over field farm (more pollen/second)
--    SPECIAL: Auto Coconut Catcher, Cloud Farm
--    CUSTOMIZATION: Every feature can be toggled on/off!
--    
--    ✅ Natural walking animation
--    ✅ Respects terrain and obstacles
--    ✅ No floating/flying effect
--    ✅ Respects game speed boosts (Haste, etc.)
--    ✅ FULLY CONFIGURABLE
--    ✅ Balloons always farmed (real game structure)
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

-- Carrega Rayfield
local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()

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
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local workspace = game:GetService("Workspace")

-- ═══════════════════════════════════════════════════════════════
--                    REFERÊNCIAS DO JOGO
-- ═══════════════════════════════════════════════════════════════

local flowerZones = workspace:WaitForChild("FlowerZones")
local hivePlatforms = workspace:WaitForChild("HivePlatforms")

-- Carrega APIs do BSS
local sharedFolder = ReplicatedStorage:FindFirstChild("Shared")
local networkFolder = sharedFolder and sharedFolder:FindFirstChild("Network")
local eventsModule = networkFolder and networkFolder:FindFirstChild("Events")

local eventsApi = nil
if eventsModule then
	pcall(function()
		eventsApi = require(eventsModule)
	end)
end

-- ═══════════════════════════════════════════════════════════════
--          LISTENER: BALLOON INFLATE (detecção instantânea)
-- ═══════════════════════════════════════════════════════════════
-- Quando um novo balloon infla, o jogo dispara BalloonInflate.
-- Usamos esse evento para acionar o farm imediatamente,
-- sem esperar o próximo tick do CheckInterval.

local CONFIG
local BALLOON_FARM
local balloonInflateConnection = nil
local function setupBalloonInflateListener()
	pcall(function()
		if eventsApi and type(eventsApi.ClientListen) == "function" then
			balloonInflateConnection = eventsApi.ClientListen("BalloonInflate", function(balloonId)
				-- Só age se o auto farm estiver ativo
				if not CONFIG.Enabled or not BALLOON_FARM.Enabled then return end
				-- Reseta o LastCheck para forçar verificação imediata
				BALLOON_FARM.LastCheck = 0
				-- Notifica (com proteção caso Rayfield não esteja pronto)
				pcall(function()
					if Rayfield and Rayfield.Notify then
						Rayfield:Notify({
							Title = "🎈 Balloon Inflated!",
							Content = "New balloon detected - going to farm!",
							Duration = 3,
							Image = 4483362458,
						})
					end
				end)
			end)
		end
	end)
end
-- Executa o setup do listener imediatamente

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

-- Função separada que roda continuamente para coletar (estilo Atlas)
local function enableToolCollect()
	if TOOL_COLLECT.Running then return end
	TOOL_COLLECT.Running = true
	
	task.spawn(function()
		while TOOL_COLLECT.Enabled and isCurrentSession() do
			local currentTime = tick()
			
			-- Verifica cooldown
			if currentTime - TOOL_COLLECT.LastCollect >= TOOL_COLLECT.Cooldown then
				-- Tenta múltiplos métodos de coleta (como o Atlas)
				local success = false
				
				-- Método 1: ClientCall (preferido)
				local tool = getEquippedCollector()
				if tool then
					success = pcall(function()
						tool:Activate()
					end)
				else
					TOOL_COLLECT.LastError = "No collector equipped"
				end
				
				-- Método 2: Events.ToolCollect:FireServer (backup)
				if success then
					TOOL_COLLECT.LastCollect = currentTime
					TOOL_COLLECT.CollectCount = TOOL_COLLECT.CollectCount + 1
					TOOL_COLLECT.LastError = nil
				end
			end
			
			task.wait(0.05) -- Loop rápido para máxima responsividade
		end
		
		TOOL_COLLECT.Running = false
	end)
end

-- Função para verificar se tem collector equipado (simples)
local function hasCollectorEquipped()
	return getEquippedCollector() ~= nil
end

local coreStats = player:WaitForChild("CoreStats")
local pollenValue = coreStats:WaitForChild("Pollen")
local capacityValue = coreStats:WaitForChild("Capacity")
local honeyValue = coreStats:WaitForChild("Honey")

-- ═══════════════════════════════════════════════════════════════
--                         CONFIGURAÇÕES
-- ═══════════════════════════════════════════════════════════════

CONFIG = {
	Enabled = false,
	SelectedField = nil,
	MoveSpeed = 45,
	FieldRadius = 18,
	CollectHeight = 3,
	CollectInterval = 0.1,
	ConvertAt = 95,
	
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
	FarmBalloons = true, -- SEMPRE ATIVO
	BalloonCheckInterval = 1,
	
	-- Cloud Farm
	FarmClouds = false,
	CloudCheckInterval = 3,
}

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
		PlantersPlanted = 0,
		PlantersHarvested = 0,
		CoconutsCaught = 0,
		BalloonsVisited = 0,
		CloudsVisited = 0,
		Runtime = 0,
		StartTime = 0,
		LastStatsUpdate = 0
	}
}

-- Planters
local PLANTERS = {
	Enabled = false,
	AutoPlant = false,
	AutoCollect = true,
	ActivePlanters = {},
	AvailablePlanters = {},
	LastCheck = 0,
	CheckInterval = 5
}

-- ═══════════════════════════════════════════════════════════════
--                      FUNÇÕES CORE
-- ═══════════════════════════════════════════════════════════════

local function getRoot()
	local character = player.Character or player.CharacterAdded:Wait()
	return character:FindFirstChild("HumanoidRootPart")
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

-- Tween para teleportar até o campo (suave, sem andar)
local function tweenToField(destination)
	local character = player.Character
	if not character then return false end
	
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then return false end
	
	-- Calcula duração baseado na distância
	local distance = (root.Position - destination).Magnitude
	local duration = math.clamp(distance / 200, 0.5, 3) -- 0.5 a 3 segundos
	
	local tweenInfo = TweenInfo.new(
		duration,
		Enum.EasingStyle.Quad,
		Enum.EasingDirection.Out
	)
	
	local tween = TweenService:Create(root, tweenInfo, {CFrame = CFrame.new(destination)})
	tween:Play()
	
	-- Aguarda terminar
	local completed = false
	local completedConnection
	completedConnection = tween.Completed:Connect(function()
		completed = true
	end)
	
	local startTime = tick()
	while not completed and CONFIG.Enabled and tick() - startTime < duration + 1 do
		task.wait(0.1)
	end
	if completedConnection then
		completedConnection:Disconnect()
	end
	
	return CONFIG.Enabled
end

-- Movimento normal (andar com Humanoid:MoveTo)
local function moveTo(destination)
	local character = player.Character
	if not character then return false end
	
	local root = character:FindFirstChild("HumanoidRootPart")
	local humanoid = character:FindFirstChild("Humanoid")
	
	if not root or not humanoid then return false end
	
	-- Só ajusta velocidade se estiver ABAIXO do configurado
	-- (respeita boosts de haste/velocidade do jogo)
	if humanoid.WalkSpeed < CONFIG.MoveSpeed then
		humanoid.WalkSpeed = CONFIG.MoveSpeed
	end
	
	-- Usa Humanoid:MoveTo simples (funciona sempre)
	humanoid:MoveTo(destination)
	
	-- Aguarda chegar no destino
	local startTime = tick()
	local timeout = 15 -- segundos
	local arrivedDistance = 5 -- studs
	
	while CONFIG.Enabled and tick() - startTime < timeout do
		if not root.Parent then return false end
		
		local distance = (root.Position - destination).Magnitude
		
		-- Chegou perto o suficiente
		if distance <= arrivedDistance then
			return true
		end
		
		task.wait(0.1)
	end
	
	return CONFIG.Enabled
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
local checkAndCollectTokens

local function startTokenCollector()
	if TOKEN_COLLECTOR.Running then return end
	TOKEN_COLLECTOR.Running = true
	
	task.spawn(function()
		while TOKEN_COLLECTOR.Enabled and CONFIG.Enabled and isCurrentSession() do
			if CONFIG.CollectTokens and not collectingToken then
				checkAndCollectTokens()
			end
			task.wait(TOKEN_COLLECTOR.CheckInterval)
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

local function getNearestToken(maxDistance)
	local root = getRoot()
	if not root then return nil end
	
	local tokensFolder = workspace:FindFirstChild("Collectibles")
	if not tokensFolder then return nil end
	
	local bestToken = nil
	local bestScore = -math.huge
	
	for _, token in ipairs(tokensFolder:GetChildren()) do
		if token:IsA("BasePart") or (token:IsA("Model") and token.PrimaryPart) then
			local tokenPos = token:IsA("BasePart") and token.Position or token.PrimaryPart.Position
			local dist = (root.Position - tokenPos).Magnitude
			
			if dist < (maxDistance or 60) then
				-- Calcula score: prioridade - distância
				local priority = getTokenPriority(token.Name)
				local score = priority - (dist * 0.5) -- Distância afeta menos que prioridade
				
				if score > bestScore then
					bestToken = token
					bestScore = score
				end
			end
		end
	end
	
	return bestToken
end

local function collectToken(token)
	if not token or not token.Parent then return false end
	
	collectingToken = true
	local character = player.Character
	if not character then collectingToken = false return false end
	
	local root = character:FindFirstChild("HumanoidRootPart")
	local humanoid = character:FindFirstChild("Humanoid")
	
	if not root or not humanoid then collectingToken = false return false end
	
	local tokenPos
	if token:IsA("BasePart") then
		tokenPos = token.Position
	elseif token:IsA("Model") and token.PrimaryPart then
		tokenPos = token.PrimaryPart.Position
	else
		collectingToken = false
		return false
	end
	
	-- Salva velocidade atual (pode ter boost ativo!)
	local currentSpeed = humanoid.WalkSpeed
	local priority = getTokenPriority(token.Name)
	
	-- Aumenta velocidade para pegar tokens mais rápido
	local speedBoost = CONFIG.MoveSpeed * 1.8
	if priority >= 70 then
		speedBoost = CONFIG.MoveSpeed * 2.5 -- Tokens importantes = ainda mais rápido
	end
	
	-- Só aumenta se não tiver boost melhor
	if currentSpeed < speedBoost then
		humanoid.WalkSpeed = speedBoost
	end
	
	-- Move direto para o token (mais agressivo)
	humanoid:MoveTo(tokenPos)
	
	-- Timeout maior para tokens distantes
	local distance = (root.Position - tokenPos).Magnitude
	local timeout = tick() + math.min(distance / 20, 5) -- Timeout dinâmico
	
	while token.Parent and (root.Position - tokenPos).Magnitude > 6 and tick() < timeout and CONFIG.Enabled do
		-- Continua indo para o token se ele ainda existir
		if token.Parent then
			local newPos = token:IsA("BasePart") and token.Position or token.PrimaryPart.Position
			humanoid:MoveTo(newPos)
		end
		task.wait(0.05)
	end
	
	-- Aguarda coleta automática
	if token.Parent then
		local collectTime = tick()
		while token.Parent and tick() - collectTime < 0.8 do
			task.wait(0.05)
		end
	end
	
	-- Restaura velocidade APENAS se mudamos
	if humanoid.WalkSpeed > currentSpeed then
		humanoid.WalkSpeed = math.max(currentSpeed, CONFIG.MoveSpeed)
	end
	
	collectingToken = false
	return not token.Parent
end

checkAndCollectTokens = function()
	if collectingToken then return end
	
	local token = getNearestToken(CONFIG.MaxTokenDistance)
	if token then
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
end

-- ═══════════════════════════════════════════════════════════════
--                  COCONUT COMBO CATCHER
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
			local tokenPos = nil
			if token:IsA("BasePart") then
				tokenPos = token.Position
			elseif token:IsA("Model") and token.PrimaryPart then
				tokenPos = token.PrimaryPart.Position
			end
			
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
		if dist < nearestDist and dist < 200 then -- Max 200 studs
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
		while COCONUT_CATCHER.Enabled and CONFIG.Enabled and isCurrentSession() do
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
	Enabled = true, -- SEMPRE ATIVO por padrão
	Running = false,
	IsFarming = false, -- flag: evita farm duplo (loop principal + thread)
	CheckInterval = 1, -- Verifica a cada 1 segundo
	LastCheck = 0,
	CurrentBalloon = nil,
	FarmRadius = 25, -- Raio para farmar ao redor do balão
	MinFarmTime = 15, -- Mínimo 15 segundos por balão
	MaxFarmTime = 45 -- Máximo 45 segundos por balão
}

-- Detecta balões ativos usando a estrutura real do BSS
local function findActiveBalloons()
	local balloons = {}
	
	-- Procura na pasta correta: Workspace.Balloons.FieldBalloons
	local balloonsFolder = workspace:FindFirstChild("Balloons")
	if not balloonsFolder then return balloons end
	
	local fieldBalloons = balloonsFolder:FindFirstChild("FieldBalloons")
	if not fieldBalloons then return balloons end
	
	local playerName = player.Name
	
	for _, balloon in ipairs(fieldBalloons:GetChildren()) do
		if balloon:IsA("Model") then
			-- Verifica se é um balão ativo (atributo ClientMotionEnabled)
			local isActive = balloon:GetAttribute("ClientMotionEnabled")
			
			-- Verifica se é do jogador
			local owner = balloon:FindFirstChild("PlayerName")
			local isOurs = owner and owner:IsA("StringValue") and owner.Value == playerName
			
			-- Pega BalloonBody (parte visual)
			local balloonBody = balloon:FindFirstChild("BalloonBody")
			
			if isActive and isOurs and balloonBody and balloonBody:IsA("BasePart") then
				-- Pega informações do balão
				local zoneName = balloon:FindFirstChild("ZoneName")
				local zone = zoneName and zoneName:IsA("StringValue") and zoneName.Value or "Unknown"
				
				local motionKind = balloon:GetAttribute("ClientMotionKind") or "Unknown"
				local homePos = balloon:GetAttribute("ClientMotionHomePosition")
				local wanderRadius = balloon:GetAttribute("ClientMotionWanderRadius") or 20
				
				table.insert(balloons, {
					Model = balloon,
					Body = balloonBody,
					Position = balloonBody.Position,
					Zone = zone,
					MotionKind = motionKind,
					HomePosition = homePos,
					WanderRadius = wanderRadius,
					IsReturning = motionKind == "FieldBalloonReturn" -- Está voltando para colmeia
				})
			end
		end
	end
	
	return balloons
end

-- Farma um balão de forma inteligente
local function farmBalloon(balloonData)
	if not balloonData or not balloonData.Body.Parent then return false end
	if BALLOON_FARM.IsFarming then return false end -- evita farm duplo
	
	-- Se o balão está voltando, não vale a pena farmar
	if balloonData.IsReturning then 
		return false 
	end
	
	BALLOON_FARM.IsFarming = true
	
	-- Calcula posição ideal: embaixo do balão + offset para evitar colisão
	local balloonPos = balloonData.Position
	local farmPos = balloonPos + Vector3.new(0, -8, 0) -- 8 studs embaixo
	
	-- Tween até o balão
	if not tweenToField(farmPos) then
		BALLOON_FARM.IsFarming = false
		return false
	end
	
	if not CONFIG.Enabled then
		BALLOON_FARM.IsFarming = false
		return false
	end
	
	RUNTIME.Stats.BalloonsVisited = RUNTIME.Stats.BalloonsVisited + 1
	
	pcall(function()
		if Rayfield and Rayfield.Notify then
			Rayfield:Notify({
				Title = "🎈 Balloon Found!",
				Content = string.format("Farming %s balloon at %s", 
					balloonData.MotionKind == "FieldBalloon" and "active" or "moving",
					balloonData.Zone),
				Duration = 3,
				Image = 4483362458,
			})
		end
	end)
	
	-- Farma ao redor do balão seguindo seu movimento
	local farmStartTime = tick()
	local lastPosUpdate = tick()
	local lastBalloonPos = balloonPos
	
	while CONFIG.Enabled and balloonData.Body.Parent and tick() - farmStartTime < BALLOON_FARM.MaxFarmTime do
		-- Verifica se o balão ainda é válido
		if not balloonData.Model.Parent or balloonData.Model:GetAttribute("ClientMotionEnabled") == false then
			break
		end
		
		-- Verifica se começou a voltar para colmeia
		local motionKind = balloonData.Model:GetAttribute("ClientMotionKind")
		if motionKind == "FieldBalloonReturn" then
			break -- Balão está voltando, para de farmar
		end
		
		-- Atualiza posição do balão (balões se movem!)
		if tick() - lastPosUpdate > 2 then
			balloonPos = balloonData.Body.Position
			
			-- Se o balão se moveu muito, atualiza posição
			if (balloonPos - lastBalloonPos).Magnitude > 15 then
				farmPos = balloonPos + Vector3.new(0, -8, 0)
				moveTo(farmPos)
			end
			
			lastBalloonPos = balloonPos
			lastPosUpdate = tick()
		end
		
		-- Move um pouco ao redor do balão (dentro do raio de coleta)
		local offset = Vector3.new(
			math.random(-BALLOON_FARM.FarmRadius, BALLOON_FARM.FarmRadius),
			0,
			math.random(-BALLOON_FARM.FarmRadius, BALLOON_FARM.FarmRadius)
		)
		moveTo(farmPos + offset)
		
		task.wait(1.5)
		
		-- Garante tempo mínimo de farm
		if tick() - farmStartTime < BALLOON_FARM.MinFarmTime then
			continue
		end
		
		-- Se o pólen está alto, volta para converter
		local pollenPercent = (pollenValue.Value / capacityValue.Value) * 100
		if pollenPercent >= CONFIG.ConvertAt then
			break
		end
	end
	
	BALLOON_FARM.IsFarming = false
	return true
end

-- Thread de verificação contínua de balões (backup para quando o loop principal não detectar)
local function startBalloonFarm()
	if BALLOON_FARM.Running then return end
	BALLOON_FARM.Running = true
	
	task.spawn(function()
		while BALLOON_FARM.Enabled and CONFIG.Enabled and isCurrentSession() do
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

-- Setup do listener de balloon inflate (após todas as variáveis estarem declaradas)
-- IMPORTANTE: Só chama após Rayfield estar carregado
task.defer(function()
	task.wait(2) -- aguarda Rayfield carregar completamente
	setupBalloonInflateListener()
end)

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
	tweenToField(cloudPos)
	
	if not CONFIG.Enabled then return false end
	
	RUNTIME.Stats.CloudsVisited = RUNTIME.Stats.CloudsVisited + 1
	
	-- Fica farmando embaixo da nuvem
	local farmTime = tick()
	while CONFIG.Enabled and cloudData.Part.Parent and tick() - farmTime < 45 do
		-- Move ao redor da nuvem
		local offset = Vector3.new(math.random(-8, 8), 0, math.random(-8, 8))
		moveTo(cloudPos + offset)
		
		task.wait(1)
	end
	
	return true
end

local function startCloudFarm()
	if CLOUD_FARM.Running then return end
	CLOUD_FARM.Running = true
	
	task.spawn(function()
		while CLOUD_FARM.Enabled and CONFIG.Enabled and isCurrentSession() do
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

local function collectNearbyFlames()
	local character = player.Character
	if not character then return end
	
	local root = character:FindFirstChild("HumanoidRootPart")
	local humanoid = character:FindFirstChild("Humanoid")
	if not root or not humanoid then return end
	
	local flamesFolder = workspace:FindFirstChild("PlayerFlames")
	if not flamesFolder then return end
	
	for _, flame in ipairs(flamesFolder:GetChildren()) do
		if flame:IsA("BasePart") and (root.Position - flame.Position).Magnitude < 30 then
			-- Move para perto da flame usando Humanoid
			local flamePos = flame.Position
			if (root.Position - flamePos).Magnitude > 5 then
				humanoid:MoveTo(flamePos)
				task.wait(0.3)
			end
			
			-- Aguarda coleta
			task.wait(0.2)
			if not flame.Parent then
				RUNTIME.Stats.FlamesCollected = RUNTIME.Stats.FlamesCollected + 1
			end
		end
	end
end

local function collectNearbyMarks()
	local root = getRoot()
	if not root then return end
	
	local marksFolder = workspace:FindFirstChild("Marks")
	if not marksFolder then return end
	
	for _, mark in ipairs(marksFolder:GetChildren()) do
		if mark:IsA("BasePart") and (root.Position - mark.Position).Magnitude < 25 then
			-- Marcas são coletadas automaticamente ao passar perto
			task.wait(0.1)
			if not mark.Parent then
				RUNTIME.Stats.MarksCollected = RUNTIME.Stats.MarksCollected + 1
			end
		end
	end
end

-- ═══════════════════════════════════════════════════════════════
--                     PLANTERS SYSTEM
-- ═══════════════════════════════════════════════════════════════

local function scanPlanters()
	PLANTERS.ActivePlanters = {}
	local plantersFolder = workspace:FindFirstChild("Planters")
	if not plantersFolder then return end
	
	for _, planter in ipairs(plantersFolder:GetChildren()) do
		if planter:IsA("Model") or planter:IsA("MeshPart") then
			-- Detecta PlanterBulb (indicador visual de pronto)
			local bulb = planter:FindFirstChild("PlanterBulb") or planter:FindFirstChildWhichIsA("MeshPart", true)
			
			if bulb then
				local planterData = {
					Model = planter,
					Bulb = bulb,
					Position = planter:IsA("Model") and planter:GetPivot().Position or planter.Position,
					Ready = false
				}
				
				-- Verifica se tem NumberValue (porcentagem)
				local percentValue = bulb:FindFirstChild("NumberValue")
				if percentValue and percentValue.Value then
					planterData.Percent = percentValue.Value
					planterData.Ready = percentValue.Value >= 100
				end
				
				table.insert(PLANTERS.ActivePlanters, planterData)
			end
		end
	end
end

local function collectReadyPlanters()
	if not PLANTERS.AutoCollect then return end
	
	scanPlanters()
	
	for _, planterData in ipairs(PLANTERS.ActivePlanters) do
		if planterData.Ready then
			local root = getRoot()
			if not root then return end
			
			-- Move para o planter
			local planterPos = planterData.Position + Vector3.new(0, 3, 0)
			moveTo(planterPos)
			
			if not CONFIG.Enabled then return end
			
			-- Tenta coletar (aproxima-se)
			task.wait(0.5)
			
			-- Verifica se foi coletado
			if not planterData.Model.Parent then
				RUNTIME.Stats.PlantersHarvested = RUNTIME.Stats.PlantersHarvested + 1
				
				Rayfield:Notify({
					Title = "🪴 Planter Collected!",
					Content = "Harvested a planter successfully",
					Duration = 3,
					Image = 4483362458,
				})
			end
		end
	end
end

local function checkPlanters()
	if not PLANTERS.Enabled then return end
	
	local currentTime = tick()
	if currentTime - PLANTERS.LastCheck < PLANTERS.CheckInterval then return end
	PLANTERS.LastCheck = currentTime
	
	collectReadyPlanters()
end

-- ═══════════════════════════════════════════════════════════════
--                     COLETA NO CAMPO (INTELIGENTE)
-- ═══════════════════════════════════════════════════════════════

-- Detecta as MELHORES flores no campo (prioriza tamanho e polen)
local function findFlowersInField(fieldObj)
	local flowers = {}
	local fPos = getFieldPosition(fieldObj)
	if not fPos then return flowers end
	
	-- Procura flores próximas ao campo
	for _, obj in ipairs(workspace:GetDescendants()) do
		if obj:IsA("BasePart") and obj.Name:find("Flower") then
			local dist = (obj.Position - fPos).Magnitude
			
			-- Só considera flores dentro do raio do campo
			if dist <= CONFIG.FieldRadius + 10 then
				-- Calcula prioridade baseado em TAMANHO (flores maiores = mais polen)
				-- Prioridade: 90% tamanho, 10% proximidade
				local size = obj.Size.Magnitude
				local priority = (size * 10) - (dist * 0.5) -- Tamanho tem 20x mais peso
				
				-- BONUS: Flores coloridas específicas (geralmente têm mais polen)
				local color = obj.Color
				if color.R > 0.8 and color.G < 0.3 then -- Vermelho
					priority = priority + 15
				elseif color.B > 0.8 then -- Azul
					priority = priority + 12
				elseif color.R > 0.8 and color.G > 0.8 then -- Amarelo/Dourado
					priority = priority + 20
				end
				
				table.insert(flowers, {
					Part = obj,
					Position = obj.Position,
					Priority = priority,
					Distance = dist,
					Size = size
				})
			end
		end
	end
	
	-- Ordena por prioridade (maior primeiro) = MELHORES FLORES PRIMEIRO
	table.sort(flowers, function(a, b)
		return a.Priority > b.Priority
	end)
	
	return flowers
end

-- Detecta GRUPOS DE POLEN densos (muitos tokens próximos = melhor area)
local function findBestPollenArea(position, radius)
	local pollenTokens = {}
	local tokensFolder = workspace:FindFirstChild("Collectibles")
	if not tokensFolder then return nil end
	
	-- Coleta TODOS os tokens de polen no campo
	for _, token in ipairs(tokensFolder:GetChildren()) do
		if token.Name:find("Pollen") or token.Name:find("Sparkle") or token.Name:find("Honey") then
			local tokenPos = token:IsA("BasePart") and token.Position or (token:IsA("Model") and token.PrimaryPart and token.PrimaryPart.Position)
			
			if tokenPos then
				local dist = (tokenPos - position).Magnitude
				if dist <= radius then
					table.insert(pollenTokens, {
						Token = token,
						Position = tokenPos,
						Distance = dist
					})
				end
			end
		end
	end
	
	if #pollenTokens == 0 then return nil end
	
	-- Encontra a AREA com mais polen (clusters)
	local bestArea = nil
	local bestScore = 0
	local clusterRadius = 8 -- Raio para considerar "cluster"
	
	for _, token in ipairs(pollenTokens) do
		local score = 0
		-- Conta quantos tokens estao proximos deste
		for _, other in ipairs(pollenTokens) do
			if other ~= token then
				local dist = (token.Position - other.Position).Magnitude
				if dist <= clusterRadius then
					score = score + 1
				end
			end
		end
		
		-- Area com MAIS polen = melhor
		if score > bestScore then
			bestScore = score
			bestArea = token.Position
		end
	end
	
	return bestArea
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
	
	-- Primeiro escaneamento
	currentFlowers = findFlowersInField(fieldObj)
	lastFlowerScan = tick()
	
	while CONFIG.Enabled and isCurrentSession() and CONFIG.SelectedField == fieldObj do
		local pollenPercent = (pollenValue.Value / capacityValue.Value) * 100
		if pollenPercent >= CONFIG.ConvertAt then
			break
		end
		
		-- Coleta flames (SE ATIVADO)
		if CONFIG.CollectFlames and tick() - lastFlameCheck > 2 then
			collectNearbyFlames()
			lastFlameCheck = tick()
		end
		
		-- Coleta marks (SE ATIVADO)
		if CONFIG.CollectMarks and tick() - lastMarkCheck > 1.5 then
			collectNearbyMarks()
			lastMarkCheck = tick()
		end
		
		-- Verifica planters (SE ATIVADO)
		if PLANTERS.Enabled then
			checkPlanters()
		end
		
		-- Re-escaneia flores a cada 5 segundos para pegar NOVAS flores melhores
		if tick() - lastFlowerScan > 5 then
			currentFlowers = findFlowersInField(fieldObj)
			currentFlowerIndex = 1
			lastFlowerScan = tick()
		end
		
		-- PRIORIDADE 1: Vai para a MELHOR flor disponível (maior polen)
		local targetPos = nil
		
		if #currentFlowers > 0 and currentFlowerIndex <= #currentFlowers then
			local flower = currentFlowers[currentFlowerIndex]
			
			-- Verifica se a flor ainda existe
			if flower.Part.Parent then
				targetPos = flower.Position + Vector3.new(0, CONFIG.CollectHeight, 0)
			else
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

		if CONFIG.FarmMode == "Route Sweep" and #fieldRoute > 0 then
			local root = getRoot()
			local routeTarget = fieldRoute[routeIndex]
			if root and (root.Position - routeTarget).Magnitude <= 7 then
				routeIndex = (routeIndex % #fieldRoute) + 1
				routeTarget = fieldRoute[routeIndex]
			end
			targetPos = routeTarget + Vector3.new(0, CONFIG.CollectHeight, 0)
		end

		-- Move para a posicao OTIMA
		moveTo(targetPos)
		if not CONFIG.Enabled then return end
		
		-- Fica coletando por um tempo antes de reavaliação
		-- Tempo reduzido para sempre buscar melhores posições
		task.wait(CONFIG.CollectInterval) 
	end
end

local function convertAtHive()
	local hive = getHive()
	if not hive then 
		task.wait(2)
		return 
	end
	
	local hivePos = hive.Position + Vector3.new(0, 3, 0)
	
	-- Usa TWEEN para voltar rápido à colmeia (teleporte suave)
	if tweenToField(hivePos) then
		if eventsApi and eventsApi.ClientCall then
			pcall(function()
				eventsApi.ClientCall("PlayerHiveCommand", "ToggleHoneyMaking")
			end)
		end
		
		task.wait(CONFIG.WaitAtHive or 3)
	end
end

-- ═══════════════════════════════════════════════════════════════
--                     LOOP PRINCIPAL
-- ═══════════════════════════════════════════════════════════════

local function automationLoop()
	if SESSION.AutomationRunning then return end
	SESSION.AutomationRunning = true
	RUNTIME.Active = true
	RUNTIME.Stats.StartTime = tick()
	RUNTIME.Stats.LastStatsUpdate = tick()
	RUNTIME.Stats.LastPollenValue = pollenValue.Value
	RUNTIME.Stats.LastHoneyValue = honeyValue.Value
	
	-- Inicia o sistema de coleta contínuo
	TOOL_COLLECT.Enabled = true
	enableToolCollect()
	
	-- Inicia o coletor de tokens contínuo
	TOKEN_COLLECTOR.Enabled = true
	startTokenCollector()
	
	-- Inicia sistemas especiais (se habilitados)
	if CONFIG.CoconutCatcher then
		COCONUT_CATCHER.Enabled = true
		startCoconutCatcher()
	end
	
	-- Balloon farm SEMPRE inicia junto com o auto farm
	BALLOON_FARM.Enabled = true
	CONFIG.FarmBalloons = true
	startBalloonFarm()
	
	if CONFIG.FarmClouds then
		CLOUD_FARM.Enabled = true
		startCloudFarm()
	end
	
	while CONFIG.Enabled and isCurrentSession() do
		if not CONFIG.SelectedField or not CONFIG.SelectedField.Parent then 
			task.wait(0.5)
		elseif pollenValue.Value >= capacityValue.Value then
			-- Atualiza pólen coletado antes de converter
			local currentPollen = pollenValue.Value
			if currentPollen > RUNTIME.Stats.LastPollenValue then
				RUNTIME.Stats.PollenCollected = RUNTIME.Stats.PollenCollected + (currentPollen - RUNTIME.Stats.LastPollenValue)
			end
			RUNTIME.Stats.LastPollenValue = 0
			
			convertAtHive()
			
			-- Atualiza mel gerado após converter
			local currentHoney = honeyValue.Value
			if currentHoney > RUNTIME.Stats.LastHoneyValue then
				RUNTIME.Stats.HoneyMade = RUNTIME.Stats.HoneyMade + (currentHoney - RUNTIME.Stats.LastHoneyValue)
			end
			RUNTIME.Stats.LastHoneyValue = currentHoney
		else
			-- Atualiza pólen durante farm
			local currentPollen = pollenValue.Value
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
				-- Usa TWEEN para ir ao campo (teleporte suave)
				tweenToField(fPos + Vector3.new(0, 3, 0))
				
				if CONFIG.Enabled and isCurrentSession() then 
					-- Depois ANDA normalmente no campo
					collectAtField(CONFIG.SelectedField)
				end
			else
				task.wait(0.5)
			end
		end
		task.wait(0.1)
	end
	
	-- Para os sistemas
	TOOL_COLLECT.Enabled = false
	TOKEN_COLLECTOR.Enabled = false
	COCONUT_CATCHER.Enabled = false
	-- Balloon farm para junto mas pode ser reativado manualmente
	BALLOON_FARM.Enabled = false
	CLOUD_FARM.Enabled = false
	
	RUNTIME.Active = false
	SESSION.AutomationRunning = false
	CONFIG.Enabled = false
end

-- ═══════════════════════════════════════════════════════════════
--                    INTERFACE RAYFIELD
-- ═══════════════════════════════════════════════════════════════

local Window = Rayfield:CreateWindow({
	Name = "🐝 BSS Auto Farm",
	LoadingTitle = "Bee Swarm Simulator",
	LoadingSubtitle = "by Professional Scripter",
	ConfigurationSaving = {
		Enabled = false,
		FolderName = nil,
		FileName = "BSS_AutoFarm"
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
			CONFIG.Enabled = true
			
			Rayfield:Notify({
				Title = "✅ Auto Farm Started",
				Content = "Farming at " .. CONFIG.SelectedField.Name,
				Duration = 3,
				Image = 4483362458,
			})
			
			task.spawn(automationLoop)
		else
			CONFIG.Enabled = false
			-- Para o sistema de coleta
			TOOL_COLLECT.Enabled = false
			TOKEN_COLLECTOR.Enabled = false
			COCONUT_CATCHER.Enabled = false
			BALLOON_FARM.Enabled = false
			CLOUD_FARM.Enabled = false
			
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

FarmTab:CreateParagraph({
	Title = "🎯 Intelligent Farming System",
	Content = "This script uses SMART POSITIONING:\n\n✅ ALWAYS targets the BIGGEST flowers (most pollen)\n✅ Color bonus: Yellow/Gold (+20), Red (+15), Blue (+12)\n✅ Detects POLLEN CLUSTERS (groups of tokens)\n✅ NO random offsets - only optimal positions!\n\nThe script constantly scans and adapts to find the BEST spots in your field!"
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

FarmTab:CreateParagraph({
	Title = "Farm modes",
	Content = "Smart Flowers follows the original flower and pollen-cluster selection. Route Sweep follows a stable grid inside the selected field."
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

CollectTab:CreateParagraph({
	Title = "Token Collection Info",
	Content = "Tokens are collected by a separate continuous thread. Lower check interval = more responsive but more CPU usage. Default 0.2s is recommended."
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

CollectTab:CreateParagraph({
	Title = "About Flames",
	Content = "PlayerFlames appear from certain bee abilities and provide bonus pollen. The script will automatically walk to nearby flames to collect them."
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

CollectTab:CreateParagraph({
	Title = "About Marks",
	Content = "Marks are special indicators left by certain bee abilities (Gummy Bee, etc.). They provide powerful bonuses when collected!"
})

-- ═══════════════════════════════════════════════════════════════
--                       TAB: SPECIAL FEATURES
-- ═══════════════════════════════════════════════════════════════

local SpecialTab = Window:CreateTab("⭐ Special", 4483362458)
local SpecialSection = SpecialTab:CreateSection("🥥 Coconut Combo Catcher")

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

SpecialTab:CreateParagraph({
	Title = "🥥 About Coconut Combo",
	Content = "Automatically detects and collects Combo Coconuts when they appear. The script will temporarily leave your field to catch them, then return to farming."
})

SpecialTab:CreateSection("🎈 Balloon Farming")

SpecialTab:CreateParagraph({
	Title = "🎈 Balloon Farm — ALWAYS ACTIVE",
	Content = "Balloon farming is ALWAYS enabled when Auto Farm is running.\n\nDetection uses Workspace.Balloons.FieldBalloons (real game structure) + BalloonInflate event for instant reaction.\n\nUse the toggle below ONLY to temporarily pause balloon farm without stopping the main farm."
})

local BalloonToggle = SpecialTab:CreateToggle({
	Name = "🎈 Balloon Farm (pause only)",
	CurrentValue = true, -- começa ativo
	Flag = "BalloonToggle",
	Callback = function(Value)
		CONFIG.FarmBalloons = Value
		BALLOON_FARM.Enabled = Value
		
		if Value and CONFIG.Enabled then
			startBalloonFarm()
		end
		
		Rayfield:Notify({
			Title = Value and "✅ Balloon Farm RESUMED" or "⏸️ Balloon Farm PAUSED",
			Content = Value and "Balloon farming is active again!" or "Balloon farming paused. Will resume on next toggle.",
			Duration = 3,
			Image = 4483362458,
		})
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

SpecialTab:CreateParagraph({
	Title = "☁️ About Cloud Farming",
	Content = "Automatically detects clouds with flowers and farms underneath them. Cloud flowers provide unique pollen types and bonuses!"
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
--                       TAB: PLANTERS
-- ═══════════════════════════════════════════════════════════════

local PlanterTab = Window:CreateTab("🪴 Planters", 4483362458)
local PlanterSection = PlanterTab:CreateSection("Planter Management")

local PlanterToggle = PlanterTab:CreateToggle({
	Name = "🪴 Enable Planter System",
	CurrentValue = false,
	Flag = "PlanterToggle",
	Callback = function(Value)
		PLANTERS.Enabled = Value
		
		if Value then
			scanPlanters()
			Rayfield:Notify({
				Title = "✅ Planter System ON",
				Content = string.format("Found %d active planters", #PLANTERS.ActivePlanters),
				Duration = 3,
				Image = 4483362458,
			})
		else
			Rayfield:Notify({
				Title = "⛔ Planter System OFF",
				Content = "Planters will not be managed",
				Duration = 2,
				Image = 4483362458,
			})
		end
	end,
})

local AutoCollectPlanter = PlanterTab:CreateToggle({
	Name = "📦 Auto-Collect Planters",
	CurrentValue = true,
	Flag = "AutoCollectPlanter",
	Callback = function(Value)
		PLANTERS.AutoCollect = Value
	end,
})

PlanterTab:CreateButton({
	Name = "🔍 Scan for Planters",
	Callback = function()
		scanPlanters()
		
		Rayfield:Notify({
			Title = "🔍 Planter Scan Complete",
			Content = string.format("Found %d active planters", #PLANTERS.ActivePlanters),
			Duration = 3,
			Image = 4483362458,
		})
		
		-- Mostra detalhes
		for i, planter in ipairs(PLANTERS.ActivePlanters) do
			if planter.Percent then
				print(string.format("[Planter %d] %.1f%% - %s", i, planter.Percent, planter.Ready and "READY" or "Growing"))
			end
		end
	end,
})

PlanterTab:CreateSection("ℹ️ Info")

PlanterTab:CreateParagraph({
	Title = "How it works",
	Content = "The script will automatically check your planters every 5 seconds. When a planter reaches 100%, it will collect it for you!"
})

-- ═══════════════════════════════════════════════════════════════
--                         TAB: STATS
-- ═══════════════════════════════════════════════════════════════

local StatsTab = Window:CreateTab("📊 Statistics", 4483362458)
local StatsSection = StatsTab:CreateSection("📈 Real-Time Stats")

local PollenLabel = StatsTab:CreateLabel("Pollen: 0 / 0 (0%)")
local HoneyLabel = StatsTab:CreateLabel("Honey: 0")
local RuntimeLabel = StatsTab:CreateLabel("Runtime: 00:00:00")
local CurrentStrategyLabel = StatsTab:CreateLabel("Strategy: Optimizing...")

StatsTab:CreateSection("📊 Session Stats")

local PollenCollectedLabel = StatsTab:CreateLabel("Pollen Collected: 0")
local PollenPerHourLabel = StatsTab:CreateLabel("Pollen/Hour: 0")
local HoneyMadeLabel = StatsTab:CreateLabel("Honey Made: 0")
local HoneyPerHourLabel = StatsTab:CreateLabel("Honey/Hour: 0")
local TokensLabel = StatsTab:CreateLabel("Tokens: 0")
local FlamesLabel = StatsTab:CreateLabel("Flames: 0")
local MarksLabel = StatsTab:CreateLabel("Marks: 0")

StatsTab:CreateSection("🔧 Collection System")

local CollectCountLabel = StatsTab:CreateLabel("ToolCollect Calls: 0")
local CollectRateLabel = StatsTab:CreateLabel("Collect Rate: 0/s")

StatsTab:CreateSection("🪴 Planter Stats")

local PlantersLabel = StatsTab:CreateLabel("Planters Harvested: 0")
local ActivePlantersLabel = StatsTab:CreateLabel("Active Planters: 0")

StatsTab:CreateSection("⭐ Special Features Stats")

local CoconutsLabel = StatsTab:CreateLabel("Coconuts Caught: 0")
local BalloonsLabel = StatsTab:CreateLabel("Balloons Visited: 0")
local BalloonsActiveLabel = StatsTab:CreateLabel("🎈 Active Balloons: checking...")
local CloudsLabel = StatsTab:CreateLabel("Clouds Visited: 0")

local function formatNumber(num)
	if num >= 1000000000 then
		return string.format("%.2fB", num / 1000000000)
	elseif num >= 1000000 then
		return string.format("%.2fM", num / 1000000)
	elseif num >= 1000 then
		return string.format("%.2fK", num / 1000)
	else
		return string.format("%.0f", num)
	end
end

-- Atualiza stats
task.spawn(function()
	local lastCollectCount = 0
	local lastCollectTime = tick()
	
	while isCurrentSession() and task.wait(1) do
		pcall(function()
			-- Stats básicos
			local pollen = pollenValue.Value or 0
			local capacity = capacityValue.Value or 1
			local percent = capacity > 0 and (pollen / capacity * 100) or 0
			
			PollenLabel:Set(string.format("Pollen: %s / %s (%.1f%%)", 
				formatNumber(pollen), formatNumber(capacity), percent))
			HoneyLabel:Set(string.format("Honey: %s", formatNumber(honeyValue.Value or 0)))
			
			-- Runtime
			if RUNTIME.Stats.StartTime > 0 then
				local elapsed = tick() - RUNTIME.Stats.StartTime
				local hours = math.floor(elapsed / 3600)
				local minutes = math.floor((elapsed % 3600) / 60)
				local seconds = math.floor(elapsed % 60)
				RuntimeLabel:Set(string.format("Runtime: %02d:%02d:%02d", hours, minutes, seconds))
				
				-- Calcula por hora
				local hoursElapsed = elapsed / 3600
				if hoursElapsed > 0 then
					local pollenPerHour = RUNTIME.Stats.PollenCollected / hoursElapsed
					local honeyPerHour = RUNTIME.Stats.HoneyMade / hoursElapsed
					
					PollenPerHourLabel:Set(string.format("Pollen/Hour: %s", formatNumber(pollenPerHour)))
					HoneyPerHourLabel:Set(string.format("Honey/Hour: %s", formatNumber(honeyPerHour)))
				end
			else
				RuntimeLabel:Set("Runtime: Not Started")
			end
			
			-- Session stats
			PollenCollectedLabel:Set(string.format("Pollen Collected: %s", 
				formatNumber(RUNTIME.Stats.PollenCollected)))
			HoneyMadeLabel:Set(string.format("Honey Made: %s", 
				formatNumber(RUNTIME.Stats.HoneyMade)))
			TokensLabel:Set(string.format("Tokens: %d", RUNTIME.Stats.TokensCollected))
			FlamesLabel:Set(string.format("Flames: %d", RUNTIME.Stats.FlamesCollected))
			MarksLabel:Set(string.format("Marks: %d", RUNTIME.Stats.MarksCollected))
			
			-- Collection system stats
			CollectCountLabel:Set(string.format("ToolCollect Calls: %d", TOOL_COLLECT.CollectCount))
			
			local currentTime = tick()
			local timeDiff = currentTime - lastCollectTime
			if timeDiff > 0 then
				local collectDiff = TOOL_COLLECT.CollectCount - lastCollectCount
				local collectRate = collectDiff / timeDiff
				CollectRateLabel:Set(string.format("Collect Rate: %.1f/s", collectRate))
			end
			lastCollectCount = TOOL_COLLECT.CollectCount
			lastCollectTime = currentTime
			
			-- Planter stats
			PlantersLabel:Set(string.format("Planters Harvested: %d", 
				RUNTIME.Stats.PlantersHarvested))
			ActivePlantersLabel:Set(string.format("Active Planters: %d", 
				#PLANTERS.ActivePlanters))
			
			-- Special features stats
			CoconutsLabel:Set(string.format("Coconuts Caught: %d", RUNTIME.Stats.CoconutsCaught))
			BalloonsLabel:Set(string.format("Balloons Visited: %d", RUNTIME.Stats.BalloonsVisited))
			
			-- Conta balloons ativos em tempo real
			local activeBalloonCount = 0
			local balloonsFolder = workspace:FindFirstChild("Balloons")
			if balloonsFolder then
				local fieldBalloons = balloonsFolder:FindFirstChild("FieldBalloons")
				if fieldBalloons then
					for _, b in ipairs(fieldBalloons:GetChildren()) do
						if b:IsA("Model") and b:GetAttribute("ClientMotionEnabled") then
							local owner = b:FindFirstChild("PlayerName")
							if owner and owner.Value == player.Name then
								activeBalloonCount = activeBalloonCount + 1
							end
						end
					end
				end
			end
			local balloonStatus = BALLOON_FARM.IsFarming and " [FARMING NOW]" or ""
			BalloonsActiveLabel:Set(string.format("🎈 Active Balloons: %d%s", activeBalloonCount, balloonStatus))
			
			CloudsLabel:Set(string.format("Clouds Visited: %d", RUNTIME.Stats.CloudsVisited))
		end)
	end
end)

-- ═══════════════════════════════════════════════════════════════
--                         TAB: ADVANCED
-- ═══════════════════════════════════════════════════════════════

local AdvancedTab = Window:CreateTab("⚙️ Advanced", 4483362458)
local AdvancedSection = AdvancedTab:CreateSection("🔧 Advanced Settings")

AdvancedTab:CreateParagraph({
	Title = "⚠️ Caution",
	Content = "These settings are for advanced users. Incorrect values may affect performance or functionality."
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

AdvancedTab:CreateSection("ℹ️ Explanations")

AdvancedTab:CreateParagraph({
	Title = "Collect Height",
	Content = "Height offset when moving around the field. Higher values may help avoid obstacles but can look unnatural."
})

AdvancedTab:CreateParagraph({
	Title = "Farm Move Interval",
	Content = "Time between movements in the field. Lower = more frequent position changes. Default: 0.1s"
})

AdvancedTab:CreateParagraph({
	Title = "ToolCollect Cooldown",
	Content = "Minimum time between ToolCollect calls. Lower = more collection attempts but higher server load. Default: 0.08s"
})

-- ═══════════════════════════════════════════════════════════════
--                         TAB: INFO
-- ═══════════════════════════════════════════════════════════════

local InfoTab = Window:CreateTab("ℹ️ Info", 4483362458)
InfoTab:CreateSection("About")

InfoTab:CreateParagraph({
	Title = "🐝 BSS Auto Farm v4.0",
	Content = "A professional auto-farming script for Bee Swarm Simulator with modern Rayfield UI and fully customizable features including SPECIAL auto-features!"
})

InfoTab:CreateParagraph({
	Title = "✨ Features",
	Content = "• 🎯 INTELLIGENT FARM: Always targets BEST flowers (largest/most pollen)\n• Tween teleport to field + smooth natural walking\n• Continuous collection system (ToolCollect) - TOGGLEABLE\n• AGGRESSIVE token collection (separate thread!) - TOGGLEABLE\n• Smart token prioritization (valuable tokens first)\n• 🌸 SMART FLOWER PRIORITY: Targets biggest flowers with color bonus\n• 📍 CLUSTER DETECTION: Finds areas with most pollen on ground\n• Automatic flame collection - TOGGLEABLE\n• Automatic mark collection - TOGGLEABLE\n• Smart planter management - TOGGLEABLE\n• 🥥 AUTO COCONUT COMBO CATCHER - NEW!\n• 🎈 AUTO BALLOON FARMING - NEW!\n• ☁️ AUTO CLOUD FARMING - NEW!\n• Real-time stats tracking (pollen/hour, honey/hour)\n• Auto honey conversion\n• Respects game speed boosts (Haste, etc.)\n• FULLY CUSTOMIZABLE - every feature can be toggled!\n\n✅ NO RANDOM POSITIONS - Always goes to optimal spots!"
})

InfoTab:CreateSection("🛠️ Collection System")

InfoTab:CreateParagraph({
	Title = "Collection System: ✅ Continuous & Automatic",
	Content = "The script runs SEPARATE collection threads:\n\n• ToolCollect: Continuous pollen/item collection (0.08s cooldown)\n• Token Collector: Separate thread checking for tokens (0.2s interval)\n• All systems can be toggled on/off individually!\n\nThis means:\n✅ Collection never stops\n✅ Movement won't break collection\n✅ Maximum efficiency!\n\nJust equip your collector tool and enable Auto Farm!"
})

InfoTab:CreateSection("⚠️ Important")

InfoTab:CreateParagraph({
	Title = "Before Starting",
	Content = "1. Make sure you have a COLLECTOR tool equipped (Dipper, Scoop, etc.)\n2. Select a field from the dropdown\n3. Enable Auto Farm\n4. The script will check if you have a collector equipped!"
})

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
		
		-- Se não tiver equipado, verifica backpack
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
print("[BSS AutoFarm] v4.1 Loaded — Balloons ALWAYS active! 🐝🎈")
print("[BSS AutoFarm] Balloon detection: Workspace.Balloons.FieldBalloons + BalloonInflate event")
print("[BSS AutoFarm] Balloons have priority over field farm (more pollen/second)")
print("[BSS AutoFarm] Check Advanced tab for fine-tuning.")
print("═══════════════════════════════════════════════════════════")
