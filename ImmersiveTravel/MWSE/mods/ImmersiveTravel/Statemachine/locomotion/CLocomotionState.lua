local AbstractState = require("ImmersiveTravel.Statemachine.CAbstractState")
local lib = require("ImmersiveTravel.lib")
local log = lib.log

-- Abstract locomotion state machine class
---@class CLocomotionState : CAbstractState
local CLocomotionState = {
    transitions = {}
}

--#region methods

-- enum for locomotion states
CLocomotionState.IDLE = "IDLE"
CLocomotionState.MOVING = "MOVING"
CLocomotionState.ACCELERATE = "ACCELERATE"
CLocomotionState.DECELERATE = "DECELERATE"

---Constructor for LocomotionState
---@return CLocomotionState
function CLocomotionState:new()
    local newObj = AbstractState:new()
    self.__index = self
    setmetatable(newObj, self)
    ---@cast newObj CLocomotionState
    return newObj
end

--- transition to moving state
---@param ctx table
---@return boolean
local function toMovingState(ctx)
    local vehicle = ctx.scriptedObject ---@cast vehicle CVehicle
    return (vehicle.spline or vehicle.virtualDestination) and
        (vehicle.speed > 0.5 or vehicle.speed < -0.5)
end

--- transition to idle state
---@param ctx table
---@return boolean
local function toIdleState(ctx)
    local vehicle = ctx.scriptedObject ---@cast vehicle CVehicle

    -- if no spline and no virtual destination, then idle
    if vehicle.spline == nil and vehicle.virtualDestination == nil then
        return true
    end

    return vehicle.speed < 0.5 and vehicle.speed > -0.5
end

--- transition to accelerate state
---@param ctx table
---@return boolean
local function toAccelerateState(ctx)
    local vehicle = ctx.scriptedObject ---@cast vehicle CVehicle
    return (vehicle.spline or vehicle.virtualDestination) and
        vehicle.speedChange > 0
end

--- transition to decelerate state
---@param ctx table
---@return boolean
local function toDecelerateState(ctx)
    local vehicle = ctx.scriptedObject ---@cast vehicle CVehicle
    return (vehicle.spline or vehicle.virtualDestination) and
        vehicle.speedChange < 0
end

--#endregion

--#region IdleState

-- Idle state class
---@class IdleState : CLocomotionState
CLocomotionState.IdleState = {
    transitions = {
        [CLocomotionState.MOVING] = toMovingState,
        [CLocomotionState.ACCELERATE] = toAccelerateState,
        [CLocomotionState.DECELERATE] = toDecelerateState
    }
}

-- constructor for IdleState
---@return IdleState
function CLocomotionState.IdleState:new()
    local newObj = CLocomotionState:new()
    self.__index = self
    setmetatable(newObj, self)
    ---@cast newObj IdleState
    return newObj
end

function CLocomotionState.IdleState:enter(scriptedObject)
    local vehicle = scriptedObject ---@cast vehicle CVehicle

    -- TODO idle sounds
    if vehicle.current_sound then
        local mount = vehicle.referenceHandle:getObject()
        tes3.removeSound({ reference = mount, sound = vehicle.current_sound })
        vehicle.current_sound = nil
    end

    -- play anim
    if vehicle.animation.idle then
        tes3.loadAnimation({ reference = vehicle.referenceHandle:getObject() })
        tes3.playAnimation({
            reference = vehicle.referenceHandle:getObject(),
            group = vehicle.animation.idle
        })
    end
end

function CLocomotionState.IdleState:update(dt, scriptedObject)
    -- Implement idle state update logic here
end

function CLocomotionState.IdleState:exit(scriptedObject)
    -- Implement idle state exit logic here
end

--#endregion

--#region MovingState

-- Moving state class
---@class MovingState : CLocomotionState
CLocomotionState.MovingState = {
    transitions = {
        [CLocomotionState.IDLE] = toIdleState,
        [CLocomotionState.ACCELERATE] = toAccelerateState,
        [CLocomotionState.DECELERATE] = toDecelerateState
    }
}

-- constructor for MovingState
---@return MovingState
function CLocomotionState.MovingState:new()
    local newObj = CLocomotionState:new()
    self.__index = self
    setmetatable(newObj, self)
    ---@cast newObj MovingState
    return newObj
end

--#region methods

---@param vehicle CVehicle
---@param nextPos tes3vector3
---@return tes3vector3, number, number
local function CalculatePositions(vehicle, nextPos)
    local mount = vehicle.referenceHandle:getObject()

    -- calculate diffs
    local mountOffset = tes3vector3.new(0, 0, vehicle.offset)
    local currentPos = vehicle.last_position - mountOffset
    local forwardDirection = vehicle.last_forwardDirection
    forwardDirection:normalize()
    local d = (nextPos - currentPos):normalized()
    local lerp = forwardDirection:lerp(d, vehicle.turnspeed / 10):normalized()
    local forward = tes3vector3.new(mount.forwardDirection.x, mount.forwardDirection.y, lerp.z):normalized()
    local delta = forward * vehicle.speed
    local position = currentPos + delta + mountOffset

    -- calculate facing
    local new_facing = math.atan2(d.x, d.y)
    local turn = 0
    local current_facing = vehicle.last_facing
    local facing = new_facing
    local diff = new_facing - current_facing
    if diff < -math.pi then diff = diff + 2 * math.pi end
    if diff > math.pi then diff = diff - 2 * math.pi end
    local angle = vehicle.turnspeed / 10000
    if diff > 0 and diff > angle then
        facing = current_facing + angle
        turn = 1
    elseif diff < 0 and diff < -angle then
        facing = current_facing - angle
        turn = -1
    else
        facing = new_facing
    end

    return position, facing, turn
end

---@param vehicle CVehicle
---@param dt number
---@param turn number
local function calculateOrientation(vehicle, dt, turn)
    local mount = vehicle.referenceHandle:getObject()

    local amplitude = lib.SWAY_AMPL * vehicle.sway
    local sway_change = amplitude * lib.SWAY_AMPL_CHANGE

    vehicle.swayTime = vehicle.swayTime + dt
    if vehicle.swayTime > (2000 * lib.SWAY_FREQ) then vehicle.swayTime = dt end

    -- periodically change anims and play sounds
    local i, f = math.modf(vehicle.swayTime)
    if i > 0 and f < dt and math.fmod(i, lib.ANIM_CHANGE_FREQ) == 0 then
        if not vehicle.loopSound and math.random() > 0.5 then
            local sound = vehicle.sound[math.random(1, #vehicle.sound)]
            vehicle.current_sound = sound
            tes3.playSound({
                sound = sound,
                reference = mount
            })
        end
    end

    local sway = amplitude *
        math.sin(2 * math.pi * lib.SWAY_FREQ * vehicle.swayTime)
    -- offset roll during turns
    if turn > 0 then
        local max = (lib.SWAY_MAX_AMPL * amplitude)
        sway = math.clamp(vehicle.last_sway - sway_change, -max, max) -- - sway
    elseif turn < 0 then
        local max = (lib.SWAY_MAX_AMPL * amplitude)
        sway = math.clamp(vehicle.last_sway + sway_change, -max, max) -- + sway
    else
        -- normalize back
        if vehicle.last_sway < (sway - sway_change) then
            sway = vehicle.last_sway + sway_change -- + sway
        elseif vehicle.last_sway > (sway + sway_change) then
            sway = vehicle.last_sway - sway_change -- - sway
        end
    end
    vehicle.last_sway = sway
    local newOrientation = lib.toWorldOrientation(tes3vector3.new(0.0, sway, 0.0), mount.orientation)

    return newOrientation
end

---@param vehicle CVehicle
---@return tes3vector3?
local function getNextPositionHeading(vehicle)
    -- handle player steer and onspline states
    if vehicle.virtualDestination then
        return vehicle.virtualDestination
    end

    -- move on spline
    if vehicle.spline == nil then
        return nil
    end
    -- move to next marker
    if vehicle.splineIndex > #vehicle.spline then
        return nil
    end

    local mount = vehicle.referenceHandle:getObject()
    local nextPos = lib.vec(vehicle.spline[vehicle.splineIndex])
    local isBehind = lib.isPointBehindObject(nextPos, mount.position, mount.forwardDirection)
    if isBehind then
        vehicle.splineIndex = vehicle.splineIndex + 1
    end
    nextPos = lib.vec(vehicle.spline[vehicle.splineIndex])

    return nextPos
end

---@param dt number
---@param vehicle CVehicle
local function Move(vehicle, dt)
    if not vehicle.referenceHandle:valid() then
        return
    end

    local nextPos = getNextPositionHeading(vehicle)
    if nextPos == nil then
        return
    end

    local position, facing, turn = CalculatePositions(vehicle, nextPos)

    -- move the reference
    local mount = vehicle.referenceHandle:getObject()
    mount.facing = facing
    mount.position = position
    -- save positions
    vehicle.last_position = mount.position
    vehicle.last_forwardDirection = mount.forwardDirection
    vehicle.last_facing = mount.facing

    -- sway
    mount.orientation = calculateOrientation(vehicle, dt, turn)

    -- update slots
    vehicle:UpdateSlots(dt)
end

--#endregion

---@param scriptedObject CTickingEntity
function CLocomotionState.MovingState:enter(scriptedObject)
    local vehicle = scriptedObject ---@cast vehicle CVehicle

    -- sounds
    if vehicle.loopSound then
        local sound = vehicle.sound[math.random(1, #vehicle.sound)]
        vehicle.current_sound = sound
        tes3.playSound({
            sound = sound,
            reference = vehicle.referenceHandle:getObject(),
            loop = true
        })
    end

    -- play anim
    if vehicle.animation.forward then
        -- local forwardAnimation = self.forwardAnimation
        -- if config.a_siltstrider_forwardAnimation then
        --     forwardAnimation = config.a_siltstrider_forwardAnimation
        -- end

        tes3.loadAnimation({ reference = vehicle.referenceHandle:getObject() })
        tes3.playAnimation({
            reference = vehicle.referenceHandle:getObject(),
            group = vehicle.animation.forward
        })
    end
end

---@param dt number
---@param scriptedObject CTickingEntity
function CLocomotionState.MovingState:update(dt, scriptedObject)
    -- Implement moving state update logic here
    local vehicle = scriptedObject ---@cast vehicle CVehicle
    Move(vehicle, dt)
end

function CLocomotionState.MovingState:exit(scriptedObject)
    -- Implement moving state exit logic here
end

--#endregion

--#region AccelerateState

-- Accelerate state class
---@class AccelerateState : CLocomotionState
CLocomotionState.AccelerateState = {
    transitions = {
        [CLocomotionState.IDLE] = toIdleState,
        [CLocomotionState.MOVING] = toMovingState,
        [CLocomotionState.DECELERATE] = toDecelerateState
    }
}

-- constructor for MovingState
---@return AccelerateState
function CLocomotionState.AccelerateState:new()
    local newObj = CLocomotionState:new()
    self.__index = self
    setmetatable(newObj, self)
    ---@cast newObj AccelerateState
    return newObj
end

function CLocomotionState.AccelerateState:enter(scriptedObject)
    local vehicle = scriptedObject ---@cast vehicle CVehicle
    -- play anim
    if vehicle.animation.accelerate then
        tes3.loadAnimation({ reference = vehicle.referenceHandle:getObject() })
        tes3.playAnimation({
            reference = vehicle.referenceHandle:getObject(),
            group = vehicle.animation.accelerate
        })
    end
end

function CLocomotionState.AccelerateState:update(dt, scriptedObject)
    -- Implement accelerate state update logic here
end

function CLocomotionState.AccelerateState:exit(scriptedObject)
    -- Implement accelerate state exit logic here
end

--#endregion

--#region DecelerateState

-- Decelerate state class
---@class DecelerateState : CLocomotionState
CLocomotionState.DecelerateState = {
    transitions = {
        [CLocomotionState.IDLE] = toIdleState,
        [CLocomotionState.MOVING] = toMovingState,
        [CLocomotionState.ACCELERATE] = toAccelerateState
    }
}

-- constructor for MovingState
---@return DecelerateState
function CLocomotionState.DecelerateState:new()
    local newObj = CLocomotionState:new()
    self.__index = self
    setmetatable(newObj, self)
    ---@cast newObj DecelerateState
    return newObj
end

function CLocomotionState.DecelerateState:enter(scriptedObject)
    -- Implement decelerate state enter logic here
end

function CLocomotionState.DecelerateState:update(dt, scriptedObject)
    -- Implement decelerate state update logic here
end

function CLocomotionState.DecelerateState:exit(scriptedObject)
    -- Implement decelerate state exit logic here
end

--#endregion

return CLocomotionState
