require("util")
require("pcad_lib")
local delimer = "|+"
local logData = print
local function parseADBlock(data, pos)
    local r = {}
    local length, t = string.unpack("I2I2", data, pos)
    local lastPos = pos+4+length
    pos = pos + 4
    if t ~= 0 then
        r.bin = string.sub(data, pos, lastPos-1)
        return r,lastPos
    end
    while pos < lastPos do
        local p1,p2 = string.find(data, delimer, pos)
        if not p1 then
            if pos < lastPos-1 then
                p1=lastPos+1
                p2 = p1
            else
                return r,lastPos
            end
        end
        --logData(p1,p2, pos)
        if p1>pos then
            if p1>lastPos then p1 = lastPos - 1 end
            local record = string.sub(data, pos, p1-1)
            --logData(record)
            string.gsub(record, "([^=]+)=([^=]+)", function(k,v)
                r[k] = v
            end)
        end
        pos = p2 + 1
    end
    return r,lastPos
end


local function parseADBlockFile(fileName)
    local f,e = io.open(fileName, "rb")
    local blocks = {}
    if f then
        local r = f:read("*a")
        --logData("Get ",#r, "bytes from ", fileName)
        local pos = 1
        while pos < #r do
            data, pos = parseADBlock(r, pos)
            blocks[#blocks+1] = data
        end
        f:close()
        return blocks
    else
        logData(e)
    end
end

local function buildFont(fontID, fonts)
    local font = {
        w =  50,
        h =  50,
        thickness= 10,
    }
    if fontID and fonts[fontID] then 
        font.w = math.floor(fonts[fontID].size * 5)
        font.h = font.w
        font.thickness = 10
    end
    return font
end


local function parse_Header(headerName)
    local blocks = parseADBlockFile(headerName)
    local compList = {}
    local fonts = {}
    if #blocks > 0 then
        local block = blocks[1]
        local cnt = tonumber(block.COMPCOUNT)
        local compCnt = cnt
        if not cnt then
            logData("No comp in file " .. headerName)
            return
        end
        for i=1,cnt do
            local nRef = 'LIBREF' .. tostring(i-1)
            local n = 'COMPDESCR'..tostring(i-1)
            local nUtf = '%UTF8%COMPDESCR'..tostring(i-1)
            compList[#compList+1] = {
                name = block[nRef],
                desc = block[n],
                desc8 = block[nUtf],
            }
            --logData(block[nRef])
        end
        cnt = tonumber(block.FONTIDCOUNT)
        if not cnt then
            logData("No font in file " .. headerName)
            return
        end
        for i=1,cnt do
            local n = tostring(i)
            fonts[n] = {
                size = block["SIZE"..n],
                name = block["FONTNAME"..n],
                unerline = block["UNDERLINE"..n],
            }
        end
        
        if #compList ~= compCnt then
            logData("Comp count parse error", #compList, compCnt)
        end
        return compList, fonts
    else
        logData("Fail to parse block in header")
    end
    return {},{}
end

local width_t = {
    ['0'] = 1,
    ['1'] = 10,
    ['2'] = 30,
    ['3'] = 60,
}
local function getWidth(width)
    if width and width_t[width] then
        return width_t[width]
    end
    return 0
end
local function getPos(data)
    if data then
        --data = string.gsub(data, "[ ]+", "")
        if type(data) == 'string' then
            string.gsub(data, "([%+%-%d%.]+)", function(x)
                data = x
            end)
        end
        --local t = string.unpack("I1", data,4)
        --print('"'..data..'"', string.format('%02x', t))
        return math.floor(tonumber(data) * 10)
    end
    return 0
end

local just_t = {
  [0] = {'B', 'L'},
  [1] = {'B', 'C'},
  [2] = {'B', 'R'},
  [3] = {'C', 'L'},
  [4] = {'C', 'C'},
  [5] = {'C', 'R'},
  [6] = {'T', 'L'},
  [7] = {'T', 'C'},
  [8] = {'T', 'R'},
}
local pin_type_t = {
  [0] = "I_Input",
  [1] = "B_I/O",
  [2] = "O_Output",
  [3] = "C_Open Collector",
  [4] = "P_Passive",
  [5] = "T_HiZ",
  [6] = "E_Open Emitter",
  [7] = "W_Power",
}

local function split_name(n)
    local p = string.find(n,"_")
    if p then
        return string.sub(n,1,p-1),n
    end
    return "",n
end

local function get_pin_type(t)
    if pin_type_t[t] then return split_name(pin_type_t[t]) end
    logData("Pin type not found for " .. tostring(t) .. ", convert to passive")
    return split_name(pin_type_t[4])
end

local pin_shape_t = {
    [0] = " line",
    [1] = "I_Invert",
    [2] = "C_Clock",
    [3] = "IC_InvClock",
    [4] = "L_LowInput",
    [5] = "CL_LowClock",
    [6] = "V_LowOutput",
    [7] = "F_ClockNegEdge",
    [8] = "X_LogicNot",
}

local function get_pin_shage(shape)
    local t = pin_shape_t[shape]
    if t then
        return split_name(t)
    end
    logData("Pin shape not found for " .. tostring(shape) .. ", convert to default")
    return "","default"
end

local function BF(d, From, To)
    To = To or From
    local t1 = math.floor(d/ (2^From))
    local div = 2^(To-From+1)
    local t2 = math.modf(t1/div)
    return t1 - (t2 * div)
end

local InEdgeClock = 3
local OutEdgeDot = 1
local OutEdgeLowIn = 4
local OutEdgeLowOut = 17
local OutNot = 6
local function get_shape(inEdge, outEdge, inShape, outShape)
    if outShape == OutNot then
        return get_pin_shage(8)
    end
    if inEdge == InEdgeClock then
        if outEdge == OutEdgeLowIn then
            return get_pin_shage(5)
        end
        if outEdge == OutEdgeDot then
            return get_pin_shage(3)
        end
        return get_pin_shage(2)
    end
    if outEdge == OutEdgeDot then
        return get_pin_shage(1)
    end
    if outEdge == OutEdgeLowIn then
        return get_pin_shage(4)
    end
    if outEdge == OutEdgeLowOut then
        return get_pin_shage(6)
    end
    return get_pin_shage(0)
end

local function adPinToSymbol(pin)
    local r = string.gsub("X $name $num $x $y $pinLength $dir $nameSize $numSize $partNum 1 $eleType", "%$(%w+)", pin)
    if pin.hide then
        r = r .. " N" .. pin.shape
    end
    if pin.shape ~= "" then
        return r .. " " .. pin.shape
    end
    return r
end

local function next_is_bar(n,i)
    if i+1<=#n then
        local t = string.sub(n,i+1,i+1)
        return t == "\\"
    end
    return false
end

local function make_symbol_pin_name(n)
    local r = string.gsub(n, "  ", " ")
    r = string.gsub(r, " ", "_")
    r = string.gsub(r, "[%s]+", "")
    r = string.gsub(r, "^[\\]+", "")
    local res = ""
    local isBar = false
    local i = 1
    while i <= #r do
        local t = string.sub(r,i,i)
        if next_is_bar(r, i) then
            if not isBar then res = res .. "~" end
            isBar = true
            i = i + 1
        else
            if isBar then res = res .. "~" end
            isBar = false
        end
        res = res .. t
        i = i + 1
    end
    return res
end

local function parsePin(data,fonts, comp)
    local pin = {}
    --local r = ""
    --for i=1,#data do
    --    local d = string.unpack("I1", data, i)
    --    r = r .. string.format("%02x ", d)
    --end
    --logData(r)
    pin.partNum = string.unpack("I1", data, 6)
    
    local inEdge,outEdge,inShape, outShape = string.unpack("I1I1I1I1", data, 9)
    pin.shape, pin.lShape = get_shape(inEdge, outEdge, inShape, outShape)
    
    if inEdge == 3 then
        
    else
    end
    
    local pos = 13
    local strLen = string.unpack("I1", data, pos)
    local str = string.unpack("c" .. strLen, data, pos+1)
    pin.desc = str
    --logData("desc:" .. str)
    pos = pos + 1 + strLen
    
    
    
    pos = pos + 1
    pin.t,pin.dir,pin.len, pin.x, pin.y = string.unpack("i1i1i2i2i2", data, pos)
    pin.disName = BF(pin.dir, 3) == 1 --and "show" or "hide"
    pin.disNum = BF(pin.dir, 4) == 1 --and "show" or "hide"
    pin.disNameT = tostring(pin.disName)
    pin.disNumT = tostring(pin.disNum)
    pin.hide = BF(pin.dir,2) == 1 --and "hide" or "show"
    pin.hideT = tostring(pin.hide)
    pin.dir = toKicadPinDir(math.floor(BF(pin.dir,0,1) * 90))
    
    pin.pinLength = getPos(pin.len)
    pin.x = getPos(pin.x)
    pin.y = getPos(pin.y)
    
    if pin.dir == "R" then
        pin.x = pin.x - pin.pinLength
        pin.bbox = BBOX.create(pin.pinLength, 10, pin.x + pin.pinLength/2, pin.y)
    elseif pin.dir == "L" then
        pin.x = pin.x + pin.pinLength
        pin.bbox = BBOX.create(pin.pinLength, 10, pin.x - pin.pinLength/2, pin.y)
    elseif pin.dir == "U" then
        pin.y = pin.y - pin.pinLength
        pin.bbox = BBOX.create(10, pin.pinLength, pin.x , pin.y + pin.pinLength/2)
    elseif pin.dir == "D" then
        pin.y = pin.y + pin.pinLength
        pin.bbox = BBOX.create(10, pin.pinLength, pin.x , pin.y - pin.pinLength/2)
    end
    
    -- TODO need parse the PinTextData to get the pin text size
    pin.nameSize = 50
    pin.numSize = 50
    
    pos = pos + 8
    
    pos = pos + 4
    
    local l1 = string.unpack("I1", data, pos)
    --logData(string.format("name len = %x", l1))
    local n1 = string.unpack("c"..l1, data, pos+1)
    pos = pos + 1 + l1
    local l2 = string.unpack("I1", data, pos)
    local n2 = string.unpack("c"..l2, data, pos + 1)
    
    pin.name = make_symbol_pin_name(n1)
    pin.num = n2
    pin.eleType,pin.tl = get_pin_type(pin.t)
    pin.toSymbol = adPinToSymbol
    
    comp.pins[#comp.pins+1] = pin
    
    --logData(string.gsub('$name($disNameT):$num($disNumT), type:$eleType,$tl len=$pinLength @$x,$y,$dir hide:$hideT, part=$partNum, $shape,$lShape', "%$(%w+)", pin))
end

local function parseText(block,fonts,comp)
    local t = block.NAME or 'user'
    local value = block.TEXT
    local x = getPos(block['LOCATION.X'])
    local y = getPos(block['LOCATION.Y'])
    local rotate = block['ORIENTATION'] or 0
    local hide = false
    local just = tonumber(block.JUSTIFICATION) or 0
    if block.ISHIDDEN and block.ISHIDDEN=='T' then
        hide = true
    end
    rotate = tonumber(rotate) * 90 
    local font = buildFont(block.FONTID, fonts)
    local hJust = just_t[just] and just_t[just][2] or 'C'
    local vJust = just_t[just] and just_t[just][1] or 'C'
    --toKicadText(x,y,rotate,t,value, font, hide, "symbol", just_t[just][2], just_t[just][1])
    --logData("Get text, " .. t.."="..value .. " @ "..tostring(x)..","..tostring(y)..","..rotate .. " just:"..just.. '='..just_t[just][1] .. just_t[just][2])
    
    if t == 'Designator' then
        value = string.sub(value,1,-2)
        comp.ref = value == "" and 'U' or value
    end
    --x = math.floor(tonumber(x))
    --x = math.floor(tonumber(y))
    local v = {
        x = x,
        y = y,
        value = value,
        t = t,
        rotate = rotate,
        font = font,
        hide = hide,
        layer = 'symbol',
        toSymbol = textToSymbol,
        isText = true,
        hJust = hJust,
        vJust = vJust,
    }
    comp.texts = comp.texts or {}
    comp.texts[#comp.texts+1] = v
end

local function list_block(block)
    for k,v in pairs(block) do
        logData("  "..k.."="..v)
    end
end

local function parseCompHeader(block,fonts,comp)
    --list_block(block)
    comp.name = block.LIBREFERENCE
    comp.drawPinNo = 'Y'
    comp.drawPinName = 'Y'
    comp.ref = '***'
    comp.partNum = block.PARTCOUNT
end

local function parseDummy(block,fonts,comp)
    return {}
end

local function element(array)
    local i = 0
    return function()
        i = i + 1
        return array[i]
    end
end

local function parseFP(block,fonts,comp)
    comp.FPName = block.MODELNAME
end

local function rectToSymbol(rect)
    return string.gsub("S $x1 $y1 $x2 $y2 $part 1 $width $fill", "%$(%w+)", rect)
end



local function parseRectangle(block, fonts, comp)
    --logData("Rectangle")
    --list_block(block)
    local f = block.ISSOLID and block.ISSOLID == 'T'
    local r = {
    x1 = getPos(block['LOCATION.X']),
    y1 = getPos(block['LOCATION.Y']),
    x2 = getPos(block['CORNER.X']),
    y2 = getPos(block['CORNER.Y']),
    part = block.OWNERPARTID or 0,
    width = getWidth(block.LINEWIDTH),
    fill = f and 'f' or 'N',
    toSymbol = rectToSymbol,
    }
    r.bbox = BBOX.create2P(r.x1,r.y1,r.x2,r.y2)
    comp.graphs[#comp.graphs+1] = r
end

local function parseArc(block, fonts, comp)
    local x = getPos(block['LOCATION.X'])
    local y = getPos(block['LOCATION.Y'])
    local r = getPos(block.RADIUS)
    local startAngle = block.STARTANGLE or 0
    local sweepAngle = block.ENDANGLE or 0
    sweepAngle = sweepAngle - startAngle
    local width = getWidth(block.LINEWIDTH)
    local v = toKicadArc(x,y,r,startAngle,sweepAngle,width,"symbol")
    v.part = block.OWNERPARTID or 0
    local f = block.ISSOLID and block.ISSOLID == 'T'
    v.fill = f and 'f' or 'N'
    v.bbox = BBOX.create(r*2,r*2)
    v.bbox = BBOX.moveTo(v.bbox, x, y)
    comp.graphs[#comp.graphs+1] = v
end

local function parseElliArc(block, fonts, comp)
    -- just ignore the second radius
    return parseArc(block, fonts, comp)
end

local function parseElliCircle(block, fonts, comp)
    block.STARTANGLE = 0
    block.ENDANGLE = 360
    return parseArc(block, fonts, comp)
end

local function buildShape(shape, x1,y1, x2,y2, size)
    -- TODO support for the line shape
end
local function parseLine(block, fonts, comp)
    --list_block(block)
    local pts = {}
    pts[1] = {getPos(block['LOCATION.X']), getPos(block['LOCATION.Y'])}
    pts[2] = {getPos(block['CORNER.X']), getPos(block['CORNER.Y'])}
    
    local v = toKicadPoly(pts, "symbol")
    v.fill = 'N'
    v.part = block.OWNERPARTID or 0
    v.width = getWidth(block.LINEWIDTH)
    v.directOutput = true
    comp.graphs[#comp.graphs+1] = v
end

local function parsePolyLine(block, fonts, comp)
    local cnt = tonumber(block.LOCATIONCOUNT)
    --list_block(block)
    local pts = {}
    for i=1,cnt do
        pts[#pts+1] = {getPos(block['X'..i]), getPos(block['Y'..i])}
    end
    
    local v = toKicadPoly(pts, "symbol")
    v.fill = 'N'
    v.part = block.OWNERPARTID or 0
    v.width = getWidth(block.LINEWIDTH)
    v.directOutput = true
    comp.graphs[#comp.graphs+1] = v
end

local function parsePoly(block, fonts, comp)
    local cnt = tonumber(block.LOCATIONCOUNT)
    local pts = {}
    for i=1,cnt do
        pts[#pts+1] = {getPos(block['X'..i]), getPos(block['Y'..i])}
    end
    pts[#pts+1] = pts[1]
    local v = toKicadPoly(pts, "symbol")
    local f = block.ISSOLID and block.ISSOLID == 'T'
    v.fill = f and 'f' or 'N'
    v.part = block.OWNERPARTID or 0
    v.width = getWidth(block.LINEWIDTH)
    v.directOutput = true
    comp.graphs[#comp.graphs+1] = v
end

local function bLineToSymbol(bline)
    local r = string.gsub("B $count $part 1 $width ", "%$(%w+)", bline)
    for i=1,#bline.pts do
        local x,y = bline.pts[i][1], bline.pts[i][2]
        r = r .. x .. " " .. y .. " "
    end
    return r .. bline.fill 
end

local function parseBLine(block, fonts, comp)
    logData("Not support bline right now")
    --[[
    local cnt = tonumber(block.LOCATIONCOUNT)
    local pts = {}
    for i=1,cnt do
        pts[#pts+1] = {getPos(block['X'..i]), getPos(block['Y'..i])}
    end
    local v = {}
    v.pts = pts
    v.count = #pts
    v.part = block.OWNERPARTID or 0
    v.width = getWidth(block.LINEWIDTH)
    local f = block.ISSOLID and block.ISSOLID == 'T'
    v.fill = f and 'f' or 'N'
    v.toSymbol = bLineToSymbol
    comp.graphs[#comp.graphs+1] = v
    --]]
end
local function IEEE_polyLine_method(param, block, fonts, comp)
    local pts = {}
    local x = getPos(block['LOCATION.X'])
    local y = getPos(block['LOCATION.Y'])
    local rotate = nil
    if block.ORIENTATION then
        rotate = tonumber(block.ORIENTATION) * 90
    end
    local scale = getPos(block.SCALEFACTOR)
    scale = scale / 100
    for pt in element(param) do
        local tx,ty = pt[1]*scale + x, pt[2]*scale + y
        if rotate then
            tx,ty = rotate_p2p(x,y,tx,ty,rotate)
        end
        pts[#pts+1] = {math.floor(tx), math.floor(ty)}
    end
    
    local v = toKicadPoly(pts, "symbol")
    local f = block.ISSOLID and block.ISSOLID == 'T'
    v.fill = f and 'f' or 'N'
    v.part = block.OWNERPARTID or 0
    v.width = getWidth(block.LINEWIDTH)
    v.directOutput = true
    comp.graphs[#comp.graphs+1] = v
end
local function IEEE_circle_method(param, block, fonts, comp)
    block.RADIUS = tostring(tonumber(block.SCALEFACTOR)/2)
    parseElliCircle(block, fonts, comp)
end

local function IEEE_arc_method(param, block, fonts, comp)
    factor = tonumber(block.SCALEFACTOR)
    local scale = factor / 100
    local rotate = 0
    if block.ORIENTATION then
        rotate = tonumber(block.ORIENTATION) * 90
    end
    local x = block['LOCATION.X']
    local y = block['LOCATION.Y']
    local mx,my = param.x*scale + x, param.y*scale + y
    mx,my = rotate_p2p(x,y,mx,my, rotate)
    block['LOCATION.X'] = mx
    block['LOCATION.Y'] = my
    block.RADIUS = param.r*scale
    block.STARTANGLE = param.startAngle + rotate
    block.ENDANGLE = param.endAngle + rotate
    parseArc(block, fonts, comp)
end

local function IEEE_mixed_method(param, block, fonts, comp)
    for action in element(param) do
        action.method(action.param, block, fonts, comp)
    end
end

-- polyline method points:
-- points with sacle factor = 100 place at 0,0, rotation = 0 degree
local IEEE_sym = {
    ['1'] = { -- dot
        method = IEEE_circle_method,
        param = {}
    },
    ['2'] = { -- right left signal flow
        method = IEEE_polyLine_method,
        param = {{0,40},{120,0},{120, 80},{0,0}}
    },
    ['3'] = { -- clock
        method = IEEE_polyLine_method,
        param = {{0,0},{0,80},{120, 40},{0,0}}
    },
    ['4'] = { -- active low input
        method = IEEE_polyLine_method,
        param = {{0,0},{120,0},{0, 60},{0,0}}
    },
    ['5'] = { -- analog in
        method = IEEE_mixed_method,
        param = {
            { method = IEEE_polyLine_method,
               param = {{0,30},{0,0},{60,0},{60,30}}
            },
            { method = IEEE_arc_method,
              param = {x=30,y=30,r=30,startAngle = 0, endAngle = 180}
            },
        }
    },
    ['6'] = { -- not logic connection
        method = IEEE_mixed_method,
        param = {
            { method = IEEE_polyLine_method,
               param = {{0,0},{80,80}}
            },
            { method = IEEE_polyLine_method,
               param = {{0,80},{80,0}}
            },
        }
    },
    ['7'] = { -- shift right
        method = IEEE_polyLine_method,
        param = {{0,0}, {60,-30}, {60,30}, {0,0}}
    },
    ['8'] = { -- postpond out
        method = IEEE_polyLine_method,
        param = {{80,0}, {80,80}, {0,80}}
    },
    ['9'] = { -- open collector
        method = IEEE_mixed_method,
        param = {
            { method = IEEE_polyLine_method,
              param = {{0,0}, {80,0}},
            },
            { method = IEEE_polyLine_method,
              param = {{0,40}, {40,0}, {80,40}, {40, 80}, {0, 40}},
            },
        }
    },
    ['10'] = { -- HiZ
        method = IEEE_polyLine_method,
        param = {{0,80}, {40,0}, {80,80}, {0,80}}
    },
    ['11'] = { -- high current
        method = IEEE_polyLine_method,
        param = {{0,0},{0,80},{80, 40},{0,0}}
    },
    ['12'] = { -- pulse
        method = IEEE_polyLine_method,
        param = {{0,0},{80,0},{80, 80},{160,80}, {160, 0}, {240,0}} 
    },
    ['13'] = { -- schmitt
        method = IEEE_polyLine_method,
        param = {{0,0},{120,10},{120, 70},{160,80}, {40,70}, {40,10},{0,0}}
    },
    ['14'] = { -- delay
        method = IEEE_polyLine_method,
        param = {{0,-20},{0,20},{0, 0},{200,0}, {200, -20} , {200, 20}}
    },
    
}
local function drawIEEESymbol(symbol, block, fonts, comp)
    local is = IEEE_sym[symbol]
    if is then
        is.method(is.param, block, fonts, comp)
    else
        logData("IEEE symbol " .. symbol .. " not support")
    end
end

local function parseIEEESymbol(block, fonts, comp)
    local sym = block.SYMBOL
    drawIEEESymbol(sym, block, fonts, comp)
    --logData("IEEE")
    --list_block(block)
end

local record_t = {
    ['1']  = parseCompHeader,
    ['41'] = parseText,
    ['34'] = parseText,
    ['4'] = parseText,
    ['44'] = parseDummy,
    ['45'] = parseFP,
    ['46'] = parseDummy,
    ['48'] = parseDummy,
    ['14'] = parseRectangle,
    ['12'] = parseArc,
    ['6']  = parsePolyLine,
    ['13'] = parseLine,
    ['7'] = parsePoly,
    ['5'] = parseBLine,
    ['11'] = parseElliArc,
    ['8'] = parseElliCircle,
    ['3'] = parseIEEESymbol,
}

local function mkDummy(text, t)
    if text then
        text = '"' .. text .. '"'
    else
        text = '"Dummy"'
    end
    if t then
        t = '"' .. t .. '"'
    else
        t = '"Dummy"'
    end
    return {
    x = 0,
    y = 0,
    value = text,
    t = t,
    rotate = 0,
    font = {w=50,h=50,thickness=10},
    hide = true,
    layer = 'symbol',
    toSymbol = textToSymbol,
    isText = true,
}
end

local function adCompToSymbol(comp, libname4symbol)
    local r = "#\n# " .. comp.name .. "\n#\n"
    local pin_str = ""
    local graph_str = ""
    comp.drawPinNo = 'N'
    comp.drawPinName = 'N'
    local partUsed = {}
    local bbox = BBOX.create(1,1)
    
    for pin in element(comp.pins) do
        pin_str = pin_str .. pin:toSymbol() .. "\n"
        if pin.disName then comp.drawPinName = 'Y' end
        if pin.disNum then comp.drawPinNo = 'Y' end
        partUsed[tonumber(pin.partNum)] = 1
        bbox = BBOX.merge(bbox, pin.bbox)
    end
    
    for graph in element(comp.graphs) do
        graph_str = graph_str .. graph:toSymbol() .. "\n"
        partUsed[tonumber(graph.part)] = 1
        bbox = BBOX.merge(bbox, graph.bbox)
    end
    comp.partNum = #partUsed
    comp.defName = make_name(comp.name)
    r = r .. string.gsub([[DEF $defName $ref 0 40 $drawPinNo $drawPinName $partNum F N]], "%$(%w+)", comp)
    r = r .. "\n"
    local fp = comp.FPName
    if libname4symbol and libname4symbol ~= "" then
        fp = libname4symbol .. ":" .. string.upper(fp)
    end
    local bbl,bbt,bbr,bbb = BBOX.splitBB(bbox)
    local texts = {mkDummy(),mkDummy(comp.name),mkDummy(fp),mkDummy("")}
    texts[3].x = math.floor(bbl)
    texts[3].y = math.floor(bbt - 200)
    texts[3].hJust = 'L'
    texts[3].vJust = 'B'
    texts[2].x = math.floor(bbl + 50)
    texts[2].y = math.floor(bbb + 150)
    texts[2].hJust = 'L'
    texts[2].vJust = 'B'
    local vPos = math.floor(bbt - 300)
    for text in element(comp.texts) do
        if      text.t == 'Designator' then
            text.x = math.floor(bbl)
            text.y = math.floor(bbb + 50)
            texts[1] = text
        elseif  text.t == 'Comment' then
            text.x = math.floor(bbl + 150)
            text.y = math.floor(bbb + 50)
            texts[#texts+1] = text
        elseif  text.t == 'ComponentLink1URL' then
            text.x = math.floor(bbl)
            text.y = math.floor(bbt - 100)
            texts[4] = text
        else
            if text.t ~= "user" then
                text.x = math.floor(bbl)
                text.y = math.floor(vPos)
            end
            texts[#texts+1] = text
            vPos = vPos - 100
        end
        text.value = text.value or ""
        text.value = '"'..text.value..'"'
        text.t = '"'..text.t..'"'
    end
    for i=1,#texts do
        r = r .. texts[i]:toSymbol(i-1, i>4) .. "\n"
    end
    
    r = r .. "DRAW\n"
    r = r .. graph_str .. pin_str
    
    r = r .. "ENDDRAW\nENDDEF\n"
    
    return r
end

local function parseComp(compPath, fonts)
    local blocks = parseADBlockFile(compPath.."/data")
    local r = {}
    r.texts = {}
    r.graphs = {}
    r.pins = {}
    --logData(compPath)
    for i=1,#blocks do
        local bk = blocks[i]
        if bk.bin then
            parsePin(bk.bin,fonts,r)
        else
            local rec = tostring(bk.RECORD,fonts)
            if record_t[rec] then
                local g = record_t[rec](bk,fonts,r)
            else
                logData("Unknown record type " .. rec .. "  in " .. compPath)
                list_block(bk)
            end
        end
    end
    r.toSymbol = adCompToSymbol
    return r
end



function parse_schlib(libpath, logFunc)
    logData = logFunc or logData
    local compList, fonts = parse_Header(libpath.."/FileHeader")
    for k,v in pairs(fonts) do
        --logData(k,v.name, v.size, tostring(v.unerline))
    end
    local comps = {}
    for i=1,#compList do
        local n = string.gsub(compList[i].name, "([/\\%*])", "_")
        if #n > 31 then
            n = string.sub(n,1,31)
        end
        if string.sub(n,#n,#n) == '.' then
            n = string.sub(n,1,#n-1) .. '_'
        end
        --print("Convert " .. compList[i].name)
        local comp = parseComp(libpath.."/"..n, fonts)
        comps[#comps+1] = comp
    end
    return comps
end

function convert_schlib(inputName, outputName, fpLibName,logFunc)
    logData = logFunc or logData
    local oPath = string.gsub(inputName, "(%.[^%.]+)$", "")
    exec('7z x "'..inputName ..'" -y -o"'..oPath..'"')
    if not outputName or outputName == "" then
        outputName = oPath .. ".lib"
    end
    local comps = parse_schlib(oPath)
    local f,e = io.open(outputName, "w+")
    if f then
        f:write([[
EESchema-LIBRARY Version 2.4
#encoding utf-8
]])
        for comp in element(comps) do
            f:write(comp:toSymbol(fpLibName))
        end
        f:write("\n#\n#End Library")
        f:close()
    else
        logData(e)
    end
    exec('rd "' .. oPath .. '" /Q /S')
end
local function usage()
    print("usage:")
    print("  Signle file mode:")
    print("    lua ad2kicad.lua <input ad library name> [output library name] [footprint lib for symbol]")
    print("  Multiple file mode:")
    print("    lua ad2kicad.lua --batch <input folder> [output folder] [footprint lib for symbol] [out lib prefix] [orgname=newname]")
    os.exit(-1)
end
if #arg < 1 then
    usage()
end

if arg[1] == "--batch" then
    if #arg < 2 then
        usage()
    end
    local inPath = arg[2]
    local outPath = arg[3] or inPath
    local symbolLib = arg[4] or ""
    local libPrefix = arg[5]
    local i = 6
    local reName = {}
    while arg[i] do
        string.gsub(arg[i], "([^=]+)=([^=]+)", function(orgName, newName)
            reName[orgName] = newName
            --print(orgName, "=", newName)
        end)
        i = i + 1
    end
    local files = get_file_names(inPath, "*.SchLib")
    print("Batch process "..#files.. " files")
    for i=1,#files do
        local libName = files[i]
        --print(libName)
        local fname = libName .. ".SchLib"
        if reName[libName] then
            libName = reName[libName]
        elseif libPrefix and libPrefix ~= "" then
            libName = libPrefix .. "_" .. libName
        end
        libName = outPath .. "/" .. libName .. ".lib"
        --print("Convert <".. inPath.."/"..fname .. "> to <"..libName..">" .. " in <"..outPath .. ">")
        --print("Convert <".. inPath.."/"..fname .. "> to <"..libName.."> " .. symbolLib)
        convert_schlib(inPath.."/"..fname, libName, symbolLib, log_info)
    end
    
    
else
    convert_schlib(arg[1], arg[2] or "", arg[3] or "", log_info)
end

--[==[
if #arg > 0 then
    local inFile = arg[1]..".schlib"
    local oPath = arg[1]
    os.execute('7z x "'..inFile ..'" -y -o"'..oPath..'"')
    local comps = parse_schlib(arg[1])
    local f = io.open(arg[1] .. ".lib", "w+")
    if f then
        f:write([[
EESchema-LIBRARY Version 2.4
#encoding utf-8
]])
        for comp in element(comps) do
            f:write(comp:toSymbol())
        end
        f:write("\n#\n#End Library")
        f:close()
    end
end
]==]