---------------------------------------------------------------------
----   PCAD ascii format library parser
----   Read data from the S-Expression file, then convert them 
----   into kicad format
----   Can convert both the symbol library and footprint library
----------------------------------------------------------------------
require("s_format")
BBOX = require("bbox")
local LogI = function() end
local progress_hook = function() end
-- convert pcad shape to kicad shape
local shapes_t = {
    Rect = "rect",
    Oval = "oval",
}
-- convert pcad layer to kicad layer
local layers_t = {
   ["6"] = "F.SilkS",
   ["21"] = "F.Fab",
   ["22"] = "F.Fab",
   ["8"] = "F.Paste",
   ["symbol"] = "symbol"
}
-- covert pcad graph to kicad graph
local graph_t = {
    arc = "fp_arc",
    line = "fp_line",
    pcbPoly = "fp_poly",
}
local global_fonts = {}
local global_units = "mil"
-- covert pcad number to kicad, mm/mil to mm, remove the unit string
local global_symbol_mode = true
function tokicad(value, quit)
    if global_symbol_mode then
        local p = string.find(value, "mm")
        if p then
            local t = string.sub(value,1, p-1)
            return string.format( "%.3f", tonumber(t)/ 0.0254)
        end
        p = string.find(value, "deg")
        if p then
            return string.sub(value,1, p-1)
        end
        p = string.find(value, "mil")
        if p then
            return math.floor(tonumber(string.sub(value,1, p-1)))
        end
        if quit then return tonumber(value) end
        return tokicad(value .. global_units, true)
    end

    local p = string.find(value, "mm")
    if p then
        return string.sub(value,1, p-1)
    end
    p = string.find(value, "deg")
    if p then
        return string.sub(value,1, p-1)
    end
    p = string.find(value, "mil")
    if p then
        local t = string.sub(value,1, p-1)
        return string.format( "%.3f", tonumber(t)* 0.0254)
    end
    if quit then return string.format( "%.3f", tonumber(value)* 0.0254) end
    -- append global units and parse again
    return tokicad(value .. global_units, true)
    --return string.format( "%.3f", tonumber(value)* 0.0254)
end

local function ele_is(v,n)
    return (type(v) == "table") and (v[1] == n)
end

-- translate pcad coordinate to kicad
local function KiCoord(x,y)
    if global_symbol_mode then
        return x,y
    end
    return x,-y
end

-- print pad in kicad format
local function posToString(x,y,rotate)
    if tonumber(rotate) == 0 then
        rotate = nil
    end
    return "at " .. x .. " " .. y .. (rotate and (" " .. rotate) or "")
end
local function print_pad(pad, num, x,y, rotate)
    local at = "("..posToString(x,y,rotate) .. ")"
    local r = "(pad " ..num .." " .. pad.type .. " " .. pad.shape ..
    at .. 
    " (size " .. pad.size .. ")" ..
    " (drill " .. pad.drill .. ")" ..
    " (layers " .. pad.layers .. ")" ..
    ")" 
    return r
end

local function pad_to_string(pad)
    return print_pad(pad.data, pad.num, pad.x, pad.y, pad.rotate)
end

-- create part's pad
local function create_part_pad(pads, name, num, x, y, rotate)
    if pads[name] then
        local bbox = pads[name].bbox
        return {
            data = pads[name],
            num = num,
            x = x,
            y = y,
            rotate = rotate,
            tostring = pad_to_string,
            bbox = BBOX.rotate(BBOX.moveTo(bbox,x,y), rotate),
        }
    else
        LogI(name, " pad style not found")
    end
end

-- create a pad style
local function build_pad(t)
    local n = t[2]
    local v = {}
    v.drill = tokicad(t[3][2])
    local w1 = t[6][4][2]
    local h1 = t[6][5][2]
    local w2 = t[7][4][2]
    local h2 = t[7][5][2]
    v.type = "smd"
    if w2 ~= "0.0" or h2 ~= "0.0" then
        v.type = "thru_hole"
        if w1 ~= w2 or h1~=h2 then
            LogI("top/bottom size missmatch in ", n)
        end
    end
    w1, h1 = tokicad(w1), tokicad(h1)
    v.size = w1 .. " " .. h1
    v.bbox = BBOX.create(w1,h1)
    local s = t[6][3][2]
    if s and shapes_t[s] then
        v.shape = shapes_t[s]
    else
        LogI("Unknown shape in ", n)
        v.shape = "unknown"
    end
    
    if (tokicad(w1) == "0") or (tokicad(h1) == "0") then
        LogI("Pad dimension may error in ", n)
    end
    
    if v.type == "smd" then
        v.layers = "F.Cu F.Paste F.Mask"
    else
        v.layers = "*.Cu *.Mask"
    end
    return n,v
end

local function fontToString(font)
    return string.gsub("font (size $h $w) (thickness $thickness)", "%$(%w+)", font)
end

local function build_font(t)
    local n = t[2]
    local v = {w=1,h=1,thickness=0.15}
    for j=3, #t do
        if ele_is(t[j], "font") then
            local r = s_expand(t[3], {fontType = 1, fontHeight = tokicad, strokeWidth = tokicad})
            if r.fontType == "Stroke" then
                v = {w=r.fontHeight,h=r.fontHeight,thickness = r.strokeWidth}
            end
        end
    end
    v.tostring = fontToString
    return n,v
end

local function progress(total, duration)
    duration = duration or 0
    local i = 1
    return function(cur)
        if i>duration then
            i = 0
            progress_hook(cur, total)
        end
        i = i + 1
    end
end
-- collect all pad and font style in the library file
local function collect_pad_font(lib_table)
    local pads = {}
    local fonts = {}
    pads.count = 0
    fonts.count = 0
    local hk = 1
    local prog = progress(#lib_table, 20)
    for i,e in s_elements(lib_table, "padStyleDef") do
        local k,v = build_pad(e)
        pads[k] = v
        pads.count = pads.count + 1
        prog(i)
    end
    for i,e in s_elements(lib_table, "textStyleDef") do
        local k,v = build_font(e)
        fonts[k] = v
        fonts.count = pads.count + 1
        prog(i)
    end
    pads.create_pad = create_part_pad
    return pads, fonts
end

local function ptParser(x,y)
    x,y = KiCoord(tokicad(x), tokicad(y))
    return {x=x, y=y}
end

local function angleParser(rot)
    return tokicad(rot.."deg")
end

local function boolParser(bool)
    return bool ~= "False"
end
local function fontParser(f)
    local font = global_fonts[f]
    if not font then
        LogI("Font (" .. f ..") not found")
    end
    return font
end
local function displayParser(p1, p2)
    return {[p1[1]] = p1[2], [p2[1]]=p2[2]}
end

local function parse_pads(t, pads)
    local r = {}
    for i,e in s_elements(t, "pad") do
        local pad = s_expand(
            e, 
            {   -- required field
                padNum=1,
                padStyleRef=1, 
                pt = ptParser,
            },{ -- optinaol field
                rotation = angleParser,
                defaultPinDes = function(num)
                    num = string.sub(num,2,-2)
                    if #num == 0 then return [[""]] end
                    return num
                end })
            
        r[#r+1] = pads:create_pad(pad.padStyleRef,pad.defaultPinDes or pad.padNum,pad.pt.x,pad.pt.y,pad.rotation)
    end
    return r
end

local function arcToString(arc)
    if math.abs(arc.angle) == 360 then
        return string.gsub("(fp_circle (center $sx $sy) (end $ex $ey) (layer $layer) (width $width))", "%$(%w+)", arc)
    else
        return string.gsub("(fp_arc (center $sx $sy) (end $ex $ey) (angle $angle) (layer $layer) (width $width))", "%$(%w+)", arc)
    end
end
local function arcToSymbol(arc, part)
    local tt = {}
    for k,v in pairs(arc) do
        tt[k] = v
    end
    tt.part = part or arc.part or 0
    local sa = tt.startAngle
    tt.startAngle = math.floor(tt.endAngle)
    tt.endAngle = math.floor(sa)
    tt.fill = arc.fill or 'N'
    if math.abs(tt.startAngle - tt.endAngle) == 3600 then
    return string.gsub("C $x $y $radius $part 1 $width $fill", "%$(%w+)", tt)
    else
    tt.sx = math.floor(arc.sx + math.cos(toArc(tt.startAngle/10))*arc.radius)
    tt.sy = math.floor(arc.sy + math.sin(toArc(tt.startAngle/10))*arc.radius)
    tt.ex = math.floor(arc.sx + math.cos(toArc(tt.endAngle/10))*arc.radius)
    tt.ey = math.floor(arc.sy + math.sin(toArc(tt.endAngle/10))*arc.radius)
    return string.gsub("A $x $y $radius $startAngle $endAngle $part 1 $width $fill $sx $sy $ex $ey", "%$(%w+)", tt)
    end
end
function toKicadArc(x,y,r,startAngle, sweepAngle, width, layer)
    local res = {}
    sweepAngle = tonumber(sweepAngle)
    res.sx,res.sy,res.ex,res.ey,res.angle,res.width = x,y, x+math.cos(toArc(startAngle))*r, y-math.sin(toArc(startAngle))*r, -sweepAngle, width
    res.radius = r
    res.x,res.y = x,y
    res.startAngle = startAngle*10
    res.endAngle = (startAngle + sweepAngle)*10
    res.layer = layer
    res.tostring = arcToString
    res.toSymbol = arcToSymbol
    res.bbox = { {res.sx-r, res.sy-r}, {res.sx+r, res.sy+r} }
    return res
end

local function lineToString(line)
    return string.gsub("(fp_line (start $sx $sy) (end $ex $ey) (layer $layer) (width $width))", "%$(%w+)", line)
end
local function lineToSymbol(line, part)
    local tt = {}
    tt.part = part
    tt.width = line.width
    tt.sx = line.sx
    tt.ex = line.ex
    tt.sy = line.sy
    tt.ey = line.ey
    return string.gsub("P 2 $part 1 $width $sx $sy $ex $ey N", "%$(%w+)", tt)
end
local function toKicadLine(pts, width, layer)
    local r = {}
    r.sx = pts[1][1]
    r.sy = pts[1][2]
    r.ex = pts[2][1]
    r.ey = pts[2][2]
    r.layer = layer
    r.tostring = lineToString
    r.toSymbol = lineToSymbol
    r.width = width
    local sx = tonumber(r.sx)
    local ex = tonumber(r.ex)
    local sy = tonumber(r.sy)
    local ey = tonumber(r.ey)
    local x1 = sx<ex and sx or ex
    local x2 = sx<ex and ex or sx
    local y1 = sy<ey and sy or ey
    local y2 = sy<ey and ey or sy
    r.bbox = { {x1,y1}, {x2,y2}}
    r.isLine = true
    return r
end
local function polyToString(poly)
    local r = "(fp_poly (pts "
    for i=1,#poly.pts do
        local pt = poly.pts[i]
        r = r .. "(xy " .. pt[1] .. " " .. pt[2] .. ")"
        if i~= #poly.pts then r = r .. " " end
    end
    r = r .. ") (layer " .. poly.layer .. ") (width 0.15))"
    return r
end
local function polyToSymbol(poly, part)
    local tt = {}
    tt.part = poly.part or part
    tt.width = poly.width or 15
    local p1,p2 = poly.pts[1], poly.pts[#poly.pts]
    
    if poly.directOutput then
    else
    if p1[1] ~= p2[1] or p1[2] ~= p2[2] then
        poly.pts[#poly.pts+1] = p1
    end
    end
    
    tt.ptCnt = #poly.pts
    local r = string.gsub("P $ptCnt $part 1 $width ", "%$(%w+)", tt)
    for i=1,#poly.pts do
        local x,y = poly.pts[i][1], poly.pts[i][2]
        r = r .. x .. " ".. y .. " "
    end
    if poly.fill then
        return r .. poly.fill
    end
    return r .. (tt.ptCnt > 4 and "f" or "N")
end
function toKicadPoly(pts, layer)
    local r = {}
    r.pts = pts
    r.layer = layer
    r.tostring = polyToString
    r.toSymbol = polyToSymbol
    local x1,x2,y1,y2
    for i=1,#pts do
        local x,y = tonumber(pts[i][1]), tonumber(pts[i][2])
        x1 = x1 or x
        x2 = x2 or x
        y1 = y1 or y
        y2 = y2 or y
        x1 = x<x1 and x or x1
        x2 = x2<x and x or x2
        y1 = y<y1 and y or y1
        y2 = y2<y and y or y2
    end
    r.bbox = {{x1+0,y1+0}, {x2+0,y2+0}}
    return r
end
local function textToString(text)
    text.fontstr = text.font:tostring()
    text.pos = posToString(text.x,text.y,text.rotate)
    text.hidestr = text.hide and " hide" or ""
    if text.t == '"RefDes"' then
        text.fpType = "reference"
        text.fpLayer = "F.SilkS"
    elseif text.t == '"Type"' then
        text.fpType = "value"
        text.fpLayer = "F.Fab"
    else
        text.fpType = text.t
        text.fpLayer = text.layer
    end
    return string.gsub([[
(fp_text $fpType $value ($pos) (layer $fpLayer)$hidestr
    (effects ($fontstr))
  )]], "%$(%w+)", text)
end

function textToSymbol(text, index, needType)
    local tt = {}
    tt.value = text.value
    tt.index = index
    tt.size = text.font.w
    tt.x = text.x
    tt.y = text.y
    local rot = tonumber(text.rotate or 0)
    if rot == 0 or rot == 180 then
        tt.dir = "H"
    else
        tt.dir = "V"
    end
    tt.visible = text.hide and "I" or "V"
    tt.hJust = text.hJust or 'C'
    tt.vJust = text.vJust or 'C'
    tt.vJustItalicBold = tt.vJust.."NN"
    local r = string.gsub([[
F$index $value $x $y $size $dir $visible $hJust $vJustItalicBold]], "%$(%w+)", tt)
    if needType then
        r = r .. " " .. text.t
    end
    return r
end

local function toKicadText(x, y, rotate, text_type, value, font, hide, layer)
    local r = {}
    local str = value
    if string.find(value, '"') then
        str = string.sub(str, 2,-2)
    end
    if not global_symbol_mode then
    
    local l = #str
    local rot = rotate and toArc(rotate) or toArc(0)
    
    local lx = font.w*l*(1/1.69333)
    local ly = font.h*(1/1.69333)
    local lr = math.sqrt(lx*lx + ly*ly)
    -- get the orignal position in normal coord
    local ox, oy = KiCoord(x, y)
    -- get the text mid point
    local mx, my = ox + lx/ 2, oy + ly/ 2
    -- rotate the mid point by org point
    local nx = (mx - ox)*math.cos(rot) - (my - oy)*math.sin(rot) + ox
    local ny = (mx - ox)*math.sin(rot) + (my - oy)*math.cos(rot) + oy
    -- covert back to kicad coord
    r.x,r.y = KiCoord(nx,ny)
    else
    r.x,r.y = x,y
    end

    r.rotate = rotate
    r.value = value
    r.t = text_type
    r.font = font
    r.hide = hide
    r.layer = layer
    r.tostring = textToString
    r.toSymbol = textToSymbol
    r.isText = true
    return r
end

local function parse_graph(gv, layer, parent_name)
    if gv[1] == "arc" then
        local arc = s_expand(gv, {
            pt=ptParser,
            radius=tokicad,
            startAngle=angleParser,
            sweepAngle=angleParser,
            width=tokicad})
        return toKicadArc(arc.pt.x,arc.pt.y,arc.radius,arc.startAngle,arc.sweepAngle,arc.width,layer)
    elseif gv[1] == "line" then
        local pts = {}
        local width
        for i=2,#gv do
            if ele_is(gv[i], "pt") then
                local x,y = tokicad(gv[i][2]), tokicad(gv[i][3])
                x,y = KiCoord(x,y)
                pts[#pts+1] = {x,y}
            elseif ele_is(gv[i], "width") then
                width = tokicad(gv[i][2])
            elseif ele_is(gv[i], "style") then
                -- kicad not support line style
            else
                LogI("Un-processed element of line graph in ", parent_name)
            end
        end
        return toKicadLine(pts,width,layer)
    elseif gv[1] == "pcbPoly" or gv[1] == "poly" then
        local pts = {}
        for i=2,#gv do
            if ele_is(gv[i], "pt") then
                local x,y = tokicad(gv[i][2]), tokicad(gv[i][3])
                x,y = KiCoord(x,y)
                pts[#pts+1] = {x,y}
            else
                LogI("Un-processed element of poly graph in ", parent_name)
            end
        end
        return toKicadPoly(pts,layer)
    elseif gv[1] == "attr" then
        local r = s_expand(gv, {[2] = "attr_t", [3] = "value", pt = ptParser, textStyleRef = fontParser},
        {rotation = angleParser, isVisible = boolParser, justify = 1, extent = 1}, { isVisible = true}, true)
        if r.attr_t == [["RefDes"]] then
            r.value = "REF**"
        elseif r.attr_t == [["Type"]] then
            if global_symbol_mode then
            r.value = removeSpaces(parent_name)
            else
            r.value = removeParentheses(parent_name)
            end
        end 
        return toKicadText(r.pt.x,r.pt.y,r.rotation, r.attr_t, r.value, r.textStyleRef, not r.isVisible, layer)
    elseif gv[1] == "text" then
        local r = s_expand(gv, {[3] = "value", pt = ptParser, textStyleRef = fontParser},
        {rotation = angleParser, isVisible = boolParser, justify = 1, extent = 1}, {isVisible = true}, true)
        return toKicadText(r.pt.x,r.pt.y,r.rotation, "user", r.value, r.textStyleRef, not r.isVisible, layer)
    else
        LogI("Unknown graph type (" .. gv[1] .. ") in ", parent_name)
    end
    return nil
end

local function parse_part_graph(t, part)
    part.graphs = part.graphs or {}
    local graphs = part.graphs
    local l = t[2][2]
    local layer = layers_t[l]
    if layer then
        for j=3, #t do
            local r = parse_graph(t[j], layer, part.name)
            if r then graphs[#graphs+1] = r end
        end
    else
        LogI("Unknown layer(" .. l .. ") in ", part.name)
    end
end

local function add_bbox_line(dest, bbox, layer, width)
    layer = layer or "F.CrtYd"
    width = width or 0.05
    local l,t,r,b = BBOX.splitBB(bbox)
    l = l - width
    t = t - width
    r = r + width
    b = b + width
    dest[#dest+1] = toKicadLine({{l,t},{r,t}},width,layer)
    dest[#dest+1] = toKicadLine({{r,t},{r,b}},width,layer)
    dest[#dest+1] = toKicadLine({{r,b},{l,b}},width,layer)
    dest[#dest+1] = toKicadLine({{l,b},{l,t}},width,layer)
end

local function create_part_bbox(part)
    local bbox = BBOX.create(1,1)
    local graphs = part.graphs
    for i=1,#part.pads do
        local r = BBOX.merge(bbox, part.pads[i].bbox)
        --add_bbox_line(graphs, part.pads[i].bbox, "B.CrtYd")
        bbox = r or bbox
        if not r then
            LogI("merge pads bbox fail")
        end
    end
    for i=1,#graphs do
        local bb = graphs[i].bbox
        if bb then
            --add_bbox_line(graphs, bb, "B.SilkS")
            local r = BBOX.merge(bbox, bb)
            bbox = r or bbox
            if not r then
                LogI("merge graph bbox fail ... ", graphs[i]:tostring())
            end
        end
    end
    add_bbox_line(graphs, bbox)
end

function make_name(n)
    if string.find(n,'"') == 1 then
        n = string.sub(n,2,-2)
    end
    n = string.gsub(n, "([%(%) ])", {["("] = "_", [")"] = "", [" "] = "_"})
    return n
end

local function build_part(t, pads)
    local r = {}
    r.pads = {}
    r.graphs = {}
    local n = t[3][2]
    local graph = t[5]
    if string.find(n,'"') == 1 then
        n = string.sub(n,2,-2)
    end
    --n = string.gsub(n, "([%(%) ])", {["("] = "_", [")"] = "", [" "] = "_"})
    n = string.gsub(n, "  ", " ")
    n = string.gsub(n, " ", "_")
    r.name = n
    for i,v in s_elements(graph, "multiLayer") do
        r.pads = parse_pads(v, pads)
    end
    for i,v in s_elements(graph, "layerContents") do
        parse_part_graph(v, r)
    end
    create_part_bbox(r)
    return r
end

local function pinToKiCadSymbol(pin)
    local r = ""
    for k,v in pairs(pin) do
        r = r .. k .. ":" .. tostring(v) .. ", "
    end
    return r
end

local function build_pin(t, parent_name)
    local pin = {}
    local r = s_expand(t, {pinNum=1,pt=ptParser, pinLength=tokicad, pinDisplay=displayParser,
    pinDes  = function(e) return parse_graph(e, "symbol", parent_name) end,
    pinName = function(e) return parse_graph(e, "symbol", parent_name) end,
    },{insideEdgeStyle=1, outsideEdgeStyle=1,isFlipped=boolParser,rotation=angleParser },{},true)
    r.toSymbol = pinToKiCadSymbol
    return r.pinNum, r
end

local function compPinToKiCadSymbol(pin)
    local r = string.gsub("X $name $num $x $y $pinLength $dir $nameSize $numSize $partNum 1 $eleType", "%$(%w+)", pin)
    if pin.hide then
        r = r .. " N"
    end
    return r
end

local eleType_t = {
    Passive = "U",
    Bidirectional = "B",
    Input = "I",
    Output = "O",
    Power = "W",
    PowerIn = "W",
    PowerOut = "w",
    ThreeState = "T",
    OpenH = "C",
    OpenL = "E",
}
local function toKicadPinEleType(pcadType)
    if eleType_t[pcadType] then
        return eleType_t[pcadType]
    else
        LogI("Unkonwn pin type " .. pcadType)
        return "U"
    end
end

function toKicadPinDir(angle)
    local a = tonumber(angle)
    if a == 0 then        return "L"
    elseif a == 90 then   return "D"
    elseif a == 180 then  return "R"
    elseif a == 270 then  return "U"
    else
        LogI("Unkonwn pin direction " .. angle)
        return "R"
    end
end

local function symbolCreatePin(sym, compPin)
    local symPin = sym.pins[compPin.symPinNum]
    local r = {}
    if symPin then
        for k,v in pairs(symPin) do
            r[k] = v
        end
        r.x = r.pt.x
        r.y = r.pt.y
        r.nameSize = r.pinDes.font.w
        r.numSize = r.pinName.font.w
        r.name = make_name(compPin.pinName)
        r.num = make_name(compPin.pinNum)
        r.disNum = r.pinDisplay.dispPinDes ~= "False"
        r.disName = r.pinDisplay.dispPinName ~= "False"
        r.partNum = compPin.partNum
        r.dir = toKicadPinDir(r.rotation)
        if r.dir == "R" then
            r.x = r.x - r.pinLength
        elseif r.dir == "L" then
            r.x = r.x + r.pinLength
        elseif r.dir == "U" then
            r.y = r.y - r.pinLength
        elseif r.dir == "D" then
            r.y = r.y + r.pinLength
        end
        r.eleType = toKicadPinEleType(compPin.pinType)
        r.toSymbol = compPinToKiCadSymbol
        return r
    else
        LogI("Fail to find pin ("..compPin.symPinNum..") in symbol " .. sym.name)
        return nil
    end
end

local function build_symbol(t)
    local n = t[2]
    local symbol = {}
    symbol.name = n
    symbol.pins = {}
    symbol.graphs = {}
    for i=4,#t do
        local e = t[i]
        if ele_is(e, "pin") then
            local pinNum, pin = build_pin(e, n)
            if symbol.pins[pinNum] then
                LogI("Pin number (" .. pinNum .. ") re-defined in " .. n)
            end
            symbol.pins[pinNum] = pin
        else
            local graph = parse_graph(e, "symbol", n)
            symbol.graphs[#symbol.graphs+1] = graph
        end
    end
    symbol.createPin = symbolCreatePin
    return n,symbol
end

local function take(t, pos)
    local r = {}
    for i=1,#t do
        if i~= pos then
            r[#r+1] = t[i]
        end
    end
    return r
end

local function pt_equal(p1,p2)
    return p1[1] == p2[1] and p1[2] == p2[2]
end
local function pt_s(l)
    return {l.sx, l.sy}
end
local function pt_e(l)
    return {l.ex, l.ey}
end
local function find_pt(pt, ls)
    local find = false
    local pos = nil
    local s = false
    for i=1,#ls do
        if pt_equal(pt, pt_s(ls[i])) then
            if not find then
                find = true
                pos = i
                s = true
            else
                --LogI("Point already get")
            end
        end
        if pt_equal(pt, pt_e(ls[i])) then
            if not find then
                find = true
                pos = i
                s = false
            else
                --LogI("Point already get")
            end    
        end
    end
    return pos,s
end

local function mergeCompLine(ls, part)
    if #ls < 1 then return end
    local ps = {ls[1].sx, ls[1].sy}
    local np = {ls[1].ex, ls[1].ey}
    local rls = take(ls,1)
    local pts = {ps,np}
    --LogI("---", ps[1],ps[2], " -> ", np[1],np[2])
    while not pt_equal(ps, np) do
        local cp = {np[1],np[2]}
        local pos,s = find_pt(np, rls)
        if pos then
            np = s and pt_e(rls[pos]) or pt_s(rls[pos])
            rls = take(rls, pos)
            pts[#pts+1] = np
        else
            --LogI("No loop find, maybe not poly")
            break
        end
        --LogI("---", cp[1],cp[2], " -> ", np[1],np[2])
    end
    local r = ""
    if pt_equal(ps, np) then
        local poly = toKicadPoly(pts, "symbol")
        r = r .. poly:toSymbol(part) .. "\n"
    else
        rls = ls
    end
    
    for i=1,#rls do
        r = r .. ls[i]:toSymbol(part) .. "\n"
    end
    return r
end
local function compToSymbol(comp, libname4symbol)
    local r = "#\n# " .. comp.name .. "\n#\n"
    r = r .. string.gsub([[DEF $name $ref 0 40 $drawPinNo $drawPinName $partNum F N]], "%$(%w+)", comp)
    r = r .. "\n"
    local sym = comp.symbols['1']
    local texts = {1,2,3,4}
    for i=1,#sym.graphs do
        local g = sym.graphs[i]
        if g.isText then
            if     g.t == '"RefDes"' then
                g.value = '"'..comp.ref..'"'
                texts[1] = g
            elseif g.t == '"Type"' then
                texts[2] = g
            elseif g.t == '"Package"' then
                g.value = comp.footPrint
                if libname4symbol then
                    g.value = '"' .. libname4symbol .. ":" .. make_name(comp.footPrint) .. '"'
                end
                texts[3] = g
            elseif g.t == '"ComponentLink1URL"' then
                texts[4] = g
            else
                if g.t == 'user' then
                    g.t = '"user"'
                end
                texts[#texts + 1] = g
            end
        end
    end
    for i=1,#texts do
        r = r .. texts[i]:toSymbol(i-1, i>4) .. "\n"
    end
    
    r = r .. "DRAW\n"
    --for k,v in pairs(comp.symbols) do
    for i = 1, 100 do
        local k = tostring(i)
        local v = comp.symbols[k]
        if not v then break end
        local compLines = {}
        for i=1,#v.graphs do
            local g = v.graphs[i]
            if g.isLine then
                compLines[#compLines+1] = g
            elseif not g.isText then
                r = r .. g:toSymbol(k) .. "\n"
            end
        end
        r = r .. mergeCompLine(compLines, k)
    end

    for i=1,#comp.pins do
        r = r .. comp.pins[i]:toSymbol() .. "\n"
    end
    r = r .. "ENDDRAW\nENDDEF\n"
    return r
end

local up_pin_name = {VCC=1, VDD=1,["V+"]=1 }
local function buildCompHidePins(comp, hide_pins)
    if #hide_pins < 1 then return end
    local sym = comp.symbols['1']
    if not sym then
        LogI("Part 1 symbol not found in ".. comp.name)
        return
    end
    if not sym.bbox then
        sym.bbox = BBOX.create(1,1)
        for i=1, #sym.graphs do
            local bb = sym.graphs[i].bbox
            if bb then
                local r = BBOX.merge(sym.bbox, bb)
                sym.bbox = r or sym.bbox
            end
         end
    end
    local tempPin = comp.pins[1]
    local upY =  sym.bbox[2][2]
    local dwonY =  sym.bbox[1][2]
    local mid = (sym.bbox[2][1] + sym.bbox[1][1]) / 2
    local dist = 100
    local upPins = {}
    local downPins = {}
    for i=1, #hide_pins do
        local cp = hide_pins[i]
        if up_pin_name[make_name(cp.pinName)] then
            upPins[#upPins+1] = cp
            cp.isUp = true
        else
            downPins[#downPins+1] = cp
        end
    end
    local upX = math.floor(mid - ((#upPins-1)*dist/2))
    local downX = math.floor(mid - ((#downPins-1)*dist/2))
    for i=1, #hide_pins do
        local cp = hide_pins[i]
        local p = {}
        for k,v in pairs(tempPin) do
            p[k] = v
        end
        p.name = make_name(cp.pinName)
        p.num = make_name(cp.pinNum)
        p.partNum = cp.partNum
        if cp.isUp then
            p.dir = "D"
            p.x = upX
            p.y = upY + p.pinLength
            upX = upX + dist
        else
            p.dir = "U"
            p.x = downX
            p.y = dwonY - p.pinLength
            downX = downX + dist
        end
        -- kicad only auto connect PowerIn with power symbol
        p.eleType = toKicadPinEleType(cp.pinType)
        p.hide = true
        
        comp.pins[#comp.pins+1] = p
    end
end

local function parse_comp(t, symbols)
    local comp = {}
    comp.name = make_name(t[2])
    local headers = s_expand(t[4], { numParts=1, refDesPrefix=make_name})
    comp.ref = headers.refDesPrefix
    comp.partNum = headers.numParts
    comp.pins = {}
    local compPins = {}
    local compSymbols = {}
    for i=5, #t do
        local e = t[i]
        if      ele_is(e, "compPin") then
            local compPin = s_expand(e, { [2]="pinNum", pinName = 1, partNum=1,symPinNum=1,pinType=1 })
            compPins[#compPins+1] = compPin
        elseif  ele_is(e, "attachedSymbol") then
            local symbol = s_expand(e, {partNum=1,symbolName=1 })
            local sym = symbols[symbol.symbolName]
            if sym then
                if compSymbols[symbol.partNum] then
                    LogI("Part("..symbol.partNum..") redefined in ".. comp.name)
                end
                compSymbols[symbol.partNum] = sym
            end
        elseif  ele_is(e, "attachedPattern") then
            local fp = s_expand(e, {patternName=1})
            comp.footPrint = fp.patternName
        end
    end
    local disName = false
    local disNum = false
    local hide_pins = {}
    for i=1,#compPins do
        local cp = compPins[i]
        local sym = compSymbols[cp.partNum]
        if sym then
            local p = sym:createPin(cp)
                if p then
                if p.disName then disName = true end
                if p.disNum then disNum = true end
                comp.pins[#comp.pins+1] = p
            end
        else
            if cp.partNum == '0' then
                hide_pins[#hide_pins+1] = cp
            else
                LogI("Pin " .. cp.pinNum .. " fail to get part " .. cp.partNum)
            end
        end
    end
    
    comp.drawPinNo = disNum and "Y" or "N"
    comp.drawPinName = disName and "Y" or "N"
    comp.symbols = compSymbols
    buildCompHidePins(comp, hide_pins)
    comp.toSymbol = compToSymbol
    return comp
end

local function colloect_comp(t, symbols)
    local comps = {}
    for i=1,#t do
        local e = t[i]
        if ele_is(e, "compDef") then
            comps[#comps+1] = parse_comp(e, symbols)
        end
    end
    return comps
end

local function collect_part_and_symbol(lib_table, pads)
    local parts = {}
    local symbols = {}
    symbols.count = 0
    for i,v in s_elements(lib_table, "patternDefExtended") do
        parts[#parts+1] = build_part(v, pads)
        progress_hook(i,#lib_table)
    end
    for i,v in s_elements(lib_table, "symbolDef") do
        local name,sym = build_symbol(v)
        symbols[name] = sym
        symbols.count = symbols.count + 1
        progress_hook(i,#lib_table)
    end
    return parts, symbols
end

local function mk_empty_dir(dir)
    exec('rm -r "' .. dir..'"')
    exec('rd "' .. dir .. '" /Q /S')
    exec('mkdir "' .. dir .. '"')
end
function removeParentheses(n)
    local pn = string.gsub(n, "%(", "[")
    pn = string.gsub(pn, "%)", "]")
    return pn
end
function removeSpaces(n)
    local pn = string.gsub(n, "[%s]+", " ")
    pn = string.gsub(pn, " ", "_")
    return pn
end

local function out_put_footprint(parts, lib_name, out_path)
    if out_path ~= "" then out_path = out_path .. "/" end
    local lib_path = out_path .. lib_name .. ".pretty"
    mk_empty_dir(lib_path)
    lib_name = lib_name or "test_lib"
    for i=1, #parts do
        local p = parts[i]
        local part_name = p.name
        local file_name = lib_path .. "\\" .. part_name .. ".kicad_mod"
        local f,err = io.open(file_name, "w+")
        if f then
            local pn = removeParentheses(part_name)
            f:write("(module "..lib_name..":"..pn.." (layer F.Cu) (tedit 58AA841A)\n")
            for j=1,#p.pads do
                local pd = p.pads[j]
                f:write("  " .. pd:tostring() .. "\n")
            end
            for j=1,#p.graphs do
                local g = p.graphs[j]
                f:write("  " .. g:tostring() .. "\n")
            end
            f:write(")")
            f:close()
        else
            LogI(err)
        end
        progress_hook(i,#parts)
    end
    local f,err = io.open(lib_path .."\\readme.txt", "w+")
    if f then
    f:write([[
These foot prints are auto generate from ]]..lib_name .. [[
 by the pcad library tool from XToolbox.org
]])
    f:close()
    end
end

local function out_put_symbol_lib(comps, outfile, libname, libname4symbol)
    local f,err = io.open(outfile, "w+")
    if f then
        f:write([[
EESchema-LIBRARY Version 2.4
#encoding utf-8
]])
        for i=1,#comps do
            local r = comps[i]:toSymbol(libname4symbol)
            f:write(r)
            --LogI(r )
        end
        f:write("\n#\n#End Library")
        f:close()
    else
        LogI(err)
    end
end

local function get_file_name(file)
    local p = string.find(file, "[^/\\]+$")
    local r = file
    if p and p>2 then
        r = string.sub(file,p)
    end
    p = string.find(r, "[^%.]+$")
    if p and p<#r then
        r = string.sub(r,1,p-2)
    end
    r = string.gsub(r, "([%(%) ])", {["("] = "_", [")"] = "", [" "] = "_"})
    return r
end
function parse_pcad_lib(filename, libname, outpath, progress, log_info, libname4symbol)
    progress_hook = progress or progress_hook
    LogI = log_info or LogI
    local r = parse_s_file(filename, progress)
    if not r then
        LogI("Fail to parse file <" .. filename..">")
        return
    end
    for i=1,#r[1] do
        if ele_is(r[1][i], "fileUnits") then
            global_units = string.lower(r[1][i][2])
        end
    end
    
    local isSymbol = false
    local isFootPrint = false
    for i=1,#r[2] do
        if ele_is(r[2][i], "symbolDef") then
            isSymbol = true
        elseif ele_is(r[2][i], "patternDefExtended") then
            isFootPrint = true
        end
    end
    
    if isSymbol and isFootPrint then
        LogI("File contains both symbol and footprint, maybe something error")
        return
    end
    if (not isSymbol) and (not isFootPrint) then
        LogI("File don't contains either symbol and footprint, maybe something error")
        return
    end
    global_symbol_mode = isSymbol
    
    --LogI("global_units: ", global_units)
    local pads,fonts = collect_pad_font(r[2])
    global_fonts = fonts
    if global_symbol_mode then
        local font = fonts['"(PinStyle)"']
        if font then
            if font.w > 50 then
                font.w = 50
                font.h = 50
            end
        end
        font = fonts['"(PartStyle)"']
        if font then
            if font.w > 50 then
                font.w = 50
                font.h = 50
            end
        end
        font = fonts['"(Default)"']
        if font then
            if font.w > 50 then
                font.w = 50
                font.h = 50
            end
        end
    else
        local font = fonts['"(Default)"']
        if font then
            if  tonumber(font.w) > 1 then
                font.w = 1
                font.h = 1
                font.thickness = 0.15
            end
        end
    end
    
    local parts,symbols = collect_part_and_symbol(r[2], pads)
    
    --LogI("get ", #parts, " parts  ", symbols.count, "  symbols")
    if libname == "" then
        libname = get_file_name(filename)
    end
    if outpath == "" then
        local p = string.find(filename, "[^/\\]+$")
        if p and p>2 then
            outpath = string.sub(filename,1,p-2)
        end
    end
    if #parts > 0 then
        out_put_footprint(parts, libname,outpath)
        local outFile = libname .. ".pretty"
        if outpath ~= "" then
            outFile = outpath .. "/" .. outFile
        end
        LogI("Convert done, generate foot print library ".. outFile)
        
    end
    if symbols.count > 0 then
        local comps = colloect_comp(r[2], symbols)
        --LogI("Get ", #comps, " components")
        local outFile = libname .. ".lib"
        if outpath ~= "" then
            outFile = outpath .."/".. libname .. ".lib"
        end
        out_put_symbol_lib(comps, outFile, libname, libname4symbol)
        LogI("Convert done, generate symbol library ".. outFile)
    end
    if symbols.count < 1 and #parts < 1 then
        LogI("No symbol or parts found in file ".. filename)
    end
end


