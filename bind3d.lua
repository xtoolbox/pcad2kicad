require("guess3d")

function match_keys(keys, kT, nT, onlyKey)
    if kT and nT and #keys > 0 then
        
        local res = {}
        local exact = {}
        if kT[keys[1]] then
            for k,v in pairs(kT[keys[1]]) do
                res[#res+1] = {k, "X"}
            end
        end
        local last_e = res
        for i=2,#keys do
            local v = keys[i]
            exact[#exact + 1] = {}
            local te = exact[#exact]
            for j,nn in ipairs(last_e) do
                n = nn[1]
                if nT[n] and nT[n][v] then
                    te[#te+1] = n
                end
            end
            last_e = te
        end
        
        if not onlyKey and #keys < 2 then
            if #res == 0 then
                local key = keys[1]
                for k,v in pairs(nT) do
                    --key = string.gsub(key, "%-", "%%%-")
                    if string.find(k,key) then
                        res[#res+1] = {k, "Y"}
                    end
                end
            end
        end
        
        local j = #exact
        local ee = 0
        while j > 0 do
            e = exact[j]
            for i,v in ipairs(e) do
                --self.modelList:addItem(QListWidgetItem(v))
                res[#res+1] = {v, tostring(ee)}
            end
            ee = ee + 1
            j = j - 1
        end
        
        table.sort(res, function(v1,v2)
            return v1[2] == v2[2] and v1[1] < v2[1] or v1[2]<v2[2]
        end)
        return res
    end
end


class "Bind3DView"(QFrame)
function Bind3DView:__init()
    QFrame.__init(self)
    self.editSysPath = QLineEdit("X:/kicad-packages3D")
    self.btnSysPath = QPushButton("...")
    self.edit3DPath = QLineEdit("X:/kicad-packages3D")
    self.btn3DPath = QPushButton("...")
    self.editModPath = QLineEdit("X:/lc_kicad_lib/lc_lib.pretty")
    self.btnModPath = QPushButton("...")
    self.fpList = QTableWidget()
    self.btnParse = QPushButton("Parse")
    self.forceParse = QCheckBox("ReParse")
    self.btnAutoMatch = QPushButton("AutoMatch")
    self.btnApply = QPushButton("Patch 3D")
    self.btnSave = QPushButton("Save")
    self.filter = QLineEdit{
        placeHolderText = "filter key here",
    }
    self.modelList = QListWidget()
    self.onlyKey = QCheckBox("Key Only")
    
    self.fpList.columnCount = 4
    --self.fpList.sortingEnabled = true
    self.fpList.hHeader = {"name","rotate", "keys", "3D Model"}
    self.layout = QVBoxLayout{
        QHBoxLayout{
            QLabel("${KISYS3DMOD}"), self.editSysPath, self.btnSysPath,
        },
        QHBoxLayout{
            QLabel("3D Model path"), self.edit3DPath, self.btn3DPath,
        },
        QHBoxLayout{
            QLabel("KiCad Mod path"), self.editModPath, self.btnModPath,
        },
        QHBoxLayout{
            self.btnParse, self.forceParse, self.btnSave, self.btnAutoMatch, self.btnApply, QLabel(""), strech = "0,0,0,0,0,1"
        },
        QHBoxLayout{
            self.fpList,
            QVBoxLayout{
                QHBoxLayout{self.filter,self.onlyKey},
                self.modelList,
            },
        }
    }
    
    function parseFpParams(path)
        local names = get_file_names(path,"*.kicad_mod")
        
        self.kimods = {}
        for i,v in ipairs(names) do
            local name = path .. "/" .. v .. ".kicad_mod"
            self.fpList:setItem(i-1, 0, QTableWidgetItem(v))
            local r = tostring(getModRotate(name))
            
            local cls, keys = splitKey(v)
            self.kimods[i] = {
                name = v,
                path = name,
                rotate = r,
                keys = keys,
                key = table.concat(keys, " ,"),
                fp = ""
            }
        end
    end
    
    function saveFpParams(path)
        local sName = path .. "/3D_bind_data.lua"
        local f = io.open(sName, "w+")
        if f then
            f:write([[
--------------------------------------------------------------------
------- this file in auto generate by the bind3D -------------------
------- https://github.com/xtoolbox/pcad2kicad   -------------------
--------------------------------------------------------------------
]])
            f:write("fpTable = {\n")
            for i,v in ipairs(self.kimods) do
                local st = string.gsub([[
  {
    name = "$name",
    path = "$path",
    rotate = "$rotate",
    key = "$key",
    fp = "$fp",
  },
]], "%$(%w+)", v)
            f:write(st)
            end
            f:write("}\nreturn fpTable\n")
            f:close()
        end
    end
    
    function loadFpParams(path, force)
        self.kimods = nil
        local sName = path .. "/3D_bind_data.lua"
        local f = nil
        if not force then
            f = io.open(sName, "r")
        end
        if f then
            logEdit:append("open "..sName.." success")
            local r = f:read("*a")
            f:close()
            self.kimods = loadstring(r)()
            for i,v in ipairs(self.kimods) do
                v.keys = {}
                string.gsub(v.key, "([^%s,]+)", function(t)
                    v.keys[#v.keys+1] = t
                    v.keys[t] = t
                end)
            end
            
        end
        if self.kimods then return end
        
        parseFpParams(path)
        saveFpParams(path)
    end
    
    function find3Dfile(n)
        local f = io.open(n, "r")
        if f then
            f:close()
            return n
        end
        return false
    end
    
    
    log = function(x) logEdit:append(x) end
    
    function get3DName(n)
        if self.nT[n] then
            local path = self.nT[n]['__path'] .. "/"
            local f = find3Dfile(path .. n .. ".step") or find3Dfile(path .. n .. ".stp") or find3Dfile(path .. n .. ".wrl")
            if f then
                log(f)
                log(self.editSysPath.text)
                local t1 = f:upper()
                local t2 = self.editSysPath.text:upper()
                t1 = t1:sub(1, #t2)
                local r = f
                if t1 == t2 then
                    r = "${KISYS3DMOD}" .. f:sub(#t2+1)
                end
                log(r)
                return r
            end
        end
        return nil
    end
    
    
    
    
    
    self.btnApply.clicked = function()
        if not self.kimods then return end
        log("clicked " .. #self.kimods)
        for i,v in ipairs(self.kimods) do
            local s = parse_s_file(v.path)
            if s and not has3DModel(s) then
                local n = get3DName(v.fp)
                if n then
                    append3DModel(v.path, v.rotate, n)
                end
            end
        end
    end
    
    self.btnSave.clicked = function()
        local path = self.editModPath.text
        saveFpParams(path)
    end
    self.btnParse.clicked = function()
        --self.fpList
        local path = self.editModPath.text
        loadFpParams(path, self.forceParse.checked)
        if self.kimods then
            self.fpListChanging = true
            self.fpList.rowCount = #self.kimods
            for i,v in ipairs(self.kimods) do
                self.fpList:setItem(i-1, 0, QTableWidgetItem(v.name))
                self.fpList:setItem(i-1, 1, QTableWidgetItem(v.rotate))
                self.fpList:setItem(i-1, 2, QTableWidgetItem(v.key))
                self.fpList:setItem(i-1, 3, QTableWidgetItem(v.fp))
            end
            self.fpListChanging = false
        end
        self.nT, self.kT = gather3DNames(self.edit3DPath.text)
    end
    
    function mmkey(keys)
        return match_keys(keys,self.kT, self.nT, self.onlyKey.checked)
    end
    
    self.btnAutoMatch.clicked = function()
        if not self.kimods then return end
        for i,mod in ipairs(self.kimods) do
            local res = mmkey(mod.keys)
            if res and res[1] then
                self.fpList:setItem(i-1, 3, QTableWidgetItem(res[1][1]))
                mod.fp = res[1][1]
            end
        end
    end
    self.fpList.cellChanged = function(row,col)
        if not self.fpListChanging and self.kimods and self.kimods[row+1] then
            local t = self.fpList:item(row,col).text
            --log("Changed "..row..", " .. col .. "  :" .. t)
            if col == 1 then
                local rot = tonumber(t) or 0
                t = tostring(rot)
                self.fpList:item(row,col).text = t
                self.kimods[row+1].rotate = t
            elseif col == 3 then
                self.kimods[row+1].fp = t
            elseif col == 0 then
                self.fpList:item(row,col).text = self.kimods[row+1].name
            elseif col == 2 then
                self.fpList:item(row,col).text = self.kimods[row+1].key
            end
            
        end
    end
    
    self.modelList.doubleClicked = function()
        local i = self.modelList.currentRow
        if self.filter3DList and self.filter3DList[i+1] then
            local v = self.filter3DList[i+1]
            local j = self.fpList.currentRow
            if j>= 0 then
                self.fpList:setItem(j, 3, QTableWidgetItem(v[1]))
                if self.kimods and self.kimods[j+1] then
                    self.kimods[j+1].fp = v[1]
                end
            end
            --logEdit:append(v[1] .. tostring(j))
        end
    end

    self.filter.textChanged = function(t)
        local r = {}
        string.gsub(t, "([^%s,]+)", function(k)
            r[#r+1] = string.upper(k)
        end)
        self.modelList:clear()
        local res = match_keys(r,self.kT, self.nT, self.onlyKey.checked)
        if not res then return end
        for i,v in ipairs(res) do
            self.modelList:addItem(QListWidgetItem(v[2] .. "  " .. v[1]))
        end
        self.filter3DList = res
    end
    
    self.btnSysPath.clicked = function()
        local r = QCommonDlg.getDir("Select 3D model sys path", self.editSysPath.text)
        if r ~= "" then self.editSysPath.text = r end
    end
    self.btn3DPath.clicked = function()
        local r = QCommonDlg.getDir("Select 3D model path", self.edit3DPath.text)
        if r ~= "" then self.edit3DPath.text = r end
    end
    self.btnModPath.clicked = function()
        local r = QCommonDlg.getDir("Select KiCad footprint path", self.editModPath.text)
        if r ~= "" then self.editModPath.text = r end
    end
end

local dd = Bind3DView()
mdiArea:addSubWindow(dd):show()
