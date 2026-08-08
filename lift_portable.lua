-- CC:Tweaked lift portable computer client.
-- Установите этот файл на портативный компьютер с беспроводным модемом.
-- Управление: стрелки вверх/вниз — выбор этажа, Enter — ехать,
-- H — открыть люк, R — обновить состояние, Q — выход.
local CONFIG = {
    modemSide = "back",
    channel = 4817,
    protocol = "lift_control_v1",
    refreshSeconds = 2,
}

local modem
local state
local selected = 1
local timer
local running = true

local function text(value, fallback)
    if value == nil then return fallback or "-" end
    return tostring(value)
end

local function clear()
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.clear()
    term.setCursorPos(1, 1)
end

local function line(value, color)
    term.setTextColor(color or colors.white)
    term.write(tostring(value or ""))
    term.clearLine()
end

local function send(action, index)
    local request = { protocol = CONFIG.protocol, action = action }
    if index ~= nil then request.index = index end
    modem.transmit(CONFIG.channel, CONFIG.channel, textutils.serialize(request))
end

local function requestState()
    send("state")
end

local function draw()
    clear()
    line("LIFT CONTROL", colors.cyan)
    term.setCursorPos(1, 2)
    line("Канал: " .. CONFIG.channel, colors.lightGray)
    term.setCursorPos(1, 3)

    if not state then
        line("Ожидание состояния лифта...", colors.yellow)
        term.setCursorPos(1, 5)
        line("R — обновить   Q — выход", colors.lightGray)
        return
    end

    local status = "Готов"
    local statusColor = colors.lime
    if state.overstressed then
        status, statusColor = "Перегрузка", colors.red
    elseif state.hatchBusy then
        status, statusColor = "Люк открывается...", colors.orange
    elseif state.busyFloor then
        status, statusColor = "Лифт движется к этажу " .. text(state.busyFloor), colors.orange
    end

    line("Статус: " .. status, statusColor)
    term.setCursorPos(1, 5)
    line("Текущий этаж: " .. text(state.currentName or state.current), colors.white)
    term.setCursorPos(1, 6)
    line("Скорость: " .. text(state.speed), colors.lightGray)

    if state.assemblyError then
        term.setCursorPos(1, 7)
        line("Ошибка сборки: " .. text(state.assemblyError), colors.red)
    elseif state.lastError then
        term.setCursorPos(1, 7)
        line("Ошибка: " .. text(state.lastError), colors.red)
    end

    term.setCursorPos(1, 9)
    line("Этажи:", colors.cyan)
    for index, floor in ipairs(state.floors or {}) do
        term.setCursorPos(1, 9 + index)
        local marker = index == selected and "> " or "  "
        local current = state.currentName == floor.name or tostring(state.current) == tostring(floor.target)
        local suffix = current and " [текущий]" or ""
        local value = marker .. index .. ". " .. text(floor.name) .. " (Y:" .. text(floor.y) .. ")" .. suffix
        line(value, index == selected and colors.yellow or current and colors.lime or colors.white)
    end

    local helpRow = 11 + #(state.floors or {})
    term.setCursorPos(1, helpRow)
    line("Enter — ехать   H — люк", colors.white)
    term.setCursorPos(1, helpRow + 1)
    line("R — обновить   Q — выход", colors.lightGray)
end

local function validSelection()
    return state and state.floors and state.floors[selected] ~= nil
end

local function handleKey(key)
    if key == keys.q then
        running = false
    elseif key == keys.up and state and #state.floors > 0 then
        selected = selected > 1 and selected - 1 or #state.floors
        draw()
    elseif key == keys.down and state and #state.floors > 0 then
        selected = selected < #state.floors and selected + 1 or 1
        draw()
    elseif key == keys.enter and validSelection() and not state.busyFloor and not state.hatchBusy then
        send("floor", selected)
    elseif key == keys.h and state and not state.busyFloor and not state.hatchBusy then
        send("hatch")
    elseif key == keys.r then
        requestState()
    end
end

local ok, err = pcall(function()
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.clear()
    term.setCursorPos(1, 1)
    print("Lift client starting...")

    modem = peripheral.find("modem")
    if not modem or not modem.transmit or not modem.open then
        error("Wireless modem not found. Attach a wireless modem to the computer.", 0)
    end
    modem.open(CONFIG.channel)
    draw()
    requestState()
    timer = os.startTimer(CONFIG.refreshSeconds)
    while running do
        local event, a, b, c, d = os.pullEvent()
        if event == "key" then
            handleKey(a)
        elseif event == "modem_message" and b == CONFIG.channel and type(d) == "string" then
            local parsed, message = pcall(textutils.unserialize, d)
            if parsed and type(message) == "table" and message.type == "state" then
                state = message
                if selected > #(state.floors or {}) then selected = math.max(1, #(state.floors or {})) end
                draw()
            end
        elseif event == "timer" and a == timer then
            requestState()
            timer = os.startTimer(CONFIG.refreshSeconds)
        end
    end
end)

if not ok then
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.red)
    term.clear()
    term.setCursorPos(1, 1)
    print("LIFT CLIENT ERROR")
    term.setCursorPos(1, 3)
    print(tostring(err))
    term.setCursorPos(1, 5)
    print("Press any key to close")
    os.pullEvent("key")
else
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.clear()
    term.setCursorPos(1, 1)
    print("Lift client stopped.")
end
