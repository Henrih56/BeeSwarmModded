ONSTANTS.BALLOON_MIN_FARM_TIME, -- Mínimo 15 segundos por balão
	MaxFarmTime = CONSTANTS.BALLOON_MAX_FARM_TIME -- Máximo 45 segundos por balão
}
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
		HomePosition  = balloonModel:GetAttribute("ClientMotionHomePosition"),
		WanderRadius  = balloonModel:GetAttribute("ClientMotionWanderRadius") or 20,
		WanderSpeed   = balloonModel:GetAttribute("ClientMotionWanderSpeed"),
		WanderAngle   = balloonModel:GetAttribute("ClientMotionWanderAngle"),
		WanderAmpX    = balloonModel:GetAttribute("ClientMotionWanderAmpX"),
		WanderAmpZ    = balloonModel:GetAttribute("ClientMotionWanderAmpZ"),
		WanderFreqX   = balloonModel:GetAttribute("ClientMotionWanderFreqX"),
		WanderFreqZ   = balloonModel:GetAttribute("ClientMotionWanderFreqZ"),
		ZoneFrame     = balloonModel:GetAttribute("ClientMotionZoneFrame"),
		ZoneHalfSize  = balloonModel:GetAttribute("ClientMotionZoneHalfSize"),
		IsCircleZone  = balloonModel:GetAttribute("ClientMotionZoneIsCircle"),
		ReturnStartTime     = balloonModel:GetAttribute("ClientMotionReturnStartTime"),
		ReturnDuration      = balloonModel:GetAttribute("ClientMotionReturnDuration"),
		ReturnStartPosition = balloonModel:GetAttribute("ClientMotionReturnStartPosition"),
		ReturnTargetPosition= balloonModel:GetAttribute("ClientMotionReturnTargetPosition"),
		ReturnArcHeight     = balloonModel:GetAttribute("ClientMotionReturnArcHeight"),
	}
end
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
local function getBalloonFarmPos(info)
	local bodyPos = info.Body and info.Body.Parent and info.Body.Position or info.Position
	if info.ZoneFrame and info.ZoneHalfSize then
		return Vector3.new(
			info.ZoneFrame.Position.X,
			bodyPos.Y + CONSTANTS.BALLOON_POSITION_OFFSET_Y,
			info.ZoneFrame.Position.Z
		)
	end
	return bodyPos + Vector3.new(0, CONSTANTS.BALLOON_POSITION_OFFSET_Y, 0)
end
local function isInsideBalloonZone(pos, info)
	if not info.ZoneFrame or not info.ZoneHalfSize then return true end
	local rel = info.ZoneFrame:PointToObjectSpace(pos)
	if info.IsCircleZone then
		local r = math.max(info.ZoneHalfSize.X, info.ZoneHalfSize.Z)
		return (rel.X^2 + rel.Z^2) <= r^2
	end
	return math.abs(rel.X) <= info.ZoneHalfSize.X and math.abs(rel.Z) <= info.ZoneHalfSize.Z
end
local function farmBalloon(balloonData)
	if not balloonData or not balloonData.Body or not balloonData.Body.Parent then return false end
	if not BALLOON_FARM.Enabled or not CONFIG.FarmBalloons then return false end
	if BALLOON_FARM.IsFarming then return false end
	if balloonData.IsReturning then return false end
	BALLOON_FARM.IsFarming = true
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
		if balloonData.Model:GetAttribute("ClientMotionKind") == "FieldBalloonReturn" then break end
		if tick() - lastPosUpdate > CONSTANTS.BALLOON_POSITION_UPDATE_INTERVAL then
			local updatedInfo = getBalloonInfoMCP(balloonData.Model)
			if updatedInfo then
				local predicted = predictBalloonPosition(updatedInfo, 2)
				if predicted then
					local newFarmPos = Vector3.new(
						predicted.X,
						predicted.Y + CONSTANTS.BALLOON_POSITION_OFFSET_Y,
						predicted.Z
					)
					if (newFarmPos - farmPos).Magnitude > CONSTANTS.BALLOON_MOVEMENT_THRESHOLD then
						farmPos = newFarmPos
						moveTo(farmPos, nil, "balloon")
					end
				end
			end
			lastPosUpdate = tick()
		end
		local root = getRoot()
		local offset = Vector3.new(
			math.random(-BALLOON_FARM.FarmRadius, BALLOON_FARM.FarmRadius),
			0,
			math.random(-BALLOON_FARM.FarmRadius, BALLOON_FARM.FarmRadius)
		)
		local targetPos = farmPos + offset
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
local function startBalloonFarm()
	if BALLOON_FARM.Running then return end
	BALLOON_FARM.Running = true
	task.spawn(function()
		while BALLOON_FARM.Enabled and CONFIG.FarmBalloons and shouldContinue() do
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
	tweenToField(cloudPos, "cloud")
	if not CONFIG.Enabled then return false end
	RUNTIME.Stats.CloudsVisited = RUNTIME.Stats.CloudsVisited + 1
	local farmTime = tick()
	while shouldContinue() and cloudData.Part.Parent and tick() - farmTime < 45 do
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
	if not CONFIG.CollectMarks then return end
	local root = getRoot()
	if not root then return end
	local marksFolder = workspace:FindFirstChild("Marks")
	if not marksFolder then return end
	for _, mark in ipairs(marksFolder:GetChildren()) do
		if mark:IsA("BasePart") and (root.Position - mark.Position).Magnitude < 25 then
			task.wait(CONSTANTS.MOVE_CHECK_INTERVAL)
			if not mark.Parent then
				RUNTIME.Stats.MarksCollected = RUNTIME.Stats.MarksCollected + 1
			end
		end
	end
end
local function findFlowersInField(fieldObj)
	local currentTime = tick()
	if FLOWER_CACHE.currentField == fieldObj
		and currentTime - FLOWER_CACHE.lastScan < CONSTANTS.FLOWER_CACHE_TIMEOUT then
		return FLOWER_CACHE.flowers
	end
	local flowers = {}
	local fPos, fSize = getFieldPosition(fieldObj)
	if not fPos then return flowers end
	local searchRadius = CONFIG.FieldRadius + 10
	local searchBox  = CFrame.new(fPos)
	local searchSize = Vector3.new(searchRadius * 2, 40, searchRadius * 2)
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	local flowersFolder = workspace:FindFirstChild("Flowers")
	if flowersFolder then
		params:AddToFilter(flowersFolder)
	end
	local candidates = workspace:GetPartBoundsInBox(searchBox, searchSize, params)
	for _, obj in ipairs(candidates) do
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
local function findBestPollenArea(position, radius)
	local tokensFolder = getCachedFolder("Collectibles")
	if not tokensFolder then return nil end
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
	local cellSize = 8
	local grid = {}
	local function cellKey(pos)
		return math.floor(pos.X / cellSize) .. "," .. math.floor(pos.Z / cellSize)
	end
	for _, pos in ipairs(pollenTokens) do
		local key = cellKey(pos)
		grid[key] = (grid[key] or {count = 0, center = pos})
		grid[key].count = grid[key].count + 1
		grid[key].center = (grid[key].center + pos) / 2
	end
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
	currentFlowers = findFlowersInField(fieldObj)
	lastFlowerScan = tick()
	local maxFieldDistance = CONFIG.FieldRadius + 30 -- Tolerância extra
	local consecutiveFailedMoves = 0
	local maxConsecutiveFailures = 3 -- Se falhar 3 movimentos, sai
	while shouldContinue() and CONFIG.SelectedField == fieldObj do
		updateBoosts()
		updateEventTracker()
		useHotbarItems()
		if checkBossEvents() then
			currentFlowers, currentFlowerIndex, lastFlowerScan = findFlowersInField(fieldObj), 1, tick()
		end
		local pollenPercent = safeGetPollenPercent()
		if pollenPercent >= CONFIG.ConvertAt then
			break
		end
		local root = getRoot()
		if root then
			local distanceFromField = (root.Position - fPos).Magnitude
			if distanceFromField > maxFieldDistance then
				break
			end
		end
		local currentTime = tick()
		if CONFIG.CollectFlames and currentTime - lastFlameCheck > 2 then
			collectNearbyFlames()
			lastFlameCheck = currentTime
		end
		if CONFIG.CollectMarks and currentTime - lastMarkCheck > 1.5 then
			collectNearbyMarks()
			lastMarkCheck = currentTime
		end
		if currentTime - lastFlowerScan > 20 then
			currentFlowers = findFlowersInField(fieldObj)
			currentFlowerIndex = 1
			lastFlowerScan = currentTime
		end
		local targetPos = nil
		if #currentFlowers > 0 and currentFlowerIndex <= #currentFlowers then
			local flower = CONFIG.SmartFlowerTargeting and getNextBestFlower(currentFlowers, root and root.Position or fPos) or currentFlowers[currentFlowerIndex]
			if flower and flower.Part.Parent then
				targetPos = flower.Position + Vector3.new(0, CONFIG.CollectHeight, 0)
			elseif not CONFIG.SmartFlowerTargeting then
				currentFlowerIndex = currentFlowerIndex + 1
			end
		end
		if not targetPos then
			local bestArea = findBestPollenArea(fPos, CONFIG.FieldRadius)
			if bestArea then
				targetPos = bestArea + Vector3.new(0, CONFIG.CollectHeight, 0)
			end
		end
		if not targetPos then
			targetPos = fPos + Vector3.new(0, CONFIG.CollectHeight, 0)
		end
		if not CONFIG.SmartFlowerTargeting and CONFIG.FarmMode == "Route Sweep" and #fieldRoute > 0 then
			local root = getRoot()
			local routeTarget = fieldRoute[routeIndex]
			if root and (root.Position - routeTarget).Magnitude <= 7 then
				routeIndex = (routeIndex % #fieldRoute) + 1
				routeTarget = fieldRoute[routeIndex]
			end
			targetPos = routeTarget + Vector3.new(0, CONFIG.CollectHeight, 0)
		end
		local moveSuccess = moveTo(targetPos, (not CONFIG.SmartFlowerTargeting and CONFIG.FarmMode == "Route Sweep") and routeArrivalDistance or nil)
		if not moveSuccess then
			consecutiveFailedMoves = consecutiveFailedMoves + 1
			if consecutiveFailedMoves >= maxConsecutiveFailures then
				break
			end
		else
			consecutiveFailedMoves = 0
		end
		if not CONFIG.Enabled then return end
		task.wait(CONFIG.CollectInterval) 
	end
end
local function convertAtHive()
	convertAtHiveRemote()
end
local function automationLoop()
	if SESSION.AutomationRunning then return end
	SESSION.AutomationRunning = true
	RUNTIME.Active = true
	local currentTime = tick()
	RUNTIME.Stats.StartTime = currentTime
	RUNTIME.Stats.LastStatsUpdate = currentTime
	RUNTIME.Stats.LastPollenValue = safeGetStatValue(pollenValue)
	RUNTIME.Stats.LastHoneyValue = safeGetStatValue(honeyValue)
	TOOL_COLLECT.Enabled = true
	enableToolCollect()
	startAntiDisconnect()
	startSpeedEnforcer()
	TOKEN_COLLECTOR.Enabled = true
	startTokenCollector()
	if AUTO_QUEST.Enabled then
		startAutoQuest()
	end
	if CONFIG.CoconutCatcher then
		COCONUT_CATCHER.Enabled = true
		startCoconutCatcher()
	end
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
			local currentPollen = safeGetStatValue(pollenValue)
			if currentPollen > RUNTIME.Stats.LastPollenValue then
				RUNTIME.Stats.PollenCollected = RUNTIME.Stats.PollenCollected + (currentPollen - RUNTIME.Stats.LastPollenValue)
			end
			RUNTIME.Stats.LastPollenValue = 0
			convertAtHive()
			local currentHoney = safeGetStatValue(honeyValue)
			if currentHoney > RUNTIME.Stats.LastHoneyValue then
				RUNTIME.Stats.HoneyMade = RUNTIME.Stats.HoneyMade + (currentHoney - RUNTIME.Stats.LastHoneyValue)
			end
			RUNTIME.Stats.LastHoneyValue = currentHoney
		else
			local currentPollen = safeGetStatValue(pollenValue)
			if currentPollen > RUNTIME.Stats.LastPollenValue then
				RUNTIME.Stats.PollenCollected = RUNTIME.Stats.PollenCollected + (currentPollen - RUNTIME.Stats.LastPollenValue)
			end
			RUNTIME.Stats.LastPollenValue = currentPollen
			if CONFIG.FarmBalloons then
				local activeBalloons = findActiveBalloons()
				if #activeBalloons > 0 then
					local root = getRoot()
					if root then
						table.sort(activeBalloons, function(a, b)
							return (root.Position - a.Position).Magnitude
								< (root.Position - b.Position).Magnitude
						end)
						local balloon = activeBalloons[1]
						farmBalloon(balloon)
						task.wait(0.1)
						continue
					end
				end
			end
			local fPos = getFieldPosition(CONFIG.SelectedField)
			if fPos then
				local adjustedPos = getAdjustedFieldPosition(CONFIG.SelectedField) or (fPos + Vector3.new(0, 3, 0))
				invalidatePathCache()
				tweenToField(adjustedPos)
				if shouldContinue() then
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
local FarmTab = Window:CreateTab("🌻 Farming", 4483362458)
local FarmSection = FarmTab:CreateSection("Auto Farm Settings")
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
			resetAllSystems()
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