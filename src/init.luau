--Allows for players to stay with anchored moving platforms.
--!strict

local ADDITIONAL_DISTANCE_BELOW_CHARACTER_TO_RAYCAST = 2

local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local AnchoredPlatformPlayerMovement = {}

export type AnchoredPlatformPlayerMovement = typeof(AnchoredPlatformPlayerMovement)

--Client state.
local LastPlatform: BasePart? = nil
local LastPlatformCFrame: CFrame = CFrame.identity
local LastPlatformOffset: CFrame = CFrame.identity



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
    
    --Return the module to allow for chaining.
    return AnchoredPlatformPlayerMovement
end



return AnchoredPlatformPlayerMovement