#!/bin/lua
-- lua command line tool to convert AD symbol library to KiCad, require 7z
require("ad_lib")
local function usage()
    print("usage:")
    print("  Signle file mode:")
    print("    lua ad2kicad.lua <inName> [outName] [fpLib]")
    print("       inName  - Input AD schlib file name")
    print("       outName - Output KiCad symbol library file name, optional")
    print("       fpLib   - footprint library name for symbol, optional")
    print("  Multiple file mode:")
    print("    lua ad2kicad.lua --batch <inPath> [outPath] [fpLib] [prefix] [O1=N1[ O2=N2...]]")
    print("       inPath  - Input AD schlib folder location")
    print("       outPath - Output KiCad symbol library folder location, optional")
    print("       fpLib   - footprint library name for symbol, optional")
    print("       prefix  - output library name prefix, optional")
    print("       Ox=Nx   - replace library name Ox with Nx, optional")
    os.exit(-1)
end

if #arg < 1 then
    usage()
end

function getLog(name)
    local res = {}
    res.fp = io.open(name, "a+")
    res.log = function(f, ...)
        if f.fp then
            f.fp:write("[",os.date(), "]", ...)
        end
        io.write(...)
        io.flush()
    end
    res.write = function(f, ...)
        if f.fp then
            f.fp:write(...)
        end
        io.write(...)
        io.flush()
    end
    res.close = function(f)
        if f and f.fp then
            f.fp:close()
        end
    end
    return res
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
        end)
        i = i + 1
    end
    local files = get_file_names(inPath, "*.SchLib")
    print("Batch process "..#files.. " files")
    local flog = getLog(outPath.."/convert.log")
    flog:log("Start convert AD schlibs to kicad lib\n")
    flog:log("Command line: lua ad2kicad.lua ")
    for i,v in ipairs(arg) do flog:write(v, " ") end
    flog:write("\n")
    _G.logE = function(...)
        local s = ""
        for i,v in ipairs({...}) do
            s = s .. tostring(v) .. " "
        end
        flog:write("ERROR:  ", s, "\n")
    end
    for i=1,#files do
        local libName = files[i]
        local fname = libName .. ".SchLib"
        if reName[libName] then
            libName = reName[libName]
        elseif libPrefix and libPrefix ~= "" then
            libName = libPrefix .. "_" .. libName
        end
        libName = outPath .. "/" .. libName .. ".lib"
        convert_schlib(inPath.."/"..fname, libName, symbolLib, log_info)
        flog:log("Convert " .. inPath.."/"..fname .. " to " .. libName .. "   done  \n")
    end
    flog:log("Convert done\n")
    flog:close()
else
    convert_schlib(arg[1], arg[2] or "", arg[3] or "", log_info)
end
