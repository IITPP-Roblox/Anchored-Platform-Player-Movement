--Moved anchored platforms on the server.
--!strict

local Workspace = game:GetService("Workspace")

local Platform1 = Instance.new("Part")
Platform1.Size = Vector3.new(10, 1, 10)
Platform1.Anchored = true
Platform1.Parent = Workspace

task.spawn(function()
    while true do
        local Time = tick()
        local Center = CFrame.new(20 * math.cos(Time), 0.5, 20 * math.sin(Time))
        Platform1.CFrame = CFrame.new(Center.Position, Vector3.new(0, 0.5, 0))
        task.wait()
    end
end)

local Platform2 = Instance.new("Part")
Platform2.Size = Vector3.new(10, 1, 10)
Platform2.Anchored = true
Platform2.Parent = Workspace

task.spawn(function()
    while true do
        for i = 0, 100, 10 do
            Platform2.CFrame = CFrame.new(0, 0.5 + i, -30)
            task.wait(0.1)
        end
        for i = 100, 0, -10 do
            Platform2.CFrame = CFrame.new(0, 0.5 + i, -30)
            task.wait(0.1)
        end
        task.wait(3)
    end
end)


local Platform3 = Instance.new("Part")
Platform3.Size = Vector3.new(10, 1, 10)
Platform3.Anchored = true
Platform3.Parent = Workspace

task.spawn(function()
    while true do
        Platform3.CFrame = CFrame.new(-30, 0.5, 0) * CFrame.Angles(0, (2 * tick()) % (2 * math.pi), 0)
        task.wait()
    end
end)

local Platform4 = Instance.new("Part")
Platform4.Size = Vector3.new(10, 1, 10)
Platform4.Anchored = true
Platform4.Parent = Workspace

task.spawn(function()
    while true do
        Platform4.CFrame = CFrame.new(0, 20, 40) * CFrame.Angles(math.rad(40) * math.sin(tick()), 0, math.rad(40) * math.cos(1.5 * tick())) * CFrame.new(0, -18, 0)
        task.wait()
    end
end)