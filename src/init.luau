--Allows for players to stay with anchored moving platforms.
--!strict

local ADDITIONAL_DISTANCE_BELOW_CHARACTER_TO_RAYCAST = 2
local ANCHORED_PLATFORM_CACHE_DEBUG_TAG = "MovingAnchoredPlatform"
local ANCHORED_PLATFORM_CACHE_INVALIDATION_TIME_SECONDS = 0.5
local ANCHORED_PLATFORM_CACHE_INVALIDATION_LOOP_DELAY_SECONDS = 0.25

local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local AnchoredPlatformPlayerMovement = {}

export type AnchoredPlatformPlayerMovement = typeof(AnchoredPlatformPlayerMovement)

--Client state.
local LastPlatform: BasePart? = nil
local LastPlatformCFrame: CFrame = CFrame.identity
local LastPlatformOffset: CFrame = CFrame.identity
local MovingAnchoredAssemblyRoots: {[BasePart]: number} = {}



--[[
Updates the local player's character based on the platform.
--]]
function AnchoredPlatformPlayerMovement.UpdateLocalPlayer(self: AnchoredPlatformPlayerMovement): ()
    --Ignore the current update if there is no valid character.
    local Character = Players.LocalPlayer.Character
    if not Character then
        LastPlatform = nil
        return
    end
    
    local Humanoid = Character:FindFirstChildOfClass("Humanoid") :: Humanoid
    local HumanoidRootPart = Character:FindFirstChild("HumanoidRootPart") :: BasePart
    if not Humanoid or not HumanoidRootPart or Humanoid.Health <= 0 or Humanoid.SeatPart then
        LastPlatform = nil
        return
    end

    --Adjust the HumanoidRootPart if there was an instance for the previous frame.
    if LastPlatform then
        local LastInstanceAssemblyRootPart = LastPlatform.AssemblyRootPart
        if LastPlatform.CFrame ~= LastPlatformCFrame and LastPlatform.Anchored or (LastInstanceAssemblyRootPart and LastInstanceAssemblyRootPart.Anchored) then
            debug.profilebegin("AnchoredPlatformPlayerMovement_UpdateLocalPlayer_MoveCharacter")
            local LastCFrameFloorCFrame = LastPlatformCFrame * LastPlatformOffset
            local CurrentFrameFloorCFrame = LastPlatform.CFrame * LastPlatformOffset
            local FloorCFrameDifference = LastCFrameFloorCFrame:Inverse() * CurrentFrameFloorCFrame
            HumanoidRootPart.CFrame = CFrame.new(FloorCFrameDifference.Position) * HumanoidRootPart.CFrame * CFrame.Angles(0, math.atan2(-FloorCFrameDifference.LookVector.X, -FloorCFrameDifference.LookVector.Z), 0)
            debug.profileend()
        end
    end

    --Raycast to find the current platform part.
    debug.profilebegin("AnchoredPlatformPlayerMovement_UpdateLocalPlayer_PrepareNextFrame")
    local Filter = RaycastParams.new()
    Filter.FilterDescendantsInstances = {Character}
    Filter.FilterType = Enum.RaycastFilterType.Exclude
    Filter.IgnoreWater = true
    Filter.RespectCanCollide = true
    
    local RaycastDepth = (HumanoidRootPart.Size.Y / 2) + Humanoid.HipHeight + Humanoid.JumpHeight + ADDITIONAL_DISTANCE_BELOW_CHARACTER_TO_RAYCAST
    local Result = Workspace:Raycast(HumanoidRootPart.Position, Vector3.new(0, -RaycastDepth, 0), Filter)
    local CurrentPlatformInstance = Result and Result.Instance
    if not Result or not CurrentPlatformInstance then
        LastPlatform = nil
        debug.profileend()
        return
    end
    local PlatformAssemblyRoot = (CurrentPlatformInstance :: BasePart).AssemblyRootPart
    if not PlatformAssemblyRoot or not PlatformAssemblyRoot.Anchored then
        LastPlatform = nil
        debug.profileend()
        return
    end
    
    --Set the assembly root as moving if the CFrame changed.
    --This tries to prevent constant updates to the server and other clients for static parts.
    if LastPlatform == PlatformAssemblyRoot and LastPlatformCFrame ~= PlatformAssemblyRoot.CFrame then
        if not MovingAnchoredAssemblyRoots[PlatformAssemblyRoot] then
            PlatformAssemblyRoot:AddTag(ANCHORED_PLATFORM_CACHE_DEBUG_TAG)
        end
        MovingAnchoredAssemblyRoots[PlatformAssemblyRoot] = tick()
    end
    
    --Store the current floor part information for the next update.
    LastPlatform = PlatformAssemblyRoot
    LastPlatformCFrame = PlatformAssemblyRoot.CFrame
    LastPlatformOffset = LastPlatformCFrame:Inverse() * CFrame.new(Result.Position)
    debug.profileend()
end

--[[
Enables local player platform updates.
Must be called on the client.
Returns AnchoredPlatformPlayerMovement to allow for chaining.
--]]
function AnchoredPlatformPlayerMovement.EnableLocalCharacterUpdates(self: AnchoredPlatformPlayerMovement): AnchoredPlatformPlayerMovement
    --Throw an error if EnableLocalCharacterUpdates was called on the server.
    if not RunService:IsClient() then
        error("AnchoredPlatformPlayerMovement::EnableLocalCharacterUpdates must be called on the client.")
    end
    
    --Update the local player before the camera.
    RunService:BindToRenderStep("AnchoredPlatformPlayerMovement_LocalCharacterUpdates", Enum.RenderPriority.Camera.Value - 1, function()
        self:UpdateLocalPlayer()
    end)

    --Invalidate the anchored platforms in the platform.
    --This is to prevent idle platforms from being constantly replicated.
    task.spawn(function()
        while true do
            --Invalidate the anchored platforms that have not moved.
            local AssemblyRootsToInvalidate = {}
            for AssemblyRoot, LastMoveTime in MovingAnchoredAssemblyRoots do
                if (tick() - LastMoveTime) < ANCHORED_PLATFORM_CACHE_INVALIDATION_TIME_SECONDS then continue end
                table.insert(AssemblyRootsToInvalidate, AssemblyRoot)
            end
            for _, AsssemblyRoot in AssemblyRootsToInvalidate do
                MovingAnchoredAssemblyRoots[AsssemblyRoot] = nil
                AsssemblyRoot:RemoveTag(ANCHORED_PLATFORM_CACHE_DEBUG_TAG)
            end

            --Wait to continue.
            task.wait(ANCHORED_PLATFORM_CACHE_INVALIDATION_LOOP_DELAY_SECONDS)
        end
    end)
    
    --Return the module to allow for chaining.
    return AnchoredPlatformPlayerMovement
end

--[[
Enables toggling a debug key to show and hide cached anchored moving platforms.
Must be called on the client.
Returns AnchoredPlatformPlayerMovement to allow for chaining. 
--]]
function AnchoredPlatformPlayerMovement.EnableDebugView(self: AnchoredPlatformPlayerMovement, KeyCode: Enum.KeyCode): AnchoredPlatformPlayerMovement
    --Connect toggling the debug view.
    local DebugViewActive = false
    local ActiveHighlights, EventConnections = {}, {}
    UserInputService.InputBegan:Connect(function(Input, Processed)
        if Processed then return end
        if Input.KeyCode ~= KeyCode then return end

        --Toggle the debug view.
        DebugViewActive = not DebugViewActive

        --Handle the view change.
        if DebugViewActive then
            --Connect new platforms being added or removed.
            table.insert(EventConnections, CollectionService:GetInstanceAddedSignal(ANCHORED_PLATFORM_CACHE_DEBUG_TAG):Connect(function(AsssemblyRoot)
                local Highlight = Instance.new("Highlight")
                Highlight.FillColor = Color3.fromRGB(0, 255, 0)
                Highlight.Adornee = AsssemblyRoot
                Highlight.Parent = AsssemblyRoot
                ActiveHighlights[AsssemblyRoot] = Highlight
            end))
            table.insert(EventConnections, CollectionService:GetInstanceRemovedSignal(ANCHORED_PLATFORM_CACHE_DEBUG_TAG):Connect(function(AsssemblyRoot)
                if not ActiveHighlights[AsssemblyRoot] then return end
                ActiveHighlights[AsssemblyRoot]:Destroy()
                ActiveHighlights[AsssemblyRoot] = nil
            end))

            --Create the existing highlights.
            for _, AsssemblyRoot in CollectionService:GetTagged(ANCHORED_PLATFORM_CACHE_DEBUG_TAG) do
                local Highlight = Instance.new("Highlight")
                Highlight.FillColor = Color3.fromRGB(0, 255, 0)
                Highlight.Adornee = AsssemblyRoot
                Highlight.Parent = AsssemblyRoot
                ActiveHighlights[AsssemblyRoot] = Highlight
            end
        else
            --Clear the highlights and event connections.
            for _, Highlight in ActiveHighlights do
                Highlight:Destroy()
            end
            ActiveHighlights = {}
            for _, EventConnection in EventConnections do
                EventConnection:Disconnect()
            end
            EventConnections = {}
        end
    end)

    --Return the module to allow for chaining.
    return AnchoredPlatformPlayerMovement
end



return AnchoredPlatformPlayerMovement