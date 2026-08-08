-- CC:Tweaked resource monitor display.
local CONFIG = {
    modemSide = "top",
    monitorSide = "monitor_2",
    channel = 4820,
    protocol = "resource_monitor_v1",
    refreshSeconds = 1,
    autoPageSeconds = 10,
    staleSeconds = 20,
    textScale = 1,
}

local function report(message) print("Resource display: " .. tostring(message)) end
local modem = peripheral.wrap(CONFIG.modemSide)
local monitor = peripheral.wrap(CONFIG.monitorSide)
if not modem or type(modem.open) ~= "function" then
    report("wireless modem is unavailable on '" .. CONFIG.modemSide .. "'")
    error("Resource display: wireless modem is unavailable", 0)
end
if not monitor or type(monitor.getSize) ~= "function" then
    report("monitor is unavailable on '" .. CONFIG.monitorSide .. "'")
    error("Resource display: monitor is unavailable", 0)
end
modem.open(CONFIG.channel)

local colorset = {
    background = colors.black, header = colors.gray, text = colors.white,
    muted = colors.lightGray, item = colors.lime, fluid = colors.cyan,
    stale = colors.orange, error = colors.red, button = colors.blue,
}
local sources, mode, page = {}, "total", 1

local function clipped(value, width)
    value = tostring(value or "")
    return width > 0 and value:sub(1, width) or ""
end

local function validMap(value)
    if type(value) ~= "table" then return false end
    for key, amount in pairs(value) do
        if type(key) ~= "string" or #key == 0 or #key > 256 then return false end
        amount = tonumber(amount)
        if not amount or amount < 0 or amount ~= amount or amount == math.huge then return false end
    end
    return true
end

local function compact(value)
    value = tonumber(value) or 0
    local absolute = math.abs(value)
    if absolute >= 1000000000 then return string.format("%.1fG", value / 1000000000) end
    if absolute >= 1000000 then return string.format("%.1fM", value / 1000000) end
    if absolute >= 1000 then return string.format("%.1fk", value / 1000) end
    return tostring(math.floor(value))
end

local function sortedEntries(items)
    local result = {}
    for id, amount in pairs(items) do result[#result + 1] = { id = id, amount = amount } end
    table.sort(result, function(a, b)
        if a.amount ~= b.amount then return a.amount > b.amount end
        return a.id < b.id
    end)
    return result
end

local function sourceLabel(source, id)
    local duplicate = false
    for otherId, other in pairs(sources) do
        if otherId ~= id and other.name == source.name then duplicate = true break end
    end
    return duplicate and (source.name .. " #" .. tostring(id)) or source.name
end

local function accept(raw)
    if type(raw) ~= "string" then return end
    local ok, message = pcall(textutils.unserialize, raw)
    if not ok or type(message) ~= "table" or message.protocol ~= CONFIG.protocol or
        message.type ~= "snapshot" then return end
    local id = tonumber(message.computerId)
    local name = message.source
    if not id or type(name) ~= "string" or #name == 0 or #name > 128 or
        not validMap(message.items) or not validMap(message.fluids) then return end
    sources[id] = {
        name = name, items = message.items, fluids = message.fluids,
        received = os.clock(), sentAt = message.sentAt,
    }
end

local function fresh(source)
    return os.clock() - source.received <= CONFIG.staleSeconds
end

local function totals()
    local items, fluids, active = {}, {}, 0
    for _, source in pairs(sources) do
        if fresh(source) then
            active = active + 1
            for id, amount in pairs(source.items) do items[id] = (items[id] or 0) + amount end
            for id, amount in pairs(source.fluids) do fluids[id] = (fluids[id] or 0) + amount end
        end
    end
    return items, fluids, active
end

local function sourceRows()
    local rows = {}
    for id, source in pairs(sources) do
        rows[#rows + 1] = { id = id, source = source, stale = not fresh(source) }
    end
    table.sort(rows, function(a, b) return sourceLabel(a.source, a.id) < sourceLabel(b.source, b.id) end)
    return rows
end

local function fill(y, background)
    local width = monitor.getSize()
    monitor.setBackgroundColor(background)
    monitor.setTextColor(colorset.text)
    monitor.setCursorPos(1, y)
    monitor.write(string.rep(" ", width))
end

local function line(y, text, foreground, background)
    local width, height = monitor.getSize()
    if y < 1 or y > height then return end
    fill(y, background or colorset.background)
    monitor.setTextColor(foreground or colorset.text)
    monitor.setCursorPos(1, y)
    monitor.write(clipped(text, width))
end

local function draw()
    local width, height = monitor.getSize()
    monitor.clear()
    local _, _, active = totals()
    local title = mode == "total" and "RESOURCE TOTAL" or "RESOURCE SOURCES"
    line(1, title .. "  " .. page .. "  ACTIVE: " .. active, colorset.text, colorset.header)
    local rows = {}
    if mode == "total" then
        local items, fluids = totals()
        for _, entry in ipairs(sortedEntries(items)) do rows[#rows + 1] = { text = "I " .. entry.id .. "  " .. compact(entry.amount), color = colorset.item } end
        for _, entry in ipairs(sortedEntries(fluids)) do rows[#rows + 1] = { text = "F " .. entry.id .. "  " .. compact(entry.amount), color = colorset.fluid } end
    else
        for _, entry in ipairs(sourceRows()) do
            local source = entry.source
            local itemCount, fluidCount = 0, 0
            for _ in pairs(source.items) do itemCount = itemCount + 1 end
            for _ in pairs(source.fluids) do fluidCount = fluidCount + 1 end
            rows[#rows + 1] = { text = (entry.stale and "STALE " or "OK    ") .. sourceLabel(source, entry.id) ..
                " I:" .. itemCount .. " F:" .. fluidCount, color = entry.stale and colorset.stale or colorset.item }
            for _, value in ipairs(sortedEntries(source.items)) do rows[#rows + 1] = { text = "  I " .. value.id .. "  " .. compact(value.amount), color = colorset.item } end
            for _, value in ipairs(sortedEntries(source.fluids)) do rows[#rows + 1] = { text = "  F " .. value.id .. "  " .. compact(value.amount), color = colorset.fluid } end
        end
        if #rows == 0 then
            rows[1] = { text = "No senders yet. Check modem and channel " .. CONFIG.channel, color = colorset.muted }
        end
    end
    if mode == "total" and #rows == 0 then
        rows[1] = { text = "Waiting for snapshots on channel " .. CONFIG.channel, color = colorset.muted }
    end
    local contentHeight = math.max(1, height - 3)
    local pages = math.max(1, math.ceil(#rows / contentHeight))
    if page > pages then page = pages end
    local first = (page - 1) * contentHeight + 1
    for offset = 0, contentHeight - 1 do
        local row = rows[first + offset]
        if row then line(2 + offset, row.text, row.color) else line(2 + offset, "", colorset.muted) end
    end
    local third = math.floor(width / 3)
    local labels = { width < 12 and "<" or "PREV", mode == "total" and (width < 12 and "SRC" or "SOURCES") or (width < 12 and "TOT" or "TOTAL"), width < 12 and ">" or "NEXT" }
    for index = 1, 3 do
        local x = (index - 1) * third + 1
        local w = index == 3 and width - x + 1 or third
        monitor.setBackgroundColor(colorset.button)
        monitor.setTextColor(colorset.text)
        monitor.setCursorPos(x, height)
        monitor.write(clipped(labels[index] .. string.rep(" ", math.max(0, w - #labels[index])), w))
    end
end

local function touch(x, y)
    local width, height = monitor.getSize()
    if y ~= height then return end
    local third = math.floor(width / 3)
    if x <= third then page = math.max(1, page - 1)
    elseif x > third * 2 then page = page + 1
    else mode = mode == "total" and "sources" or "total"; page = 1 end
    draw()
end

monitor.setTextScale(CONFIG.textScale)
draw()
local refreshTimer = os.startTimer(CONFIG.refreshSeconds)
local autoTimer = os.startTimer(CONFIG.autoPageSeconds)
while true do
    local event, side, channel, replyChannel, message = os.pullEvent()
    if event == "modem_message" and channel == CONFIG.channel then
        accept(message)
        draw()
    elseif event == "monitor_touch" and side == CONFIG.monitorSide then
        touch(channel, replyChannel)
    elseif event == "timer" and side == refreshTimer then
        draw()
        refreshTimer = os.startTimer(CONFIG.refreshSeconds)
    elseif event == "timer" and side == autoTimer then
        page = page + 1
        draw()
        autoTimer = os.startTimer(CONFIG.autoPageSeconds)
    elseif event == "term_resize" then
        draw()
    end
end
