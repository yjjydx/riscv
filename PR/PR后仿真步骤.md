# PR 后仿真（VCS + SDF）

目标：验证 **PR 最终门级网表 + CTS/布线延迟** 下，程序仍能使 `x31=1`。

## 1. 需要的文件

| 文件 | 来源/用途 |
|---|---|
| `riscv.vg` | PR 最终门级网表。当前 `step6.chipfinish.tcl` 的 `saveNetlist ../data/${init_design}.vg` 会导出。 |
| `riscv_post_pr.sdf` | 必须由**同一份最终 Innovus 数据库**导出，包含单元、CTS 与布线延迟。 |
| `riscv_post_pr.sdc` | 后端最终约束；用于记录/STA，不直接放入 VCS `files.f`。 |
| 标准单元 Verilog 模型 | `/home/library/tsmc65lp/std/TSMCHOME/digital/Front_End/verilog/tcbn65lp_200a/tcbn65lp.v` |
| SRAM Verilog 模型 | `/home/library/tsmc65lp/sram/ts1n65lpll2048x64m8_220a/VERILOG/ts1n65lpll2048x64m8_220a_ss1p08v125c.v` |
| `riscv_pr_sim.v` | PR 专用 TB：时钟、复位、SDF 标注、SRAM 指令预加载、x31 检查。 |
| `code.hex` | 每行一条 32-bit 指令。 |
| `sram.preload.data` | 由 `code.hex` 转出的 64-bit 二进制指令文件，供 SRAM 模型的 `preloadData()` 使用。 |

`SPEF` 用于 PrimeTime/STA；VCS 后仿真直接使用 SDF，不把 SPEF 加入 `files.f`。

## 2. 导出成对的 PR 网表和 SDF

在 Innovus 的**最终 chipfinish/postroute 数据库**中执行；网表和 SDF 必须在同一次最终数据库状态下导出：

```tcl
saveNetlist ../data/riscv.vg
write_sdf ../data/riscv_post_pr.sdf
write_sdc ../data/riscv_post_pr.sdc
```

当前 `PR/step6.chipfinish.tcl` 已有 `saveNetlist` 与 `write_sdc`；补充 `write_sdf` 后再运行最终导出阶段。

## 3. 生成 SRAM 预加载文件

在 VCS 的 `sim/` 目录执行：

```csh
tr -d '\r' < ../hex/code.hex | \
perl -ne 'chomp; next if /^\s*$/; die "bad word: $_\n" unless /^[0-9A-Fa-f]{8}$/; printf "%064b\n", hex($_);' \
>! sram.preload.data

wc -l ../hex/code.hex sram.preload.data
```

两者行数必须相同。不要在 PR 门级网表 TB 中使用 RTL 的 `$readmemh(...U_IM.memory)`。

## 4. PR TB 的关键内容

1. 实例化 PR 网表顶层：`riscv U_RISCV (...)`。
2. 标注最终 SDF：

```verilog
// setup 后仿真：Innovus SDF 常为 min::max，typical 为空
$sdf_annotate("../rtl/riscv_post_pr.sdf", U_RISCV, , , "MAXIMUM");
```

若单独进行 hold 后仿真，将最后一个参数改为 `"MINIMUM"`。不要使用默认的
`TYPICAL`，否则空的 typical 延迟可能被 VCS 当作零延迟。

3. 先从最终 PR 网表确认 SRAM/x31 层级，不能沿用旧网表的假设：

```csh
grep -n 'TS1N65LPLL2048X64M8' ../rtl/riscv.vg
grep -n 'register\[31\]\|register_reg\[31\]' ../rtl/riscv.vg | head
```

4. 将 grep 得到的指令 SRAM 实例用于：

```verilog
defparam <IM_SRAM_INSTANCE>.preloadFile = "sram.preload.data";
#1 <IM_SRAM_INSTANCE>.preloadData();
```

5. x31 要读取触发器的 `Q` 网线（通常是 `register[31][bit]`），不是 `register_reg[...]` 触发器实例。
6. TB 时钟必须与 PR 约束一致；200 MHz 对应 `always #2.5 clk = ~clk;`（`timescale 1ns/1ps`）。复位在负边沿后释放，避开上升沿。

## 5. `files.f` 与运行

```text
/home/library/tsmc65lp/std/TSMCHOME/digital/Front_End/verilog/tcbn65lp_200a/tcbn65lp.v
/home/library/tsmc65lp/sram/ts1n65lpll2048x64m8_220a/VERILOG/ts1n65lpll2048x64m8_220a_ss1p08v125c.v
../rtl/riscv.vg
../tb/riscv_pr_sim.v
```

VCS 编译与运行时不要使用 `+notimingchecks` 或 `+nospecify`。运行参数至少包含：

```makefile
./simv +neg_tchk +sdfverbose -l simv.log
```

`+neg_tchk` 同时放入 `vcs` 编译命令，并在修改后执行 `make clean && make test`，避免复用旧 `simv`。

> 当前 CPU 的 SRAM 地址会在时钟边沿切换，而 SRAM 行为模型会把该模型级 timing check
> 直接传播为 `X`。`riscv_pr_sim.v` 默认仅 force `U_SRAM_IM/U_SRAM_DM` 的
> `check_noidle=0`，保留标准单元及 SDF 延迟检查；SRAM 引脚的严格 setup/hold 结论以
> Innovus 的 `U_IM/U_SRAM_IM/A[*]`、`CLK` STA 报告为准。若需要观察模型自身的 SRAM
> timing check，将 `DISABLE_SRAM_TIMING_CHECKS` 改为 `1'b0`。

## 6. 通过判据

```csh
grep -E 'PASS|FAIL|Timing violation|SDFCOM' simv.log
```

- 看到 `PASS: x31 = 0x00000001`：功能检查通过。
- 出现 `Timing violation`：PR 时序仿真未通过，不能只靠延长等待时间解决。
- 出现大面积 SDF 未标注/实例不匹配：检查 `riscv.vg` 与 `riscv_post_pr.sdf` 是否由同一次最终 PR 数据库导出。
