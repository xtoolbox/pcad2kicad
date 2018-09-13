require("pcad_lib")
if #arg < 1 then
    print("usage:")
    print("lua pcad2kicad.lua <input pcad library name> [output library name] [output library path]")
    os.exit(-1)
end
local function log_info(...)
    local r = "\n"
    for k,v in pairs({...}) do
        r = r .. "  " .. tostring(v)
    end
    print(r)
end
local function progress(cur,total)
    io.write("\r","Current/Total:",cur,"/",total);
end
parse_pcad_lib(arg[1], arg[2] or "", arg[3] or "", progress, log_info)