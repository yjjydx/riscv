# Step 6: Post-Route Optimization
# 作用：从 route 阶段数据库继续执行寄生参数提取、via/wire/power 优化、
#      post-route setup/hold 优化，以及最终连通性和 DRC 检查。
#
# 流程衔接提醒：当前 step5.route.tcl 已包含一套 post-route setup/hold 优化，
# 并保存 ../database/riscv.route_opt.enc；本脚本按原图从 riscv.route.enc 重新开始。
# 正式串联流程前应选择其中一套方案，避免重复优化或让后续 chip finish 读取错误数据库。

# 生成当前时间字符串，用于 runtime.log 中记录本阶段启动时间。
set rundate [clock format [clock seconds] -format %Y_%m_%d_%I:%M_%p]

# 设置顶层设计名称，后续数据库路径均由该变量拼接。
set init_design "riscv"

# 将 post-route 阶段的开始时间追加到运行时间日志。
echo "START : 06_postroute $rundate" >> ../report/runtime.log

# 加载 route 阶段保存的设计数据库，作为本阶段输入。
source ../database/$init_design.route.enc

# 设置本地并行 CPU 数量为 32，提高提取、优化和检查速度。
setMultiCpuUsage -local 32

####### POSTROUTE ######

# 删除旧的 postroute 报告目录，避免本轮报告与历史结果混在一起。
exec rm -rf ../report/postroute

# 创建本轮 post-route 报告目录。
file mkdir ../report/postroute

########################################
# Analysis and delay calculation modes
########################################

# 使用 OCV 分析方式，考虑同一芯片上工艺、电压和温度变化造成的时序差异。
setAnalysisMode -analysisType onChipVariation

# setup 和 hold 均开启 CPPR，消除公共时钟路径上的重复悲观量。
setAnalysisMode -cppr both

# 使用 ECSM 等效波形模型进行延迟计算，提高非线性波形建模精度。
setDelayCalMode -equivalent_waveform_model_type ecsm

# 延迟计算时遵守 slew propagation constraint，避免传播出不符合约束的转换时间。
setDelayCalMode -honorSlewPropConstraint true

# 使用 AAE 延迟计算引擎。
setDelayCalMode -engine aae

# 开启 SI-aware 延迟计算，将串扰等信号完整性影响纳入分析。
setDelayCalMode -SIAware true

# 设置 post-route RC 提取引擎，当前 effort 为 low，侧重运行速度。
setExtractRCMode -engine postRoute -effortLevel low

########################
# Route mode settings
########################

# 设置普通信号布线允许使用的最低层为 M1。
# 注意：最低层是否应为 M1 需要与当前工艺和项目布线策略一致。
setNanoRouteMode -routeBottomRoutingLayer 1

# 设置普通信号布线允许使用的最高层为 M9。
setNanoRouteMode -routeTopRoutingLayer 9

# 开启 timing-driven routing，让布线优化优先关注关键时序路径。
setNanoRouteMode -routeWithTimingDriven true

# 开启 SI-driven routing，让布线同时考虑串扰和信号完整性。
setNanoRouteMode -routeWithSiDriven true

########################
# Place mode settings
########################

# 允许详细摆放使用常规 one-site filler，不强制使用 no-diffusion 类型 filler。
setPlaceMode -place_detail_use_no_diffusion_one_site_filler false

# 详细合法化时设置实例间隙目标为 2 个 placement site。
setPlaceMode -place_detail_legalization_inst_gap 2

########################
# Optimization settings
########################

# 设置优化过程允许处理的最大连线长度目标为 200，具体单位由设计数据库单位决定。
setOptMode -maxLength 200

# 为本阶段插入的 hold 修复实例添加前缀，便于在网表和 GUI 中识别。
# 原图使用 POSTCTS_HOLD_，虽然位于 post-route 阶段，仍按原设置保留。
setOptMode -addInstancePrefix "POSTCTS_HOLD_"

# 限定 hold 修复时可以插入的 buffer/delay cell，工具会从列表中选择合适驱动和延迟。
setOptMode -holdFixingCells "BUFFD3 BUFFD2 BUFFD1 DEL2 DEL1 DEL02 DEL015 DEL01 DEL005"

########################
# Via optimization
########################

# 允许 post-route via 优化把单切孔替换为 multi-cut via，提高可靠性并降低 via 电阻。
setNanoRouteMode -droutePostRouteSwapVia multiCut

# 执行 via 优化，在满足 DRC 的前提下优化通孔结构。
routeDesign -viaOpt

# via 优化完成后关闭自动 swap-via 模式，避免影响后续步骤。
setNanoRouteMode -droutePostRouteSwapVia false

# 再次明确使用 OCV 分析，确保后续 RC/时序报告沿用正确分析类型。
setAnalysisMode -analysisType onChipVariation

# 基于当前真实布线提取电阻、电容寄生参数，供 post-route 时序分析使用。
extractRC

# 输出 multi-cut via 优化后的 post-route setup 时序报告。
timeDesign -expandedViews -postRoute -outDir ../report/postroute -prefix postroute_multivia

########################
# Wire optimization
########################

# 开启 post-route spread-wire，通过适当增大线间距改善 DRC、串扰和信号完整性。
setNanoRouteMode -droutePostRouteSpreadWire true

# 执行 wire optimization，优化已完成布线的线形、间距等细节。
routeDesign -wireOpt

# 设置 wire optimization 可处理路径的最小 slack 为 0.000ns。
# 该命令在原图中位于 routeDesign -wireOpt 之后，因此主要影响后续相关 route/ECO 动作；
# 若希望它控制上面的 wireOpt，应在服务器上确认命令顺序后再前移。
setNanoRouteMode -drouteMinSlackForWireOptimization 0.000

# 关闭 spread-wire 模式，避免后续 ECO route 持续使用该策略。
setNanoRouteMode -droutePostRouteSpreadWire false

# 输出 spread-wire/wireOpt 后的 post-route setup 时序报告。
timeDesign -expandedViews -postRoute -outDir ../report/postroute -prefix postroute_spreadwire

########################
# Power optimization
########################

# 指定功耗分析使用 func_setup_view 分析视图。
set_power_analysis_mode -analysis_view "func_setup_view"

# 设置功耗优化时 leakage 与 dynamic power 的权衡比例为 1。
setOptMode -leakageToDynamicRatio 1

# 执行 post-route 功耗优化，在保持布线和时序可收敛的前提下降低功耗。
optPower -postRoute

########################
# Setup optimization
########################

# 允许 post-route setup 优化使用 useful skew 调整时钟到达时间，帮助改善 setup slack。
setOptMode -usefulSkewPostRoute true

# 为 setup 优化阶段新增的实例添加独立前缀，便于追踪 ECO 改动。
setOptMode -addInstancePrefix "POSTROUTE_SETUP_"

# 执行 post-route setup 优化并输出 expanded-view 报告。
optDesign -postroute -expandedViews -outDir ../report/postroute -prefix postrouteOptSetup

########################
# Hold optimization
########################

# hold 优化阶段继续允许使用 post-route useful skew。
setOptMode -usefulSkewPostRoute true

# 为 hold 优化阶段新增的实例添加独立前缀。
setOptMode -addInstancePrefix "POSTROUTE_HOLD_"

# 执行 post-route hold 优化，通常会插入 delay/buffer 或调整局部连线以增加最小延迟。
optDesign -postroute -hold -expandedViews -outDir ../report/postroute -prefix postrouteOptHold

########################
# Route and physical verification
########################

# 清除旧的 DRC marker；该命令只清除标记，不等于修复真实违例。
clearDrc

# 检查当前详细布线状态，识别 open、short、未完成布线等 route 问题。
checkRoute

# 检查信号和电源网络连通性；忽略 soft PG connection 和 antenna 检查，
# 最多记录 10000 个 error、500 个 warning，并将结果写入报告。
verifyConnectivity -noSoftPGConnect -noAntenna -error 10000 -warning 500 \
  -report ../report/postroute/verifyConnectivity.rpt

# 执行 Innovus 内部几何 DRC 检查，最多输出 100000 个 violation。
verify_drc -limit 100000 -report ../report/postroute/verify_drc.rpt

########################
# Final ECO route and reports
########################

# 删除可清理的 violation marker，同时保留被标记为 fixed 的对象/标记。
editDeleteViolations -keep_fixed

# 执行局部 ECO 布线，修补前面优化或检查后需要更新的连接与线形。
ecoRoute

# 输出最终 post-route setup 时序报告。
timeDesign -expandedViews -postRoute -prefix postroute_finish -outDir ../report/postroute

# 输出最终 post-route hold 时序报告。
timeDesign -expandedViews -postRoute -hold -prefix postroute_finish -outDir ../report/postroute

# 保存 post-route 优化后的数据库，供下一阶段继续使用。
saveDesign -tcon ../database/$init_design.postroute.enc

# 将阶段结束记录追加到 runtime.log。
# 注意：原图沿用启动时生成的 $rundate，因此这里记录的仍是启动时间，而非真实结束时间。
echo "END : 06_postroute $rundate" >> ../report/runtime.log
