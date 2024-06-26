local lib = require("ImmersiveTravel.lib")
local log = lib.log

-- Define the CAbstractStateMachine class
---@class CAbstractStateMachine
---@field currentState CAbstractState
---@field states table<string, CAbstractState>
---@field name string
local CAbstractStateMachine = {}

-- Constructor
---@return CAbstractStateMachine
function CAbstractStateMachine:new()
    local newObj = {}
    self.__index = self
    setmetatable(newObj, self)
    return newObj
end

-- update the current state
---@param dt number
---@param scriptedObject CTickingEntity
function CAbstractStateMachine:update(dt, scriptedObject)
    -- transition to the new state if needed
    -- go through the transitions of the current state
    local ctx = {
        scriptedObject = scriptedObject
    }
    for state, transition in pairs(self.currentState.transitions) do
        if transition(ctx) then
            log:debug("[%s] Exiting state: %s", self.name, self.currentState.name)
            self.currentState:exit(scriptedObject)
            self.currentState = self.states[state]
            log:debug("[%s] Entering state: %s", self.name, self.currentState.name)
            self.currentState:enter(scriptedObject)
        end
    end

    -- update the current state
    self.currentState:update(dt, scriptedObject)
end

--#region events

---@param scriptedObject CTickingEntity
function CAbstractStateMachine:OnActivate(scriptedObject)
    log:debug("CAbstractStateMachine:OnActivate")
    self.currentState:OnActivate(scriptedObject)
end

--#endregion

return CAbstractStateMachine
