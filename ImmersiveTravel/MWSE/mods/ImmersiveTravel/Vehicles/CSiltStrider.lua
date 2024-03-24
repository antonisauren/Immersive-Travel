local config = require("ImmersiveTravel.config")
local CVehicle = require("ImmersiveTravel.Vehicles.CVehicle")

-- Define the CSiltStrider class inheriting from CVehicle
---@class CSiltStrider : CVehicle
local CSiltStrider = {
    id = "a_siltstrider",
    sound = {
        "Silt_1",
        "Silt_2",
        "Silt_3"
    },
    loopSound = false,
    mesh = "r\\Siltstrider.nif",
    offset = -1220,
    sway = 1,
    speed = 3,
    turnspeed = 30,
    hasFreeMovement = false,
    freedomtype = "ground",
    forwardAnimation = "runForward",
    nodeName = "Body",
    nodeOffset = tes3vector3.new(0, 56, 1005),
    guideSlot = {
        animationGroup = { "idle5" },
        position = tes3vector3.new(0, 10, 1223)
    },
    hiddenSlot = {
        position = tes3vector3.new(0, 0, 1000)
    },
    slots = {
        {
            animationGroup = {},
            position = tes3vector3.new(0, 80, 1223)
        },
        {
            animationGroup = {},
            position = tes3vector3.new(-81, 20, 1230)
        },
        {
            animationGroup = {},
            position = tes3vector3.new(81, 40, 1230)
        },
    }
}
setmetatable(CSiltStrider, { __index = CVehicle })

---Constructor for CSiltStrider
---@return CSiltStrider
function CSiltStrider:new()
    local newObj = CVehicle:new()
    self.__index = self
    setmetatable(newObj, self)
    ---@cast newObj CSiltStrider

    return newObj
end

---@param position tes3vector3
---@param orientation tes3vector3
---@param facing number
---@return CSiltStrider
function CSiltStrider:create(position, orientation, facing)
    -- create reference
    local mountOffset = tes3vector3.new(0, 0, self.offset)
    local reference = tes3.createReference {
        object = self.id,
        position = position + mountOffset,
        orientation = orientation
    }
    reference.facing = facing

    local newObj = CVehicle:create(reference)
    self.__index = self
    setmetatable(newObj, self)
    ---@cast newObj CSiltStrider

    newObj:OnCreate()

    return newObj
end

-- overrides

function CSiltStrider:PlayAnimation()
    if self.forwardAnimation then
        local mount = self.referenceHandle:getObject()

        local forwardAnimation = self.forwardAnimation
        if config.a_siltstrider_forwardAnimation then
            forwardAnimation = config.a_siltstrider_forwardAnimation
        end

        tes3.loadAnimation({ reference = mount })
        tes3.playAnimation({ reference = mount, group = tes3.animationGroup[forwardAnimation] })
    end
end

return CSiltStrider
