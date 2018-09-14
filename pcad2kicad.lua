require("pcad_lib")
local function usage()
    print("usage:")
    print("  Signle file mode:")
    print("    lua pcad2kicad.lua <input pcad library name> [output library name] [output library path] [footprint lib for symbol]")
    print("  Multiple file mode:")
    print("    lua pcad2kicad.lua --batch <input folder> [output folder] [footprint lib for symbol] [out lib prefix] [orgname=newname]")
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
local function get_file_names(folder, filter)
    local files = {}
    local t = io.popen('dir "'.. folder .. '\\' ..filter .. '"',"r")
    if t then 
        local r = t:read("*a")
        local p1,p2,f = string.find(r, "[0-9/]+%s+[0-9:]+%s+[0-9,]+%s+([%w _]+)%.%w+")
        while p1 do
            files[#files+1] = f
            p1,p2,f = string.find(r, "[0-9/]+%s+[0-9:]+%s+[0-9,]+%s+([%w _]+)%.%w+",p2+1)
        end
        t:close()
    end
    return files
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
            --print(orgName, "=", newName)
        end)
        i = i + 1
    end
    local files = get_file_names(inPath, "*.lia")
    print("Batch process "..#files.. " files")
    for i=1,#files do
        local libName = files[i]
        --print(libName)
        local fname = libName .. ".lia"
        if reName[libName] then
            libName = reName[libName]
        elseif libPrefix and libPrefix ~= "" then
            libName = libPrefix .. "_" .. libName
        end
        
        --print("Convert <".. inPath.."/"..fname .. "> to <"..libName..">" .. " in <"..outPath .. ">")
        parse_pcad_lib(inPath.."/"..fname, libName, outPath, progress, log_info, symbolLib)
    end
    
    
else
    parse_pcad_lib(arg[1], arg[2] or "", arg[3] or "", progress, log_info, arg[4])
end