# Chip Finish 后 Calibre GUI DRC 流程

本流程只使用服务器上的 **Calibre Interactive / nmDRC GUI** 运行 DRC，不使用 batch 运行脚本。

首轮 `21163` 条结果的根因、CSR block-level 处理方法以及当前剩余 `81` 条结果，详见 [DRC问题分析.md](./DRC问题分析.md)。

项目根目录固定为：

```text
/home/project/cp_training_backend1/users/cpu26/target/PR_ydx
```

## 1. 固定输入、配置和输出文件

| 类型 | 固定路径 | 说明 |
| --- | --- | --- |
| Chip Finish 数据库 | `database/riscv.chipfinish.enc` | 上游来源，Calibre 不直接读取 |
| DRC/LVS 共用 GDS | `data/riscv.gds2` | DRC 唯一版图输入，不复制到 `drc_flow` |
| PDK DRC rule deck | `/home/library/tsmc65lp/pdk_new/Calibre/online/drc_online/1p9m_6X2Z0U/calibre.drc` | 直接引用原始只读 deck，不复制、不修改 |
| GUI 配置 | `drc_flow/drc.runset` | 第一次配置 nmDRC 后由 GUI 保存，不手写 |
| Block 规则选择 | `drc_flow/block_checks.svrf` | 固定排除 145 条 full-chip corner CSR 检查，作为 GUI Include 加载 |
| GUI 临时工作 deck | `drc_flow/calibre.drc` | 运行期间可能由 GUI 自动生成，关闭后可能自动删除；不是持久交付物，不手改 |
| DRC 结果库 | `drc_flow/drc.results` | 供 RVE 加载 |
| DRC 汇总报告 | `drc_flow/drc.summary` | 判断违例总数 |
| 非零规则摘要 | `drc_flow/drc.nonzero` | 从过长的 `drc.summary` 固定提取，重复生成时覆盖 |
| GUI transcript | `drc_flow/drc.log` | 通过 GUI 的 Transcript 菜单另行保存 |
| PDK 辅助输出 | `drc_flow/*.density`、`drc_flow/*.rep` | rule deck 自动生成的固定名辅助物，不手工改名 |

nmDRC 重跑时只覆盖 `drc.results`、`drc.summary`、`drc.nonzero`、`drc.log`。仅当 GUI 配置发生变化时，才覆盖保存同一个 `drc.runset`。`database/riscv.chipfinish.enc` 和 `data/riscv.gds2` 只由上游 PR/导出流程更新，PDK 原始 `calibre.drc` 永不覆盖。

不要创建 `drc_1`、`drc_2`、`drc_final`、日期后缀或 `.bak_*` 文件。

Calibre 自己产生的隐藏文件和临时文件不作为流程输入，也不人为改名保存。

`calibre.drc` 若在 GUI 关闭后消失属于正常的临时文件清理，不代表 DRC 失败；不要把它列为必须长期存在的结果文件。

`*.density`、`*.rep` 文件是否为空及其字节数不能用来判断规则是否通过；`ls -l` 开头的 `total` 也只是目录占用块合计。DRC 数量始终以 `drc.summary` 和 RVE 为准。

## 2. 当前项目必须采用的 GDS

当前服务器实况为：

- `database/riscv.chipfinish.enc`：2026-07-13 10:25 生成；
- `data/riscv.gds2`：2026-07-13 10:26 生成，大小为 19,432,124 字节；
- `data/riscv.gds2` 已被最终 LVS 流程使用。

因此本轮 DRC 直接使用：

```text
/home/project/cp_training_backend1/users/cpu26/target/PR_ydx/data/riscv.gds2
```

不要改用当前 `script/step6.chipfinish.tcl` 写出的 `output/riscv.gds2`。服务器当前脚本中的该输出没有 `-merge` 标准单元和 SRAM GDS，不能证明是完整 signoff GDS。

本文档当前只适用于这份已经用于最终 LVS 的现有 `data/riscv.gds2`。

再次执行 Chip Finish 前，必须先把上游导出流程统一为：从最新 `database/riscv.chipfinish.enc` 生成完整的 `data/riscv.gds2`，并合入标准单元和 SRAM 的真实 GDS。当前服务器上的 `step6.chipfinish.tcl` 尚未满足这个条件，因此在导出路径和 `-merge` 修正前，不得拿旧的 `data/riscv.gds2` 代表新一轮 PR 结果。

新 GDS 生成后，先确认同一份 `data/riscv.gds2` 的 LVS 仍为 `CORRECT`，再重新运行 DRC。

## 3. 第一次启动 Calibre GUI

在服务器终端执行：

```csh
cd /home/project/cp_training_backend1/users/cpu26/target/PR_ydx/drc_flow
calibre -gui
```

在 Calibre Interactive 主窗口选择：

```text
nmDRC
```

第一次运行不要加载旧 runset，按下面步骤逐项配置。

## 4. 配置 Rules 页面

填写：

```text
DRC Rules File:
/home/library/tsmc65lp/pdk_new/Calibre/online/drc_online/1p9m_6X2Z0U/calibre.drc

Run Directory:
/home/project/cp_training_backend1/users/cpu26/target/PR_ydx/drc_flow
```

注意：

- 工艺栈必须是 `1p9m_6X2Z0U`，不能选 `1p9m_6X1Z1U`；
- 不修改 PDK 原始 `calibre.drc`；
- 不创建 `calibre_gui.drc` 或其他 rule deck 副本；
- 保留 rule deck 中的 `DRC MAXIMUM RESULTS ALL`；
- 不自行关闭或跳过规则。

## 5. 配置 Inputs 页面

填写：

```text
Layout System : GDSII
Layout File   : /home/project/cp_training_backend1/users/cpu26/target/PR_ydx/data/riscv.gds2
Top Cell      : riscv
```

有些 Calibre 版本把 `Top Cell` 显示为 `Layout Primary`，两者都填写 `riscv`。

不要把下面这些文件作为 Layout File：

```text
database/riscv.chipfinish.enc
data/riscv.def
output/riscv.gds2
```

## 6. 配置 Outputs 页面

全部使用绝对路径：

```text
Results Database:
/home/project/cp_training_backend1/users/cpu26/target/PR_ydx/drc_flow/drc.results

Summary Report:
/home/project/cp_training_backend1/users/cpu26/target/PR_ydx/drc_flow/drc.summary
```

`Results Database` 的数据库格式保持 PDK/GUI 默认，不额外改成其他格式。

当前服务器版本没有通过 Outputs 页面生成 `drc.log`。运行前在 Calibre Interactive 顶部菜单选择类似：

```text
Transcript -> Echo to File...
```

固定指定：

```text
/home/project/cp_training_backend1/users/cpu26/target/PR_ydx/drc_flow/drc.log
```

选择覆盖已有文件。若本轮 GUI 窗口仍未关闭，可使用类似 `Transcript -> Save As...` 将当前 transcript 补存到同一路径。Transcript 设置不一定写入 `drc.runset`，每次新 GUI 会话都要重新核对。若实际菜单名称不同，以该服务器 GUI 展开的 Transcript 菜单为准。

如果界面有 `Run Name`，固定填写：

```text
drc
```

如果界面提供运行模式和 CPU 设置，使用：

```text
Run Mode : Hierarchical
CPU/Turbo: 32
```

这些设置只影响执行方式，不改变固定文件名。

首轮实际保存的 `drc.runset` 中为 `totalCpus 1`、`minCpus 1`，说明本次按单 CPU 配置运行。这只影响速度，不会产生 `CSR.R.1` 违例；不要仅为修改 CPU 数重跑。后续若服务器允许 32 CPU，再在 GUI 中修改并覆盖保存同一个 `drc.runset`。

## 7. 保存固定 runset

运行前在 nmDRC 中选择类似下面的菜单：

```text
File -> Save Runset As
```

不同 Calibre 版本的菜单文字可能略有区别。固定保存为：

```text
/home/project/cp_training_backend1/users/cpu26/target/PR_ydx/drc_flow/drc.runset
```

`drc.runset` 必须由当前服务器上的 Calibre GUI 生成，不要手写，因为不同版本的 runset 字段可能不同。

后续运行时：

1. 启动 `calibre -gui` 并进入 nmDRC；
2. 使用 `File -> Load Runset` 加载同一个 `drc.runset`；
3. 核对输入仍是 `data/riscv.gds2`；
4. 直接覆盖原有结果，不另起文件名。

## 8. 在 GUI 中运行 DRC

核对 Rules、Inputs、Outputs 后，点击：

```text
Run DRC
```

如果 GUI 提示下列文件已经存在，选择覆盖：

```text
drc.results
drc.summary
```

不要为了保留旧结果而改变文件名。需要重跑时，旧结果已经不再代表当前 GDS。

如果文件正被 RVE 或 DESIGNrev 占用，先关闭旧的 RVE/DESIGNrev 窗口，再运行。只有 GUI 仍不能覆盖时，才在 `drc_flow` 中删除旧结果：

```csh
rm -f drc.results drc.summary
```

不要删除 `drc.runset`。

## 9. 判断 Calibre 是否正常跑完

GUI 显示结束后，先检查 `drc.summary` 页脚。正常完成和 DRC 清零是两件事：有违例时 Calibre 也可能正常完成。

终端辅助检查命令：

```csh
cd /home/project/cp_training_backend1/users/cpu26/target/PR_ydx/drc_flow

ls -lh drc.runset drc.results drc.summary
tail -20 drc.summary

# 已按第 6 节保存 transcript 时再执行：
ls -lh drc.log
grep -niE 'fatal|abort|referenced but not defined|warning|error' drc.log | head -100
tail -50 drc.log
```

运行完成至少要有以下证据：

1. `drc.summary` 页脚存在 `TOTAL CPU Time`、`TOTAL REAL Time`、`TOTAL DRC RuleChecks Executed` 和 `TOTAL DRC Results Generated`；
2. `drc.summary` 和 `drc.results` 的更新时间属于本次运行；
3. `drc.results` 能被 RVE 正常加载；
4. 已保存 `drc.log` 时，其中没有 `FATAL`、`ABORT` 或 `Cell ... is referenced but not defined`。

本项目首轮结果已经出现完整 summary 页脚：执行 `1819` 个 RuleCheck、生成 `21163` 个 result，因此本轮 nmDRC 引擎已经运行到汇总结束。缺少 `drc.log` 表示 GUI transcript 没有落盘，不代表这 `21163` 个结果由日志缺失造成。

若出现 `referenced but not defined`，优先检查 GDS 是否合入标准单元和 SRAM 的真实 GDS，不要把它当普通几何 DRC 错误处理。

## 10. 用 DESIGNrev 和 RVE 定位错误

在 `drc_flow` 终端执行：

```csh
calibredrv ../data/riscv.gds2
```

在 DESIGNrev 中依次选择：

```text
Verification -> Start RVE
```

加载固定结果库：

```text
/home/project/cp_training_backend1/users/cpu26/target/PR_ydx/drc_flow/drc.results
```

必须从打开了本次输入 GDS 的 DESIGNrev 启动 RVE。不要从 nmDRC 主窗口单独启动 RVE，否则错误与版图可能无法 cross-probe 联动。

在 RVE 中：

1. 展开具体规则；
2. 展开 `Cell riscv`；
3. 选中最底层的错误编号；
4. 使用 `Highlight in Context` 或 `Zoom to Highlights`；
5. 读取下方 `@` 后面的完整规则说明、阈值和坐标。

不要只根据 `M2.DN.1`、`CSR.R.1` 等缩写猜修法，PDK 原始规则说明和实际定位才是依据。

## 11. DRC 通过标准

流程运行成功的标准：

- `drc.summary` 可正常读取且具有完整汇总页脚；
- `drc.results` 能由 RVE 加载并与 `data/riscv.gds2` 联动。
- 已保存 `drc.log` 时，其中没有 fatal/abort/缺失 cell；未保存 transcript 不能单独作为 DRC 失败的依据。

Signoff DRC 通过的标准还包括：

- `drc.summary` 中最终 DRC 违例总数为 `0`；
- 若比赛或 PDK 允许 waiver，必须逐项记录规则、数量和依据，不能直接忽略；
- 不能仅凭 GUI 任务显示绿色判断 DRC clean。

## 12. 当前已知风险

首轮 summary 已确认：

```text
TOTAL DRC RuleChecks Executed: 1819
TOTAL DRC Results Generated : 21163
```

这不表示 `1819` 条规则全部出错。首轮 `drc.summary` 中每条非零 `RULECHECK` 在两个统计区块各出现一次，未去重的 AWK 因而得到 `42326 = 2 × 21163`。按规则名去重后，结果可以与页脚精确闭合：

```text
CSR.R.1（36 个非零子项）                           21082
PO.R.8                                                   57
M2/M3/M4/M5/M8/M9.DN.1（各 2）                          12
DM2.R.1 ～ DM9.R.1（各 1）                                8
ESD.WARN.1、M6.DN.1、M7.DN.1、PO.DN.2（各 1）             4
----------------------------------------------------------------
合计                                                   21163
```

因此 `CSR.R.1` 占本轮结果约 `99.62%`，其他规则合计只有 `81` 个。不能在不了解父规则含义时把 `21082` 个 CSR marker 当作独立根因逐点修改。截图中同时可见许多常规 width、spacing、enclosure 规则为 `0`。

`CSR.R.1` 已经取得 PDK 原文：

```text
CSR.R.1:M2i { @ M2i is not allowed inside the empty area of chip corner.
  EMPTY_AREA AND M2i
}
```

RVE 规则树同时显示 NWell、implant、contact、SRAM marker、M1～M9 和 VIA 等多类 `CSR.R.1:*` 子项非零；所选 M2i marker 是与 `EMPTY_AREA` 相交的多边形。这高度表明本轮报告的 `21082` 个 CSR result 共享 chip-corner 区域条件，不是 21082 个互不相关的 width/spacing 缺陷。部分子项达到 `1000`，可能触及单条规则的结果上限，因此 `21082` 只表示本次结果库报告数，不保证是真实几何总数。

`DM2.R.1`～`DM9.R.1`、`M4.DN.1` 等其余规则的精确定义仍需 PDK/RVE 原文。服务器当前 `step6.chipfinish.tcl` 没有发现 metal/dummy fill 命令，这是需要调查的相关事实，但是否为这些规则的根因必须由规则阈值、坐标和 marker 分布证明。

当前项目已经可以确定为 CPU+SRAM 的 core/block，而不是可独立流片的 full-chip：顶层使用普通逻辑端口和 `editPin` block pin；物理脚本只有 core ring 与 SRAM block ring；没有 IO pad/corner/filler、ESD、seal/scribe 流程；Chip Finish 还导出了 `write_lef_abstract`。现有比赛材料只要求 CPU 模块的 P&R 版图和物理报告，没有发现必须补齐 pad ring/seal ring 的要求。

因此，当前 `CSR.R.1:*` 应暂停逐点修复，并标记为 **block 层级不适用候选**。还需先验证整族规则都采用相同的 chip-corner/`EMPTY_AREA AND` 模式，再通过 PDK/课程认可的 block-level runset、GUI rule selection、开关或书面 waiver处理。确认前 CSR 仍是 open item，不能宣称已经豁免或 DRC clean。不要给当前 block 伪造 IO/seal，也不要直接修改 foundry 原始 deck。

CSR 规则语义已经取证，block 适用性/排除依据尚待确认。排除 CSR 后，下一步应优先检查最大的非 CSR 规则 `PO.R.8=57`，再取其余三类代表证据：

1. `PO.R.8`：完整 `@` 原文、一个代表 marker 及其所属 cell；
2. `DM2.R.1`：完整 `@` 原文和唯一 result 的位置；
3. `M4.DN.1`：完整 `@` 原文、上下限方向、window/step 和两个坐标；
4. `ESD.WARN.1`：完整 `@` 原文，确认它对 block/full-chip 的适用条件。

下面的只读命令可以复现 `CSR.R.1:M2i` 的规则原文；注意，普通的 `grep -m1 'CSR.R.1'` 会先命中 `DOD.R.2` 中的交叉引用，并不是规则定义：

```csh
set deck = /home/library/tsmc65lp/pdk_new/Calibre/online/drc_online/1p9m_6X2Z0U/calibre.drc

grep -nF -B3 -A12 'CSR.R.1:M2i' "$deck" | head -60
```

若工艺 deck 版本变化、第一条没有输出，再执行：

```csh
grep -nE -B2 -A12 '^[[:space:]]*CSR\.R\.1([^[:space:]{]*)?[[:space:]]*\{' "$deck" | head -80
```

若 rule deck 通过宏动态生成名称、终端仍找不到定义，就在 RVE 中选择 `CSR.R.1:M2i` 的第一个 result，通过 `Rule Text`/`Rule Description` 面板读取从 `@` 开始的完整说明。

用下面三项计数确认整族 CSR 是否都采用相同模式：

```csh
grep -Ec '^[[:space:]]*CSR\.R\.1:' "$deck"
grep -Ec '^[[:space:]]*CSR\.R\.1:.*empty area of chip corner' "$deck"
grep -A1 -E '^[[:space:]]*CSR\.R\.1:' "$deck" | grep -Ec 'EMPTY_AREA[[:space:]]+AND'
```

只有三个数字相等，才把整个 `CSR.R.1:*` 家族归入同一 chip-corner 检查类别。

本项目实测三个数字均为 `145`，因此已经确认 145 条 `CSR.R.1:*` 定义全部使用相同的 `empty area of chip corner` / `EMPTY_AREA AND` 模式。

服务器使用的是 Calibre Interactive nmDRC `v2018.4_34.26`，实测 `Setup` 菜单没有 `Select Checks...`。本项目不再寻找该菜单，改用固定的附加规则文件：

```text
/home/project/cp_training_backend1/users/cpu26/target/PR_ydx/drc_flow/block_checks.svrf
```

文件内容固定为：

```svrf
GROUP CPU26_BLOCK_CSR_EXCLUDE "CSR.R.1:?"
DRC UNSELECT CHECK CPU26_BLOCK_CSR_EXCLUDE
```

这里的 `?` 是 SVRF `GROUP` 对 RuleCheck 名使用的通配符，匹配 `CSR.R.1:` 后的全部名称；不要改写成 Unix 风格的 `*`，也不要直接写 `DRC UNSELECT CHECK CSR.R.1:*`。

由于服务器文件不能从本地导入，可在 `drc_flow` 中一次性生成同名文件：

```csh
printf '%s\n' \
'GROUP CPU26_BLOCK_CSR_EXCLUDE "CSR.R.1:?"' \
'DRC UNSELECT CHECK CPU26_BLOCK_CSR_EXCLUDE' \
>! block_checks.svrf

cat block_checks.svrf
```

保持 Rules 页面中的主 Rules File 仍为原始 PDK deck，不改路径。进入：

```text
Setup -> DRC Options -> Includes
```

加入 `block_checks.svrf` 的绝对路径；如果界面区分 Before/After Main Rules File，选择 After。保存时仍覆盖同一个 `drc.runset`，DRC 仍通过 GUI 的 `Run DRC` 执行，不使用 batch 脚本。

运行后的强制验证条件：

```text
TOTAL DRC RuleChecks Executed: 1674
CSR.R.1 summary 行数        : 0
TOTAL DRC Results Generated : 81（仅在 GDS 和其他配置未变化时）
```

其中 `1674 = 1819 - 145`。任一条件不满足，都不能认定全部 CSR 已排除。

```csh
grep -E '^[[:space:]]*TOTAL DRC (RuleChecks Executed|Results Generated):' drc.summary
grep -Ec '^[[:space:]]*RULECHECK[[:space:]]+CSR\.R\.1:' drc.summary
```

这属于 block-level rule selection，不等于完整 foundry deck signoff clean。取得课程/PDK 对 block 检查范围的认可后，仍覆盖保存同一个 `drc.runset`，并覆盖同名 `drc.results`、`drc.summary`、`drc.log` 和 `drc.nonzero`；不得创建 `_block`、`_2` 等迭代名称。若本轮唯一变化是排除全部 CSR，预期剩余结果数为 `81`。

当前已经可以执行的固定输入流程为：

```text
现有且已通过 LVS 的 data/riscv.gds2
-> 加载 drc.runset
-> 覆盖 drc.results / drc.summary / drc.nonzero / drc.log
-> RVE 复查
```

PR 修复后的完整闭环目前还缺少一项已验证步骤：服务器实际如何从最新 Chip Finish 数据库生成带标准单元/SRAM merge 的 `data/riscv.gds2`。在该步骤确认或修正前，不把旧 GDS 用于新 PR 结果。

确认上游导出后，数据库、GDS、runset 和 DRC 输出仍分别使用表中的固定名称，不增加迭代后缀。文件名固定不等于保留旧结果；每次结果只对应当前的 `data/riscv.gds2`。

## 13. 首轮 GUI 运行后的回传证据

第一次在服务器 GUI 中保存 `drc.runset` 并完成 DRC 后，保留下面四项证据，便于继续判断是否需要修改 GUI 配置或回到 PR 修复：

```csh
cd /home/project/cp_training_backend1/users/cpu26/target/PR_ydx/drc_flow

# 从过长的 summary 中按规则名去重，只保留每条非零规则的最大计数。
awk '$1=="RULECHECK" { c=0; for(i=1;i<=NF;i++) if($i=="=") { c=$(i+1)+0; break } r=$2; if(c>v[r]) v[r]=c } END { for(r in v) if(v[r]>0) printf "%8d  %s\n",v[r],r }' drc.summary | sort -k1,1nr >! drc.nonzero

wc -l drc.nonzero
awk '{s+=$1} END {print "dedup_total =",s}' drc.nonzero
head -80 drc.nonzero
tail -80 drc.nonzero

tail -20 drc.summary
cat drc.runset

# 已保存 GUI transcript 时再执行。
grep -niE 'fatal|abort|referenced but not defined|warning|error' drc.log | head -100
tail -50 drc.log
```

同时保存一张 RVE 左侧完整规则树截图。截图至少要能看到：

- 规则名；
- `Results`/`Flat` 数量；
- 顶层 cell `riscv`；
- 任意一个代表性错误的 `@` 规则说明和坐标。

首轮运行前本地没有 `drc.runset` 是正常的；它只能由当前服务器版本的 nmDRC GUI 首次保存后生成。`head`/`tail` 只用于快速预览，非零规则超过 160 行时会省略中间部分。

如果服务器文件无法导出到本地，不需要上传 `drc.nonzero`。直接在服务器终端用下面两条命令生成少量屏幕输出并截图：

```csh
# 按冒号前的规则族聚合，只显示结果数最多的前 40 族。
awk '$1=="RULECHECK" { c=0; for(i=1;i<=NF;i++) if($i=="=") { c=$(i+1)+0; break } r=$2; if(c>v[r]) v[r]=c } END { for(r in v) if(v[r]>0) { f=r; sub(/:.*/,"",f); n[f]++; s[f]+=v[r] } for(f in s) printf "%10d  %4d unique_checks  %s\n",s[f],n[f],f }' drc.summary | sort -k1,1nr | head -40

# 不聚合，显示单项结果数最多的前 60 条非零规则。
head -60 drc.nonzero

# runset 很小，可直接整屏显示。
sed -n '1,120p' drc.runset

```

把这三段终端输出分别截图即可，不需要把任何服务器文件复制出来。RVE 中的规则原文和全芯片高亮同样直接截图。
