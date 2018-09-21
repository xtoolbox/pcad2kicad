---------------------------------------------------------------------
-- guess 3d model
---------------------------------------------------------------------
-- lua guess3d.lua <footprint name> <pin 1 position> <3d model path>
require("util")
require("s_format")
local function progress(cur,total)
    io.write("\r","Current/Total:", string.format("%8d/%8d",cur,total));
end

local prefix_map = {
    C = 1,
    D = 1,
    R = 1,
    L = 1,
    LED = 1,
    CP = 1,
    Crystal = 1,
    QFN = 1,
    DFN = 1,
    LQFP = 1,
    TSSOP = 1,
    SSOP = 1,
    SO = 1,
    SOT = 1,
    SOIC = 1,
}

function appendKey(r,k)
    if not r[k] then
        r[k] = k
        r[#r+1] = k
    end
end

function is_array(p)
    local r = string.upper(p)
    local res,res1
    string.gsub(r, "(%dX)([%d]+)$", function(v,v1)
        v = string.gsub(v,"%.", "")
        res,res1 = v,v1
    end)
    if res then return res,res1 end
    string.gsub(r, "[LCR]X(%d)$", function(v)
        v = string.gsub(v,"%.", "")
        res = v .. "X"
    end)
    return res,res1
end

function is_pitch(p)
    local r = string.upper(p)
    local res
    string.gsub(r, "PITCH([%d%.]+)", function(v)
        v = string.gsub(v,"%.", "")
        res = v .. "P"
    end)
    if res then return res end
    string.gsub(r, "P([%d%.]+)", function(v)
        v = string.gsub(v,"%.", "")
        res = v .. "P"
    end)
    if res then return res end
    string.gsub(r, "([%d%.]+)P", function(v)
        v = string.gsub(v,"%.", "")
        res = v .. "P"
    end)
    return res
end

function moreKey(r,v)
    local p1 = string.find(v, "-1EP")
    if p1 then
        appendKey(r,'1EP')
        appendKey(r,'EP')
        appendKey(r,string.sub(v, 1, p1-1))
    end
    if v == "1EP" then
        appendKey(r,'EP')
    end
    
    string.gsub(v, "(SMD)-(%d+)", function(v1,v2)
        appendKey(r,v1)
        appendKey(r,v2)
    end)
    string.gsub(v, "(%d+)-(%d+)PIN", function(v1,v2)
        appendKey(r,v1)
        appendKey(r,v2.."P")
    end)
    p1 = string.find(v, "VQFN")
    if p1 then
        appendKey(r,string.sub(v,2))
    end
    
    
    local t = is_pitch(v)
    if t then appendKey(r, t) end
    local t1,t2 = is_array(v)
    if t1 then
        appendKey(r, t1)
        appendKey(r, "ARRAY")
    end
    if t2 then
        appendKey(r, t2)
    end
end



function splitKey(n)
    local r = {}
    local cls = nil
    string.gsub(n, "([^_%(%)]+)", function(v)
        v = string.upper(v)
        cls = cls or v
        moreKey(r,v)
        appendKey(r,v)
    end)
    return cls, r
end

local keyTable = {}
local nameTable = {}

local function parse3Dname(path, name)
    local cls, keys = splitKey(name)
    --if not prefix_map[cls] then return end
    for k,v in pairs(keys) do
        if not keyTable[k] then
            keyTable[k] = {}
        end
        keyTable[k][name] = path
    end
end



local stdF = {
    write = function(t,...)
        io.write(...)
    end
}

local function dumpKey(f)
    f = f or stdF
    f:write("local keyTable = {\n")
    for k,v in pairs(keyTable) do
        f:write('  ["'..k..'"] = {\n')
        for m,n in pairs(v) do
            n = string.gsub(n, "\\", "/")
            f:write("    ['" .. m .. "'] = '" .. n .. "',\n")
        end
        f:write('  },\n')
    end
    f:write("}\n")
end

local function dumpName(f)
    f = f or stdF
    f:write("local nameTable = {\n")
    for k,v in pairs(nameTable) do
        f:write('  ["'..k..'"] = {\n')
        for m,n in pairs(v) do
            f:write("    ['" .. m .. "'] = '" .. n .. "',\n")
        end
        f:write('  },\n')
    end
    f:write("}\n")
end


function  gather3DNames(path3D, force)
    local f = nil
    if not force then
        f = io.open("keyMap.lua", "r")
    end
    if f then
        local r = require("keyMap")
        nameTable = r.nameTable
        keyTable = r.keyTable
        f:close()
    else
        local path = get_file_names(path3D,"*.3dshapes")
        for i,v in ipairs(path) do
            local fpath = path3D .. "/" .. v .. ".3dshapes"
            local fnames = get_file_names(fpath, "*.step")
            for j,n in ipairs(fnames) do
                local cls, keys = splitKey(n)
                keys["__path"] = string.gsub(fpath, "\\", "/")
                nameTable[n] = nameTable[n] or keys
                parse3Dname(fpath, n)
            end
            fnames = get_file_names(fpath, "*.wrl")
            for j,n in ipairs(fnames) do
                local cls, keys = splitKey(n)
                keys["__path"] = string.gsub(fpath, "\\", "/")
                nameTable[n] = nameTable[n] or keys
                parse3Dname(fpath, n)
            end
        end
        f = io.open("keyMap.lua", "w+")
        dumpName(f)
        dumpKey(f)
        f:write("return {nameTable = nameTable, keyTable = keyTable}")
        f:close()
    end
    return nameTable, keyTable
end

local function find3DModel(name)
    local cls, keys = splitKey(name)
    --print(cls)
end

function has3DModel(fp)
    for i,e in s_elements(fp[1], "model") do
       return true 
    end
    return false
end
local function getFpPad1(fp)
    for i, e in s_elements(fp[1], "pad") do
        if e[2] == '1' or e[2] == 'K' or e[2] == 'A1' or e[2] == 'A2' or e[2] == 'A3' then
            local r = s_expand(e, {at = function(x,y)
                return {x=tonumber(x),y=tonumber(y)}
            end})
            return r.at.x, r.at.y
        end
    end
    print("Fail to find pad 1 in " .. tostring(fp[1][2]))
    return nil
end

local function fpRotation(x,y)
    if x and y then
        if x<0 then
            if y < 0 then
                return 0
            elseif y > 0 then
                return -90
            else
                return 0
            end
        elseif x>0 then
            if y < 0 then
                return 90
            elseif y>0 then
                return 180
            else
                return 180
            end
        else
            if y <= 0 then
                return 0
            else
                return 180
            end
        end
    end
    return 0
end

local temp = [[
  (model $name
    (at (xyz 0 0 0))
    (scale (xyz 1 1 1))
    (rotate (xyz 0 0 $rotate))
  )
]]

function append3DModel(name, rotate, modelName)
    local f = io.open(name, "r")
    if f then
        local t = f:read("*a")
        f:close()
        local i = #t
        while i>0 do
            if string.sub(t,i,i) == ")" then
                local tt = {
                    name = modelName,
                    rotate = rotate
                }
                t = string.sub(t,1,i-1)
                t = t .. string.gsub(temp, "%$(%w+)", tt)
                t = t .. ")"
                f = io.open(name, "w+")
                if f then
                    f:write(t)
                    f:close()
                end
                return
            end
            i = i - 1
        end
    end
end

function getModRotate(name)
    local s = parse_s_file(name)
    if not s then print("Fail to parse mod file " .. v) end
    local x,y = getFpPad1(s)
    local rotate = fpRotation(x,y)
    return rotate
end

local function loadFps(path)
    local names = get_file_names(path,"*.kicad_mod")
    for i,v in ipairs(names) do
        local modFile = path .. "/"..v..".kicad_mod"
        local s = parse_s_file(modFile)
        if not s then print("Fail to parse mod file " .. v) end
        local x,y = getFpPad1(s)
        local rotate = fpRotation(x,y)
        local modelName = find3DModel(v)
        if modelName and not has3DModel(s) then
            append3DModel(modFile, rotate, modelName)
        end
    end
    
end

local function usage()
    print("usage:")
    print("  lua guess3d.lua <fpPath> <3dPath>")
    print("    <fp_name> - kicad footprint path")
    print("    <3dPath>  - kicad 3d model path")
    os.exit(-1)
end

if arg then
if #arg < 2 then
    usage()
else
    local force = false
    for i,v in pairs(arg) do
        if v == 'force' then
            force = true
        end
    end
    gather3DNames(arg[2], force)
    loadFps(arg[1])
end
end


