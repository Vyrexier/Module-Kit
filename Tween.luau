local Players = cloneref(game:GetService("Players"))
local RunService = cloneref(game:GetService("RunService"))

local Player = cloneref(Players.LocalPlayer)

local TweenController = {}
TweenController.Part = nil
TweenController.Speed = 16
TweenController.Running = false
TweenController.Connection = nil
TweenController.Target = nil

local Highlight = Instance.new("Highlight")
Highlight.Name = "MovementHighlight"
Highlight.FillColor = Color3.fromRGB(0, 170, 255)
Highlight.OutlineColor = Color3.fromRGB(80, 220, 255)
Highlight.FillTransparency = 0.65
Highlight.OutlineTransparency = 0
Highlight.Enabled = false
Highlight.Parent = game:GetService("CoreGui")

function TweenController:SetPart(Part)
    assert(typeof(Part) == "Instance" and Part:IsA("BasePart"), "Part must be a BasePart")
    self.Part = Part
end

function TweenController:SetPosition(Position)
    if typeof(Position) == "Vector3" then
        self.Target = CFrame.new(Position)
    elseif typeof(Position) == "CFrame" then
        self.Target = Position
    else
        error("SetPosition expects Vector3 or CFrame")
    end
end

function TweenController:Start()
    if self.Running or not self.Target then
        return
    end

    local Character = Player.Character
    local Root = self.Part or (Character and Character:FindFirstChild("HumanoidRootPart"))

    if not Root then
        return
    end

    self.Running = true
    self.Root = Root
    Highlight.Adornee = Character
    Highlight.Enabled = true

    self.Connection = RunService.Heartbeat:Connect(function(DeltaTime)
        if not self.Running or not self.Root.Parent then
            self:Stop()
            return
        end

        local Current = self.Root.CFrame
        local Target = self.Target
        local Distance = (Target.Position - Current.Position).Magnitude
        local Step = self.Speed * DeltaTime

        if Distance <= 0.01 then
            self.Root.CFrame = Target
            return
        end

        local Alpha = math.min(Step / Distance, 1)
        local Position = Current.Position:Lerp(Target.Position, Alpha)
        local Rotation = Current.Rotation:Lerp(Target.Rotation, Alpha)

        self.Root.CFrame = CFrame.new(Position) * Rotation
    end)
end

function TweenController:Stop()
    self.Running = false

    if self.Connection then
        self.Connection:Disconnect()
        self.Connection = nil
    end

    Highlight.Enabled = false
    Highlight.Adornee = nil
end

function TweenController:SetSpeed(Speed)
    assert(typeof(Speed) == "number" and Speed > 0, "Speed must be a positive number")
    self.Speed = Speed
end

-- TweenController:Stop()
-- TweenController:SetPosition(CFrame.new(20, 5, 10))
-- TweenController:Start()
