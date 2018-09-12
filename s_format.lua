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
