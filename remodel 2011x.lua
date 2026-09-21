local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local ASSET_ID = 128586608703896
local isScriptActive = false
local currentMdl = nil
local syncConn = nil
local originalTransparencies = {}
local originalColors = {}
local isCurrentlyInvisible = false

local cachedGameParts = {}
local invisHighlight = nil

local function loadAsset(id)
	local ok, objects = pcall(game.GetObjects, game, "rbxassetid://" .. id)
	if not ok or not objects or #objects == 0 then return nil end
	return objects[1]:Clone()
end

local function getPlayerModel()
	local playersFolder = workspace:FindFirstChild("Players")
	return playersFolder and playersFolder:FindFirstChild(player.Name)
end

local function isTailsDoll()
	local model = getPlayerModel()
	return model and model:GetAttribute("Character") == "2011x"
end

local function updateCachedParts()
	table.clear(cachedGameParts)
	local oldVisual = getPlayerModel()
	
	local function addPartsFrom(parent)
		if not parent then return end
		for _, v in ipairs(parent:GetDescendants()) do
			if v:IsA("BasePart") and not (currentMdl and v:IsDescendantOf(currentMdl)) then
				table.insert(cachedGameParts, v)
			end
		end
	end

	addPartsFrom(character)
	addPartsFrom(oldVisual)
end

-- Activa el tono rojo puro e intenso durante la habilidad de invisibilidad
local function setCustomModelInvisible(invisible)
	if not currentMdl then return end

	if invisible then
		-- Crear el Highlight rojo puro sin matices de verde o azul
		if not invisHighlight or not invisHighlight.Parent then
			invisHighlight = Instance.new("Highlight")
			invisHighlight.Name = "InvisRedEffect"
			invisHighlight.FillColor = Color3.fromRGB(255, 0, 0) -- Rojo puro
			invisHighlight.FillTransparency = 0.4 -- Transparencia equilibrada
			invisHighlight.OutlineColor = Color3.fromRGB(180, 0, 0)
			invisHighlight.OutlineTransparency = 0.2
			invisHighlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
			invisHighlight.Parent = currentMdl
		end

		for _, v in ipairs(currentMdl:GetDescendants()) do
			if v:IsA("BasePart") then
				local origT = originalTransparencies[v] or 0
				-- Mantiene ocultas las partes invisibles originales (cubos/hitboxes)
				if origT < 0.9 and v.Name ~= "HumanoidRootPart" and v.Name ~= "Waist" then
					v.Transparency = 0.45
					v.Color = Color3.fromRGB(220, 0, 0) -- Rojo intenso
				end
			end
		end
	else
		-- Quitar el efecto rojo y volver a las texturas y colores originales
		if invisHighlight then
			invisHighlight:Destroy()
			invisHighlight = nil
		end

		for _, v in ipairs(currentMdl:GetDescendants()) do
			if v:IsA("BasePart") or v:IsA("Decal") or v:IsA("Texture") then
				local origT = originalTransparencies[v]
				v.Transparency = origT ~= nil and origT or 0
				
				if v:IsA("BasePart") then
					local origC = originalColors[v]
					if origC then
						v.Color = origC
					end
				end
			elseif v:IsA("ParticleEmitter") or v:IsA("Trail") or v:IsA("Beam") then
				v.Enabled = true
			end
		end
	end
end

local function checkGameInvisibility()
	local oldVisual = getPlayerModel()
	local source = oldVisual or character
	if not source then return false end

	local invAttr = source:GetAttribute("Invisible") 
		or source:GetAttribute("Invis") 
		or source:GetAttribute("Stealth")
		or player:GetAttribute("Invisible")
	if invAttr ~= nil then
		return invAttr == true
	end

	local transparentCount = 0
	local totalCount = 0

	for i = 1, #cachedGameParts do
		local v = cachedGameParts[i]
		if v and v.Parent then
			local name = v.Name:lower()
			if not name:find("root") and not name:find("waist") and not name:find("hitbox") then
				totalCount = totalCount + 1
				if v.Transparency > 0.5 then
					transparentCount = transparentCount + 1
				end
			end
		end
	end

	if totalCount > 0 then
		return (transparentCount / totalCount) >= 0.5
	end

	return false
end

local function setupViewport()
	task.spawn(function()
		local viewportFrame = player.PlayerGui
			:WaitForChild("Round", 30)
			:WaitForChild("Game", 30)
			:WaitForChild("SurvivorHP", 30)
			:WaitForChild("ViewportFrame", 30)
		if not viewportFrame then return end
		local viewportModel = viewportFrame
			:WaitForChild("WorldModel", 30)
			:WaitForChild("Default", 30)
		if not viewportModel then return end

		local vpOverrideModel = nil
		local function replaceViewportModel()
			local ok, objects = pcall(game.GetObjects, game, "rbxassetid://" .. 81352974023012)
			if not ok or #objects == 0 then return end
			if vpOverrideModel and vpOverrideModel.Parent then
				vpOverrideModel:Destroy()
				vpOverrideModel = nil
			end
			local newModel = objects[1]:Clone()
			vpOverrideModel = newModel
			for _, part in ipairs(viewportModel:GetDescendants()) do
				if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
					part.Transparency = 1
				end
			end
			local newHum = newModel:FindFirstChildOfClass("Humanoid")
			if newHum then newHum:Destroy() end
			for _, v in ipairs(newModel:GetDescendants()) do
				if v:IsA("BasePart") then v.CanCollide = false end
			end
			newModel.Parent = viewportModel
			local viewportHRP = viewportModel:FindFirstChild("HumanoidRootPart")
			local primaryPart = newModel.PrimaryPart or newModel:FindFirstChildWhichIsA("BasePart")
			if viewportHRP and primaryPart then
				newModel:PivotTo(viewportHRP.CFrame)
				primaryPart.Transparency = 1
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = viewportHRP
				weld.Part1 = primaryPart
				weld.Parent = viewportHRP
			end
		end

		replaceViewportModel()

		viewportModel.DescendantAdded:Connect(function()
			task.wait(0.1)
			if not vpOverrideModel or not vpOverrideModel.Parent then
				vpOverrideModel = nil
				replaceViewportModel()
			end
		end)
	end)
end

local function setupCharacter(char)
	if not isScriptActive then return end
	if syncConn then syncConn:Disconnect() syncConn = nil end
	table.clear(originalTransparencies)
	table.clear(originalColors)
	isCurrentlyInvisible = false

	if currentMdl and currentMdl.Parent then currentMdl:Destroy() currentMdl = nil end

	local oldVisual = getPlayerModel()
	local mdl = loadAsset(ASSET_ID)
	if not mdl then return end

	for _, v in ipairs(mdl:GetDescendants()) do
		if v:IsA("BasePart") then
			v.CanCollide = false
			if v.Name == "HumanoidRootPart" or v.Name == "Waist" then
				v.Transparency = 1
			end
			originalTransparencies[v] = v.Transparency
			originalColors[v] = v.Color
		elseif v:IsA("Decal") or v:IsA("Texture") then
			originalTransparencies[v] = v.Transparency
		end
	end

	if oldVisual then mdl.Parent = oldVisual else mdl.Parent = char end

	local hrp = char:FindFirstChild("HumanoidRootPart")
	local newHrp = mdl:FindFirstChild("HumanoidRootPart")
	if not hrp or not newHrp then mdl:Destroy() return end

	newHrp.Anchored = true
	newHrp.Transparency = 1

	local mdlHum = mdl:FindFirstChildOfClass("Humanoid")
	if mdlHum then mdlHum:Destroy() end
	local mdlAnim = mdl:FindFirstChildOfClass("Animator")
	if mdlAnim then mdlAnim:Destroy() end

	newHrp.CFrame = hrp.CFrame
	currentMdl = mdl

	updateCachedParts()

	local function listenForChanges(parent)
		if not parent then return end
		parent.DescendantAdded:Connect(function(v)
			if v:IsA("BasePart") and not (currentMdl and v:IsDescendantOf(currentMdl)) then
				table.insert(cachedGameParts, v)
			end
		end)
	end
	listenForChanges(char)
	listenForChanges(oldVisual)

	syncConn = RunService.RenderStepped:Connect(function()
		if not char.Parent or not hrp.Parent or not newHrp.Parent then
			if syncConn then syncConn:Disconnect() syncConn = nil end
			return
		end

		newHrp.CFrame = hrp.CFrame

		for i = 1, #cachedGameParts do
			local part = cachedGameParts[i]
			if part and part.Parent then
				part.LocalTransparencyModifier = 1
			end
		end

		local shouldBeInvisible = checkGameInvisibility()
		if shouldBeInvisible ~= isCurrentlyInvisible then
			isCurrentlyInvisible = shouldBeInvisible
			setCustomModelInvisible(isCurrentlyInvisible)
		end
	end)
end

local function startScript()
	if isScriptActive then return end
	task.wait(3)
	isScriptActive = true
	setupViewport()
	if character then setupCharacter(character) end
end

local function stopScript()
	if not isScriptActive then return end
	isScriptActive = false
	if syncConn then syncConn:Disconnect() syncConn = nil end
	table.clear(originalTransparencies)
	table.clear(originalColors)
	table.clear(cachedGameParts)
	if invisHighlight then invisHighlight:Destroy() invisHighlight = nil end
	if currentMdl and currentMdl.Parent then currentMdl:Destroy() currentMdl = nil end
	if character then
		for _, v in ipairs(character:GetDescendants()) do
			if v:IsA("BasePart") then v.LocalTransparencyModifier = 0 end
		end
	end
end

player.CharacterAdded:Connect(function(newChar)
	character = newChar
	if isScriptActive then
		task.wait(1)
		setupCharacter(newChar)
		setupViewport()
	end
end)

local isCurrentlyTailsDoll = false
RunService.Heartbeat:Connect(function()
	local check = isTailsDoll()
	if check ~= isCurrentlyTailsDoll then
		isCurrentlyTailsDoll = check
		if isCurrentlyTailsDoll then startScript() else stopScript() end
	end
end)

if isTailsDoll() then
	isCurrentlyTailsDoll = true
	startScript()
end