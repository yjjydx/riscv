# PR_ydx：RISC-V 后端实现结果说明

## 1. 工程概述

PR_ydx 为 RISC-V 处理器后端实现目录，使用 Cadence Innovus 完成初始化、Floorplan、Placement、CTS、Route 和 Chip Finish，并使用 PrimeTime、StarRC、Calibre 完成时序、寄生参数、DRC 和 LVS 验证。

| 项目 | 内容 |
|---|---|
| 顶层设计 | riscv |
| 工艺平台 | TSMC 65LP |
| 金属层 | 9M，6X2Z |
| SRAM | TS1N65LPLL2048X64M8 |
| 后端工具 | Cadence Innovus |
| Signoff 工具 | PrimeTime、StarRC、Calibre |
| 最终交付 | 门级网表、DEF、GDS、后端 SDC、SPEF、DRC/LVS 结果 |

## 2. 目录与结果文件

~~~text
PR_ydx/
├── data/          最终网表、DEF、SDC、LEF 等交付文件
├── database/      Innovus 各阶段数据库
├── drc_flow/      Calibre DRC 配置与结果
├── logs/          流程运行日志
├── lvs_flow/      Calibre LVS 配置与结果
├── map_work/      GDS 映射文件
├── report/        时序、DRV、连通性和物理检查报告
├── script/        六阶段 Innovus 脚本及 Signoff 脚本
├── work/          innovus工具运行目录
~~~
## 3. 六阶段后端流程

~~~text
    Step 1 初始化
  → Step 2 Floorplan
  → Step 3 Placement
  → Step 4 CTS
  → Step 5 Route
  → Step 6 Chip Finish
~~~

| 阶段 | 脚本 | 主要结果 | 报告位置 |
|---|---|---|---|
| Step 1 初始化 | step1.init.tcl | riscv.init.enc | report/init/ |
| Step 2 Floorplan | step2.fp.tcl | riscv.floorplan.enc | report/floorplan/ |
| Step 3 Placement | step3.place.tcl | riscv.place.enc | report/place_opt/、report/preCTS/ |
| Step 4 CTS | step4.cts.tcl | riscv.cts_opt.enc | report/cts/、report/postCTS/ |
| Step 5 Route | step5.route.tcl | riscv.route_opt.enc | report/postRoute/、report/postRouteOpt/ |
| Step 6 Chip Finish | step6.chipfinish.tcl | riscv.chipfinish.enc | data/、output/ |

### Step 1：初始化

读取综合后网表、SDC、标准单元及 SRAM 库，建立 MMMC 分析视图，输出初始化数据库和布局前时序报告。

审阅文件：

~~~text
script/init_setup.tcl
script/mmmc.tcl
database/riscv.init.enc
report/init/
~~~

### Step 2：Floorplan

完成 Core Box、SRAM Macro、IO pin、Halo、电源环、电源条带和电源连接设计。

文件：
~~~text
script/step2.fp.tcl
database/riscv.floorplan.enc
report/floorplan/vdd_connect.rpt
report/floorplan/vss_connect.rpt
report/floorplan/pg_short.rpt
report/floorplan/drc.rpt
~~~

### Step 3：Placement

完成标准单元布局、布局合法化、Pre-CTS setup 优化和 DRV 优化。

内容：
~~~text
database/riscv.place.enc
report/place_opt/
report/preCTS/
~~~

主要指标为 WNS、TNS、Violated Paths、max_transition 和 max_capacitance。

### Step 4：CTS

完成时钟树综合、时钟偏差控制及 Post-CTS setup/hold 优化。

内容：
~~~text
database/riscv.cts_opt.enc
report/cts/
report/postCTS/
~~~

主要指标为 clock skew、clock latency、clock transition、setup WNS 和 hold WNS。

### Step 5：Route

完成信号布线、天线处理、Post-Route 时序优化及连通性检查。

内容：
~~~text
database/riscv.route_opt.enc
report/postRoute/
report/postRouteOpt/
report/postRouteOpt/verifyConnectivity.rpt
report/postRouteOpt/verify_drc.rpt
report/postRouteOpt/verify_antenna.rpt
~~~

### Step 6：Chip Finish

完成 Filler/Decap、局部布线修复和最终数据导出。

文件：
~~~text
database/riscv.chipfinish.enc
data/riscv.vg
data/riscv.def
data/riscv_post_pr.sdc
output/riscv.gds2
~~~

## 5. Signoff 结果

### PrimeTime 与 StarRC

StarRC 根据最终 DEF 和工艺 RC 模型提取 SPEF，PrimeTime 读取最终网表、SDC、时序库和 SPEF，完成 setup、hold、DRV 及寄生标注检查。

~~~text
script/starrc.cmd
script/pt.tcl
PT_test/starrc_flow/riscv_core_typical.spef
PT_test/work/report/timing/
~~~

### Calibre DRC

Calibre DRC 对合并标准单元及 SRAM 版图后的最终 GDS 进行规则检查。DRC 流程包括 M2～M9 metal fill、完整 GDS 合并和局部密度修复。

审阅文件：

~~~text
drc_flow/drc.summary
drc_flow/drc.results
~~~

#### DRC 运行

`drc_flow/drc.runset` 已保存 DRC 规则文件、输入 GDS、顶层 Cell、结果文件和运行目录等配置。

1. 在服务器终端进入 `PR_ydx/drc_flow/`；
2. 执行 `calibre -gui`，在 Calibre Interactive 中选择 `nmDRC`；
3. 选择 `File → Load Runset`，加载 `drc.runset`；
4. 核对 Rules、Inputs、Outputs 和 Run Control 页面中的文件路径；
5. 执行 `Run DRC`；
6. 执行 `Start RVE`，加载 `drc.results` 查看规则检查结果及版图标记。

### Calibre LVS

Calibre LVS 比较最终 GDS 提取网表与后端门级网表，检查器件、网络及端口的一致性。

审阅文件：

~~~text
lvs_flow/lvs.runset
lvs_flow/lvs.report
lvs_flow/lvs.report.ext
lvs_flow/erc.summary
lvs_flow/query_results
~~~

#### LVS 运行

`lvs_flow/lvs.runset` 已保存 LVS 规则文件、输入 GDS、源网表、顶层 Cell、结果文件和运行目录等配置。

1. 在服务器终端进入 `PR_ydx/lvs_flow/`；
2. 执行 `calibre -gui`，在 Calibre Interactive 中选择 `nmLVS`；
3. 选择 `File → Load Runset`，加载 `lvs.runset`；
4. 核对 Rules、Inputs、Outputs 和 Run Control 页面中的文件路径；
5. 执行 `Run LVS`；
6. 查看 `lvs.report`、`lvs.report.ext` 和 `query_results`，确认版图网表与源网表的比较结果。


工程编号：CICC1000645  
工程目录：CICC1000645_2026_7_18/PR_ydx  
文档更新时间：2026-07-16
