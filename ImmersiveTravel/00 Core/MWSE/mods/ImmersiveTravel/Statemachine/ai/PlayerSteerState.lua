local CAiState = require("ImmersiveTravel.Statemachine.ai.CAiState")
local CPlayerVehicleManager = require("ImmersiveTravel.CPlayerVehicleManager")
local lib = require("ImmersiveTravel.lib")

-- player steer state class
---@class PlayerSteerState : CAiState
---@field cameraOffset tes3vector3?
local PlayerSteerState = {
    name = CAiState.PLAYERSTEER,
    transitions = {
        [CAiState.PLAYERTRAVEL] = CAiState.ToPlayerTravel,
        [CAiState.ONSPLINE] = CAiState.ToOnSpline,
        [CAiState.NONE] = CAiState.ToNone,
    },
    cameraOffset = nil,
}
setmetatable(PlayerSteerState, { __index = CAiState })

-- constructor for PlayerSteerState
---@return PlayerSteerState
function PlayerSteerState:new()
    local newObj = CAiState:new()
    self.__index = self
    setmetatable(newObj, self)
    ---@cast newObj PlayerSteerState
    return newObj
end

--#region events

--- hold w or s to change speed
--- @param e keyDownEventData
local function mountKeyDownCallback(e)
    local vehicle = CPlayerVehicleManager.getInstance().trackedVehicle
    if not vehicle then
        return
    end

    if e.keyCode == tes3.scanCode["w"] then
        -- increment speed
        if vehicle.current_speed < vehicle.maxSpeed then
            vehicle.speedChange = 1
        end
    elseif e.keyCode == tes3.scanCode["s"] then
        -- decrement speed
        if vehicle.current_speed > vehicle.minSpeed then
            vehicle.speedChange = -1
        end
    end
end

--- release w or s to stop changing speed
--- @param e keyUpEventData
local function keyUpCallback(e)
    local vehicle = CPlayerVehicleManager.getInstance().trackedVehicle
    if not vehicle then
        return
    end

    local mountData = vehicle.userData
    if not mountData then
        return
    end
    local mountHandle = vehicle.referenceHandle

    if mountHandle and mountHandle:valid() then
        if e.keyCode == tes3.scanCode["w"] or e.keyCode == tes3.scanCode["s"] then
            -- stop increment speed
            vehicle.speedChange = 0
            -- if DEBUG then
            --     tes3.messageBox("Current Speed: " .. tostring(vehicle.current_speed))
            -- end
        end
    end
end

--- set virtual position
--- @param e simulatedEventData
local function mountSimulatedCallback(e)
    local vehicle = CPlayerVehicleManager.getInstance().trackedVehicle
    if not vehicle then
        return
    end

    local mountHandle = vehicle.referenceHandle

    -- update next pos
    if mountHandle and mountHandle:valid() then
        local mount = mountHandle:getObject()

        -- get lookat position
        local dist = 2048
        if vehicle.freedomtype == "ground" then
            dist = 100
        end
        local target = tes3.getPlayerEyePosition() + tes3.getPlayerEyeVector() * dist
        local isControlDown = tes3.worldController.inputController:isControlDown()
        if isControlDown then
            target = mount.sceneNode.worldTransform * tes3vector3.new(0, 2048, 0)
        end

        -- adjust for vehicle type
        if vehicle.freedomtype == "boat" then
            -- pin to waterlevel
            target = tes3vector3.new(target.x, target.y, 0)
        elseif vehicle.freedomtype == "ground" then
            -- pin to groundlevel
            local z = lib.getGroundZ(target + tes3vector3.new(0, 0, 100))
            if not z then
                target = tes3vector3.new(target.x, target.y, 0)
            else
                target = tes3vector3.new(target.x, target.y, target.z + 50)
            end
        end

        -- delegate to vehicle
        vehicle.virtualDestination = target

        -- TODO debug
        -- if DEBUG and travelMarker then
        --     travelMarker.translation = target
        --     local m = tes3matrix33.new()
        --     if isControlDown then
        --         m:fromEulerXYZ(mount.orientation.x, mount.orientation.y, mount.orientation.z)
        --     else
        --         m:fromEulerXYZ(tes3.player.orientation.x, tes3.player.orientation.y, tes3.player.orientation.z)
        --     end
        --     travelMarker.rotation = m
        --     travelMarker:update()
        -- end
    end
end

--#endregion

---@param scriptedObject CTickingEntity
function PlayerSteerState:enter(scriptedObject)
    local vehicle = scriptedObject ---@cast vehicle CVehicle
    CPlayerVehicleManager.getInstance().trackedVehicle = vehicle

    -- register events
    event.register(tes3.event.mouseWheel, lib.mouseWheelCallback)
    event.register(tes3.event.keyDown, mountKeyDownCallback)
    event.register(tes3.event.keyUp, keyUpCallback)
    event.register(tes3.event.simulated, mountSimulatedCallback)

    self.cameraOffset = tes3.get3rdPersonCameraOffset()

    -- visualize debug marker
    -- TODO debug
    -- if DEBUG and travelMarkerMesh then
    --     local vfxRoot = tes3.worldController.vfxManager.worldVFXRoot
    --     local child = travelMarkerMesh:clone()
    --     local from = tes3.getPlayerEyePosition() + tes3.getPlayerEyeVector() * 256
    --     child.translation = from
    --     child.appCulled = false
    --     ---@diagnostic disable-next-line: param-type-mismatch
    --     vfxRoot:attachChild(child)
    --     vfxRoot:update()
    --     travelMarker = child
    -- end
end

---@param dt number
---@param scriptedObject CTickingEntity
function PlayerSteerState:update(dt, scriptedObject)
    -- Implement player steer state update logic here
    local mountHandle = scriptedObject.referenceHandle
    ---@cast scriptedObject CVehicle
    local vehicle = scriptedObject

    -- collision
    if mountHandle and mountHandle:valid() then
        -- raytest at sealevel to detect shore transition
        local box = mountHandle:getObject().object.boundingBox
        local max = box.max * vehicle.scale
        local min = box.min * vehicle.scale
        local t = mountHandle:getObject().sceneNode.worldTransform

        if vehicle.current_speed > 0 then
            -- detect shore
            if vehicle.freedomtype == "boat" then
                local bowPos = t * tes3vector3.new(0, max.y, min.z + (vehicle.offset * vehicle.scale))
                local hitResult1 = tes3.rayTest({
                    position = bowPos,
                    direction = tes3vector3.new(0, 0, -1),
                    root = tes3.game.worldLandscapeRoot,
                    --maxDistance = 4096
                })
                if (hitResult1 == nil) then
                    vehicle.current_speed = 0
                    -- if DEBUG then
                    --     tes3.messageBox("HIT Shore Fwd")
                    --     log:debug("HIT Shore Fwd")
                    -- end
                end
            end

            -- raytest from above to detect objects in water
            local bowPosTop = t * tes3vector3.new(0, max.y, max.z)
            local hitResult2 = tes3.rayTest({
                position = bowPosTop,
                direction = tes3vector3.new(0, 0, -1),
                root = tes3.game.worldObjectRoot,
                ignore = { mountHandle:getObject() },
                maxDistance = max.z * vehicle.scale
            })
            if (hitResult2 ~= nil) then
                vehicle.current_speed = 0
                -- if DEBUG then
                --     tes3.messageBox("HIT Object Fwd")
                --     log:debug("HIT Object Fwd")
                -- end
            end
        elseif vehicle.current_speed < 0 then
            -- detect shore
            if vehicle.freedomtype == "boat" then
                local sternPos = t * tes3vector3.new(0, min.y, min.z + (vehicle.offset * vehicle.scale))
                local hitResult1 = tes3.rayTest({
                    position = sternPos,
                    direction = tes3vector3.new(0, 0, -1),
                    root = tes3.game.worldLandscapeRoot,
                    --maxDistance = 4096
                })
                if (hitResult1 == nil) then
                    vehicle.current_speed = 0
                    -- if DEBUG then
                    --     tes3.messageBox("HIT Shore Back")
                    --     log:debug("HIT Shore Back")
                    -- end
                end
            end

            -- raytest from above to detect objects in water
            local sternPosTop = t * tes3vector3.new(0, min.y, max.z)
            local hitResult2 = tes3.rayTest({
                position = sternPosTop,
                direction = tes3vector3.new(0, 0, -1),
                root = tes3.game.worldObjectRoot,
                ignore = { mountHandle:getObject() },
                maxDistance = max.z
            })
            if (hitResult2 ~= nil) then
                vehicle.current_speed = 0
                -- if DEBUG then
                --     tes3.messageBox("HIT Object Back")
                --     log:debug("HIT Object Back")
                -- end
            end
        end
    end
end

---@param scriptedObject CTickingEntity
function PlayerSteerState:exit(scriptedObject)
    -- reset camera
    if self.cameraOffset then
        tes3.set3rdPersonCameraOffset({ offset = self.cameraOffset })
    end

    local vehicle = scriptedObject ---@cast vehicle CVehicle

    vehicle:EndPlayerSteer()

    -- don't delete ref since we may want to use the mount later
    vehicle:Detach()
    CPlayerVehicleManager.getInstance().trackedVehicle = nil

    -- unregister events
    event.unregister(tes3.event.mouseWheel, lib.mouseWheelCallback)
    event.unregister(tes3.event.keyDown, mountKeyDownCallback)
    event.unregister(tes3.event.keyUp, keyUpCallback)
    event.unregister(tes3.event.simulated, mountSimulatedCallback)
end

---@param scriptedObject CTickingEntity
function PlayerSteerState:OnActivate(scriptedObject)
    local vehicle = scriptedObject ---@cast vehicle CVehicle
    vehicle:EndPlayerSteer()
end

return PlayerSteerState
