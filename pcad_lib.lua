require("s_format")
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
function tokicad(value, quit)
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

local PI = math.asin(1)
local function toArc(angle)
    return angle/90*PI
end

local function splitBB(bb)
    return bb[1][1], bb[1][2], bb[2][1], bb[2][2]
end
local function packBB(l,t,r,b)
    return {{l,t},{r,b}}
end

local function rotate_p2p(ox,oy, mx,my, rotate)
    local rot = rotate and toArc(rotate) or toArc(0)
    ox, oy = ox, -oy
    mx, my = mx, -my
    local nx = (mx - ox)*math.cos(rot) - (my - oy)*math.sin(rot) + ox
    local ny = (mx - ox)*math.sin(rot) + (my - oy)*math.cos(rot) + oy
    return nx,-ny
end
local function min_max(...)
    local mi,ma
    for k,v in pairs({...}) do
        if not mi then mi = v end
        if not ma then ma = v end
        if mi > v then mi = v end
        if ma < v then ma = v end
    end
    return mi,ma
end
local BBOX = {
    create = function(w,h,x,y)
        x = x or 0
        y = y or 0
        return packBB(-w/2+x, -h/2+y, w/2+x, h/2+y)
    end,
    moveTo = function(bb, x, y)
        local l,t,r,b = splitBB(bb)
        if l>r or t>b then
            LogI("BBox error when move", l,t,r,b)
        end
        return packBB(-(r-l)/2 + x, 
                      -(b-t)/2 + y,
                       (r-l)/2 + x, 
                       (b-t)/2 + y)
    end,
    merge = function(bb1, bb2)
        if bb1 and bb2 then
            local l1,t1,r1,b1 = splitBB(bb1)
            local l2,t2,r2,b2 = splitBB(bb2)
            if l1>r1 or t1>b1 then
                LogI("BBox1 error when merge", l1,t1,r1,b1)
                return nil
            end
            if l2>r2 or t2>b2 then
                LogI("BBox2 error when merge", l2,t2,r2,b2)
                return nil
            end
            l1 = l1<l2 and l1 or l2
            t1 = t1<t2 and t1 or t2
            r1 = r1>r2 and r1 or r2
            b1 = b1>b2 and b1 or b2
            return packBB(l1,t1,r1,b1)
        else
            return (bb1 and bb1 or bb2)
        end
    end,
    rotate = function(bb, rot)
        rot = rot or 0
        local l,t,r,b = splitBB(bb)
        if l>r or t>b then
            LogI("BBox error when rotate", l,t,r,b)
        end
        local ox, oy = (r+l)/2, (b+t)/2
        x1,y1 = rotate_p2p(ox,oy,l,t,rot)
        x2,y2 = rotate_p2p(ox,oy,r,b,rot)
        x3,y3 = rotate_p2p(ox,oy,l,b,rot)
        x4,y4 = rotate_p2p(ox,oy,r,t,rot)
        local l1,r1 = min_max(x1,x2,x3,x4)
        local t1,b1 = min_max(y1,y2,y3,y4)
        return packBB(l1,t1,r1,b1)
    end
}

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
            local ft,h,thick
            for i=2, #t[3] do
                local fe = t[3][i]
                if ele_is(fe, "fontType") then
                    ft = fe[2]
                elseif ele_is(fe, "fontHeight") then
                    h = tokicad(fe[2])
                elseif ele_is(fe, "strokeWidth") then
                    thick = tokicad(fe[2])
                end
            end
            if ft == "Stroke" then
                v = {w=h,h=h,thickness = thick}
            end
        end
    end
    v.tostring = fontToString
    return n,v
end

-- collect all pad and font style in the library file
local function collect_pad_font(lib_table)
    local pads = {}
    local fonts = {}
    pads.count = 1
    fonts.count = 1
    local hk = 1
    for i=1,#lib_table do
        local t = lib_table[i]
        if ele_is(t, "padStyleDef") then
        --if type(t) == "table" then
            --if t[1] == "padStyleDef" then
                local k,v = build_pad(t)
                pads[k] = v
                pads.count = pads.count + 1
            --end
        elseif ele_is(t, "textStyleDef") then
            local k,v = build_font(t)
            fonts[k] = v
            fonts.count = fonts.count + 1
        end
        hk = hk + 1
        if hk>20 then
            hk = 1
            progress_hook(i,#lib_table)
        end
    end
    LogI("Get ", pads.count, " pads, ", fonts.count, " fonts")
    pads.create_pad = create_part_pad
    return pads, fonts
end

local function parse_pads(t, pads)
    local r = {}
    for i=1,#t do
        local p = t[i]
        if ele_is(p, "pad") then
            local num,x,y,pn,rotate,num2
            for j=2,#p do
                if ele_is(p[j], "padNum") then
                    num = p[j][2]
                elseif ele_is(p[j], "padStyleRef") then
                    pn = p[j][2]
                    --if pads[pn] then
                    --    pad.data = pads[pn]
                    --else
                    --    LogI("Pad ", pn , " not found in part")
                    --end
                elseif ele_is(p[j], "pt") then
                    x = tokicad(p[j][2])
                    y = tokicad(p[j][3])
                elseif ele_is(p[j], "rotation") then
                    rotate = tokicad(p[j][2].."deg")
                elseif ele_is(p[j], "defaultPinDes") then
                    num2 = p[j][2]
                    num2 = string.sub(num2,2,-2)
                    if #num2 == 0 then num2 = [[""]] end
                else
                    LogI("Un-processed element of pad in ")
                end
            end
            num = num2 or num
            x,y = KiCoord(x,y)
            r[#r+1] = pads:create_pad(pn,num,x,y,rotate)
        end
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
local function toKicadArc(x,y,r,startAngle, sweepAngle, width, layer)
    local res = {}
    sweepAngle = tonumber(sweepAngle)
    res.sx,res.sy,res.ex,res.ey,res.angle,res.width = x,y, x+math.cos(toArc(startAngle))*r, y-math.sin(toArc(startAngle))*r, -sweepAngle, width
    res.layer = layer
    res.tostring = arcToString
    res.bbox = { {res.sx-r, res.sy-r}, {res.sx+r, res.sy+r} }
    return res
end

local function lineToString(line)
    return string.gsub("(fp_line (start $sx $sy) (end $ex $ey) (layer $layer) (width $width))", "%$(%w+)", line)
end
local function toKicadLine(pts, width, layer)
    local r = {}
    r.sx = pts[1][1]
    r.sy = pts[1][2]
    r.ex = pts[2][1]
    r.ey = pts[2][2]
    r.layer = layer
    r.tostring = lineToString
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
local function toKicadPoly(pts, layer)
    local r = {}
    r.pts = pts
    r.layer = layer
    r.tostring = polyToString
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
    return string.gsub([[
(fp_text $t $value ($pos) (layer $layer)$hidestr
    (effects ($fontstr))
  )]], "%$(%w+)", text)
end
local function toKicadText(x, y, rotate, text_type, value, font, hide, layer)
    local r = {}
    local str = value
    if string.find(value, '"') then
        str = string.sub(str, 2,-2)
    end
    local l = #str
    local rot = rotate and toArc(rotate) or toArc(0)
    
    local lx = font.w*l*(1/1.69333)
    local ly = font.h*(1/1.69333)
    local lr = math.sqrt(lx*lx + ly*ly)
    -- get the orignal position in normal coord
    local ox, oy = x, -y
    -- get the text mid point
    local mx, my = ox + lx/ 2, oy + ly/ 2
    -- rotate the mid point by org point
    local nx = (mx - ox)*math.cos(rot) - (my - oy)*math.sin(rot) + ox
    local ny = (mx - ox)*math.sin(rot) + (my - oy)*math.cos(rot) + oy
    -- covert back to kicad coord
    r.x = nx
    r.y = -ny
    r.rotate = rotate
    r.value = value
    r.t = text_type
    r.font = font
    r.hide = hide
    r.layer = layer
    r.tostring = textToString
    return r
end

local function parse_graph(t, part)
    part.graphs = part.graphs or {}
    local graphs = part.graphs
    local l = t[2][2]
    local layer = layers_t[l]
    if layer then
        for j=3, #t do
            local gv = t[j]
            if gv[1] == "arc" then
                local x,y,r,startAngle,sweepAngle, width
                for i=2,#gv do
                    if ele_is(gv[i], "pt") then
                        x = tokicad(gv[i][2])
                        y = tokicad(gv[i][3])
                    elseif ele_is(gv[i], "radius") then
                        r = tokicad(gv[i][2])
                    elseif ele_is(gv[i], "startAngle") then
                        startAngle = tokicad(gv[i][2].."deg")
                    elseif ele_is(gv[i], "sweepAngle") then
                        sweepAngle = tokicad(gv[i][2].."deg")
                    elseif ele_is(gv[i], "width") then
                        width = tokicad(gv[i][2])
                    else
                        LogI("Un-processed element of arc graph in ", part.name)
                    end
                end
                x,y = KiCoord(x,y)
                graphs[#graphs+1] = toKicadArc(x,y,r,startAngle,sweepAngle,width,layer)
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
                    else
                        LogI("Un-processed element of line graph in ", part.name)
                    end
                end
                graphs[#graphs+1] = toKicadLine(pts,width,layer)
            elseif gv[1] == "pcbPoly" then
                local pts = {}
                for i=2,#gv do
                    if ele_is(gv[i], "pt") then
                        local x,y = tokicad(gv[i][2]), tokicad(gv[i][3])
                        x,y = KiCoord(x,y)
                        pts[#pts+1] = {x,y}
                    else
                        LogI("Un-processed element of poly graph in ", part.name)
                    end
                end
                graphs[#graphs+1] = toKicadPoly(pts,layer)
            elseif (gv[1] == "attr") or (gv[1] == "text") then
                local attr_t,x,y,rotate,hide,font,value
                attr_t = gv[2]
                value = gv[3]
                for i=4,#gv do
                    if ele_is(gv[i], "pt") then
                        x,y = tokicad(gv[i][2]),tokicad(gv[i][3])
                    elseif ele_is(gv[i], "rotation") then
                        rotate = tokicad(gv[i][2].."deg")
                    elseif ele_is(gv[i], "isVisible") then
                        hide = not (gv[i][2] == "True")
                    elseif ele_is(gv[i], "textStyleRef") then
                        font = global_fonts[gv[i][2]]
                        if not font then
                            LogI("Font (" .. gv[i][2] ..") not found in ", part.name)
                        end
                    else
                        LogI("Un-processed element of attr in ", part.name)
                    end
                end
                
                if gv[1] == "text" then
                    x,y = tokicad(gv[2][2]),tokicad(gv[2][3])
                end
                x,y = KiCoord(x,y)
                if attr_t == [["RefDes"]] then
                    graphs[#graphs+1] = toKicadText(x,y,rotate, "reference", "REF**", font, hide,"F.SilkS")
                elseif attr_t == [["Type"]] then
                    graphs[#graphs+1] = toKicadText(x,y,rotate, "value", part.name, font, hide,"F.Fab")
                elseif gv[1] == "text" then
                    graphs[#graphs+1] = toKicadText(x,y,rotate, "user", value, font, hide, layer)
                else
                    LogI("Unknown attr type " .. attr_t  .. " in", part.name)
                end
            else
                LogI("Unknown graph type (" .. gv[1] .. ") in ", part.name)
            end
        end
    else
        LogI("Unknown layer(" .. l .. ") in ", part.name)
    end
end

local function add_bbox_line(dest, bbox, layer, width)
    layer = layer or "F.CrtYd"
    width = width or 0.05
    local l,t,r,b = splitBB(bbox)
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

local function make_name(n)
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
    n = string.gsub(n, "([%(%) ])", {["("] = "_", [")"] = "", [" "] = "_"})
    r.name = n
    for i=1,#graph do
        local t = graph[i]
        if ele_is(t, "multiLayer") then
            r.pads = parse_pads(t, pads)
        elseif ele_is(t, "layerContents") then
            parse_graph(t, r)
        end
    end
    create_part_bbox(r)
    return r
end

local function collect_part(lib_table, pads)
    local r = {}
    for i=1,#lib_table do
        local t = lib_table[i]
        if type(t) == "table" then
            if t[1] == "patternDefExtended" then
                local v = build_part(t, pads)
                r[#r+1] = v
            end
        end
        progress_hook(i,#lib_table)
    end
    return r
end

local function mk_empty_dir(dir)
    os.execute("del " .. dir .. " /Q")
    os.execute("mkdir " .. dir)
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
            f:write("(module "..lib_name..":"..part_name.." (layer F.Cu) (tedit 58AA841A)\n")
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

function parse_pcad_lib(filename, libname, outpath, progress, log_info)
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
    
    _G.pcad = r
    
    
    --for k,v in pairs(pads) do
    --    log(k, print_pad(v,1, 1.12, 3.34))
    --end
    
    --[[
    progress_hook = function() end
    LogI = function(...) log(...) end
    _G.pcad_contimue = function()
    --]]
    LogI("global_units: ", global_units)
        local pads,fonts = collect_pad_font(r[2])
        global_fonts = fonts
        local parts = collect_part(r[2], pads)
        
        LogI("get ", #parts, " parts")
        if libname == "" then
            libname = make_name(r[2][2])
        end
        if outpath == "" then
            local p = string.find(filename, "[^/\\]+$")
            if p and p>2 then
                outpath = string.sub(filename,1,p-2)
            end
        end
        out_put_footprint(parts, libname, outpath)
        LogI("Convert done, library <"..libname.. "> generate in folder <" .. outpath .. ">")
        --[[
        for i=1, 10 do
            local p = parts[i]
            --log(p.name)
            log("(module LC_Lib:"..p.name.." (layer F.Cu) (tedit 58AA841A)")
            for j=1,#p.pads do
                local pd = p.pads[j]
                log("  " .. pd:tostring())
            end
            for j=1,#p.graphs do
                local g = p.graphs[j]
                log("  " .. g:tostring())
            end
            log(")")
        end
        --]]
    --end
end


--[[
function test_bbox()
    local bb = BBOX.create(2,2)
    log(splitBB(bb))
    bb = BBOX.moveTo(bb,0,0)
    log(splitBB(bb))
    bb = BBOX.rotate(bb, 180)
    log(splitBB(bb))
end
test_bbox()
--]]

