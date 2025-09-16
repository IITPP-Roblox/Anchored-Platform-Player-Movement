--Allows for players to stay with anchored moving platforms, and moving other players.
--!strict

local PLAYER_ENTRY_SIZE_BYTES = (3 * 4) + (4 * 4) + (3 * 4) + (3 * 4) --Vector3 offset (3 x 4 bytes) + Rotation offset (4 x 4 bytes, Axis Angle format) + Vector3 velocity (3 x 4 bytes) + Vector3 angular velocity (3 x 4 bytes)
local PLAYER_ENTRY_SIZE_BYTES_WITH_KEY = 8 + PLAYER_ENTRY_SIZE_BYTES
local ADDITIONAL_DISTANCE_BELOW_CHARACTER_TO_RAYCAST = 2
local MAX_EXTRAPOLATION_SECONDS = 0.1
local ANCHORED_PLATFORM_CACHE_DEBUG_TAG = "MovingAnchoredPlatform"
local ANCHORED_PLATFORM_CACHE_INVALIDATION_TIME_SECONDS = 0.5
local ANCHORED_PLATFORM_CACHE_INVALIDATION_LOOP_DELAY_SECONDS = 0.25

local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local BufferedRemoteEventSender = require(script:WaitForChild("Packages"):WaitForChild("NexusBufferedReplication")).Sender.BufferedRemoteEventSender

local AnchoredPlatformPlayerMovement = {}

export type AnchoredPlatformPlayerMovement = typeof(AnchoredPlatformPlayerMovement)

--Client state.
local LastPlatform: BasePart? = nil
local LastPlatformCFrame: CFrame = CFrame.identity
local LastPlatformOffset: CFrame = CFrame.identity
local LastHumanoidRootPartOffset: CFrame? = nil
local LastHumanoidRootPartVelocity: Vector3? = nil
local LastHumanoidRootPartAngularVelocity: Vector3? = nil
local MovingAnchoredAssemblyRoots: {[BasePart]: number} = {}



--Create the replication instances.
if RunService:IsServer() then
    local SetPlatformOffsetEvent = Instance.new("RemoteEvent")
    SetPlatformOffsetEvent.Name = "SetPlatformOffset"
    SetPlatformOffsetEvent.Parent = script
    
    local UpdatePlatformOffsetEvent = Instance.new("RemoteEvent")
    UpdatePlatformOffsetEvent.Name = "UpdatePlatformOffset"
    UpdatePlatformOffsetEvent.Parent = script

    local PlayerCurrentPlatforms = Instance.new("Folder")
    PlayerCurrentPlatforms.Name = "PlayerCurrentPlatforms"
    PlayerCurrentPlatforms.Parent = script
end



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
        LastHumanoidRootPartOffset = LastPlatform.CFrame:Inverse() * HumanoidRootPart.CFrame
        LastHumanoidRootPartVelocity = HumanoidRootPart.AssemblyLinearVelocity
        LastHumanoidRootPartAngularVelocity = HumanoidRootPart.AssemblyAngularVelocity
    else
        LastHumanoidRootPartOffset = nil
        LastHumanoidRootPartVelocity = nil
        LastHumanoidRootPartAngularVelocity = nil
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

--[[
Enables client replication of other characters.
This allows for other players to appear as moving on platforms.
Must be called on the client.
Returns AnchoredPlatformPlayerMovement to allow for chaining.
--]]
function AnchoredPlatformPlayerMovement.EnableClientReplication(self: AnchoredPlatformPlayerMovement): AnchoredPlatformPlayerMovement
    --Throw an error if EnableClientReplication was called on the server.
    if not RunService:IsClient() then
        error("AnchoredPlatformPlayerMovement::EnableClientReplication must be called on the client.")
    end
    
    --Get the replication instances.
    local SetPlatformOffsetEvent = script:WaitForChild("SetPlatformOffset")
    local UpdatePlatformOffsetEvent = script:WaitForChild("UpdatePlatformOffset")
    local PlayerCurrentPlatforms = script:WaitForChild("PlayerCurrentPlatforms")
    
    --Replicate the current offset to the server at about 60hz.
    local LastReplicatedPlatform = nil
    task.spawn(function()
        while true do
            --Determine the platform to replicate.
            local PlatformToReplicate = LastPlatform
            if PlatformToReplicate and not MovingAnchoredAssemblyRoots[PlatformToReplicate] then
                PlatformToReplicate = nil
            end

            --Replicate the change.
            if LastReplicatedPlatform ~= PlatformToReplicate then
                SetPlatformOffsetEvent:FireServer(PlatformToReplicate, PlatformToReplicate and LastHumanoidRootPartOffset, LastHumanoidRootPartVelocity, LastHumanoidRootPartAngularVelocity)
                LastReplicatedPlatform = PlatformToReplicate
            elseif PlatformToReplicate and LastHumanoidRootPartOffset then
                UpdatePlatformOffsetEvent:FireServer(LastHumanoidRootPartOffset, LastHumanoidRootPartVelocity, LastHumanoidRootPartAngularVelocity)
            end
            
            --Wait to send additional requests.
            task.wait(1 / 60)
        end
    end)
    
    --Store the platforms of players.
    local PlayerPlatformAssemblyRoots = {}
    local function InitializeAssemblyRootValue(Value: Instance): ()
        --Return if the value is not an ObjectValue, the player it is for doesn't exist, or it is the local player.
        if not Value:IsA("ObjectValue") then return end
        local Player = Players:GetPlayerByUserId(tonumber(Value.Name))
        if not Player or Player == Players.LocalPlayer then return end
        
        --Store the initial entry.
        local Entry = {
            Player = Player,
            LastUpdateTime = tick(),
            AssemblyRoot = Value.Value :: BasePart,
            CharacterOffset = nil :: CFrame?,
            CharacterVelocity = nil :: Vector3?,
            CharacterAngularVelocity = nil :: Vector3?,
        }
        PlayerPlatformAssemblyRoots[Player.UserId] = Entry
        
        --Connect changes to the value.
        --The event connection is not stored since it will be connected when it is destroyed on the server.
        Value:GetPropertyChangedSignal("Value"):Connect(function()
            Entry.AssemblyRoot = Value.Value :: BasePart
            Entry.CharacterOffset = nil
        end)
    end

    for _, Value in PlayerCurrentPlatforms:GetChildren() do
        InitializeAssemblyRootValue(Value)
    end
    PlayerCurrentPlatforms.ChildAdded:Connect(InitializeAssemblyRootValue)
    PlayerCurrentPlatforms.ChildRemoved:Connect(function(Value)
        local UserId = tonumber(Value.Name)
        if not UserId then return end
        PlayerPlatformAssemblyRoots[UserId] = nil
    end)
    Players.PlayerRemoving:Connect(function(Player)
        PlayerPlatformAssemblyRoots[Player.UserId] = nil
    end)
    
    --Listen to updated character offsets from the server.
    UpdatePlatformOffsetEvent.OnClientEvent:Connect(function(AssemblyOffsetsBuffer: buffer)
        for i = 1, buffer.len(AssemblyOffsetsBuffer) / PLAYER_ENTRY_SIZE_BYTES_WITH_KEY do
            local StartOffset = ((i - 1) * PLAYER_ENTRY_SIZE_BYTES_WITH_KEY)
            local UserId = buffer.readf64(AssemblyOffsetsBuffer, StartOffset)
            local CurrentPlatform = PlayerPlatformAssemblyRoots[UserId]
            if not CurrentPlatform then continue end
            local OffsetPosition = Vector3.new(buffer.readf32(AssemblyOffsetsBuffer, StartOffset + 8), buffer.readf32(AssemblyOffsetsBuffer, StartOffset + 12), buffer.readf32(AssemblyOffsetsBuffer, StartOffset + 16))
            local OffsetAxisAngleVector3, OffsetAxisAngleRotation = Vector3.new(buffer.readf32(AssemblyOffsetsBuffer, StartOffset + 20), buffer.readf32(AssemblyOffsetsBuffer, StartOffset + 24), buffer.readf32(AssemblyOffsetsBuffer, StartOffset + 28)), buffer.readf32(AssemblyOffsetsBuffer, StartOffset + 32)
            local Velocity = Vector3.new(buffer.readf32(AssemblyOffsetsBuffer, StartOffset + 36), buffer.readf32(AssemblyOffsetsBuffer, StartOffset + 40), buffer.readf32(AssemblyOffsetsBuffer, StartOffset + 44))
            local AngularVelocity = Vector3.new(buffer.readf32(AssemblyOffsetsBuffer, StartOffset + 48), buffer.readf32(AssemblyOffsetsBuffer, StartOffset + 52), buffer.readf32(AssemblyOffsetsBuffer, StartOffset + 56))
            CurrentPlatform.LastUpdateTime = tick()
            CurrentPlatform.CharacterOffset = CFrame.new(OffsetPosition) * CFrame.fromAxisAngle(OffsetAxisAngleVector3, OffsetAxisAngleRotation)
            CurrentPlatform.CharacterVelocity = Velocity
            CurrentPlatform.CharacterAngularVelocity = AngularVelocity
        end
    end)
    
    --Update the other players with the stored values before the camera updates.
    RunService:BindToRenderStep("AnchoredPlatformPlayerMovement_UpdateOtherPlayers", Enum.RenderPriority.Camera.Value - 1, function()
        debug.profilebegin("AnchoredPlatformPlayerMovement_UpdateOtherPlayers")
        for _, CurrentPlatform in PlayerPlatformAssemblyRoots do
            local AssemblyRoot = CurrentPlatform.AssemblyRoot
            local CharacterOffset = CurrentPlatform.CharacterOffset
            local CharacterVelocity = CurrentPlatform.CharacterVelocity or Vector3.zero
            local CharacterAngularVelocity = CurrentPlatform.CharacterAngularVelocity or Vector3.zero
            if not AssemblyRoot or not CharacterOffset then continue end
            local Character = CurrentPlatform.Player.Character
            if not Character then continue end
            local Humanoid = Character:FindFirstChildOfClass("Humanoid") :: Humanoid
            local HumanoidRootPart = Character:FindFirstChild("HumanoidRootPart") :: BasePart
            if not Humanoid or not HumanoidRootPart or Humanoid.Health <= 0 then continue end
            if HumanoidRootPart.AssemblyRootPart ~= HumanoidRootPart then continue end --The AssemblyRootPart is checked in case the player is attached to something else (like the platform through a seat).
            local ExtrapolationTime = math.min((tick() - CurrentPlatform.LastUpdateTime), MAX_EXTRAPOLATION_SECONDS)
            local ExtrapolatedAnglularVelocity = ExtrapolationTime * CharacterAngularVelocity
            HumanoidRootPart.CFrame = CFrame.new(ExtrapolationTime * CharacterVelocity) * AssemblyRoot.CFrame * CharacterOffset * CFrame.Angles(ExtrapolatedAnglularVelocity.X, ExtrapolatedAnglularVelocity.Y, ExtrapolatedAnglularVelocity.Z)
        end
        debug.profileend()
    end)
    
    --Return the module to allow for chaining.
    return AnchoredPlatformPlayerMovement
end

--[[
Enables server replication of characters.
Must be called on the server.
Returns AnchoredPlatformPlayerMovement to allow for chaining.
--]]
function AnchoredPlatformPlayerMovement.EnableServerReplication(self: AnchoredPlatformPlayerMovement): AnchoredPlatformPlayerMovement
    --Throw an error if EnableServerReplication was called on the client.
    if not RunService:IsServer() then
        error("AnchoredPlatformPlayerMovement::EnableServerReplication must be called on the server.")
    end
    
    --Get the replication instances.
    local SetPlatformOffsetEvent = script:WaitForChild("SetPlatformOffset")
    local UpdatePlatformOffsetEvent = script:WaitForChild("UpdatePlatformOffset")
    local PlayerCurrentPlatforms = script:WaitForChild("PlayerCurrentPlatforms")
    
    --Set up replication of platform offsets.
    --To reduce network load, updates are sent in bulk.
    local OffsetBufferedRemoteEventSender = BufferedRemoteEventSender.WithPlayerKeys(UpdatePlatformOffsetEvent, function(Data: {Offset: CFrame, Velocity: Vector3, AngularVelocity: Vector3}): buffer
        local Offset = Data.Offset
        local AxisAngleVector3, AxisAngleRotation = Offset:ToAxisAngle()
        local Velocity = Data.Velocity
        local AngularVelocity = Data.AngularVelocity

        local PlatformOffsetBuffer = buffer.create(PLAYER_ENTRY_SIZE_BYTES)
        buffer.writef32(PlatformOffsetBuffer, 0, Offset.X)
        buffer.writef32(PlatformOffsetBuffer, 4, Offset.Y)
        buffer.writef32(PlatformOffsetBuffer, 8, Offset.Z)
        buffer.writef32(PlatformOffsetBuffer, 12, AxisAngleVector3.X)
        buffer.writef32(PlatformOffsetBuffer, 16, AxisAngleVector3.Y)
        buffer.writef32(PlatformOffsetBuffer, 20, AxisAngleVector3.Z)
        buffer.writef32(PlatformOffsetBuffer, 24, AxisAngleRotation)
        buffer.writef32(PlatformOffsetBuffer, 28, Velocity.X)
        buffer.writef32(PlatformOffsetBuffer, 32, Velocity.Y)
        buffer.writef32(PlatformOffsetBuffer, 36, Velocity.Z)
        buffer.writef32(PlatformOffsetBuffer, 40, AngularVelocity.X)
        buffer.writef32(PlatformOffsetBuffer, 44, AngularVelocity.Y)
        buffer.writef32(PlatformOffsetBuffer, 48, AngularVelocity.Z)
        return PlatformOffsetBuffer
    end)
    OffsetBufferedRemoteEventSender:StartDataSendingWithEvent(RunService.Heartbeat)

    --Connect requests from the client to change platforms.
    SetPlatformOffsetEvent.OnServerEvent:Connect(function(Player: Player, AssemblyRoot: BasePart, Offset: CFrame?, Velocity: Vector3?, AngularVelocity: Vector3?)
        local CurrentAssemblyRootValue = PlayerCurrentPlatforms:FindFirstChild(tostring(Player.UserId))
        if AssemblyRoot then
            --Update or create the ObjectValue containing the platform.
            if CurrentAssemblyRootValue then
                CurrentAssemblyRootValue.Value = AssemblyRoot
            else
                local NewAssemblyRootValue = Instance.new("ObjectValue")
                NewAssemblyRootValue.Name = tostring(Player.UserId)
                NewAssemblyRootValue.Value = AssemblyRoot
                NewAssemblyRootValue.Parent = PlayerCurrentPlatforms
            end
            
            --Store the offset if it was provided.
            if Offset and Velocity and AngularVelocity then
                OffsetBufferedRemoteEventSender:QueueData(Player, {
                    Offset = Offset,
                    Velocity = Velocity,
                    AngularVelocity = AngularVelocity,
                })
            end
        else
            --Remove the platform ObjectValue if it exist.
            if CurrentAssemblyRootValue then
                CurrentAssemblyRootValue:Destroy()
            end
        end
    end)
    
    --Connect requests from the client to change the offset.
    UpdatePlatformOffsetEvent.OnServerEvent:Connect(function(Player: Player, Offset: CFrame, Velocity: Vector3, AngularVelocity: Vector3)
        OffsetBufferedRemoteEventSender:QueueData(Player, {
            Offset = Offset,
            Velocity = Velocity,
            AngularVelocity = AngularVelocity,
        })
    end)
    
    --Return the module to allow for chaining.
    return self
end



return AnchoredPlatformPlayerMovement