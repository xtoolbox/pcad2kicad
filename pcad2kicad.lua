#!/bin/lua
-- lua command line tool to convert PCAD ASCII symbol/footprint library to KiCad
require("pcad_lib")
require("util")
local function usage()
    print("usage:")
    print("  Signle file mode:")
    print("    lua pcad2kicad.lua <inName> [outName] [outPath] [fpLib]")
    print("       inName  - Input PCAD library file name")
    print("       outName - Output KiCad symbol/footprint library file name, optional")
    print("       outPath - Output KiCad symbol/footprint library folder location, optional")
    print("       fpLib   - footprint library name for symbol, optional")
    print("  Multiple file mode:")
    print("    lua pcad2kicad.lua --batch <inPath> [outPath] [fpLib] [prefix] [O1=N1[ O2=N2...]]")
    print("       inPath  - Input PCAD library folder location")
    print("       outPath - Output KiCad symbol/footprint library folder location, optional")
    print("       fpLib   - footprint library name for symbol, optional")
    print("       prefix  - output library name prefix, optional")
    print("       Ox=Nx   - replace library name Ox with Nx, optional")
    os.exit(-1)
end
if #arg < 1 then
    usage()
end
local function log_info(...)
    local r = "\n"
    for k,v in pairs({...}) do
        r = r .. "  " .. tostring(v)
    end
    print(r)
end
local function progress(cur,total)
    io.write("\r","Current/Total:", string.format("%8d/%8d",cur,total));
end

if arg[1] == "--batch" then
    if #arg < 2 then
        usage()
    end
    local inPath = arg[2]
    local outPath = arg[3] or inPath
    local symbolLib = arg[4]
    local libPrefix = arg[5]
    local i = 6
    local reName = {}
    while arg[i] do
        string.gsub(arg[i], "([^=]+)=([^=]+)", function(orgName, newName)
            reName[orgName] = newName
        end)
        i = i + 1
    end
    local files = get_file_names(inPath, "*.lia")
    print("Batch process "..#files.. " files")
    for i=1,#files do
        local libName = files[i]
        local fname = libName .. ".lia"
        if reName[libName] then
            libName = reName[libName]
        elseif libPrefix and libPrefix ~= "" then
            libName = libPrefix .. "_" .. libName
        end
        parse_pcad_lib(inPath.."/"..fname, libName, outPath, progress, log_info, symbolLib)
    end
    
    
else
    parse_pcad_lib(arg[1], arg[2] or "", arg[3] or "", progress, log_info, arg[4])
end