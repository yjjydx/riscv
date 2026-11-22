# Calibre DRC 操作

本文档只记录本项目的三件事：导出完整 GDS、启动并运行 Calibre DRC、在 RVE / DESIGNrev 中查看错误。

## 1. 导出用于 DRC 的完整 GDS

Calibre 的输入不是 Innovus 数据库或 DEF，而是 GDS。导出的顶层 GDS 必须包含：

- 顶层 `riscv` 的版图与布线；
- 标准单元的真实 GDS；
- 本项目 SRAM `TS1N65LPLL2048X64M8` 的真实 GDS。

如果未合入标准单元或 SRAM GDS，Calibre 会报：

```text
Cell BUFPD0 is referenced but not defined
Cell FILL4 is referenced but not defined
```

这不是 DRC 几何错误，而是 GDS 缺少被引用 cell 的版图定义。

在 Innovus 完成 `step6.chipfinish.tcl` 后，执行下面命令导出用于 Calibre 的完整 GDS：

```tcl
# GDS 层映射文件：必须和当前 9M_6X2Z 工艺栈匹配。
set gds_map_file "/home/library/tsmc65lp/std/TSMCHOME/digital/Back_End/lef/tcbn65lp_200a/techfiles/Virtuoso/map/mapfiles/Vir65nm_9M_6X2Z_v1.4b.042508.map"
set gds_lib_name "RISCV_65NM_LIB"

# 标准单元与本项目所用 SRAM 的真实 GDS。
set std_gds_file "/home/library/tsmc65lp/std/TSMCHOME/digital/Back_End/gds/tcbn65lp_200a/tcbn65lp.gds"
set sram_gds_file "/home/library/tsmc65lp/sram/ts1n65lpll2048x64m8_220a/GDSII/ts1n65lpll2048x64m8_220a.gds"
set merge_gds_files [list $std_gds_file $sram_gds_file]

setStreamOutMode -version 600
setStreamOutMode -textSize 0.1
setStreamOutMode -virtualConnection true
setStreamOutMode -uniquifyCellNamesPrefix true
setStreamOutMode -SEvianames true

file mkdir ../output

streamOut ../output/${init_design}.gds2 \
  -mapFile $gds_map_file \
  -libName $gds_lib_name \
  -units 1000 \
  -mode ALL \
  -merge $merge_gds_files
```

本项目预期输出：

```text
../output/riscv.gds2
```

在 Linux 终端确认文件已生成：

```bash
cd ../output
ls -lh riscv.gds2
```

## 2. 启动并配置 Calibre DRC

在 GDS 所在的 `output` 目录启动 Calibre：

```bash
calibre -gui
```

出现 Calibre Interactive 主窗口后，点击：

```text
nmDRC
```

### 2.1 Rules 页面

在 `DRC Rules File` 填入本项目对应的 rule deck：

```text
/home/library/tsmc65lp/pdk_new/Calibre/online/drc_online/1p9m_6X2Z0U/calibre.drc
```

它和 Innovus 使用的 `Vir65nm_9M_6X2Z...map` 对应；不要误选 `1p9m_6X1Z1U`。

### 2.2 Inputs 页面

填写：

```text
Layout File   : riscv.gds2
Layout System : GDSII
Top Cell      : riscv
```

如果是在其他目录启动 Calibre，`Layout File` 要填 `riscv.gds2` 的实际绝对路径或相对路径。

### 2.3 Outputs 页面

设置结果文件，建议保存在当前 `output` 目录：

```text
Results Database : drc.results
Summary Report   : drc.summary
Transcript       : drc.log
```

然后点击：

```text
Run DRC
```

运行完成后先保留生成的 `drc.results`，不要从 nmDRC 窗口单独启动 RVE。后续从 DESIGNrev 中启动 RVE，才能让错误结果与 GDS 版图建立联动。

## 3. 打开 GDS 版图并查看错误

先用 `Calibre DESIGNrev` 打开 GDS，再从 DESIGNrev 启动 RVE。这样两个窗口会建立 cross-probe 联动，选择 DRC 错误时，DESIGNrev 才能定位并高亮对应版图区域。

在 GDS 所在目录的终端执行：

```bash
calibredrv riscv.gds2
```

不要在命令前多输入字符；本服务器将它放到后台时可能出现 `Suspended (tty output)`，因此直接前台运行最稳。

成功后会出现标题类似下面的窗口：

```text
Calibre DESIGNrev -- riscv.gds2
```

在 DESIGNrev 顶部菜单依次点击：

```text
Verification -> Start RVE
```

在弹出的文件选择窗口中加载：

```text
drc.results
```

随后打开的 RVE 已经与当前 `riscv.gds2` 版图窗口连接。不要改为从 Calibre Interactive/nmDRC 窗口单独启动 RVE，否则 RVE 与 DESIGNrev 可能互不关联，点击错误后右侧版图不会高亮。

### 3.1 在 RVE 中查看某条错误

RVE 左侧的层级通常是：

```text
Check <规则名>
  Cell riscv
    <错误编号>
```

展开规则和 cell，选中最底层的错误编号，例如：

```text
Check M2.DN.1
  Cell riscv
    5437
```

选中后，RVE 下方会显示：

- 规则名；
- 错误图形类型；
- 所在 cell；
- 错误框的坐标。

例如：

```text
Check M2.DN.1, Cell riscv
4-Vertex Polygon
(19.76 169.76) (630.24 169.76) (630.24 319.76) (19.76 319.76)
```

这条错误位于 `M2` 层，错误窗口范围为：

```text
X: 19.76 ~ 630.24
Y: 169.76 ~ 319.76
```

### 3.2 RVE 的高亮操作

在由 DESIGNrev 启动的 RVE 中，展开规则和 cell，选中最底层的具体错误编号。双击该编号，或者使用：

```text
Highlight -> Highlight in Context
```

或：

```text
Highlight -> Zoom to Highlights
```

如果希望每次高亮都自动缩放，在 RVE 中设置：

```text
Setup -> Options -> Highlighting
```

将 `On New Highlighting` 从：

```text
No view change
```

改为：

```text
Zoom to highlights
```

再点击 `Apply`。

正确联动后的操作顺序为：

```text
calibredrv riscv.gds2
-> DESIGNrev: Verification -> Start RVE
-> 选择 drc.results
-> RVE 中选择具体错误编号
-> DESIGNrev 定位并高亮错误区域
```

## 4. 截图中各类规则怎么看

规则名称只能用于快速分类，最终含义以 RVE 下方显示的 `@` 规则说明为准。例如：

```text
M3.DN.1 @ M3 local density must be >= 0.1 ...
```

这句话才是该规则的准确检查条件、阈值和窗口大小。

### 4.1 规则名中的常见缩写

| 缩写 | 通常表示 | 说明 |
| --- | --- | --- |
| `NW` | N-Well | N 型阱层 |
| `OD` | Active/Diffusion | 有源区、扩散区 |
| `PO` | Poly | 多晶硅层 |
| `PP` | P+ Implant | P 型重掺杂注入层 |
| `NP` | N+ Implant | N 型重掺杂注入层 |
| `M1`～`M9` | Metal 1～9 | 各层金属 |
| `VIA1`～`VIA8` | Via | 相邻金属层之间的通孔 |
| `.S.` | Spacing | 间距类检查 |
| `.DN.` | Density | 局部或全局密度检查 |
| `.R.` | PDK 自定义限制/组合规则 | 不能只根据 `R` 猜具体含义，要看 RVE 中的规则说明 |
| `WARN` | Warning | 警告项，不一定是必须清零的几何 DRC |

### 4.2 基础工艺层规则

| 截图中的规则 | 简短解释 | 当前 place 阶段怎么看 |
| --- | --- | --- |
| `NW.S.1`、`NW.S.2` | N-Well 最小间距等井层 spacing 检查 | 可能与标准单元行、macro 边界、endcap/filler 尚未完整有关；先定位一个代表点，最终在 filler/chip finish 后复查 |
| `OD.DN.2:L`、`OD.DN.3:L` | OD/扩散区密度子规则；`:L` 是 rule deck 的子检查标识 | place 阶段版图尚未完整，只作趋势参考；准确上下限看 RVE 下方 `@` 说明 |
| `OD2.S.5` | `OD2` 辅助有源区的间距规则，含义由该 PDK 定义 | 先看错误是否位于 SRAM/标准单元内部；不要仅凭名称修改 floorplan |
| `PO.DN.2` | Poly 局部或全局密度规则 | place 阶段可能不满足，最终结合完整单元、填充和工艺要求复查 |
| `PO.R.8` | Poly 的 PDK 专用限制规则 | `R.8` 不能直接翻译成固定几何规则，必须查看 RVE 下方原始说明和错误位置 |
| `PP.S.1` | P+ implant 间距规则 | 标准单元之间缺 filler/endcap 时可能大量出现，chip finish 后复查 |
| `NP.S.1` | N+ implant 间距规则 | 处理原则与 `PP.S.1` 相同 |

如果 `NW/OD/PO/PP/NP` 错误全部位于某个标准单元或 SRAM 内部，优先检查使用的库 GDS 与 PDK/rule deck 版本是否匹配，不要直接修改库单元内部版图。

### 4.3 M1～M9 金属密度规则

```text
M1.DN.1
M2.DN.1
...
M9.DN.1
```

这些是各金属层的 density 检查。它们通常在固定大小的滑动窗口内计算金属面积比例，因此高亮结果往往是一个较大的矩形或多边形区域，不是某根金属线画错。

当前只完成 placement 时：

- 信号线尚未 route；
- metal fill 尚未完成；
- M1～M9 密度不满足并不意外；
- 不应逐条手工修改这些 density result。

应在 route/chip finish 和工艺要求的 metal fill 完成后重新跑最终 DRC。若最终仍有密度违例，再检查 metal fill、fill blockage、macro 周边空白区和电源网格分布。

### 4.4 `CSR.R.1:*` 组合规则

截图中的例子包括：

```text
CSR.R.1:NWi
CSR.R.1:PPi
CSR.R.1:NPi
CSR.R.1:COi
CSR.R.1:M1i
CSR.R.1:M1_real
CSR.R.1:VIA1i
CSR.R.1:SRM
CSR.R.1:SRAMDMY
```

`CSR.R.1` 是该 TSMC rule deck 的组合/全局检查，冒号后的名称表示该检查涉及的 Calibre 内部派生层：

- `NWi/PPi/NPi/COi`：井、implant、contact 等内部层；
- `M1i/M1_real`：Calibre 处理后的 M1 内部/实际图形层；
- `VIA1i` 等：内部 via 层；
- `SRM/SRAMDMY`：SRAM 相关 marker/dummy 层。

这些后缀不是需要在 Innovus 中逐一寻找并替换的 cell 名。若 `CSR.R.1` 同时在很多层上成百上千地出现，先怀疑该组合规则依赖的顶层边界、marker、检查区域或运行选项没有满足，而不是逐个修改几何图形。`CSR` 的精确定义属于 PDK 专用内容，必须点击具体规则并读取 RVE 下方的 `@` 说明后再决定修法。

### 4.5 `DM2.R.1`～`DM9.R.1`

`DMx` 通常表示对应金属层的 dummy metal/金属填充相关派生层。截图中每层只有一个结果时，常见情况是整层或某个大窗口的填充/标记检查。

place 阶段尚未完成 route 和 metal fill，因此先记录，不要按单个坐标手工补金属。最终 chip finish 后仍存在时，再结合该规则的 `@` 说明检查 dummy fill、密度窗口和 fill exclusion。

### 4.6 `ESD.WARN.1` 与 `DENSITY_PRINT_FILES`

| 规则 | 解释 |
| --- | --- |
| `ESD.WARN.1` | ESD 结构、端口或标记相关警告。若当前只是 core/block 级设计，没有完整 pad ring/ESD 单元，可能出现该警告；需结合交付层级判断是否必须处理 |
| `DENSITY_PRINT_FILES` | rule deck 用于生成密度报告的控制/输出项；绿色且结果为 0 时不是 DRC 违例 |

### 4.7 Results 与 Flat 数量

RVE 中常见两个数量列：

- `Results`：结果数据库中保存/显示的结果数，可能受最大结果数限制；
- `Flat`：层次展开后的实际出现次数。同一个标准单元被实例化很多次时，`Flat` 可能远大于 `Results`。

很多规则刚好显示 `1000`，通常表示该检查达到了结果保存上限，不代表实际总数正好是 1000。例如 `PO.R.8` 的 `Results=1000`、`Flat=18446` 表示层次展开后共有大量重复出现。

## 5. 最小排查顺序

1. 先确认 `riscv.gds2` 已用 `-merge` 合入标准单元和 SRAM GDS；若出现 `referenced but not defined`，先重新导出 GDS。
2. 优先排除全局配置类问题，例如大量 `CSR.R.1:*`、缺失 boundary/marker、rule deck 或工艺栈不匹配。
3. 在 RVE 中选择一个有代表性的最底层错误编号，查看下方 `@` 原始规则说明并在 DESIGNrev 中定位。
4. 优先处理 short、spacing、width、via enclosure 等真实几何错误；不要先处理 place 阶段的 metal density。
5. route、filler/decap 和 metal fill 完成后重新导出最终 GDS，再以最终 DRC 结果决定是否回到 floorplan、route 或 chip finish 修复。
