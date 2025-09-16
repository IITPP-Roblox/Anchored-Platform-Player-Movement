--Sets up AnchoredPlatformPlayerMovement on the client.
--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AnchoredPlatformPlayerMovement = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("AnchoredPlatformPlayerMovement"))
AnchoredPlatformPlayerMovement:EnableLocalCharacterUpdates()
AnchoredPlatformPlayerMovement:EnableClientReplication()
AnchoredPlatformPlayerMovement:EnableDebugView(Enum.KeyCode.F2)