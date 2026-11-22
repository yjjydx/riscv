# PrimeTime 完整流程

## 1. 流程概览

```text
Innovus 完成布局布线
    ↓
导出 riscv.def、riscv.vg、riscv_post_pr.sdc
    ↓
StarRC 根据 DEF、LEF 和 RC 工艺文件生成 SPEF
    ↓
PrimeTime 读取网表、时序库、SDC、SPEF
    ↓
检查寄生标注率并分析 setup、hold 和 DRV
```

## 2. 输入文件

| 文件 | 作用 |
|---|---|
| `riscv.vg` | CTS、ECO 和布线后的最终门级网表 |
| `riscv.def` | 单元位置、布线和通孔几何信息 |
| `riscv_post_pr.sdc` | 时钟、IO 延迟和例外路径约束 |
| 标准单元与 SRAM `.db` | 单元延时、功耗和电气规则模型 |
| `riscv_core_typical.spef` | StarRC 提取的互连电阻与电容 |

`riscv.vg`、`riscv.def` 和 `riscv_post_pr.sdc` 必须来自同一次 PR；SPEF 必须由该 DEF 重新提取。

## 3. StarRC 提取寄生 RC

配置文件：`starrc.cmd`

关键输入：

```text
TOP_DEF_FILE  → 最终 riscv.def
LEF_FILE      → Tech LEF、SRAM LEF
TCAD_GRD_FILE → RC 工艺参数库 nxtgrd
MAPPING_FILE  → DEF 层名到 StarRC 层名的映射
NETLIST_FILE  → 输出 SPEF
```

`def_starrc.map` 只负责名称映射，如 `M1 → metal1`；`starrcxt.nxtgrd` 才包含金属电阻、电容和介质参数，两者不能互相替代。

运行：

```bash
cd /home/project/cp_training_backend1/users/cpu26/target/PT_test/starrc_flow
bash -lc 'StarXtract -clean starrc.cmd 2>&1 | tee starrc_run.log'
```

检查结果：

```bash
tail -100 starrc_run.log
cat starrc.sum
ls -lh --time-style=long-iso riscv_core_typical.spef
grep -m1 '^\*DESIGN' riscv_core_typical.spef
grep -c '^\*D_NET' riscv_core_typical.spef
```

日志应正常结束并出现 `Done`，SPEF 中的 `*DESIGN` 应为 `riscv`，`*D_NET` 数量应大于 0。

## 4. PrimeTime 分析

脚本：`pt.tcl`

执行顺序：

```text
设置 link_library
→ read_verilog
→ current_design / link_design
→ read_parasitics
→ 读取 SDC
→ set_propagated_clock
→ check_timing
→ 检查寄生标注率
→ update_timing
→ 输出 setup、hold 和约束报告
```

运行：

```bash
cd /home/project/cp_training_backend1/users/cpu26/target/PT_test
bash -lc 'pt_shell -f script/pt.tcl 2>&1 | tee pt_run.log'
```

当前脚本默认关闭人为 OCV derate：

```tcl
set enable_ocv_derate false
```

因此原来的 `clock late=1.08`、`data late=1.11` 不生效；`set_propagated_clock` 和 `0.04 ns` clock uncertainty 保留。

## 5. 关键检查

### 5.1 寄生标注

```tcl
report_annotated_parasitics -check -max_nets 1000 \
  -list_not_annotated -pin_to_pin_nets
```

不能存在大量 `not annotated`，否则通常表示 SPEF 与网表的实例名或版本不一致。

### 5.2 Setup 和 Hold

- `slack >= 0`：满足时序。
- `slack < 0`：存在时序违例。
- Setup 查看 `-delay_type max`。
- Hold 查看 `-delay_type min`。

### 5.3 DRV

重点检查：

```text
max_transition
max_capacitance
max_fanout
min_period / min_pulse_width
```

时序通过不代表 DRV 一定通过，两者需要分别判断。

## 6. 当前流程限制

1. StarRC 暂时使用 `1p9m_6X1Z1U/starrcxt.nxtgrd`，它与 PR 使用的 `9lmT2 + alrdl_top2` 是否对应仍未确认。
2. Setup 和 Hold 当前共用慢角 `wc/ss` 库，Hold 只能作为初步检查；正式 Hold 应使用 `bc/ff` 快角库。
3. Setup 和 Hold 当前共用一个 typical SPEF，尚未建立 RC worst/best 双角分析。
4. 当前关闭 OCV derate，结果表示不考虑人为工艺变化放大系数时的时序情况。

以上流程可用于比赛调试和结果复现；严格 signoff 还需要匹配的 RC 工艺模型、快慢角库和多角分析配置。
