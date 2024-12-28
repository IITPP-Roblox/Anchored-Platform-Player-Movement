# Anchored-Platform-Player-Movement
Anchored Platform Player Movement moves players on moving
anchored platforms and moving surrounding players.

Roblox supports this for unanchored parts, but not anchored
parts.

# Setup
Setup is only required for the module loading. No changes to
any parts are needed.

## Client
On the client, at least `EnableLocalCharacterUpdates` must be
called in the module to move the local player. `EnableDebugView`
can be optionally called to add a keybind for the debug view,
and `EnableServerReplication` to enable replication (server setup
required).

```luau
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AnchoredPlatformPlayerMovement = require(...)

AnchoredPlatformPlayerMovement:EnableLocalCharacterUpdates() --Sets up moving the local player (required).
AnchoredPlatformPlayerMovement:EnableServerReplication() --Sets up replication and moving other players (optional).
AnchoredPlatformPlayerMovement:EnableDebugView(Enum.KeyCode.F2) --Sets up a debug view toggle (optional).
```

The functions can be chained together, if desired.

```luau
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AnchoredPlatformPlayerMovement = require(...)

AnchoredPlatformPlayerMovement:EnableLocalCharacterUpdates()
                              :EnableServerReplication()
                              :EnableDebugView(Enum.KeyCode.F2)
```

## Server
The server is only required if replicating other player positions.
If `EnableClientReplication` is not used on the client, the server
setup will have no effect.

```luau
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AnchoredPlatformPlayerMovement = require(...)

AnchoredPlatformPlayerMovement:EnableServerReplication()
```

# License
This project is available under the terms of the MIT License.
See [LICENSE](LICENSE) for details.