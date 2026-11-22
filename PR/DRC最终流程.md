# riscv block DRC 最终流程

这份流程只保留最后跑通的主线：**Chip Finish → M2～M9 metal dummy → 完整 GDS → block DRC → DPO 修复 `PO.DN.2` → 最终 DRC/LVS**。

> 适用对象：当前 TSMC 65LP、top cell 为 `riscv` 的 CPU+SRAM block。这里得到的是 block-level clean，不等同于顶层芯片的 foundry signoff。

## 固定文件

| 用途 | 固定路径 |
| --- | --- |
| 工程根目录 | `/home/project/cp_training_backend1/users/cpu26/target/PR_ydx` |
| 干净 Chip Finish DB | `database/riscv.chipfinish.enc` |
| metal fill DB | `database/riscv.metalfill_work.enc` |
| metal fill 后 GDS | `data/riscv_m2fill_test.gds2` |
| 最终 GDS | `data/riscv_po_dn2_fix.gds2` |
| PDK 原始 deck | `/home/library/tsmc65lp/pdk_new/Calibre/online/drc_online/1p9m_6X2Z0U/calibre.drc` |
| block deck | `drc_flow/calibre_block.drc` |
| GUI runset | `drc_flow/drc.runset` |
| DRC 结果 | `drc_flow/drc.results`、`drc_flow/drc.summary` |
| `PO.DN.2` 修复脚本 | `drc_flow/add_po_dn2_dpo.py` |

文件名保持不变，不再创建 `_1`、`_2`、`final2` 等迭代文件。

## 1. 得到干净的 Chip Finish DB

如果 `database/riscv.chipfinish.enc` 已经是干净版本，可直接进入第 2 步。否则从 `route_opt` 重跑第 6 步：

```tcl
source ../database/$init_design.route_opt.enc
```

继续执行 `step6.chipfinish.tcl` 中的 DCAP/FILL、`refinePlace`、`ecoRoute` 和 `verify_drc`，然后保存：

```tcl
saveDesign -tcon ../database/$init_design.chipfinish.enc
```

这一步不要运行 `setMetalFill`、`addMetalFill`，也不要覆盖这个干净 DB。

## 2. 插入 M2～M9 metal dummy

加载干净 DB，在 Innovus Console 执行下面这一段。M1、PO、CO 不在这里处理。

```tcl
source ../database/riscv.chipfinish.enc

proc add_dummy_fill {layer gap min_size} {
    set iter "MF_TEST_$layer"

    setMetalFill \
        -iterationName $iter \
        -layer $layer \
        -activeSpacing 1.5 \
        -gapSpacing $gap \
        -borderSpacing 2.5 \
        -minWidth $min_size \
        -maxWidth 3.0 \
        -minLength $min_size \
        -maxLength 3.0 \
        -minDensity 10 \
        -preferredDensity 30 \
        -maxDensity 80 \
        -windowSize {75 75} \
        -windowStep {37.5 37.5} \
        -regular

    addMetalFill \
        -layer $layer \
        -iterationNameList [list $iter] \
        -squareShape \
        -timingAware off
}

foreach layer {M2 M3 M4 M5 M6 M7} {
    add_dummy_fill $layer 0.3 0.5
}

foreach layer {M8 M9} {
    add_dummy_fill $layer 0.4 0.8
}

saveDesign -tcon ../database/riscv.metalfill_work.enc
```

不要在同一个 DB 中重复执行。要重做时，重新加载 `riscv.chipfinish.enc`。

## 3. 导出包含标准单元和 SRAM 的 GDS

仍在当前 Innovus Console 执行：

```tcl
checkRoute
verifyConnectivity -type all -error 1000 -warning 50

set gds_map_file "../map_work/gds2_9M_6X2Z_innovus.map"
set gds_lib_name "RISCV_65NM_LIB"
set std_gds_file \
    "/home/library/tsmc65lp/std/TSMCHOME/digital/Back_End/gds/tcbn65lp_200a/tcbn65lp.gds"
set sram_gds_file \
    "/home/library/tsmc65lp/sram/ts1n65lpll2048x64m8_220a/GDSII/ts1n65lpll2048x64m8_220a.gds"

setStreamOutMode -version 600
setStreamOutMode -textSize 0.1
setStreamOutMode -virtualConnection true
setStreamOutMode -uniquifyCellNamesPrefix true
setStreamOutMode -SEvianames true
#riscv_drc_metal
streamOut ../data/riscv_drc_metal.gds2 \
    -mapFile $gds_map_file \
    -libName $gds_lib_name \
    -units 1000 \
    -mode ALL \
    -merge [list $std_gds_file $sram_gds_file]
```

`-merge` 不能省，否则 Calibre 看不到标准单元和 SRAM 的完整版图。

## 4. 准备 block DRC deck

在工程根目录执行。原始 PDK deck 只读，不直接修改。

```csh
cd /home/project/cp_training_backend1/users/cpu26/target/PR_ydx
set deck = /home/library/tsmc65lp/pdk_new/Calibre/online/drc_online/1p9m_6X2Z0U/calibre.drc

if (! -e drc_flow/calibre_block.drc) cp -p "$deck" drc_flow/calibre_block.drc
sed -i 's@^#DEFINE FULL_CHIP@//#DEFINE FULL_CHIP@' drc_flow/calibre_block.drc

diff -u "$deck" drc_flow/calibre_block.drc
```

`diff` 应只有一处：`#DEFINE FULL_CHIP` 被注释。`CHECK_LOW_DENSITY`、`FRONT_END`、`BACK_END` 保持开启。

最终流程不加载 `block_checks.svrf`，也不全局屏蔽 `CSR.R.1` 或 `PO.R.8`。这些 full-chip 分支由 `FULL_CHIP` 开关决定，不靠 waiver 伪装通过。

## 5. 用 Calibre GUI 跑第一次 block DRC

启动 Calibre Interactive/nmDRC，填写：

```text
Rules File : .../PR_ydx/drc_flow/calibre_block.drc
Layout Path: .../PR_ydx/data/riscv_m2fill_test.gds2
Primary    : riscv
Run Dir    : .../PR_ydx/drc_flow
Results    : drc.results
Summary    : drc.summary
Runset     : .../PR_ydx/drc_flow/drc.runset
```

保存同一个 `drc.runset`，点击 `Run DRC`，完成后进入 RVE。此时预期 `M2.DN.1～M9.DN.1` 已清零，只剩一条 `PO.DN.2`：

如果旧 runset 的 Include 页面还有 `block_checks.svrf`，先清空并覆盖保存。运行前检查：

```csh
grep -nE 'drcRulesFile|drcLayoutPaths|drcLayoutPrimary|drcIncludeFiles' drc_flow/drc.runset
```

应看到 `calibre_block.drc`、当前 GDS 和 primary `riscv`，不能出现 `drcIncludeFiles`。

```csh
grep 'RULECHECK' drc_flow/drc.summary | grep -v 'Count = 0'
```

如果还有别的规则，先处理别的规则，不要直接进入下一步。

## 6. 修复 `PO.DN.2`

`PO.DN.2` 是 `{OD、DOD、PO、DPO}` 的 20 µm × 20 µm 局部最小密度检查。剩余窗口位于左侧 die/core halo，普通 core filler 覆盖不到，所以在当前 deck/map 规定的 DPO 层 `17/1` 加 dummy poly。

在工程根目录执行：

```csh
python3 drc_flow/add_po_dn2_dpo.py
```

成功输出应包含：

```text
OUTPUT=data/riscv_po_dn2_fix.gds2
TOP=riscv ADDED_DPO_17_1=49
DPO_BOX=X9.6..10.4 Y4.6..485.4 um
```

检查最终 GDS 确实含有 `17/1`：

```csh
calibredrv -a 'puts [layout peek /home/project/cp_training_backend1/users/cpu26/target/PR_ydx/data/riscv_po_dn2_fix.gds2 -layers]' >! drc_flow/gds_layers_po_dn2_fix.txt
grep -F '{17 1}' drc_flow/gds_layers_po_dn2_fix.txt
```

这个脚本始终从 `riscv_m2fill_test.gds2` 重新生成固定输出，不会在旧输出上重复叠加。脚本坐标是固定的；只有 DIEAREA、左侧 halo 和 `PO.DN.2` 失败窗口都没变化时才能直接重跑。floorplan、尺寸或 marker 位置变化后，应先跑未补丁 DRC，再重新计算 DPO 图形。

## 7. 跑最终 DRC

重新加载同一个 `drc.runset`，只把 `Layout Path` 改为：

```text
.../PR_ydx/data/riscv_po_dn2_fix.gds2
```

覆盖原来的 `drc.results` 和 `drc.summary`，再次点击 `Run DRC`。验收命令：

```csh
tail -20 drc_flow/drc.summary
grep -E 'TOTAL DRC (RuleChecks Executed|Results Generated)' drc_flow/drc.summary
stat -c '%y  %s  %n' \
    data/riscv_po_dn2_fix.gds2 \
    drc_flow/drc.results \
    drc_flow/drc.summary
```

通过条件：

- `TOTAL DRC Results Generated: 0`；
- RVE 没有活动 marker；
- `drc.summary` 的时间晚于最终 GDS；
- 如果 GUI 已保存 transcript，再确认其中没有 `FATAL`、`ABORT` 或 `referenced but not defined`。

RVE 中点了 `Waive` 不算修复，最终以未豁免的 summary 为准。

## 8. 用同一份最终 GDS 重跑 LVS

最后一次 GDS 修改发生在 DPO 补丁之后，因此必须再跑一次 LVS。DRC 与 LVS 的 `LAYOUT PATH` 都应是：

```text
data/riscv_po_dn2_fix.gds2
```

LVS 只复用 [LVS验证操作.md](./LVS验证操作.md) 中的 Rules、Source、H-Cells 和 Include 设置。文档里旧的 `data/riscv.gds2` 或 `data/riscv_m2fill_test.gds2` 都要改成 `data/riscv_po_dn2_fix.gds2`。结果必须显示 `CORRECT`/netlists match，并且没有 unresolved cell。

再检查 LVS 报告确实来自最终 GDS之后：

```csh
stat -c '%y  %s  %n' data/riscv_po_dn2_fix.gds2 lvs_flow/lvs_gui.report
```

保存最终 GDS 的校验值：

```csh
sha256sum data/riscv_po_dn2_fix.gds2 >! drc_flow/final_gds.sha256
cat drc_flow/final_gds.sha256
```

只有“最终 DRC 为 0 + 补丁后 LVS 通过”同时满足，流程才算结束。
