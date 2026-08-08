-- CC:Tweaked panel for a gold farm.
local CONFIG = {
    monitorSide = "monitor_2",
    goldVaultSide = "left",
    cobblestoneVaultSide = "create:item_vault_0",
    goldId = "minecraft:gold_ingot",
    cobblestoneId = "minecraft:cobblestone",
    generatorSide = "right",
    pulseSeconds = 0.2,
    refreshSeconds = 1,
    textScale = 1,
}

local function report(message)
    print("Gold panel: " .. tostring(message))
end

local monitor = peripheral.wrap(CONFIG.monitorSide)
local goldVault = peripheral.wrap(CONFIG.goldVaultSide)
local cobblestoneVault = peripheral.wrap(CONFIG.cobblestoneVaultSide)

if not monitor then
    report("monitor is unavailable on '" .. CONFIG.monitorSide .. "'")
    error("Gold panel: monitor is unavailable", 0)
end
if not goldVault then
    report("gold vault is unavailable on '" .. CONFIG.goldVaultSide .. "'")
end
if not cobblestoneVault then
    report("cobblestone vault is unavailable on '" .. CONFIG.cobblestoneVaultSide .. "'")
end
if not redstone or type(redstone.setOutput) ~= "function" then
    report("redstone API is unavailable")
    error("Gold panel: redstone API is unavailable", 0)
end

local palette = {
    background = colors.black,
    header = colors.gray,
    text = colors.white,
    muted = colors.lightGray,
    good = colors.lime,
    error = colors.red,
    button = colors.blue,
    buttonActive = colors.green,
    buttonText = colors.white,
}

local state = {
    count = nil,
    cobblestoneCount = nil,
    speed = nil,
    storageStatus = "WAITING",
    storageError = nil,
    cobblestoneStatus = "WAITING",
    cobblestoneError = nil,
    generatorOn = false,
    pulsing = false,
}

local button = { x = 1, y = 1, width = 1, height = 1 }

local function clipped(value, width)
    value = tostring(value or "")
    if width <= 0 then return "" end
    return value:sub(1, width)
end

local function centered(value, width)
    value = clipped(value, width)
    local padding = width - #value
    return string.rep(" ", math.floor(padding / 2)) .. value ..
        string.rep(" ", math.ceil(padding / 2))
end

local function setColors(background, foreground)
    monitor.setBackgroundColor(background)
    monitor.setTextColor(foreground)
end

local function fill(x, y, width, height, background)
    if width <= 0 or height <= 0 then return end
    setColors(background, palette.text)
    for row = 0, height - 1 do
        monitor.setCursorPos(x, y + row)
        monitor.write(string.rep(" ", width))
    end
end

local function writeLine(y, value, foreground, background)
    local width, height = monitor.getSize()
    if y < 1 or y > height then return end
    fill(1, y, width, 1, background)
    setColors(background, foreground)
    monitor.setCursorPos(1, y)
    monitor.write(clipped(value, width))
end

local function draw()
    local width, height = monitor.getSize()
    monitor.clear()
    writeLine(1, " GOLD FARM PANEL", palette.text, palette.header)

    local count = state.count == nil and "--" or tostring(state.count)
    local cobblestoneCount = state.cobblestoneCount == nil and "--" or tostring(state.cobblestoneCount)
    local speed = state.speed == nil and "--" or string.format("%.2f", state.speed)
    writeLine(2, "Gold: " .. count, palette.good, palette.background)
    writeLine(3, "Rate: " .. speed .. "/s", palette.muted, palette.background)

    writeLine(4, "Cobble: " .. cobblestoneCount, palette.muted, palette.background)
    local storage = state.storageError and "ERR: " .. state.storageError or state.storageStatus
    local cobblestoneStorage = state.cobblestoneError and "ERR: " .. state.cobblestoneError or state.cobblestoneStatus
    writeLine(5, "Gold vault: " .. storage, state.storageError and palette.error or palette.muted, palette.background)
    writeLine(6, "Cobble vault: " .. cobblestoneStorage,
        state.cobblestoneError and palette.error or palette.muted, palette.background)

    button.width = width
    button.height = math.max(1, math.min(5, height - 6))
    button.y = math.max(1, height - button.height + 1)
    local label = state.pulsing and "PULSE..." or (state.generatorOn and "VKL" or "VYKL")
    local hint = state.pulsing and "0.2s HIGH" or "TOGGLE (0.2s PULSE)"
    fill(button.x, button.y, button.width, button.height,
        state.generatorOn and palette.buttonActive or palette.button)
    setColors(state.generatorOn and palette.buttonActive or palette.button, palette.buttonText)
    monitor.setCursorPos(button.x, button.y + math.floor((button.height - 1) / 2))
    monitor.write(centered(label, width))
    if button.height >= 3 then
        setColors(state.generatorOn and palette.buttonActive or palette.button, palette.muted)
        monitor.setCursorPos(button.x, button.y + math.floor((button.height - 1) / 2) + 1)
        monitor.write(centered(hint, width))
    end
end

local previousCount
local previousTime

local function readVault()
    if not goldVault or type(goldVault.list) ~= "function" then
        goldVault = peripheral.wrap(CONFIG.goldVaultSide)
    end
    if not goldVault or type(goldVault.list) ~= "function" then
        state.storageError = "unavailable"
        state.storageStatus = "ERROR"
    end

    if not cobblestoneVault or type(cobblestoneVault.list) ~= "function" then
        cobblestoneVault = peripheral.wrap(CONFIG.cobblestoneVaultSide)
    end
    if not cobblestoneVault or type(cobblestoneVault.list) ~= "function" then
        state.cobblestoneError = "unavailable"
        state.cobblestoneStatus = "ERROR"
    end

    local goldContents
    local goldOk = false
    if goldVault and type(goldVault.list) == "function" then
        goldOk, goldContents = pcall(goldVault.list)
    end
    if not goldOk or type(goldContents) ~= "table" then
        state.storageError = "read failed"
        state.storageStatus = "ERROR"
    end

    local cobblestoneContents
    local cobblestoneOk = false
    if cobblestoneVault and type(cobblestoneVault.list) == "function" then
        cobblestoneOk, cobblestoneContents = pcall(cobblestoneVault.list)
    end
    if not cobblestoneOk or type(cobblestoneContents) ~= "table" then
        state.cobblestoneError = "read failed"
        state.cobblestoneStatus = "ERROR"
    end

    local total = 0
    local cobblestoneTotal = 0
    if goldOk and type(goldContents) == "table" then
        for _, item in pairs(goldContents) do
            if type(item) == "table" and item.name == CONFIG.goldId then
                total = total + (tonumber(item.count) or 0)
            end
        end
    end
    if cobblestoneOk and type(cobblestoneContents) == "table" then
        for _, item in pairs(cobblestoneContents) do
            if type(item) == "table" and item.name == CONFIG.cobblestoneId then
                cobblestoneTotal = cobblestoneTotal + (tonumber(item.count) or 0)
            end
        end
    end

    if goldOk and type(goldContents) == "table" then
        local now = os.clock()
        if previousCount ~= nil and previousTime and now > previousTime then
            state.speed = (total - previousCount) / (now - previousTime)
        else
            state.speed = nil
        end
        previousCount, previousTime = total, now
        state.count = total
        state.storageError = nil
        state.storageStatus = "OK"
    end
    if cobblestoneOk and type(cobblestoneContents) == "table" then
        state.cobblestoneCount = cobblestoneTotal
        state.cobblestoneError = nil
        state.cobblestoneStatus = "OK"
    end
end

local function pulse()
    state.pulsing = true
    state.generatorOn = not state.generatorOn
    draw()
    local ok, err = pcall(function()
        redstone.setOutput(CONFIG.generatorSide, true)
        sleep(CONFIG.pulseSeconds)
    end)
    pcall(redstone.setOutput, CONFIG.generatorSide, false)
    state.pulsing = false
    if not ok then report("generator pulse failed: " .. tostring(err)) end
    draw()
end

local function inside(x, y)
    return x >= button.x and x < button.x + button.width and
        y >= button.y and y < button.y + button.height
end

local function run()
    monitor.setTextScale(CONFIG.textScale)
    readVault()
    draw()
    local timer = os.startTimer(CONFIG.refreshSeconds)
    while true do
        local event, side, x, y = os.pullEvent()
        if event == "monitor_touch" and side == CONFIG.monitorSide and inside(x, y) then
            if not state.pulsing then pulse() end
        elseif event == "timer" and side == timer then
            readVault()
            draw()
            timer = os.startTimer(CONFIG.refreshSeconds)
        elseif event == "term_resize" then
            draw()
        end
    end
end

-- Keep the generator input LOW even when the program is stopped by an error.
local ok, err = pcall(run)
pcall(redstone.setOutput, CONFIG.generatorSide, false)
if not ok then
    report(err)
    pcall(monitor.clear)
    pcall(monitor.setCursorPos, 1, 1)
    pcall(monitor.setTextColor, palette.error)
    pcall(monitor.write, clipped("Critical error: " .. tostring(err), monitor.getSize()))
end
