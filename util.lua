
function exec(command)
    local t = io.popen(command)
    t:close()
end

local patten =  "[0-9/]+%s+[0-9:]+%s+[0-9,%w<>]+%s+([%w%-%(%) _%.]+)%.%w+"
function get_file_names(folder, filter)
    local files = {}
    local t = io.popen('dir "'.. folder .. '\\' ..filter .. '"',"r")
    if t then 
        local r = t:read("*a")
        local p1,p2,f = string.find(r, patten)
        while p1 do
            files[#files+1] = f
            p1,p2,f = string.find(r, patten,p2+1)
        end
        t:close()
    end
    return files
end