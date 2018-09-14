-- a simple script to parse the s-expression file
local sub = function(s,p)
    return string.sub(s,p,p)
end

local function isquote(s, pos)
    return (string.sub(s, pos, pos) == '"') or (string.sub(s, pos, pos) == "'")
end
local function isLPar(s,pos)
    return (string.sub(s, pos, pos) == '(')
end
local function isRPar(s,pos)
    return (string.sub(s, pos, pos) == ')')
end
local function isSpace(s, pos)
    local c = string.sub(s, pos, pos)
    return c == ' ' or c == '\t' or c == '\r' or c == '\n'
end
local function skip_space(s,pos)
    for i=pos,#s do
        if not isSpace(s, i) then
            return i
        end
    end
    return #s
end

local s_parse_progress = function(current, total) end
local get_list_data

function get_atom(s, pos)
    pos = skip_space(s,pos)
    if isquote(s,pos) then
        for i=pos+1,#s do
            if isquote(s,i) then
                return string.sub(s,pos,i), i+1
            end
        end
    elseif isLPar(s,pos) then
        return get_list_data(s, pos+1)
    else
        for i=pos+1, #s do
            if isSpace(s,i) or isRPar(s,i) then
                return string.sub(s,pos,i-1),i
            end
        end
    end
    error("can not reach here")
end

local cnt = 1
function get_list_data(s, pos)
    pos = skip_space(s, pos)
    if cnt > 100 then
        s_parse_progress(pos,#s)
        cnt = 0
    end
    cnt = cnt + 1
    local r = {}
    local e
    while pos < #s do
        r[#r+1],e = get_atom(s,pos)
        --LogI("test", sub(s,pos), r[#r])
        pos = skip_space(s,e)
        if isRPar(s,pos) then
            return r,pos+1
        end
    end
    return r,pos
end
local function find_s_data(s, pos)
    local r = {}
    while pos<#s do
        if isLPar(s,pos) then
            r[#r+1],pos = get_list_data(s, pos+1)
        end
        pos = pos + 1
    end
    return r
end

-- expand the k,v pairs in the table
function s_expand(t, keys, opt_keys, def_keys, full_parse)
    local r = {}
    local chk = {}
    for k,v in pairs(keys) do
        chk[k] = 0
    end
    if opt_keys then
        for k,v in pairs(opt_keys) do
            chk[k] = 1
        end
    end
    if def_keys then
        for k,v in pairs(def_keys) do
            r[k] = v
        end
    end
    for i=2,#t do
        if type(t[i]) == "table" then
            local n = t[i][1]
            local m = keys[n]
            if not m and opt_keys then m = opt_keys[n] end
            if m then
                chk[n] = chk[n] + 1
                if type(m) == "function" then
                    r[n] = m(t[i][2], t[i][3], t[i][4], t[i][5], t[i][6])
                else
                    r[n] = t[i][2]
                end
            else
               if full_parse then
                    error(n.." in map not processed")
               end
            end
        elseif keys[i] or opt_keys[i] then
            chk[i] = chk[i] + 1
            r[keys[i]] = t[i]
        elseif full_parse then
            error("index " .. i .. " in map not processed")
        end
    end
    for k,v in pairs(chk) do
        if v == 0 then
            error("Key: " .. k .. "  not processed in map")
        end
    end
    return r
end

-- iterate name elements in the array
function s_elements(array, name)
    local i = 0
    return function()
        i = i + 1
        while array[i] do
            local t = array[i]
            local key = t[1]
            if name == t[1] then
                return i,t
            end
            i = i + 1
        end
        return nil
    end
end

function parse_s_file(filename, parse_progress) 
    s_parse_progress = parse_progress or s_parse_progress
    local f = io.open(filename, "r")
    if f then
        local value = f:read("*a")
        f:close()
        return find_s_data(value,1)
    end
    return nil
end
