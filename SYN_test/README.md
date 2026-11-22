# SYN_test：RISC-V 逻辑综合工程说明

## 1. 工程用途

`SYN_test` 是本项目的 Synopsys Design Compiler 逻辑综合目录，用于将 RISC-V RTL 及其 SRAM 宏综合为可供后续形式验证、门级仿真和物理设计使用的门级网表。

当前流程采用 DC Topographical 物理感知综合模式，主要包括：

- 读取并展开 RISC-V RTL；
- 加载标准单元库和 SRAM 时序库；
- 使用 Milkyway 物理库、TLUPlus RC 模型及 floorplan DEF；
- 在 SS/WC 角进行 setup/max 分析；
- 在 FF/BC 角进行 hold/min 分析；
- 执行 `compile_ultra` 综合及增量优化；
- 输出门级网表、约束、延迟文件和综合报告；
- 为 Formality 等价性检查提供 SVF 和综合后网表。

## 2. 目录结构
```text
SYN_test/
├── all_scripts/    # DC 参数和综合主脚本
├── fm_check/       # Formality 检查结果或相关工作文件
├── formality/      # Formality 等价性检查脚本
├── log/            # DC 运行日志
├── output/         # 综合输出：网表、SDC、DDC、SDF、SVF 等
├── report/         # 时序、面积、功耗、QoR 和约束报告
├── rtl_code/       # 综合输入 RTL，顶层设计为 riscv
├── sram/           # SRAM 模型及相关物理库文件
└── work/           # DC 启动和运行工作目录
```

各目录中的脚本及生成文件以服务器上的实际内容为准。`work/` 是推荐的命令执行目录，脚本中的相对路径也以该目录为基准。

## 3. 主要设计配置

| 项目 | 当前配置 |
|---|---|
| 顶层设计 | `riscv` |
| RTL 目录 | `rtl_code/` |
| 主时钟 | `clk` |
| 时钟周期 | `5.0 ns`（200 MHz） |
| 复位端口 | `rst`，综合阶段按理想网络处理 |
| 主综合命令 | `compile_ultra` |
| 综合模式 | DC Topographical 物理感知综合 |
| Setup/max 标准单元角 | WC/SS：`tcbn65lpwc.db` |
| Hold/min 标准单元角 | BC/FF：`tcbn65lpbc.db` |
| Setup/max SRAM 角 | SS：`ss1p08v125c` |
| Hold/min SRAM 角 | FF：`ff1p32vm40c` |
| 最大扇出约束 | `32` |
| 最大转换时间约束 | `0.6 ns` |
| 互连模型 | Milkyway + TLUPlus max/min RC |
| 物理约束 | 来自 `PR_ydx` floorplan DEF |

SS/WC 和 FF/BC 库描述的是同一批物理标准单元在不同 PVT 条件下的时序、功耗特性。综合映射仍以 WC/SS 库为主，FF/BC 库通过 `set_min_library` 与 max 库配对，用于 min/hold 分析。

具体库路径、DEF 路径、输出目录和综合选项请查看：

```text
all_scripts/set.tcl
all_scripts/script.tcl
```

## 4. 运行环境

综合需要具备 DC Topographical/Graphical 功能及相应许可证。普通 `dc_shell` 模式无法完整执行 Milkyway、TLUPlus 和 DEF 物理约束相关命令。

推荐启动方式：

```bash
cd /home/project/cp_training_backend1/users/cpu26/target/CICC1000645_2026_7_18/SYN_test/work

dc_shell -topographical_mode \
    -f ../all_scripts/script.tcl \
    2>&1 | tee ../log/dc_$(date +%Y%m%d_%H%M).log
```

如果服务器上的主脚本文件名不同，请以 `all_scripts/` 中实际提交的 Tcl 脚本为准。

## 5. 综合流程

综合主脚本按以下顺序执行：

1. 读取参数、标准单元库、SRAM 库和物理库配置；
2. 读取 RTL，执行 `analyze`、`elaborate`、`current_design`、`link`；
3. 创建时钟并设置时钟不确定度、I/O delay、输出负载及 DRV 约束；
4. 将复位网络设置为理想网络，避免在综合阶段构造复位树；
5. 加载 Milkyway 工作库和 max/min TLUPlus RC 文件；
6. 通过 `extract_physical_constraints` 读取 floorplan DEF；
7. 执行 `compile_ultra` 及配置的增量综合；
8. 输出门级网表、SDC、DDC、SDF 和 SVF；
9. 生成 setup、hold、面积、功耗、约束和 QoR 报告。

在运行日志中看到以下信息，表示 floorplan DEF 已成功进入本次综合：

```text
extract_physical_constraints completed successfully. Floorplan DEF is loaded.
```

`check_physical_design` 是附加检查命令。某些 DC 版本不提供该命令，但只要 `extract_physical_constraints` 成功，并不表示 DEF 未被使用。

## 6. 输出文件

### `output/`

| 文件 | 用途 |
|---|---|
| `riscv_<时间戳>.v` | 综合后门级 Verilog 网表 |
| `riscv_<时间戳>.sdc` | 综合约束，供后端和 STA 使用 |
| `riscv_<时间戳>_compile.ddc` | DC 综合数据库 |
| `riscv_<时间戳>.sdf` | 门级仿真延迟回标文件 |
| `riscv_<时间戳>.svf` | Formality 逻辑对应关系文件 |

### `report/`

| 报告 | 主要内容 |
|---|---|
| `*_qor.rpt` | 综合 QoR 总览 |
| `*_area.rpt` | 总面积和层次面积 |
| `*_setup_ss.rpt` | SS/WC 角 setup/max 时序 |
| `*_hold_ff.rpt` | FF/BC 角 hold/min 时序 |
| `*_constraint.rpt` | 时序和 DRV 约束违例 |
| `*_power.rpt` | 综合阶段功耗估算 |
| `*_check_timing.rpt` | 时钟及未约束路径检查 |
| `*_physical_constraints.rpt` | 从 DEF 提取的物理约束 |
| `*_clock_gating.rpt` | 时钟门控检查结果 |
| `*_corner_summary.rpt` | max/min 工艺角和报告对应关系 |

实际生成的文件取决于 DC 版本、许可证及脚本配置。

## 7. 建议审阅顺序

组委会可以按以下顺序快速查看本工程：

1. `all_scripts/set.tcl`：顶层设计、时钟、库、物理环境及综合参数；
2. `all_scripts/script.tcl`：完整综合流程；
3. `report/*_qor.rpt`：整体 QoR；
4. `report/*_setup_ss.rpt` 和 `report/*_hold_ff.rpt`：setup/hold 时序；
5. `report/*_constraint.rpt`：DRV 和其他约束检查；
6. `report/*_area.rpt`、`report/*_power.rpt`：面积及功耗；
7. `output/*.v`、`output/*.sdc`：提交给后端的网表和约束；
8. `formality/`、`fm_check/`：RTL 与综合网表的等价性检查。

## 8. 复现与注意事项

- 请从 `work/` 目录启动 DC，避免相对路径失效；
- 运行前确认 `all_scripts/set.tcl` 中标准单元库、SRAM 库、Milkyway、TLUPlus 和 DEF 路径在当前服务器有效；
- 物理感知模式下不再叠加传统 wire load model；
- `work/`、`log/`、`output/` 和 `report/` 中大部分内容属于运行生成文件；
- 若重新综合，请保留对应日志和同一时间戳的报告，避免混用不同批次结果；
- 综合后功能正确性应结合 Formality 等价性检查和门级仿真共同确认；
- 查看 hold 报告前，应先确认 `list_libs` 中 WC/SS 与 BC/FF 的 max/min 配对关系正确。

---

工程编号：`CICC1000645`  
目录：`CICC1000645_2026_7_18/SYN_test`  
文档更新时间：2026-07-16
