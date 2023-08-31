local this = {}

local logger = require("logging.logger")
local log = logger.new {
    name = "Immersive Travel",
    logLevel = "DEBUG",
    logToConsole = true,
    includeTimestamp = true
}

this.localmodpath = "mods\\rfuzzo\\ImmersiveTravel\\"
this.fullmodpath = "Data Files\\MWSE\\" .. this.localmodpath

local localmodpath = this.localmodpath
local fullmodpath = this.fullmodpath

-- /////////////////////////////////////////////////////////////////////////////////////////
-- ////////////// COMMON

-- Transform a local offset to world coordinates given a fixed orientation
---@param localVector tes3vector3
---@param worldOrientation tes3vector3
--- @return tes3vector3
function this.toWorld(localVector, worldOrientation)
    -- Convert the local orientation to a rotation matrix
    local baseRotationMatrix = tes3matrix33.new()
    baseRotationMatrix:fromEulerXYZ(worldOrientation.x, worldOrientation.y,
                                    worldOrientation.z)

    -- Combine the rotation matrices to get the world rotation matrix
    return baseRotationMatrix * localVector
end

---comment
---@param point tes3vector3
---@param objectPosition tes3vector3
---@param objectForwardVector tes3vector3
---@return boolean
function this.isPointBehindObject(point, objectPosition, objectForwardVector)
    local vectorToPoint = point - objectPosition
    local dotProduct = vectorToPoint:dot(objectForwardVector)
    return dotProduct < 0
end

--- list contains
---@param table string[]
---@param str string
function this.is_in(table, str)
    for index, value in ipairs(table) do if value == str then return true end end
    return false
end

--- @param forward tes3vector3
--- @return tes3matrix33
function this.rotationFromDirection(forward)
    forward:normalize()
    local up = tes3vector3.new(0, 0, -1)
    local right = up:cross(forward)
    right:normalize()
    up = right:cross(forward)

    local rotation_matrix = tes3matrix33.new(right.x, forward.x, up.x, right.y,
                                             forward.y, up.y, right.z,
                                             forward.z, up.z)

    return rotation_matrix
end

--- load json spline from file
---@param start string
---@param destination string
---@param data ServiceData
---@return PositionRecord[]|nil
function this.loadSpline(start, destination, data)
    local fileName = start .. "_" .. destination
    local filePath = localmodpath .. data.class .. "\\" .. fileName
    if tes3.getFileExists("MWSE\\" .. filePath .. ".json") then
        local result = json.loadfile(filePath)
        if result ~= nil then
            log:debug("loaded spline: " .. fileName)
            return result
        else
            log:error("!!! failed to load spline: " .. fileName)
            return nil
        end
    else
        -- check if return route exists
        fileName = destination .. "_" .. start
        filePath = localmodpath .. data.class .. "\\" .. fileName
        if tes3.getFileExists("MWSE\\" .. filePath .. ".json") then
            local result = json.loadfile(filePath)
            if result ~= nil then
                log:debug("loaded spline: " .. fileName)

                -- reverse result
                local reversed = {}
                for i = #result, 1, -1 do
                    local val = result[i]
                    table.insert(reversed, val)
                end

                log:debug("reversed spline: " .. fileName)
                return reversed
            else
                log:error("!!! failed to load spline: " .. fileName)
                return nil
            end

        else
            log:error("!!! failed to find any file: " .. fileName)
        end

    end

end

--- load json static mount data
---@param id string
---@return MountData|nil
function this.loadMountData(id)
    local filePath = localmodpath .. "mounts\\" .. id .. ".json"
    local result = {} ---@type table<string, MountData>
    result = json.loadfile(filePath)
    if result then
        log:debug("loaded mount: " .. id)
        return result
    else
        log:error("!!! failed to load mount: " .. id)
        return nil
    end
end

--- Load all services
---@return table<string,ServiceData>|nil
function this.loadServices()
    log:debug("Loading travel services...")

    ---@type table<string,ServiceData>|nil
    local services = {}
    for fileName in lfs.dir(fullmodpath .. "services") do
        if (string.endswith(fileName, ".json")) then
            -- parse
            local r = json.loadfile(localmodpath .. "services\\" .. fileName)
            if r then
                services[fileName:sub(0, -6)] = r

                log:debug("Loaded " .. fileName)
            else
                log:error("!!! failed to load " .. fileName)
            end
        end

    end
    return services
end

--- Load all route splines for a given service
---@param service ServiceData
function this.loadRoutes(service)
    local map = {} ---@type table<string, table>
    for file in lfs.dir(fullmodpath .. service.class) do
        if (string.endswith(file, ".json")) then
            local split = string.split(file:sub(0, -6), "_")
            if #split == 2 then
                local start = ""
                local destination = ""
                for i, id in ipairs(split) do
                    if i == 1 then
                        start = id
                    else
                        destination = id
                    end
                end

                local result = table.get(map, start, nil)
                if not result then
                    local v = {}
                    v[destination] = 1
                    map[start] = v
                else
                    result[destination] = 1
                    map[start] = result
                end

                -- add return trip
                result = table.get(map, destination, nil)
                if not result then
                    local v = {}
                    v[start] = 1
                    map[destination] = v
                else
                    result[start] = 1
                    map[destination] = result
                end
            end
        end
    end

    local r = {}
    for key, value in pairs(map) do
        local v = {}
        for d, _ in pairs(value) do table.insert(v, d) end
        r[key] = v
    end
    service.routes = r
end

--- 
---@param data MountData
---@param startPoint tes3vector3
---@param nextPoint tes3vector3
---@param mountId string
---@return tes3reference
function this.createMount(data, startPoint, nextPoint, mountId)
    local d = nextPoint - startPoint
    d:normalize()

    local newFacing = math.atan2(d.x, d.y)

    -- create mount
    local mountOffset = tes3vector3.new(0, 0, data.offset)
    local mount = tes3.createReference {
        object = mountId,
        position = startPoint + mountOffset,
        orientation = d
    }
    mount.facing = newFacing

    return mount
end
--- 
---@param data MountData
---@param startPoint tes3vector3
---@param nextPoint tes3vector3
---@param mountId string
---@return niNode
function this.createMountVfx(data, startPoint, nextPoint, mountId)
    local d = nextPoint - startPoint
    d:normalize()

    -- create mount
    local vfxRoot = tes3.worldController.vfxManager.worldVFXRoot
    local mountOffset = tes3vector3.new(0, 0, data.offset)

    local meshPath = data.mesh
    local mount = tes3.loadMesh(meshPath):clone()
    mount.translation = startPoint + mountOffset
    mount.rotation = this.rotationFromDirection(d)

    debug.log(mount)
    vfxRoot:attachChild(mount)

    return mount
end

-- sitting mod
-- idle2 ... praying
-- idle3 ... crossed legs
-- idle4 ... crossed legs
-- idle5 ... hugging legs
-- idle6 ... sitting

-- TODO if sitting: fixed facing?

---@param data MountData
---@return integer|nil index
local function getFirstFreeSlot(data)
    for index, value in ipairs(data.slots) do
        if value.reference == nil then return index end
    end
    return nil
end

---@param data MountData
---@param reference tes3reference|nil
---@param idx integer
function this.registerInSlot(data, reference, idx)
    data.slots[idx].reference = reference
    -- play animation
    if reference then
        local slot = data.slots[idx]

        tes3.loadAnimation({reference = reference})
        if slot.animationFile then
            tes3.loadAnimation({
                reference = reference,
                file = slot.animationFile
            })
        end
        local group = tes3.animationGroup.idle5
        if slot.animationGroup then
            group = tes3.animationGroup[slot.animationGroup]
        end
        tes3.playAnimation({reference = reference, group = group})

        log:debug("registered " .. reference.id .. " in slot " .. tostring(idx))
    end

end

---@param data MountData
---@param reference tes3reference
function this.registerRef(data, reference)
    -- get first free slot
    local i = getFirstFreeSlot(data)
    if not i then return end

    reference.mobile.movementCollision = false;
    this.registerInSlot(data, reference, i)
end

---@param data MountData
---@param reference tes3reference|nil
---@param idx integer
function this.registerNodeInSlot(data, reference, idx)
    data.slots[idx].reference = reference

    -- play animation
    if reference then
        local slot = data.slots[idx]

        tes3.loadAnimation({reference = reference})
        if slot.animationFile then
            tes3.loadAnimation({
                reference = reference,
                file = slot.animationFile
            })
        end
        local group = tes3.animationGroup.idle5
        if slot.animationGroup then
            group = tes3.animationGroup[slot.animationGroup]
        end
        tes3.playAnimation({reference = reference, group = group})

        log:debug("registered " .. reference.id .. " in slot " .. tostring(idx))
    end
end

---@param data MountData
---@param reference tes3reference
function this.registerNode(data, reference)
    -- get first free slot
    local i = getFirstFreeSlot(data)
    if not i then return end

    reference.mobile.movementCollision = false;
    this.registerNodeInSlot(data, reference, i)
end

return this
