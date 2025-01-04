--Sets up AnchoredPlatformPlayerMovement on the server.
--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AnchoredPlatformPlayerMovement = require(ReplicatedStorage:WaitForChild("AnchoredPlatformPlayerMovement"))
AnchoredPlatformPlayerMovement:EnableServerReplication()
