--Sets up AnchoredPlatformPlayerMovement on the client.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AnchoredPlatformPlayerMovement = require(ReplicatedStorage:WaitForChild("AnchoredPlatformPlayerMovement"))
AnchoredPlatformPlayerMovement:EnableLocalCharacterUpdates()
AnchoredPlatformPlayerMovement:EnableDebugView(Enum.KeyCode.F2)