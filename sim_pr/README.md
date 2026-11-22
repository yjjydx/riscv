# PR 后仿真（sim_pr）

本目录用于验证 **PR 最终网表 + 最终 SDF**。它包含 CTS、布线和寄生延迟，是最终物理实现后的门级功能验证。

## 目录约定

```text
sim_pr/
├── hex/    # code.hex
├── rtl/    # 同一次 Innovus 最终数据库导出的 .vg/.v、.sdf、.sdc
├── tb/     # riscv_pr_sim.v
└── sim/    # files.f、Makefile、sram.preload.data、VCS 产物
```

## 关键要求

- PR 网表和 SDF 必须由同一次最终 post-route/chipfinish 数据库导出。
- `files.f` 依次加入标准单元模型、SRAM 模型、PR 网表、`riscv_pr_sim.v`。
- `.sdc` 用于记录和 STA，不放入 VCS `files.f`；SPEF 也不直接用于 VCS。
- TB 时钟与约束一致：200 MHz 使用 `` `timescale 1ns/1ps`` 和 `always #2.5 clk = ~clk;`。
- SDF 标注建议明确指定角：`$sdf_annotate("../rtl/riscv_post_pr.sdf", U_RISCV, , , "MAXIMUM");`。单独检查 hold 时改为 `"MINIMUM"`。

## 运行

在 `sim_pr/sim/` 中生成 SRAM 预加载文件：

```csh
tr -d '\r' < ../hex/code.hex | \
perl -ne 'chomp; next if /^\s*$/; die "bad word: $_\n" unless /^[0-9A-Fa-f]{8}$/; printf "%064b\n", hex($_);' \
>! sram.preload.data
```

再运行：

```bash
make clean
make test
```

VCS 的编译和运行均保留 `+neg_tchk`，不要使用 `+notimingchecks` 或 `+nospecify`。

## SRAM 模型说明

当前 SRAM 行为模型在地址切换与时钟边沿重合时会把模型级 timing check 传播为 `X`。`riscv_pr_sim.v` 仅关闭 IM/DM SRAM 模型的 `check_noidle`，保留标准单元和 SDF 延迟检查；SRAM 引脚 setup/hold 以 Innovus STA 报告为准。

## 通过判据

```text
PASS: x31 = 0x00000001
```

如果出现大面积 `X`，先检查 SDF 是否标注、网表/SDF 是否成对、SRAM 预加载是否成功，以及 SRAM 模型实例层级是否与 TB 一致。
