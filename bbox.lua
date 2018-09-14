local function splitBB(bb)
    return bb[1][1], bb[1][2], bb[2][1], bb[2][2]
end
local function packBB(l,t,r,b)
    return {{l,t},{r,b}}
end
local PI = math.asin(1)
function toArc(angle)
    return angle/90*PI
end

local function rotate_p2p(ox,oy, mx,my, rotate)
    local rot = rotate and toArc(rotate) or toArc(0)
    ox, oy = KiCoord(ox, oy)
    mx, my = KiCoord(mx, my)
    local nx = (mx - ox)*math.cos(rot) - (my - oy)*math.sin(rot) + ox
    local ny = (mx - ox)*math.sin(rot) + (my - oy)*math.cos(rot) + oy
    return KiCoord(nx,ny)
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
    splitBB = splitBB,
    packBB = packBB,
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

return BBOX
