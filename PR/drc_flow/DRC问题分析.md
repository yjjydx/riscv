# DRC 问题分析与处理记录

> 记录日期：2026-07-14  
> 适用对象：`riscv`（CPU + SRAM block）  
> 版图输入：`/home/project/cp_training_backend1/users/cpu26/target/PR_ydx/data/riscv.gds2`  
> 运行方式：服务器 Calibre Interactive / nmDRC GUI

## 1. 当前结论

首轮 DRC 的 `21163` 条结果中，`21082` 条来自 `CSR.R.1:*`。现有规则原文与工程层级证据高度表明，本次大量 CSR result 来自 chip-corner `EMPTY_AREA` 检查施加到 CPU + SRAM block；这是当前的高置信度工程判断，最终适用性仍需课程要求或 PDK block-flow 规范确认。

在不修改原始 PDK rule deck 的前提下，通过 GUI 加载固定的 block 规则选择文件。该文件按设计意图匹配 `145` 条 `CSR.R.1:*`；当前已确认原本非零的 `36` 个 CSR 子检查不再产生结果，RVE 已从 `21163 Results` 降到：

```text
riscv, 81 Results (in 19 of 22 Checks)
```

这说明 CSR 大量结果已经被正确移出本次 block-level DRC；剩余 `81` 条仍需逐项分析，当前不能称为 DRC clean。

后续对 `PO.R.8` 的定位已经确认：现有结果集中在 `clk`、`rst` 两个 block 顶层输入的直接负载区域。这两个网络在当前 GDS 中有实际布线和内部负载，但其块外驱动不属于 `riscv.gds2`。当前决定在继续调试其他规则时暂时屏蔽 `PO.R.8`；该动作属于临时 rule selection，不是版图修复，也不能据此宣称完整 DRC clean。屏蔽后的数量仍需由新一轮 `drc.summary` 和 RVE 验证。

## 2. 首轮“大量错误”的数量复盘

首轮 `drc.summary` 页脚显示：

```text
TOTAL DRC RuleChecks Executed: 1819
TOTAL DRC Results Generated:   21163
```

按规则名去重统计后：

| 类别 | 报告结果数 | 占总结果比例 |
| --- | ---: | ---: |
| `CSR.R.1:*` | 21082 | 约 99.62% |
| 其他规则 | 81 | 约 0.38% |
| 合计 | 21163 | 100% |

其中 `CSR.R.1:*` 有 `36` 个非零子检查。部分子检查显示 `1000`，可能已经达到单项结果上限，所以 `21082` 只能理解为结果库中报告出来的 marker 数，不能保证等于所有真实几何违例的总数。

### `drc.summary` 看起来重复的原因

同一个非零 `RULECHECK` 会在 `drc.summary` 的两个统计区块中各列一次。简单地把所有 `RULECHECK` 行累加，会得到两倍结果：

```text
CSR：42164 = 2 × 21082
全部：42326 = 2 × 21163
```

这不是 Calibre 把 marker 生成了两遍，也不是 DRC 又跑了一次。权威总数应以 `drc.summary` 页脚和 RVE 顶部的 Results 数量为准。

## 3. 高置信度工程判断：chip-corner 检查与当前 block 层级不匹配

### 3.1 当前 `riscv` 是 block，不是完整 full-chip

从现有 PR 工程可以确认：

- 顶层使用 `editPin` 放置 block pins；
- 只建立了 core ring 和 SRAM block ring；
- 加载的物理 LEF 为标准单元 tech/physical LEF 和 SRAM LEF，未发现 IO pad、corner 或 ESD 库 LEF；
- 未看到 IO pad、corner cell、ESD pad、seal ring、scribe line 等 full-chip 结构；
- Chip Finish 阶段还导出了 `write_lef_abstract`，这是典型的 block/hard macro 交付物。

因此，当前 GDS 的实现层级应按 CPU + SRAM block 理解。

### 3.2 `CSR.R.1:*` 实际检查的内容

对原始 PDK deck 的检查结果为：

```text
CSR.R.1:* 定义总数                         145
描述含 empty area of chip corner 的数量   145
下一行使用 EMPTY_AREA AND 的数量          145
```

代表性规则如下：

```svrf
CSR.R.1:M2i { @ M2i is not allowed inside the empty area of chip corner.
  EMPTY_AREA AND M2i
}
```

RVE 中 `CSR.R.1:M2i` 的一个 marker 坐标为：

```text
(8.000 21.635) (12.000 21.635) (12.000 21.965) (8.000 21.965)
```

这些规则不是普通的 M1/M2 间距、宽度或短路检查，而是在检查 `chip corner` 的 `EMPTY_AREA` 派生区域与某类图形是否相交。结合标准单元、implant、contact、SRAM marker、各层金属和 via 等多种派生层同时触发的 RVE 现象，判断这些结果共享同一个 `EMPTY_AREA` 区域条件；`EMPTY_AREA` 的具体边界派生尚未单独展开验证。

### 3.3 为什么不能逐个修改这些 marker

若沿着 `21082` 个 CSR marker 逐点改 M1、M2、implant 或 via，会破坏已经完成的布局布线，而且没有解决层级不匹配这个根因。也不能为了消除 CSR 报告而伪造 IO、corner 或 seal 结构。

正确动作是在明确本次交付目标是 block DRC 后，进行 **block-level rule selection**。如果最终验收要求 full-chip，则不能排除 CSR，必须补全 pad/corner/seal/芯片边界后重新运行完整 deck。

## 4. 已采用的解决方法

### 4.1 固定规则选择文件

服务器固定文件：

```text
/home/project/cp_training_backend1/users/cpu26/target/PR_ydx/drc_flow/block_checks.svrf
```

文件内容：

```svrf
// CPU+SRAM block-level DRC selection.
// The 145 CSR.R.1:* checks are full-chip corner EMPTY_AREA checks.
// Keep all non-CSR checks enabled.
GROUP CPU26_BLOCK_CSR_EXCLUDE "CSR.R.1:?"
DRC UNSELECT CHECK CPU26_BLOCK_CSR_EXCLUDE
```

这里的 `?` 家族匹配方式已验证能够移除本次所有原本非零的 CSR 结果；是否使全部 `145` 条 RuleCheck 均未执行，仍待新版 `drc.summary` 确认 `1674` 和 CSR summary 行数为 `0`。不要把该匹配方式泛化成所有工具都相同的通配符规则。

### 4.2 GUI 中的加载方式

1. 主 Rules File 继续使用原始 PDK deck：

   ```text
   /home/library/tsmc65lp/pdk_new/Calibre/online/drc_online/1p9m_6X2Z0U/calibre.drc
   ```

2. 在 Calibre Interactive 中进入 `Setup -> DRC Options -> Includes`。
3. 添加 `block_checks.svrf` 的绝对路径。
4. 如果界面要求选择 Include 顺序，选择主规则之后，即 **After main rules**。
5. 覆盖保存同一个 `drc.runset`，不要生成日期或迭代后缀。
6. 继续通过 GUI 点击 `Run DRC`，覆盖同名 `drc.results` 和 `drc.summary`。

没有修改、复制或覆盖 PDK 原始 `calibre.drc`。

### 4.3 当前验证结果

RVE 已确认：

- 总结果从 `21163` 降为 `81`；
- 当前为 `19` 个非零检查；
- 非零结果树中不再出现 `CSR.R.1:*`。

按首轮执行数推算，排除 `145` 条 CSR 检查后应执行：

```text
1819 - 145 = 1674 RuleChecks
```

但目前还没有截取新版 `drc.summary` 页脚，所以 `1674` 仍是预期值，不写成已确认。需要在服务器补做：

```csh
cd /home/project/cp_training_backend1/users/cpu26/target/PR_ydx/drc_flow
grep -E '^[[:space:]]*TOTAL DRC (RuleChecks Executed|Results Generated):' drc.summary
grep -Ec '^[[:space:]]*RULECHECK[[:space:]]+CSR\.R\.1:' drc.summary
```

期望输出分别证明：

```text
TOTAL DRC RuleChecks Executed: 1674
TOTAL DRC Results Generated:   81
CSR.R.1 summary 行数：          0
```

只有这 `145` 条 CSR 定义原本均属于首轮 `1819` 个已执行 RuleCheck，且 GDS、主 deck 和 runset 其他选项都未变化时，`1819 - 145 = 1674` 才成立。

## 5. 剩余 81 条结果

当前 RVE 中的数量能够完全闭合：

| 规则 | 数量 | 当前判断 |
| --- | ---: | --- |
| `PO.R.8` | 57 | 已定位为 `clk/rst` 顶层输入缺少块外驱动上下文；计划在调试阶段临时屏蔽，不等于修复 |
| `PO.DN.2` | 1 | 已确认是 OD/DOD/PO/DPO 的局部最小密度检查 |
| `M2.DN.1` | 2 | 金属密度类；阈值和位置待读取 |
| `M3.DN.1` | 2 | 金属密度类；阈值和位置待读取 |
| `M4.DN.1` | 2 | 金属密度类；阈值和位置待读取 |
| `M5.DN.1` | 2 | 金属密度类；阈值和位置待读取 |
| `M6.DN.1` | 1 | 金属密度类；阈值和位置待读取 |
| `M7.DN.1` | 1 | 金属密度类；阈值和位置待读取 |
| `M8.DN.1` | 2 | 金属密度类；阈值和位置待读取 |
| `M9.DN.1` | 2 | 金属密度类；阈值和位置待读取 |
| `DM2.R.1` ～ `DM9.R.1` | 各 1，共 8 | 规则含义待读取，暂不能直接解释成 dummy metal |
| `ESD.WARN.1` | 1 | 警告规则含义待读取，不能仅因名字含 WARN 就豁免 |
| **合计** | **81** | **仍需处理** |

数量分类为：

```text
PO.R.8             57
PO/Metal DN        15
DM2～DM9            8
ESD.WARN.1          1
总计                81
```

RVE 中绿色的 `DENSITY_PRINT_FILES = 0` 只说明这个控制/输出 check 没有 marker，不代表 `PO.DN.2` 或 `M2～M9.DN.1` 已通过。

## 6. 剩余结果的处理方法

### 6.1 `PO.R.8`：57 条，已定位为 block 顶层输入上下文

#### 6.1.1 规则含义与产生原因

PDK deck 中的规则原文为：

```svrf
PO.R.8 { @ It is prohibited for Floating Gate if the effective source/drain is not connected together
  Float_GATE_check INTERACT NSDu > 1 BY NET
  Float_GATE_check INTERACT PSDu > 1 BY NET
}
```

它是浮空栅极相关的物理连通性检查。Calibre 只根据当前参与检查的 GDS 层级提取网络，不会自动假设版图之外将来会接入什么驱动电路。

当前检查对象是独立的 `riscv` block：

```text
块外环境（不在 riscv.gds2 中）
              │
              ▼
          clk / rst
              │
              ▼
       block 内部布线和栅极负载
```

`clk` 和 `rst` 是 `riscv` 的顶层输入。在当前 GDS 中，Calibre 可以看到端口、布线以及标准单元的 gate 负载，却看不到本应位于父层、IO 或上一级逻辑中的驱动器件及其源/漏极路径。因此，从这个独立版图层级观察，相关网络呈现出“连接了 gate，但没有可见的块内驱动器件”的特征，从而触发 `PO.R.8`。

Innovus 的只读查询给出了以下证据：

| 网络 | 端口方向 | block 内部 driver | 物理 wire 数 | 直接负载数 |
| --- | --- | --- | ---: | ---: |
| `clk` | `input` | `<NONE>` | 7 | 2 |
| `rst` | `input` | `<NONE>` | 27 | 4 |

`clk` 的直接负载为：

```text
U_IR/clk_gate_out_ins_reg/latch/CP    CELL=CKLND6
CTS_cci_inv_00043/I                  CELL=INVD8
```

`rst` 的直接负载为：

```text
U_IR/U3/I                            CELL=CKND4
U_PC/U2/I                            CELL=CKND4
U_ControlUnit/U3/I                   CELL=CKND8
FE_DBTC23_rst/I                      CELL=CKND2
```

这些负载的 bbox 与 RVE 中现有 `PO.R.8` marker 的空间区域相符。`WIRE_COUNT` 非零说明这里不是端口断线；`DRIVER=<NONE>` 对 block 顶层输入本身也是合理现象，因为其驱动按接口定义应来自父层。

LVS 正确与该结果并不矛盾。LVS 对比允许 block 顶层输入没有 block 内部 driver，而 `PO.R.8` 检查的是当前物理层级中是否存在可见的有效驱动环境。

对 deck 的关键词检查没有发现明显适用于 `PO.R.8` 的官方 block/IP/port 模式：deck 中名为 `Block` 的对象是工艺派生层，不是层级验证开关；`SRAMDMMY` 和 `LUPWDMY` 分别是 SRAM、Latch-Up 的专用 waiver 层，`PO.R.8` 本身没有引用这些排除条件，不能拿它们来掩盖本规则。

#### 6.1.2 当前 standalone `riscv` 与 verification wrapper 的区别

当前 standalone `riscv` 只包含 CPU、SRAM、供电和 block 内部布线。它没有完整芯片级的 IO pad、输入接口、ESD、corner、seal ring，也没有承载 `clk/rst` 块外驱动的父层电路。

一个合法的 verification wrapper 则是在不修改 `riscv` 内部逻辑的前提下，另外建立更高一层验证顶层，例如：

```text
wrapper 外部端口
        │
        ▼
合法 IO/pad、输入接口或 PDK 认可的端口模型
        │
        ▼
     clk / rst
        │
        ▼
   riscv block 实例
```

二者的区别为：

| 项目 | 当前 standalone `riscv` | verification wrapper |
| --- | --- | --- |
| DRC 顶层 | `riscv` | 包含 `riscv` 实例的更高层验证顶层 |
| `clk/rst` 驱动 | 位于当前 GDS 之外，Calibre 不可见 | 在检查层级中通过合法接口器件或正式模型明确呈现 |
| Calibre 可见内容 | 端口、布线和内部 gate 负载 | 接口环境、驱动路径、`riscv` 端口及内部负载 |
| `PO.R.8` | 可能因缺少父层上下文而产生 | 模型与连接正确时，相关上下文结果应自然消失 |
| 对 `riscv` 的影响 | 原始交付 block | wrapper 仅提供验证环境，不应修改 block 内部功能和版图 |

wrapper 不能由随意绘制的图形、假的 tie 或任意标准单元拼成。普通 buffer 如果其输入仍然没有合法驱动，只会把浮空问题转移到上一级。必须使用该 PDK/项目正式允许的 IO/pad、输入接口或端口模型，正确连接电源、地和信号，并在不屏蔽 `PO.R.8` 的情况下重新验证。wrapper 通过也只证明 `riscv` 放入该验证环境后满足规则；最终 full-chip 如果采用不同接口，仍需在实际顶层重新检查。

#### 6.1.3 当前临时屏蔽决定及其边界

当前决定在 block 调试阶段暂时不执行 `PO.R.8`，以便先处理其余 DRC 结果。拟在项目自己的附加 SVRF 中使用：

```svrf
GROUP CPU26_BLOCK_PO_R8_EXCLUDE "PO.R.8"
DRC UNSELECT CHECK CPU26_BLOCK_PO_R8_EXCLUDE
```

这两行只是让 Calibre 不再执行该 RuleCheck，不会改变任何版图图形、网络或器件，因此必须准确表述为“临时屏蔽/排除”，不能表述为“`PO.R.8` 已修复”。在尚未重跑前，权威原始结果仍是 `81`；若其他条件不变，屏蔽后预期活动结果为 `81 - 57 = 24`，但必须用新的 `drc.summary` 和 RVE 实际确认。

整条屏蔽的风险是：它不仅隐藏现有的 `clk/rst` 上下文结果，也会隐藏以后新出现的真实内部浮空 gate。为控制风险，应做到：

1. 不修改原始 PDK deck，只在项目自己的附加文件中操作；
2. 保留未屏蔽运行的 `57` 个结果、网络查询和 marker 证据；
3. 汇报时分别记录“当前活动结果”和“被临时屏蔽的 `PO.R.8` 结果”；
4. 任何 `clk/rst`、顶层端口、相关标准单元或布线发生变化后，恢复规则并重新检查；
5. 如工具和验收流程支持，优先采用具体结果级 waiver，而不是永久关闭整条规则。

出现以下任一情况时，必须恢复 `PO.R.8`：

- 建立了合法的 verification wrapper；
- `riscv` 被集成到包含真实 IO/pad 的 full-chip；
- 进入最终 DRC/signoff 或正式提交验收阶段；
- `clk/rst`、顶层端口或相关版图连接发生修改；
- 出现无法证明属于块外输入上下文的新 `PO.R.8` marker。

恢复规则后，应确认相关结果确实因为合法驱动环境而消失；否则仍需继续定位，或按照课程/PDK 流程申请有记录的具体结果级 waiver。

### 6.2 `PO.DN.2`：局部最小密度，1 条

RVE 已显示规则原文：

```text
{OD OR DOD OR PO OR DPO} local density (minimum)
over window 20um × 20um, stepping 10um >= 0.1%
```

marker 坐标为：

```text
(0.0 48.0) (20.0 48.0) (20.0 438.0) (0.0 438.0)
```

它位于版图左侧边界，表示连续的一组 `20 µm × 20 µm` 滑动窗口中，OD/DOD/PO/DPO 合并密度低于 `0.1%`。该 `20 × 390 µm` 长条 marker 与多个连续失败窗口被合并或派生为长条区域的现象一致，但仍需在 RVE 或规则输出中确认；不能把它当作单个 `20 × 390 µm` 窗口，更不能照着 marker 手画一个大图形。

处理步骤：

1. 在 RVE/版图查看器中确认 marker 与 core boundary、row 终点和 placement blockage 的关系；
2. 在 PDK deck 中读取 `CHIPx`、`PODEXC` 和相关 exclusion 的定义；
3. 判断 block 边缘是否应使用 PDK 认可的 density exclusion；
4. 如果该区域确实必须参与密度检查，则使用工艺认可的 OD/PO fill 流程，而不是手工画任意图形；
5. 修改后只重跑 DRC，并确认该规则由 `1` 变为 `0`。

### 6.3 `M2～M9.DN.1`：金属密度，共 14 条

这些规则是剩余的金属密度类结果，但目前还没有各层规则的 `@` 原文、窗口、步长、阈值和坐标。不能仅看 `.DN.1` 就直接添加 metal fill。

应先在 RVE 对每一层至少取一个 marker，记录：

- minimum 还是 maximum density；
- window 和 step；
- marker 是否都贴着 block 四边；
- 是否落在 SRAM、power ring、routing blockage 或 macro halo 附近；
- PDK 是否提供专用 metal fill / density fill 流程。

如果确认是最小密度不足，再走 PDK/Innovus 认可的 metal fill 流程；如果属于 block 边界窗口，则先核对 deck 的 block/chip 边界配置和 density exclusion，不能用错误的填充掩盖边界配置问题。

### 6.4 `DM2.R.1～DM9.R.1`：每层 1 条，共 8 条

仅凭 `DM` 前缀不能断定它就是“缺少 dummy metal”。每层恰好一条，可能是全局/边界类 marker，也可能是某个派生层规则。

应先展开 `DM2.R.1`，读取完整 `@` 说明和坐标，再检查 `DM3～DM9` 是否完全同构。若八层说明和位置相同，可作为同一根因处理；若不同，则分别处理。没有读到规则原文前不做 waiver，也不手工补图形。

### 6.5 `ESD.WARN.1`：1 条

当前 block 没有完整 ESD pad 结构，确实可能触发 full-chip/ESD 相关警告，但这只是工程推测。必须先读取该规则完整说明、涉及层和 marker 位置，再判断它是否属于：

- block 交付允许的已知 warning；
- 缺少 ESD/pad wrapper 的层级性提示；
- 或当前 block 内真实需要修复的连接/几何问题。

在得到课程验收或 PDK 使用规范确认前，不能因为规则名包含 `WARN` 就直接忽略。

## 7. GUI 的 32 个 Warnings 不是 DRC marker

首轮 GUI 的 Warnings 面板显示 `32` 条运行期 warning，其中可见多次：

```text
Cell name parameter for INSIDE CELL operation not located.
```

这些是运行期 warning，与 `21163` 个 DRC Results 属于不同通道，不能说它们导致了大量 CSR marker，也不能仅凭 DRC 正常结束就认定全部无害。

后续应通过 GUI 的 Transcript 菜单把日志固定保存为：

```text
/home/project/cp_training_backend1/users/cpu26/target/PR_ydx/drc_flow/drc.log
```

然后至少确认：

```csh
grep -niE 'warning|cell name parameter|projecting operation|fatal|abort|referenced but not defined' drc.log
```

应先看所有唯一 warning，再判断是否与 block 缺少特定 full-chip cell 有关。如果这些消息没有写入 Transcript，必须直接在 GUI Warnings 面板中查看或截图，不能用 `grep` 无输出证明 warning 已清零。

## 8. 不应采用的处理方式

- 不修改 `/home/library/.../calibre.drc` 原始 PDK deck；
- 不逐点修改 `21082` 个 CSR marker；
- 不伪造 IO pad、corner cell、seal ring 或 ESD 图形；
- 不为消除 `PO.R.8` 而给 `clk/rst` 增加假的 tie、随意的 buffer 或虚构驱动；
- 不把 CSR 排除描述为“修好了版图几何”；
- 不把临时屏蔽 `PO.R.8` 描述为“浮空栅极已经修复”；
- 不把当前结果描述为 foundry signoff DRC clean；
- 不根据 `*.density`、`*.rep` 是否为空判断 DRC pass/fail；
- 不根据 `DENSITY_PRINT_FILES = 0` 判断其他 density 规则已通过；
- 不在没有读取规则原文时盲目加 PO/metal/dummy fill；
- 不为重跑创建 `drc_1`、`drc_2`、`final` 或日期后缀。

`*.density`、`*.rep` 是 PDK deck 按固定名生成的辅助输出；文件为 0 字节或非 0 字节，以及 `ls` 显示的 `total`，都不是 DRC 数量或 pass/fail 证据。判断结果仍以 `drc.summary` 和 RVE 为准。

## 9. 固定文件和下一步

所有重跑继续使用固定名字：

| 文件 | 用途 |
| --- | --- |
| `drc.runset` | GUI 配置 |
| `block_checks.svrf` | 项目级 block rule selection；当前包含 CSR 排除，如执行本次决定则追加 `PO.R.8` 临时屏蔽 |
| `drc.results` | RVE 结果库 |
| `drc.summary` | 汇总报告 |
| `drc.nonzero` | 非零规则摘要 |
| `drc.log` | GUI Transcript |

后续顺序固定为：

1. 在修改 rule selection 前记录当前未屏蔽运行的 `81` 条结果及 `PO.R.8=57` 证据；
2. 如按当前决定临时屏蔽 `PO.R.8`，只修改项目自己的 `block_checks.svrf`，继续通过同一个 GUI runset 覆盖重跑；
3. 在 GDS、主 deck 和其他选项不变时，预期为 `1673 RuleChecks / 24 Results`，并且 CSR、`PO.R.8` summary 行数均为 `0`；该数字必须由新版 `drc.summary` 实际验证，不能提前写成已确认；
4. 保存并检查 `drc.log` 中的唯一 warnings；
5. 核查 `PO.DN.2` 左边界窗口；
6. 依次读取 `M2.DN.1`、`DM2.R.1`、`ESD.WARN.1` 的完整规则原文和代表坐标；
7. 每次只改变一种原因对应的版图或配置，再通过同一个 GUI runset 覆盖重跑；
8. 最终同时报告活动结果和临时屏蔽项，以 `drc.summary` 页脚、RVE 和 waiver/rule-selection 记录为验收依据。

## 10. 验收边界

当前 CSR 处理的准确表述是：

> 本次已对 CPU + SRAM block 通过附加 SVRF 实施 block-level CSR rule selection；其是否可用于最终验收，仍待课程要求或 PDK block-flow 规范认可。

当前 `PO.R.8` 处理的准确表述是：

> 已确认现有 `PO.R.8` 结果与 `clk/rst` 顶层输入缺少块外驱动上下文有关；为继续 block 调试，暂时在项目级附加 SVRF 中屏蔽该 RuleCheck。该动作不是版图修复，原始 `57` 个结果仍需记录，并应在 verification wrapper、full-chip 或最终 signoff 阶段恢复检查。

这不等于完整芯片的 foundry signoff clean。若课程最终要求提交 full-chip GDS，应恢复完整 deck，不加载该排除文件，并补齐 IO/pad/corner/seal/ESD 等芯片级结构后重新 DRC。
