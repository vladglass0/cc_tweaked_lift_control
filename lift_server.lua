-- CC:Tweaked lift server.
-- Установите этот файл на компьютере рядом с лебедкой.
local CONFIG = {
    modemSide = "back",
    liftSide = "bottom",
    redstoneSide = "back",
    channel = 4817,
    protocol = "lift_control_v1",
    callPulseSeconds = 0.2,
    hatchPulseSeconds = 0.2,
    refreshSeconds = 5,
    hatchFloorY = 58,
    floorNamesByY = {
        [28] = "Niz",
        [40] = "Mid",
        [58] = "Verx",
    },
}

local function fail(message)
    error("Lift server: " .. message, 0)
end

local modem = peripheral.wrap(CONFIG.modemSide)
if not modem or not modem.transmit then fail("wireless modem is unavailable on '" .. CONFIG.modemSide .. "'") end
local lift = peripheral.wrap(CONFIG.liftSide)
if not lift then fail("lift is unavailable on '" .. CONFIG.liftSide .. "'") end
if not redstone then fail("redstone API is unavailable") end
modem.open(CONFIG.channel)

local function safeCall(object, method)
    local callback = object[method]
    if type(callback) ~= "function" then return nil end
    local ok, value = pcall(callback)
    return ok and value or nil
end

local function loadFloors()
    local source = safeCall(lift, "getFloors")
    if type(source) ~= "table" then return {} end
    local result = {}
    for key, value in pairs(source) do
        local target, y, name = value, value, value
        if type(value) == "table" then
            target = value.floor or value.id or value.y or key
            y = value.y or value.height or value.targetY or target
            name = value.name or value.label or target
        elseif type(key) == "number" and type(value) == "string" then
            target, y = key, key
        end
        local custom = CONFIG.floorNamesByY[y] or CONFIG.floorNamesByY[tostring(y)]
        result[#result + 1] = { target = target, y = y, name = tostring(custom or name) }
    end
    table.sort(result, function(a, b)
        local ay, by = tonumber(a.y), tonumber(b.y)
        if ay and by then return ay > by end
        return tostring(a.name) < tostring(b.name)
    end)
    return result
end

local function setRedstone(value)
    pcall(redstone.setOutput, CONFIG.redstoneSide, value)
end

local function pulse(seconds)
    setRedstone(true)
    sleep(seconds)
    setRedstone(false)
end

local function isAt(value, expected)
    if type(value) == "table" then
        value = value.y or value.height or value.targetY or value.floor or value.id or value.name
    end
    return value ~= nil and tostring(value) == tostring(expected)
end

local function findCurrentFloor(current, floors)
    if current == nil then return nil end
    for index, floor in ipairs(floors) do
        if isAt(floor.target, current) or isAt(floor.y, current) or
            isAt(floor.name, current) or isAt(index, current) then
            return floor
        end
    end
end

local function snapshot(floors, busy, hatchBusy, lastError)
    local current = safeCall(lift, "getCurrentFloor")
    local entry = findCurrentFloor(current, floors)
    return {
        type = "state",
        floors = floors,
        current = current,
        currentName = entry and entry.name or nil,
        speed = safeCall(lift, "getSpeed"),
        overstressed = safeCall(lift, "isOverstressed") or false,
        assemblyError = safeCall(lift, "getLastAssemblyError"),
        busyFloor = busy,
        hatchBusy = hatchBusy or false,
        lastError = lastError,
    }
end

local floors = loadFloors()
if #floors == 0 then fail("getFloors() returned no floors") end
local busyFloor, hatchBusy, lastError = nil, false, nil

local function sendState(replyChannel)
    local message = textutils.serialize(snapshot(floors, busyFloor, hatchBusy, lastError))
    if replyChannel then modem.transmit(replyChannel, CONFIG.channel, message) end
    modem.transmit(CONFIG.channel, CONFIG.channel, message)
end

local function performFloor(index)
    if busyFloor or hatchBusy or not floors[index] then return end
    busyFloor, lastError = index, nil
    sendState()
    local current = safeCall(lift, "getCurrentFloor")
    local callAtHatch = isAt(floors[index].y, CONFIG.hatchFloorY)
    local departureAtHatch = isAt(current, CONFIG.hatchFloorY)
    if callAtHatch or departureAtHatch then pulse(CONFIG.callPulseSeconds) end
    local ok, err = pcall(lift.setTargetFloor, floors[index].target)
    if not ok then lastError = tostring(err) end
    busyFloor = nil
    sendState()
end

local function performHatch()
    if busyFloor or hatchBusy then return end
    hatchBusy, lastError = true, nil
    sendState()
    pulse(CONFIG.hatchPulseSeconds)
    hatchBusy = false
    sendState()
end

local timer = os.startTimer(CONFIG.refreshSeconds)
print("Lift server started on channel " .. CONFIG.channel)
sendState()
while true do
    local event, side, channel, replyChannel, raw = os.pullEvent()
    if event == "modem_message" and channel == CONFIG.channel then
        local message = raw
        if type(message) == "string" then
            local ok, request = pcall(textutils.unserialize, message)
            if ok and type(request) == "table" and request.protocol == CONFIG.protocol then
                if request.action == "state" then
                    floors = loadFloors()
                    sendState(replyChannel)
                elseif request.action == "floor" then
                    performFloor(tonumber(request.index))
                elseif request.action == "hatch" then
                    performHatch()
                end
            end
        end
    elseif event == "timer" and side == timer then
        floors = loadFloors()
        sendState()
        timer = os.startTimer(CONFIG.refreshSeconds)
    end
end
