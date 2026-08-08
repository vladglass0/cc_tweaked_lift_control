-- CC:Tweaked resource snapshot sender.
local CONFIG = {
    modemSide = "top",
    channel = 4820,
    protocol = "resource_monitor_v1",
    sourceName = "Resource source",
    refreshSeconds = 5,
}

local function report(message)
    print("Resource sender: " .. tostring(message))
end

local modem = peripheral.wrap(CONFIG.modemSide)
if not modem or type(modem.transmit) ~= "function" then
    report("wireless modem is unavailable on '" .. CONFIG.modemSide .. "'")
    error("Resource sender: wireless modem is unavailable", 0)
end
modem.open(CONFIG.channel)

local function addCount(target, key, amount)
    if type(key) ~= "string" or #key == 0 or #key > 256 then return false end
    amount = tonumber(amount)
    if not amount or amount < 0 or amount ~= amount or amount == math.huge then return false end
    target[key] = (target[key] or 0) + amount
    return true
end

local function readItems(device, items)
    if type(device.list) ~= "function" then return false end
    local ok, contents = pcall(device.list)
    if not ok or type(contents) ~= "table" then return false end
    for _, item in pairs(contents) do
        if type(item) == "table" then addCount(items, item.name, item.count) end
    end
    return true
end

local function tankEntries(device)
    local methods = { "tanks", "getTanks" }
    for _, method in ipairs(methods) do
        if type(device[method]) == "function" then
            local ok, result = pcall(device[method])
            if ok and type(result) == "table" then return result, true end
        end
    end
    return nil, false
end

local function readFluids(device, fluids)
    local tanks, supported = tankEntries(device)
    if not supported then return false end
    for _, tank in pairs(tanks) do
        if type(tank) == "table" then
            local detail = tank.name or tank.id or tank.fluidName or
                (type(tank.fluid) == "table" and (tank.fluid.name or tank.fluid.id))
            local amount = tank.amount or tank.contents or tank.volume
            if type(amount) == "table" then
                detail = detail or amount.name or amount.id
                amount = amount.amount or amount.volume
            end
            if detail then addCount(fluids, detail, amount) end
        end
    end
    return true
end

local function collect()
    local items, fluids = {}, {}
    local inventoryCount, tankCount, unsupportedTanks = 0, 0, 0
    local seen = {}
    local namesOk, names = pcall(peripheral.getNames)
    if not namesOk or type(names) ~= "table" then
        return items, fluids, inventoryCount, tankCount, 0
    end
    for _, name in ipairs(names) do
        if name ~= CONFIG.modemSide then
            local ok, device = pcall(peripheral.wrap, name)
            if ok and device and not seen[device] then
                seen[device] = true
                if readItems(device, items) then inventoryCount = inventoryCount + 1 end
                local supported = readFluids(device, fluids)
                if supported then tankCount = tankCount + 1
                elseif type(device.tanks) == "function" or type(device.getTanks) == "function" then
                    unsupportedTanks = unsupportedTanks + 1
                end
            end
        end
    end
    return items, fluids, inventoryCount, tankCount, unsupportedTanks
end

local function sendSnapshot()
    local items, fluids, inventories, tanks, unsupported = collect()
    local snapshot = {
        protocol = CONFIG.protocol,
        type = "snapshot",
        source = CONFIG.sourceName,
        computerId = os.getComputerID(),
        sentAt = os.clock(),
        items = items,
        fluids = fluids,
    }
    local ok, message = pcall(textutils.serialize, snapshot)
    if not ok then return nil, "serialization failed: " .. tostring(message), inventories, tanks, unsupported end
    local sent, err = pcall(modem.transmit, CONFIG.channel, CONFIG.channel, message)
    if not sent then return nil, "transmit failed: " .. tostring(err), inventories, tanks, unsupported end
    return true, nil, inventories, tanks, unsupported
end

local lastSent = "never"
local lastError = nil
local function drawStatus(inventories, tanks, unsupported)
    term.clear()
    term.setCursorPos(1, 1)
    print("Resource sender: " .. CONFIG.sourceName)
    print("Channel: " .. CONFIG.channel)
    print("Inventories: " .. tostring(inventories or 0) .. "  Tanks: " .. tostring(tanks or 0))
    if unsupported and unsupported > 0 then print("Unsupported tanks: " .. unsupported) end
    print("Last sent: " .. tostring(lastSent))
    if lastError then print("Error: " .. tostring(lastError)) end
end

print("Resource sender started on channel " .. CONFIG.channel)
local timer = os.startTimer(0)
while true do
    local event, id = os.pullEvent()
    if event == "timer" and id == timer then
        local ok, err, inventories, tanks, unsupported = sendSnapshot()
        lastError = err
        if ok then lastSent = os.date("%H:%M:%S") end
        drawStatus(inventories, tanks, unsupported)
        timer = os.startTimer(CONFIG.refreshSeconds)
    elseif event == "term_resize" then
        drawStatus()
    end
end
