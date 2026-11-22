# Chip Finish 后 Calibre LVS 最终流程

本流程已在项目中验证通过。所有终端命令均按 `csh/tcsh` 编写。

项目根目录：

```text
/home/project/cp_training_backend1/users/cpu26/target/PR_ydx
```

固定文件名：

```text
map_work/gds2_9M_6X2Z_innovus.map
data/riscv.gds2
data/riscv_lvs.vg
data/riscv_sram_box.spi
data/riscv_source.sp
database/riscv.chipfinish.enc
lvs_flow/calibre_gui.lvs
lvs_flow/sram_box.svrf
lvs_flow/v2lvs.log
lvs_flow/lvs_gui.report
```

GDS、VG、SPICE 数据统一放在 `data`，LVS 操作统一从 `lvs_flow` 执行。文件名不加日期、序号或 `_final` 后缀。

## 1. Chip Finish 与 Innovus 导出

`step6.chipfinish.tcl` 从 route-opt 数据库开始：

```tcl
source ../database/riscv.route_opt.enc
```

完成 DCAP/FILL、`refinePlace`、`ecoRoute` 后，检查并导出：

```tcl
checkRoute
verifyConnectivity -type all -error 1000 -warning 50

file mkdir ../data

saveNetlist -excludeLeafCell -includePowerGround -phys \
    ../data/riscv_lvs.vg

set gds_map_file "../map_work/gds2_9M_6X2Z_innovus.map"
set gds_lib_name "RISCV_65NM_LIB"
set std_gds_file \
    "/home/library/tsmc65lp/std/TSMCHOME/digital/Back_End/gds/tcbn65lp_200a/tcbn65lp.gds"
set sram_gds_file \
    "/home/library/tsmc65lp/sram/ts1n65lpll2048x64m8_220a/GDSII/ts1n65lpll2048x64m8_220a.gds"

foreach f [list $gds_map_file $std_gds_file $sram_gds_file] {
    if {![file readable $f]} { error "Missing GDS input: $f" }
}

setStreamOutMode -version 600
setStreamOutMode -textSize 0.1
setStreamOutMode -virtualConnection true
setStreamOutMode -uniquifyCellNamesPrefix true
setStreamOutMode -SEvianames true

streamOut ../data/riscv_m2fill_test.gds2 \
    -mapFile $gds_map_file \
    -libName $gds_lib_name \
    -units 1000 \
    -mode ALL \
    -merge [list $std_gds_file $sram_gds_file]

saveDesign -tcon ../database/riscv.chipfinish.enc
```

从 `PR_WORK_DIR` 运行：

```csh
cd /home/project/cp_training_backend1/users/cpu26/target/PR_ydx/PR_WORK_DIR
innovus -files ../script/step6.chipfinish.tcl
```

`checkRoute` 应显示设计网络均已连接。`verifyConnectivity` 中的 dangling wire 需记录，但最终仍以 LVS 是否 `CORRECT` 为准。

## 2. 检查导出文件

```csh
cd /home/project/cp_training_backend1/users/cpu26/target/PR_ydx/lvs_flow

stat -c '%y  %s  %n' \
../data/riscv.gds2 \
../data/riscv_lvs.vg

grep -nE '^[[:space:]]*module[[:space:]]+riscv([[:space:]]|$)' ../data/riscv_lvs.vg
```

GDS 与 VG 应来自同一次 Chip Finish，且必须找到顶层 `module riscv`。

## 3. SRAM BOX 接口文件

`data/riscv_sram_box.spi` 是固定的 SRAM 空壳接口，后续迭代直接复用。只有 SRAM 宏版本或 GDS 发生变化时才重新生成。

如需从 Calibre 已提取的 `lay.net` 重新生成：

```csh
awk 'toupper($1)==".SUBCKT" && toupper($2)=="TS1N65LPLL2048X64M8" {p=1; print; next} p && $1=="+" {print; next} p {print ".ENDS TS1N65LPLL2048X64M8"; exit}' lay.net >! ../data/riscv_sram_box.spi
```

检查首尾和端口数量：

```csh
head -3 ../data/riscv_sram_box.spi
tail -3 ../data/riscv_sram_box.spi

awk 'toupper($1)==".SUBCKT" && toupper($2)=="TS1N65LPLL2048X64M8" {p=1; for(i=3;i<=NF;i++) print $i; next} p && $1=="+" {for(i=2;i<=NF;i++) print $i; next} p {exit}' ../data/riscv_sram_box.spi | wc -l
```

端口应为 `210` 个。端口顺序必须来自 `lay.net`，不能直接使用 SRAM 原始 SPICE 的顺序。

## 4. 生成 `riscv_source.sp`

在 `lvs_flow` 执行：

```csh
set std_spi = "/home/library/tsmc65lp/std/TSMCHOME/digital/Back_End/spice/tcbn65lp_200a/tcbn65lp_200a_ori.spi"
set sram_v = "/home/library/tsmc65lp/sram/ts1n65lpll2048x64m8_220a/VERILOG/ts1n65lpll2048x64m8_220a_tt1p2v25c.v"

v2lvs -v ../data/riscv_lvs.vg \
    -o ../data/riscv_source.sp \
    -l $sram_v \
    -lsr $std_spi \
    -s $std_spi \
    -s ../data/riscv_sram_box.spi \
    -s0 VSS -s1 VDD >& v2lvs.log
```

不要对 SRAM 使用 `-lsr`，否则 `TSEL` 等总线可能被反向解释。

删除 Source 中不参与版图器件比较的 FILL 实例：

```csh
sed -i -E '/^[Xx][^[:space:]]+[[:space:]]+FILL(1|2|4|8|16|32|64)[[:space:]]/d' ../data/riscv_source.sp
```

检查：

```csh
grep -niE '^\.SUBCKT[[:space:]]+riscv([[:space:]]|$)' ../data/riscv_source.sp
grep -ciE '^[Xx][^[:space:]]+[[:space:]]+FILL(1|2|4|8|16|32|64)[[:space:]]' ../data/riscv_source.sp
grep -niE 'fatal|error|unresolved|duplicate declaration' v2lvs.log | head -50
```

FILL 计数必须为 `0`。`v2lvs.log` 中的 case-insensitive duplicate warning 可以保留，因为 Calibre 将通过 `SOURCE CASE YES` 区分 `N91` 与 `n91` 等网络。

## 5. 准备 Calibre 规则

只复制并修改 PDK rule deck 的本地副本：

```csh
cp /home/library/tsmc65lp/pdk_new/Calibre/online/lvs_online/1p9m_6X2Z0U/calibre.lvs calibre_gui.lvs

sed -i -E '/^[[:space:]]*(LAYOUT[[:space:]]+(PRIMARY|PATH|SYSTEM)|SOURCE[[:space:]]+(PRIMARY|PATH|SYSTEM)|LVS[[:space:]]+REPORT[[:space:]]+"[^"]*"[[:space:]]*$)/ s|^[[:space:]]*|//|' calibre_gui.lvs
```

`LVS REPORT MAXIMUM` 和 `LVS REPORT OPTION` 必须保持启用。

生成固定附加规则：

```csh
printf "LAYOUT CASE YES\nSOURCE CASE YES\nLVS BOX TS1N65LPLL2048X64M8\n" >! sram_box.svrf
cat sram_box.svrf
```

三项作用分别是：保持 Layout 名称大小写、保持 Source 网络大小写、将 SRAM 内部作为 BOX，只比较宏端口及外部连接。

## 6. Calibre nmLVS 配置

```csh
cd /home/project/cp_training_backend1/users/cpu26/target/PR_ydx/lvs_flow
calibre -gui
```

选择 `nmLVS`，填写：

```text
Rules File    : /home/project/cp_training_backend1/users/cpu26/target/PR_ydx/lvs_flow/calibre_gui.lvs
Run Directory : /home/project/cp_training_backend1/users/cpu26/target/PR_ydx/lvs_flow

Layout System : GDSII
Layout File   : /home/project/cp_training_backend1/users/cpu26/target/PR_ydx/data/riscv.gds2
Layout Primary: riscv

Source System : SPICE
Source File   : /home/project/cp_training_backend1/users/cpu26/target/PR_ydx/data/riscv_source.sp
Source Primary: riscv

Power         : VDD
Ground        : VSS
LVS Report    : /home/project/cp_training_backend1/users/cpu26/target/PR_ydx/lvs_flow/lvs_gui.report
Run mode      : Hierarchical
CPU           : 32
```

额外设置：

1. `Run Control → H-Cells`：勾选 H-Cells 文件并加载：

   ```text
   /home/library/tsmc65lp/sram/ts1n65lpll2048x64m8_220a/SPICE/ts1n65lpll2048x64m8_220a.hcell
   ```

2. `Setup → LVS Options → Include`：加入：

   ```text
   sram_box.svrf
   ```

3. 勾选 `Include Rule Files After Main LVS Rules File`。

完成后点击 `Run LVS`，再点击 `Start RVE` 查看结果。

## 7. 通过标准

```csh
grep -nE 'OVERALL COMPARISON RESULTS|CORRECT|INCORRECT' lvs_gui.report | head -20
```

通过时应满足：

- RVE 中 `riscv` 为绿色；
- Layout/Source 的 nets 和 instances 数量相等；
- SRAM 显示为 `LVS Box`；
- 报告明确显示 `CORRECT`，没有 `INCORRECT` 或 `NOT COMPARED`。

不要恢复以下旧做法：创建 `riscv_filler.spi`、对 SRAM SPICE 使用 `-lsr`、删除 `SOURCE CASE YES`，或修改 PDK 原始规则文件。
