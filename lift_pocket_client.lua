-- CC:Tweaked lift client for a pocket computer.
-- Управление: цифры 1-9 - этаж, H - открыть люк, R - обновить, Q - выход.
local CONFIG = {
    modemSide = nil, -- nil: найти первый доступный модем, включая встроенный pocket-модем
    channel = 4817,
    protocol = "lift_control_v1",
    refreshSeconds = 2,
}

local function findModem()
    if CONFIG.modemSide then
        return peripheral.wrap(CONFIG.modemSide)
    end
    return peripheral.find("modem")
end

local modem = findModem()
if not modem or not modem.transmit then
    error("Lift pocket client: wireless modem unavailable", 0)
end

modem.open(CONFIG.channel)

local state
local message = "Waiting for lift..."
local messageColor = colors.lightGray

local function terminalSize()
    return term.getSize()
end

local function truncate(value, width)
    value = tostring(value or "")
    if #value > width then return value:sub(1, math.max(0, width)) end
    return value
end

local function writeLine(y, text, foreground, background)
    local width = terminalSize()
    term.setCursorPos(1, y)
    term.setBackgroundColor(background or colors.black)
    term.setTextColor(foreground or colors.white)
    term.write(truncate(text, width) .. string.rep(" ", math.max(0, width - #truncate(text, width))))
end

local function draw()
    local width, height = terminalSize()
    term.clear()

    writeLine(1, " LIFT CONTROL", colors.white, colors.gray)
    if not state then
        writeLine(3, message, messageColor, colors.black)
        writeLine(height, "R refresh   Q quit", colors.lightGray, colors.black)
        return
    end

    local status = state.overstressed and "OVERSTRESSED" or "READY"
    local statusColor = state.overstressed and colors.red or colors.lime
    local info = "Floor: " .. tostring(state.currentName or state.current or "?")
    if state.speed ~= nil then info = info .. "  Speed: " .. tostring(state.speed) end

    if state.busyFloor then
        status, statusColor = "MOVING", colors.orange
        info = "Setting floor " .. tostring(state.busyFloor) .. "..."
    elseif state.hatchBusy then
        status, statusColor = "BUSY", colors.orange
        info = "Opening hatch..."
    elseif state.assemblyError then
        status, statusColor = "ERROR", colors.red
        info = "Err: " .. tostring(state.assemblyError)
    end

    writeLine(2, info, colors.lightGray, colors.black)
    writeLine(3, "Status: " .. status, statusColor, colors.black)

    local available = math.max(1, height - 6)
    for index, floor in ipairs(state.floors or {}) do
        if index > available then break end
        local marker = (state.busyFloor == index and "> ") or "  "
        local current = state.currentName == floor.name and " *" or ""
        local line = marker .. index .. ". " .. tostring(floor.name) .. " (Y:" .. tostring(floor.y) .. ")" .. current
        local color = state.busyFloor == index and colors.orange or
            (current ~= "" and colors.cyan or colors.white)
        writeLine(4 + index, line, color, colors.black)
    end

    local controls = "1-9 floor   H hatch   R refresh   Q quit"
    writeLine(height, controls, colors.lightGray, colors.black)
    term.setBackgroundColor(colors.black)
end

local function send(action, index)
    local request = textutils.serialize({
        protocol = CONFIG.protocol,
        action = action,
        index = index,
    })
    modem.transmit(CONFIG.channel, CONFIG.channel, request)
end

local function requestState()
    send("state")
end

local function setMessage(text, color)
    message = text
    messageColor = color or colors.lightGray
end

local function numberForKey(key)
    local keyNames = {
        [1] = {keys.one, keys.numPad1}, [2] = {keys.two, keys.numPad2},
        [3] = {keys.three, keys.numPad3}, [4] = {keys.four, keys.numPad4},
        [5] = {keys.five, keys.numPad5}, [6] = {keys.six, keys.numPad6},
        [7] = {keys.seven, keys.numPad7}, [8] = {keys.eight, keys.numPad8},
        [9] = {keys.nine, keys.numPad9},
    }
    for number, names in pairs(keyNames) do
        if key == names[1] or key == names[2] then return number end
    end
end

local function run()
    term.setCursorBlink(false)
    requestState()
    draw()
    local timer = os.startTimer(CONFIG.refreshSeconds)

    while true do
        local event, a, b, _, raw = os.pullEvent()
        if event == "key" then
            if a == keys.q then
                return
            elseif a == keys.r then
                setMessage("Requesting state...", colors.yellow)
                requestState()
                draw()
            elseif a == keys.h then
                if state and not state.busyFloor and not state.hatchBusy then
                    send("hatch")
                    setMessage("Opening hatch...", colors.orange)
                end
                draw()
            else
                local index = numberForKey(a)
                if index and state and state.floors[index] and
                    not state.busyFloor and not state.hatchBusy then
                    send("floor", index)
                    setMessage("Moving to " .. tostring(state.floors[index].name) .. "...", colors.orange)
                    draw()
                end
            end
        elseif event == "modem_message" and b == CONFIG.channel and type(raw) == "string" then
            local ok, incoming = pcall(textutils.unserialize, raw)
            if ok and type(incoming) == "table" and incoming.type == "state" then
                state = incoming
                setMessage("")
                draw()
            end
        elseif event == "timer" and a == timer then
            requestState()
            timer = os.startTimer(CONFIG.refreshSeconds)
        end
    end
end

local ok, err = pcall(run)
term.setBackgroundColor(colors.black)
term.setTextColor(colors.white)
term.clear()
term.setCursorPos(1, 1)
if not ok then
    term.write("Critical error:")
    term.setCursorPos(1, 2)
    term.write(truncate(err, terminalSize()))
    print(err)
end
