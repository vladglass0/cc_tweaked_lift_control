-- CC:Tweaked lift monitor client.
-- Установите этот файл на компьютеры с монитором и беспроводным модемом.
local CONFIG = {
    modemSide = "back",
    monitorSide = "monitor_1",
    channel = 4817,
    protocol = "lift_control_v1",
    textScale = 1,
    columns = 2,
    showClock = true,
    highlightCurrentFloor = true,
    colors = {
        background = colors.black, headerBg = colors.gray, headerText = colors.white,
        subText = colors.lightGray, statusReady = colors.lime, statusBad = colors.red,
        statusBusy = colors.orange, buttonIdle = colors.blue, buttonIdleText = colors.white,
        buttonBusy = colors.yellow, buttonBusyText = colors.black, buttonCurrent = colors.cyan,
        buttonCurrentText = colors.black, hatchIdle = colors.orange, hatchIdleText = colors.white,
        hatchBusy = colors.yellow, hatchBusyText = colors.black, errorText = colors.red,
    },
    theme = {
        [colors.black] = {18,18,24}, [colors.gray] = {54,58,69},
        [colors.lightGray] = {142,148,161}, [colors.white] = {236,239,244},
        [colors.blue] = {0,161,194}, [colors.cyan] = {56,189,201},
        [colors.lime] = {88,214,141}, [colors.yellow] = {255,196,61},
        [colors.orange] = {255,140,66}, [colors.red] = {235,77,75},
    },
}

local modem = peripheral.wrap(CONFIG.modemSide)
local monitor = peripheral.wrap(CONFIG.monitorSide)
if not modem or not modem.transmit then error("Lift client: wireless modem unavailable", 0) end
if not monitor then error("Lift client: monitor unavailable", 0) end
modem.open(CONFIG.channel)
local isColor = monitor.isColor and monitor.isColor()
local c = CONFIG.colors
local originalPalette = {}

if isColor and monitor.setPaletteColor then
    for color, rgb in pairs(CONFIG.theme) do
        local ok, r, g, b = pcall(monitor.getPaletteColor, color)
        if ok then originalPalette[color] = {r, g, b} end
        pcall(monitor.setPaletteColor, color, rgb[1]/255, rgb[2]/255, rgb[3]/255)
    end
end

local function setColors(bg, fg)
    if isColor then monitor.setBackgroundColor(bg); monitor.setTextColor(fg) end
end
local function fill(x, y, w, h, bg)
    if not isColor then return end
    monitor.setBackgroundColor(bg)
    for row = 0, h - 1 do monitor.setCursorPos(x, y + row); monitor.write(string.rep(" ", math.max(0, w))) end
end
local function truncate(text, w)
    text = tostring(text or "")
    return #text > w and text:sub(1, math.max(0, w)) or text
end
local function center(text, w)
    text = truncate(text, w)
    local p = w - #text
    return string.rep(" ", math.floor(p/2)) .. text .. string.rep(" ", math.ceil(p/2))
end
local function row(y, w, left, leftColor, right, rightColor, bg)
    fill(1, y, w, 1, bg); setColors(bg, leftColor); monitor.setCursorPos(1,y); monitor.write(truncate(left,w))
    if right and #right > 0 and #right <= w then setColors(bg,rightColor); monitor.setCursorPos(w-#right+1,y); monitor.write(right) end
end
local function button(x,y,w,h,label,sub,bg,fg,subFg)
    if isColor then
        fill(x,y,w,h,bg); setColors(bg,fg)
        if sub and h >= 4 then
            local ly = y + math.floor(h/2)-1; monitor.setCursorPos(x,ly); monitor.write(center(label,w))
            setColors(bg,subFg or fg); monitor.setCursorPos(x,ly+1); monitor.write(center(sub,w))
        else monitor.setCursorPos(x,y+math.floor((h-1)/2)); monitor.write(center(label,w)) end
    else
        local line = "+" .. string.rep("-", math.max(0,w-2)) .. "+"
        monitor.setCursorPos(x,y); monitor.write(line)
        for r=1,h-2 do monitor.setCursorPos(x,y+r); monitor.write("|"..center(r==math.floor(h/2) and label or "",w-2).."|") end
        monitor.setCursorPos(x,y+h-1); monitor.write(line)
    end
end
local function layout(w,h,count)
    local cols = math.max(1,math.min(CONFIG.columns,count)); local rows = math.ceil(count/cols); local top=3; local gap=1; local hatchH=2
    local usable=math.max(rows*3,h-top-hatchH-gap); local ch=math.max(3,math.floor(usable/rows)); local cw=math.max(6,math.floor(w/cols)); local bs={}
    for i=1,count do
        local col=(i-1)%cols; local r=math.floor((i-1)/cols)
        bs[i]={floor=i,x=col*cw+1,y=top+r*ch,width=math.max(4,((col==cols-1 and w-col*cw or cw)-gap)),height=math.max(3,((r==rows-1 and usable-(rows-1)*ch or ch)-gap))}
    end
    return bs,{x=1,y=h-hatchH+1,width=w,height=hatchH}
end
local function inside(b,x,y) return x>=b.x and x<b.x+b.width and y>=b.y and y<b.y+b.height end
local function clock()
    if CONFIG.showClock and textutils and textutils.formatTime then return textutils.formatTime(os.time(),true) end
end
local state
local function draw()
    if not state then return end
    local w,h=monitor.getSize(); monitor.clear(); setColors(c.background,c.headerText)
    row(1,w," LIFT CONTROL",c.headerText,clock(),c.subText,c.headerBg)
    local status=state.overstressed and "OVERSTR." or "READY"; local statusColor=state.overstressed and c.statusBad or c.statusReady
    local info="F:"..tostring(state.currentName or state.current or "?").." Spd:"..tostring(state.speed or "?")
    if state.hatchBusy then info="Opening hatch..."; status=""; statusColor=c.subText
    elseif state.busyFloor then info="Setting floor..." elseif state.assemblyError then info="Err: "..tostring(state.assemblyError); status=""; statusColor=c.errorText end
    row(2,w,info,state.busyFloor and c.statusBusy or c.subText,status,statusColor,c.background)
    local bs,hatch=layout(w,h,#state.floors)
    for i,b in ipairs(bs) do
        local busy=state.busyFloor==i; local current=CONFIG.highlightCurrentFloor and state.currentName==state.floors[i].name and not busy
        local bg,fg=busy and c.buttonBusy or current and c.buttonCurrent or c.buttonIdle, busy and c.buttonBusyText or current and c.buttonCurrentText or c.buttonIdleText
        button(b.x,b.y,b.width,b.height,state.floors[i].name,b.height>=4 and ("Y:"..tostring(state.floors[i].y)) or nil,bg,fg,c.subText)
    end
    button(hatch.x,hatch.y,hatch.width,hatch.height,"OPEN HATCH",nil,state.hatchBusy and c.hatchBusy or c.hatchIdle,state.hatchBusy and c.hatchBusyText or c.hatchIdleText)
end
local function send(action,index)
    modem.transmit(CONFIG.channel,CONFIG.channel,textutils.serialize({protocol=CONFIG.protocol,action=action,index=index}))
end
local function requestState() send("state") end
local ok,err=pcall(function()
    monitor.setTextScale(CONFIG.textScale); requestState(); local timer=os.startTimer(2)
    while true do
        local event,a,b,d,raw=os.pullEvent()
        if event=="monitor_touch" and a==CONFIG.monitorSide and state and not state.busyFloor and not state.hatchBusy then
            local w,h=monitor.getSize(); local bs,hatch=layout(w,h,#state.floors)
            if inside(hatch,b,d) then send("hatch") else for i,v in ipairs(bs) do if inside(v,b,d) then send("floor",i); break end end end
        elseif event=="modem_message" and b==CONFIG.channel and type(raw)=="string" then
            local good,message=pcall(textutils.unserialize,raw); if good and type(message)=="table" and message.type=="state" then state=message; draw() end
        elseif event=="timer" and a==timer then requestState(); timer=os.startTimer(2) end
    end
end)
if isColor and monitor.setPaletteColor then for color,rgb in pairs(originalPalette) do pcall(monitor.setPaletteColor,color,rgb[1],rgb[2],rgb[3]) end end
if not ok then monitor.clear(); monitor.setCursorPos(1,1); monitor.write("Critical error:"); monitor.setCursorPos(1,2); monitor.write(tostring(err):sub(1,monitor.getSize()-1)); print(err) end
