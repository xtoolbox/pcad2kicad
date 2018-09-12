-- XToolBox initial script
function log(...)
    local r = ""
    for k,v in pairs({...}) do
        r = r .. "  " .. tostring(v)
    end
    logEdit:append(r)
end

require("pcad_lib")

class "PCadView"(QFrame)
function PCadView:__init()
    QFrame.__init(self)
    
    self.fileName = QLineEdit("Miscellaneous Devices LC.lia")
    self.btnParse = QPushButton("Convert to KiCad footprint")
    self.textLibName = QLineEdit{
        placeHolderText = "Use lib name in the lia file"
    }
    self.status = QLabel("")
    self.btnSelectFile = QPushButton("Load PCAD lib")
    self.textLibPath = QLineEdit{
        placeHolderText = "Use the lia file path"
    }
    self.btnLibPath = QPushButton("Set ouput path")
    self.layout = QVBoxLayout{
        QHBoxLayout{
            QLabel("PCAD lib:"),
            self.fileName,
            self.btnSelectFile,
        },
        QHBoxLayout{
            QLabel("Ouput library name:"),
            self.textLibName,
        },
        QHBoxLayout{
            QLabel("Output library path"),
            self.textLibPath,
            self.btnLibPath
        },
        self.btnParse,

        QHBoxLayout{
            QLabel("Current Progress:"), self.status, QLabel(""), strech = "0,0,1"
        },
    }
    function progress(cur, total)
        self.status.text = tostring(cur) .. "/"..total
        self:startTimer(1)
        coroutine.yield()
    end
    function log_info(...)
        log(...)
        self:startTimer(1)
        coroutine.yield()
    end
    self.btnSelectFile.clicked = function()
        local r = QCommonDlg.getOpenFileName("Select the pcad library file", "", "PCAD lib (*.lia);;All files (*)")
        if r ~= "" then self.fileName.text = r end
    end
    self.btnLibPath.clicked = function()
        local r = QCommonDlg.getDir("Set kicad library output path")
        if r ~= "" then self.textLibPath.text = r end
        if pcad_contimue then pcad_contimue() end
    end
    self.btnParse.clicked = function()
        self.co = coroutine.create(function()
            parse_pcad_lib(self.fileName.text, self.textLibName.text, self.textLibPath.text, progress, log_info)
        end)
        coroutine.resume(self.co)
    end
    self.eventFilter = QTimerEvent.filter(function(obj, evt)
        self:killTimer(evt.timerId)
        coroutine.resume(self.co)
    end)
end

local dd = PCadView()
mdiArea:addSubWindow(dd):show()


