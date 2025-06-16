--// Properties //--

local ALERT_ABOUT_FLIPBOOK_DIMENSIONS = true
local REDUCE_RATE_BY_QUALITY = true
local DELTA_TIME = nil -- leave nil if you want to use user framerate

--// Types //--

export type ParticleEmitter2D = ParticleEmitter & {
	EmitPosition: UDim2,
	EmitParent: GuiObject?,
	FlipbookDimensions: number?,

	EmitAtPosition: (self: ParticleEmitter2D, particleCount: number?, position: UDim2?) -> (),
	EmitInParent: (self: ParticleEmitter2D, particleCount: number?, parent: GuiObject) -> (),
}

type ParticleReference = {
	label: ImageLabel,
	particleEmitter: ParticleEmitter,
	particleEmitterProperties: {[string]: any},
	aspectRatio: UIAspectRatioConstraint,

	time: number,
	lifetime: number,

	seed: number,

	drag: number,
	speed: number,
	rotSpeed: number,
	size: UDim2,
	direction: UDim2,
	position: UDim2?,

	currentFrame: number?,
	frameRate: number,
}

--// Constaints //--

local EMITTER_PROPERTIES = {
	"Acceleration",
	"Color",
	"Drag",
	"EmissionDirection",
	"Enabled",
	"FlipbookFramerate",
	"FlipbookLayout",
	"FlipbookMode",
	"FlipbookStartRandom",
	"LockedToPart",
	"Lifetime",
	"Orientation",
	"Rate",
	"Rotation",
	"RotSpeed",
	"Size",
	"Speed",
	"SpreadAngle",
	"Squash",
	"Texture",
	"Transparency",
	"ZOffset",
	"TimeScale"
}

local DIMENSIONS_ARRAY = {8, 16, 32, 64, 128, 256, 512, 1024}

local EMISSION_DIRECTION: {[Enum.NormalId]: number} = {
	[Enum.NormalId.Left] = 0,
	[Enum.NormalId.Top] = 90,
	[Enum.NormalId.Right] = 180,
	[Enum.NormalId.Bottom] = 270
}

local FLIPBOOK_LAYOUT_TO_NUMBER = {
	[Enum.ParticleFlipbookLayout.Grid2x2] = 2,
	[Enum.ParticleFlipbookLayout.Grid4x4] = 4,
	[Enum.ParticleFlipbookLayout.Grid8x8] = 8,
}

--// Main Setup //--
local Ember = {}

Ember.FlipbookDimensions = {
	By8x8 = 8,
	By16x16 = 16,
	By32x32 = 32,
	By64x64 = 64,
	By128x128 = 128,
	By256x256 = 256,
	By512x512 = 512,
	By1024x1024 = 1024
}

--// Services //--

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local UserGameSettings = UserSettings():GetService("UserGameSettings") :: UserGameSettings

--// Variables //--

local LocalPlayer = Players.LocalPlayer
local Camera = workspace.CurrentCamera

local ParticlesGUI = Instance.new("ScreenGui")
ParticlesGUI.DisplayOrder = 5
ParticlesGUI.Name = "Particles"
ParticlesGUI.Parent = LocalPlayer.PlayerGui
ParticlesGUI.ScreenInsets = Enum.ScreenInsets.None

--// Tables //--

local CachedEmitters2D: {[ParticleEmitter]: ParticleEmitter2D} = {}
local RecycledParticles: {[ParticleEmitter]: {ParticleReference}} = {}
local Particles: {[ParticleEmitter]: {ParticleReference}} = {}
local EmitterProperties: {[ParticleEmitter]: {[string]: any}} = {}
local AllParticles: {ParticleReference} = {}

--// Connections //--

local ParticleRenderer: RBXScriptConnection

--// Helper functions //--

local _, set_value = xpcall(function() game.test = true end, function() return debug.info(2, "f") end)
local _, get_value = xpcall(function()  _ = game[nil] end, function() return debug.info(2, "f") end)
local get_attribute = game.GetAttribute

local function decimalRandom(min: number, max: number): number
	return math.lerp(min, max, math.random())
end

local function evalNumberSequence(sequence: NumberSequence, t: number, seed: number) : number
	local sequenceKeypoints = sequence.Keypoints
	local sequenceLength = #sequenceKeypoints

	if t <= 0 then
		local keyPoint = sequenceKeypoints[1]
		return keyPoint.Value + seed * keyPoint.Envelope
	elseif t >= 1 then
		local keyPoint = sequenceKeypoints[sequenceLength]
		return keyPoint.Value + seed * keyPoint.Envelope
	end

	for i = 1, sequenceLength - 1 do
		local thisKeypoint = sequenceKeypoints[i]
		local nextKeypoint = sequenceKeypoints[i + 1]

		local thisKeypointTime = thisKeypoint.Time
		local nextKeypointTime = nextKeypoint.Time

		if t >= thisKeypointTime and t < nextKeypointTime then
			local alpha = (t - thisKeypointTime) / (nextKeypointTime - thisKeypointTime)

			return math.lerp(thisKeypoint.Value, nextKeypoint.Value, alpha) + seed * math.lerp(thisKeypoint.Envelope, nextKeypoint.Envelope, alpha)
		end
	end
end

local function evalColorSequence(sequence: ColorSequence, t: number) : Color3
	local sequenceKeypoints = sequence.Keypoints
	local sequenceLength = #sequenceKeypoints

	if t <= 0 then
		return sequenceKeypoints[1].Value
	elseif t >= 1 then
		return sequenceKeypoints[sequenceLength].Value
	end

	for i = 1, sequenceLength - 1 do
		local thisKeypoint = sequenceKeypoints[i]
		local nextKeypoint = sequenceKeypoints[i + 1]

		local thisKeypointTime = thisKeypoint.Time
		local nextKeypointTime = nextKeypoint.Time

		if t >= thisKeypointTime and t < nextKeypointTime then
			local alpha = (t - thisKeypointTime) / (nextKeypointTime - thisKeypointTime)

			local thisKeypointValue = thisKeypoint.Value
			local nextKeypointValue = nextKeypoint.Value

			return Color3.new(
				math.lerp(thisKeypointValue.R, nextKeypointValue.R, alpha), 
				math.lerp(thisKeypointValue.G, nextKeypointValue.G, alpha),
				math.lerp(thisKeypointValue.B, nextKeypointValue.B, alpha)
			)
		end
	end
end

local function getRandomPositionInFrame(frame: Frame) : Vector2
	local size = frame.AbsoluteSize
	local position = frame.AbsolutePosition
	local rotation = math.rad(frame.AbsoluteRotation)

	local center = position + size / 2

	local localX = math.random() * size.X - size.X / 2
	local localY =  math.random() * size.Y - size.Y / 2

	local rotatedX = localX * math.cos(rotation) - localY * math.sin(rotation)
	local rotatedY = localX * math.sin(rotation) + localY * math.cos(rotation)

	local normalized = (center + Vector2.new(rotatedX, rotatedY)) / Camera.ViewportSize

	return UDim2.fromScale(normalized.X, normalized.Y)
end

local function getRandomDirectionVector(baseAngleDeg: number, spreadAngleDeg: number) : UDim2	
	local halfSpread = spreadAngleDeg / 2
	local minAngle = baseAngleDeg - halfSpread
	local maxAngle = baseAngleDeg + halfSpread
	local randomAngleDeg = math.random() * (maxAngle - minAngle) + minAngle
	local randomAngleRad = math.rad(randomAngleDeg)

	local x = math.cos(randomAngleRad)
	local y = math.sin(randomAngleRad)

	local normalized = Vector2.new(x, y) / Camera.ViewportSize

	return UDim2.fromScale(-normalized.X, -normalized.Y) 
end

local function getFrameFromFlipbook(dimensions: number, layout: number, frame: number) : (Vector2, Vector2)
	frame = math.max(1, frame % (layout * layout)) - 1

	local frameSize = dimensions / layout

	local columIndex = frame % layout
	local rowIndex = frame // layout

	local offsetX = columIndex * frameSize
	local offsetY = rowIndex * frameSize

	return Vector2.new(offsetX, offsetY), Vector2.new(frameSize, frameSize)
end

local function createParticleEmitterFromTable(emitterData: ParticleEmitter)
	local emitter = Instance.new("ParticleEmitter")
	
	for property, value in emitterData do
		if not table.find(EMITTER_PROPERTIES, property) then continue end
		
		emitter[property] = value
	end
	
	return emitter
end

--// Main functions //--

local function DestroyParticleReference(particleReference: ParticleReference)
	local index = table.find(AllParticles, particleReference)

	if index then
		particleReference.label.Visible = false
		particleReference.label.Position = UDim2.fromScale(-.5, -.5)

		table.remove(AllParticles, index)
		table.insert(RecycledParticles[particleReference.particleEmitter], particleReference.label)

		table.clear(particleReference)
	end
end

local function RenderParticles(dt: number)
	dt = DELTA_TIME or dt
	local cameraSize = get_value(Camera, "ViewportSize")
	local cameraX, cameraY = cameraSize.X, cameraSize.Y

	set_value(ParticlesGUI, "Enabled", false)

	for index, particle in AllParticles do
		local label = particle.label
		local emitterProperties = particle.particleEmitterProperties
		local aspectRatioConstraint = particle.aspectRatio 

		local t = particle.time

		particle.time += dt * emitterProperties.TimeScale

		local lifetime = particle.lifetime
		local alpha = t / lifetime

		if alpha >= 1 then
			set_value(label, "Visible", false)

			local emitter = particle.particleEmitter
			table.insert(RecycledParticles[emitter], label)
			table.remove(AllParticles, index)
			table.clear(particle)

			continue
		end

		local seed = particle.seed
		local drag = particle.drag
		local speed = particle.speed
		local direction = particle.direction
		local rotSpeed = particle.rotSpeed

		local acceleration = emitterProperties.Acceleration
		local accX = acceleration.X / cameraX * t * t * 20
		local accY = acceleration.Y / cameraY * t * t * 20

		local actualSpeed = drag and speed * (0.5 ^ (t / drag)) or speed
		local newPosition = particle.position + UDim2.fromScale(
			direction.X.Scale * actualSpeed * t - accX,
			direction.Y.Scale * actualSpeed * t - accY
		)

		local positionXScale, positionYScale = newPosition.X.Scale, newPosition.Y.Scale
		if positionXScale < -.1 or positionXScale > 1.1 or positionYScale > 1.1 or positionYScale < -.1 then continue end

		local transparency = evalNumberSequence(emitterProperties.Transparency, alpha, seed)
		if transparency == 1 then continue end

		local sizeAlpha = evalNumberSequence(emitterProperties.Size, alpha, seed) / 10
		local squash = evalNumberSequence(emitterProperties.Squash, alpha, seed)
		local color = evalColorSequence(emitterProperties.Color, alpha)
		local rotation = get_value(label, "Rotation")

		set_value(label, "Position", newPosition)
		set_value(label, "ImageTransparency", transparency)
		set_value(label, "ImageColor3", color)
		set_value(label, "Rotation", rotation + rotSpeed * dt)
		set_value(label, "Size", UDim2.fromScale(sizeAlpha, sizeAlpha))

		set_value(aspectRatioConstraint, "AspectRatio", squash > 0 and squash + 1 or math.max(1e-4, 1 + (squash / 3)))

		local layout = emitterProperties.FlipbookLayout
		if layout ~= Enum.ParticleFlipbookLayout.None then
			local frame = particle.currentFrame
			local flipbookDim = emitterProperties.FlipbookDimensions or Ember.FlipbookDimensions.By1024x1024
			local layoutSize = FLIPBOOK_LAYOUT_TO_NUMBER[layout]
			local mode = emitterProperties.FlipbookMode

			local offset, size = getFrameFromFlipbook(flipbookDim, layoutSize, frame // 1)
			set_value(label, "ImageRectOffset", offset)
			set_value(label, "ImageRectSize", size)

			if mode == Enum.ParticleFlipbookMode.Loop then
				frame = t * particle.frameRate
			elseif mode == Enum.ParticleFlipbookMode.OneShot then
				frame = alpha * layoutSize * layoutSize
			elseif mode == Enum.ParticleFlipbookMode.Random then
				frame = math.random(layoutSize * layoutSize)
			else
				frame = (alpha < 0.5)
					and (alpha * layoutSize * layoutSize * 2)
					or ((1 - alpha) * layoutSize * layoutSize * 2)
			end

			particle.currentFrame = frame
		end
	end

	set_value(ParticlesGUI, "Enabled", true)
end

local function GenerateParticleReference(particleEmitter: ParticleEmitter, particleLabelTemplate: ImageLabel) : ParticleReference
	local particleLabel: ImageLabel = table.remove(RecycledParticles[particleEmitter])

	if not particleLabel then
		particleLabel = particleLabelTemplate:Clone()
		particleLabel.ZIndex = particleEmitter.ZOffset * 1e4
		particleLabel.Parent = particleLabelTemplate.Parent or ParticlesGUI
		particleLabel.Rotation = decimalRandom(particleEmitter.Rotation.Min, particleEmitter.Rotation.Max)
	else
		particleLabel.Position = UDim2.fromScale(-.5, -.5)
	end

	particleLabel.Visible = true

	local lifeTime = decimalRandom(particleEmitter.Lifetime.Min, particleEmitter.Lifetime.Max)
	local speed = decimalRandom(particleEmitter.Speed.Min, particleEmitter.Speed.Max) * 20
	local rotSpeed = decimalRandom(particleEmitter.RotSpeed.Min, particleEmitter.RotSpeed.Max)
	local frameRate = decimalRandom(particleEmitter.FlipbookFramerate.Min, particleEmitter.FlipbookFramerate.Max)

	local particleReference = {
		label = particleLabel,
		particleEmitter = particleEmitter,
		particleEmitterProperties = EmitterProperties[particleEmitter],
		aspectRatio = particleLabel:FindFirstChildWhichIsA("UIAspectRatioConstraint"),

		time = 0,
		lifetime = lifeTime,

		seed = math.random() - 1,

		speed = speed,
		drag = particleEmitter.Drag ~= 0 and particleEmitter.Drag,
		rotSpeed = rotSpeed,
		size = particleLabelTemplate.Size,

		frameRate = frameRate
	}

	if particleEmitter.FlipbookLayout ~= Enum.ParticleFlipbookLayout.None then
		local layout = FLIPBOOK_LAYOUT_TO_NUMBER[particleEmitter.FlipbookLayout]

		particleReference.currentFrame = particleEmitter.FlipbookStartRandom and math.random(layout * layout) or 1
	end

	table.insert(Particles[particleEmitter], particleReference)

	return particleReference
end

local function EmitAtPosition(particleEmitter: ParticleEmitter, particleLabelTemplate: ImageLabel, position: UDim2)
	local particleReference = GenerateParticleReference(particleEmitter, particleLabelTemplate)
	local particleDirection = getRandomDirectionVector(EMISSION_DIRECTION[particleEmitter.EmissionDirection] or 90, decimalRandom(particleEmitter.SpreadAngle.X, particleEmitter.SpreadAngle.Y))

	particleReference.position = position
	particleReference.direction = particleDirection

	table.insert(AllParticles, 1, particleReference)
end

local function EmitInParent(particleEmitter: ParticleEmitter, particleLabelTemplate: ImageLabel, parent: GuiObject)
	local particleReference = GenerateParticleReference(particleEmitter, particleLabelTemplate)
	local particleDirection = getRandomDirectionVector((EMISSION_DIRECTION[particleEmitter.EmissionDirection] or 90) + parent.AbsoluteRotation, decimalRandom(particleEmitter.SpreadAngle.X, particleEmitter.SpreadAngle.Y))

	particleReference.position = getRandomPositionInFrame(parent) 
	particleReference.direction = particleDirection

	table.insert(AllParticles, particleReference)
end

--// Module functions //--

function Ember.createFromTable(struct : ParticleEmitter & {EmitPosition: Vector2?}) : ParticleEmitter2D	
	return Ember.new(createParticleEmitterFromTable(struct), struct.EmitPosition)
end

function Ember.new(particleEmitter: ParticleEmitter, emitPosition: UDim2?) : ParticleEmitter2D
	if CachedEmitters2D[particleEmitter] then return CachedEmitters2D[particleEmitter] end
	if ALERT_ABOUT_FLIPBOOK_DIMENSIONS and particleEmitter.FlipbookLayout ~= Enum.ParticleFlipbookLayout.None then
		warn("Flipbook particle detected, make sure to set the FlipbookDimensions if its different from 1024x1024")
	end

	local folder = Instance.new("Folder")
	folder.Name = particleEmitter.Name
	folder.Parent = ParticlesGUI

	local particleLabel = Instance.new("ImageLabel")
	particleLabel.AnchorPoint = Vector2.new(.5, .5)
	particleLabel.BackgroundTransparency = 1
	particleLabel.Size = UDim2.fromScale(.05, .05)
	particleLabel.Position = UDim2.fromScale(-.5, -.5)
	particleLabel.Image = particleEmitter.Texture
	particleLabel.Visible = false
	particleLabel.Parent = folder

	local uiAspectRatioConstraint = Instance.new("UIAspectRatioConstraint")
	uiAspectRatioConstraint.Parent = particleLabel

	local emitParticlesThread: thread 
	local enabledChanged: RBXScriptConnection
	local destroyedParticle: RBXScriptConnection
	local propertyChanged: RBXScriptConnection

	local uiParticleEmitter: ParticleEmitter2D

	RecycledParticles[particleEmitter] = RecycledParticles[particleEmitter] or {}
	Particles[particleEmitter] = Particles[particleEmitter] or {}
	EmitterProperties[particleEmitter] = EmitterProperties[particleEmitter] or {} 

	for _, propertyName in EMITTER_PROPERTIES do
		EmitterProperties[particleEmitter][propertyName] = particleEmitter[propertyName]
	end
	EmitterProperties[particleEmitter].FlipbookDimensions = Ember.FlipbookDimensions.By1024x1024

	local variableGetFunctions = {
		FlipbookDimensions = function()
			return EmitterProperties[particleEmitter].FlipbookDimensions or Ember.FlipbookDimensions.By1024x1024
		end,
	}

	local variableSetFunctions = {
		Enabled = function(enabled: boolean?)
			enabled = enabled or particleEmitter.Enabled

			if enabled and not emitParticlesThread then
				emitParticlesThread = task.spawn(function()
					while true do
						local rate = particleEmitter.Rate
						
						if REDUCE_RATE_BY_QUALITY then
							local qualityLevel = UserGameSettings.SavedQualityLevel.Value
							local rateReduction = qualityLevel == 0 and .5 or qualityLevel/10
							
							rate *= rateReduction
						end
						
						for _ = 1, math.max(rate, 1) do
							if particleEmitter.Parent:IsA("GuiObject") then
								EmitInParent(particleEmitter, particleLabel, particleEmitter.Parent)
							else
								EmitAtPosition(particleEmitter, particleLabel, uiParticleEmitter.EmitPosition or UDim2.fromScale(.5, .5))
							end

							task.wait(1/rate)
						end
					end
				end)
			elseif emitParticlesThread and not enabled then
				task.cancel(emitParticlesThread)
				emitParticlesThread = nil
			end
		end,

		FlipbookDimensions = function(dimensions: Vector2)
			if not table.find(DIMENSIONS_ARRAY, dimensions) then
				return warn("The flipbook texture must be of pixel dimensions 8×8, 16×16, 32×32, 64×64, 128×128, 256×256, 512×512, or 1024×1024")
			end

			EmitterProperties[particleEmitter].FlipbookDimensions = dimensions
		end,
	}

	uiParticleEmitter = setmetatable({
		EmitPosition = emitPosition or UDim2.fromScale(.5, .5),

		Clear = function(self)
			local particles = Particles[particleEmitter]

			for i = #particles, 1, -1 do
				local particleReference = table.remove(particles, i)
				DestroyParticleReference(particleReference)
			end
		end,

		Emit = function(self, particleCount: number?)
			particleCount = particleCount or 16

			task.spawn(function()
				for _ = 1, particleCount do
					if particleEmitter.Parent:IsA("GuiObject") then
						EmitInParent(particleEmitter, particleLabel, particleEmitter.Parent)
					else
						EmitAtPosition(particleEmitter, particleLabel, self.EmitPosition)
					end

					task.wait()
				end
			end)
		end,

		EmitAtPosition = function(self, particleCount: number?, position: UDim2?)
			particleCount = particleCount or 16
			position = position or self.EmitPosition

			task.spawn(function()
				for _ = 1, particleCount do
					EmitAtPosition(particleEmitter, particleLabel, position)
					task.wait()
				end
			end)
		end,

		EmitInParent = function(self, particleCount: number?, parent: GuiObject?)
			particleCount = particleCount or 16
			parent = parent or particleEmitter.Parent

			if not parent:IsA("GuiObject") then
				return warn("The parent is not a gui object")
			end

			task.spawn(function()
				for _ = 1, particleCount do
					EmitInParent(particleEmitter, particleLabel, parent)
					task.wait()
				end
			end)
		end,

		Destroy = function()
			if emitParticlesThread then
				task.cancel(emitParticlesThread)
			end

			destroyedParticle:Disconnect()
			propertyChanged:Disconnect()

			particleLabel:Destroy()
			folder:Destroy()

			RecycledParticles[particleEmitter] = nil
			Particles[particleEmitter] = nil
			EmitterProperties[particleEmitter] = nil
			CachedEmitters2D[particleEmitter] = nil

			table.clear(variableSetFunctions)
			table.clear(variableGetFunctions)
			table.clear(uiParticleEmitter)
		end,

	} :: ParticleEmitter, {
		__index = function(self, key)
			if variableGetFunctions[key] then
				return variableGetFunctions[key]()
			else
				return particleEmitter[key]
			end
		end,

		__newindex = function(self, key, value)
			if variableSetFunctions[key] then
				variableSetFunctions[key](value)
			else
				EmitterProperties[particleEmitter][key] = value
				particleEmitter[key] = value
			end
		end
		,})

	propertyChanged = particleEmitter.Changed:Connect(function(key: string)
		local value = particleEmitter[key]

		if variableSetFunctions[key] then
			variableSetFunctions[key](value)
		elseif table.find(EMITTER_PROPERTIES, key) then
			EmitterProperties[particleEmitter][key] = value
		end
	end)

	destroyedParticle = particleEmitter.Destroying:Connect(uiParticleEmitter.Destroy)

	variableSetFunctions.Enabled(particleEmitter.Enabled)

	CachedEmitters2D[particleEmitter] = uiParticleEmitter

	return uiParticleEmitter
end

function Ember.RenderEnabled(enabled: boolean?)
	enabled = enabled or not ParticleRenderer.Connected

	if enabled and ParticlesGUI.Enabled then
		ParticleRenderer = RunService.PreRender:Connect(RenderParticles)
	elseif ParticleRenderer.Connected then
		ParticleRenderer:Disconnect()

		for _, particleReference in AllParticles do
			DestroyParticleReference(particleReference)
		end
	end
end

--// Connection Setup //--

ParticleRenderer = RunService.PreRender:Connect(RenderParticles)

return Ember