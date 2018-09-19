# PCAD/AD库文件转换KiCad工具
# Convert PCAD/AD library to Kicad
特点:

1. Altium Designer的二进制原理图库转换成KiCad格式

2. PCAD的ASCII原理图库转换成KiCad格式

3. PCAD的ASCII封装图库转换成KiCad格式

Feature:

1. Altium Designer binary schlib to KiCad symbol library

2. PCAD ASCII symbol library to KiCad symbol library

3. PCAD ASCII footprint library to KiCad footprint library


## ad2kicad
require [7z](https://www.7-zip.org/download.html) and [lua 5.3](https://sourceforge.net/projects/luabinaries/files/5.3.4/)
### Signle mode:
```sh
lua ad2kicad.lua <inName> [outName] [fpLib]
```
### Batch mode:
```sh
lua ad2kicad.lua --batch <inPath> [outPath] [fpLib] [prefix] [O1=N1[ O2=N2...]]
```



## pcad2kicad
require [lua 5.3](https://sourceforge.net/projects/luabinaries/files/5.3.4/)
### Signle mode:
```sh
lua pcad2kicad.lua <inName> [outName] [outPath] [fpLib]
```
### Batch mode:
```sh
lua pcad2kicad.lua --batch <inPath> [outPath] [fpLib] [prefix] [O1=N1[ O2=N2...]]
```