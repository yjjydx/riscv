# Step 5: Route
# Standalone script with all variables embedded (no external setup.tcl dependency)

# 命令说明：生成当前运行时间字符串，作为 route 阶段写入 runtime.log 的时间标记。
set rundate [clock format [clock seconds] -format %Y_%m_%d_%I:%M_%p]
# 命令说明：设置当前 Innovus 数据库对应的顶层设计名称。
set init_design "riscv"

# 命令说明：向 runtime.log 追加 route 阶段开始时间，便于统计每一步运行耗时。
echo "START : 05_route $rundate" >> ../report/runtime.log

# 命令说明：加载 CTS 优化后保存的设计数据库，route 阶段从该数据库继续执行。
source ../database/$init_design.cts_opt.enc

# 命令说明：设置本地并行 CPU 数量为 32，提高 route 和优化阶段运行速度。
setMultiCpuUsage -localCpu 32

####### ROUTE ######
# 命令说明：删除旧的 route 报告目录，避免新旧报告混在一起。
exec rm -rf ../report/route
# 命令说明：重新创建 route 报告目录，用于存放本轮 route 相关报告。
file mkdir ../report/route

# Route layer settings
# 命令说明：设置 NanoRoute 最低可用布线层为 M1。
setNanoRouteMode -quiet -routeBottomRoutingLayer 1
# 命令说明：设置 NanoRoute 最高可用布线层为 M9。
setNanoRouteMode -quiet -routeTopRoutingLayer 9

# NanoRoute mode settings (values embedded)
# 命令说明：开启 timing-driven routing，使布线过程考虑时序收敛目标。
setNanoRouteMode -routeWithTimingDriven true
# 命令说明：开启 SI-driven routing，使布线过程考虑串扰和信号完整性影响。
setNanoRouteMode -routeWithSiDriven true
# 命令说明：设置 routeDesign 不额外修复时钟网络，避免破坏 CTS 已构建的时钟树。
setNanoRouteMode -routeDesignFixClockNets false
# 命令说明：设置详细布线阶段使用多切通孔的努力程度为 high，提高通孔可靠性。
setNanoRouteMode -drouteUseMultiCutViaEffort high
# 命令说明：设置并发减少通孔数量的努力程度为 medium，在布线质量和运行时间之间折中。
setNanoRouteMode -routeConcurrentMinimizeViaCountEffort medium
# 命令说明：设置详细布线结束迭代次数使用工具默认值。
setNanoRouteMode -quiet -drouteEndIteration default
# 命令说明：开启天线二极管插入，使工具在 route 阶段尝试修复天线效应问题。
# 名词解释：antenna 指“天线效应”，不是芯片真的有天线。
# 初学者理解：制造芯片时，金属线会一步步被刻蚀出来。如果某根金属线很长，
# 但它连接的晶体管栅极很小，那么加工过程中金属线可能积累电荷，
# 这些电荷会通过栅极释放，严重时会击穿栅氧，损坏晶体管。
# 天线二极管的作用是给这些电荷提供一条泄放路径，降低栅极被损坏的风险。
setNanoRouteMode -routeInsertAntennaDiode true
# 命令说明：指定天线二极管单元名称为 ANTENNA，供工具自动插入使用。
setNanoRouteMode -routeAntennaCellName "ANTENNA"

# 命令说明：执行全芯片信号布线，包括全局布线和详细布线。
routeDesign
# 命令说明：保存 route 完成后的 Innovus 数据库，作为未优化的 post-route 结果。
saveDesign ../database/$init_design.route.enc

# Set analysis mode to OCV for post-route timing analysis
# 命令说明：设置 post-route 时序分析为 OCV 模式，并在 setup/hold 中启用 CPPR。
# 初学者理解：
# 1. OCV(on-chip variation) 的意思是“同一块芯片上，不同位置的器件表现也会不一样”。
#    真实芯片里，晶体管、金属线、接触孔不可能完全一样，所以工具不能把整个芯片都当成
#    完全一致的理想状态来算时序。开启 OCV 后，工具会更保守地考虑工艺、电压、温度等
#    变化带来的快慢差异，这样分析结果更接近真实硅片。
# 2. cppr both 是“公共路径悲观修正”。
#    时钟从同一个源头出发，去寄存器 A 和寄存器 B 的时候，前面有一段公共时钟路径是相同的。
#    如果不做修正，工具会把这段公共路径在 launch 和 capture 两边各算一遍，等于把同一段路
#    重复扣分，结果会显得比真实情况更差。CPPR 就是把这部分重复的悲观量减掉，让 setup/hold
#    分析更合理。
# 3. 这里设置成 both，表示 setup 和 hold 两种检查都使用 CPPR。
#    这样可以避免时钟树分析太悲观，也更符合 post-route 阶段的真实情况。
setAnalysisMode -analysisType onChipVariation -cppr both
# 命令说明：打印提示信息，说明 post-route 分析模式已经设置为 OCV + CPPR。
puts "INFO: Analysis mode set to OCV with CPPR for post-route stage"

# 命令说明：执行 post-route setup 时序分析，并输出扩展 view 下的报告。
timeDesign -expandedViews -postRoute -prefix postRoute -outDir ../report/postRoute
# 命令说明：执行 post-route hold 时序分析，并输出扩展 view 下的报告。
timeDesign -expandedViews -postRoute -hold -prefix postRoute -outDir ../report/postRoute
# 命令说明：检查布线连通性，忽略 soft PG connect 和 antenna 检查，并输出连通性报告。
# 名词解释：PG connect 里的 PG 是 Power/Ground，也就是电源和地。
# 初学者理解：标准单元和 macro 都需要接 VDD/VSS。PG connect 检查的重点是：
# 单元的电源脚有没有真正连到电源网络，地脚有没有真正连到地网络。
# 如果 PG 没连好，逻辑线即使都布通了，芯片也不能正常工作。
# 这里的 -noSoftPGConnect 表示不检查 soft PG 连接。
# soft PG 可以简单理解为“工具数据库里推断出来的电源连接关系”，
# 它不一定对应已经显式画出来的物理连线，所以这里先不把它作为错误检查重点。
# 这里的 -noAntenna 表示本次连通性检查里不检查 antenna，
# 因为 antenna 后面会用 verifyProcessAntenna 单独检查。
verifyConnectivity -noSoftPGConnect -noAntenna -error 1000 -warning 500 -report ../report/postRoute/verifyConnectivity.rpt
# 命令说明：执行布线后 DRC 检查，最多报告 100000 个 DRC 问题。
verify_drc -limit 100000 -report ../report/postRoute/verify_drc.rpt

####### Route optimization #######
# 命令说明：设置 post-route setup 修复开关为 true，表示执行 setup/DRV 优化。
set postRoute_setup_fixing true
# 命令说明：根据 setup 修复开关决定是否执行 post-route setup 优化流程。
if {$postRoute_setup_fixing} {
  # 命令说明：打印 post-route setup 优化开始提示。
  puts "INFO: Starting postRoute setup optimization..."
  # 命令说明：打印当前将执行 setup timing 和 DRV 优化。
  puts "INFO: Performing setup timing and DRV optimization"

  # Apply clock uncertainty to all clocks
  # 命令说明：对所有时钟设置 setup uncertainty 为 0.15ns，用于保留 setup 时序裕量。
  set_clock_uncertainty -setup 0.15 [all_clocks]
  # 命令说明：对所有时钟设置 hold uncertainty 为 0.05ns，用于保留 hold 时序裕量。
  set_clock_uncertainty -hold 0.05 [all_clocks]
  # 命令说明：打印提示信息，说明 clock uncertainty 已经应用到所有时钟。
  puts "INFO: Clock uncertainty applied to all clocks"

  # 命令说明：开启电容、transition 和 fanout/load 违例修复。
  setOptMode -fixCap true -fixTran true -fixFanoutLoad true
  # 命令说明：设置 setup/hold 优化目标 slack 为 0.0ns，要求工具至少优化到非负 slack。
  setOptMode -setupTargetSlack 0.0 -holdTargetSlack 0.0
  # 命令说明：执行 post-route setup 方向优化，同时修复部分 DRV 问题。
  optDesign -postRoute

  # 命令说明：输出 post-route setup 优化后的 setup 时序路径和 slack 报告。
  timeDesign -postRoute -pathReports -slackReports -numPaths 50 -prefix postRoute_opt_setup -outDir ../report/postRouteOpt
  # 命令说明：输出 post-route setup 优化后的 hold 时序路径和 slack 报告。
  timeDesign -postRoute -hold -pathReports -slackReports -numPaths 50 -prefix postRoute_opt_setup -outDir ../report/postRouteOpt
  # 命令说明：清除当前 GUI/数据库中的 DRC 标记，便于后续重新检查优化后的 DRC。
  clearDrc
  # 命令说明：打印 post-route setup 优化完成提示。
  puts "INFO: postRoute setup optimization completed"
} else {
  # 命令说明：当 setup 修复开关关闭时，打印跳过 setup 优化提示。
  puts "INFO: postRoute setup optimization skipped"
}

# 命令说明：设置 post-route hold 修复开关为 true，表示执行 hold 优化。
set postRoute_hold_fixing true
# 命令说明：根据 hold 修复开关决定是否执行 post-route hold 修复流程。
if {$postRoute_hold_fixing} {
  # 命令说明：打印 post-route hold 修复开始提示。
  puts "INFO: Starting postRoute hold fixing..."
  # 命令说明：打印当前将执行 hold timing 优化。
  puts "INFO: Performing hold timing optimization"
  # 命令说明：禁止 hold 修复显著牺牲 setup 时序，避免修 hold 时把 setup 弄坏。
  setOptMode -fixHoldAllowSetupTnsDegrade false
  # 命令说明：执行 post-route hold 优化，通常通过插 buffer、绕线等方式增加最小延迟。
  optDesign -postRoute -hold
  # 命令说明：输出 hold 修复后的 setup 时序路径和 slack 报告，确认 setup 没被破坏。
  timeDesign -postRoute -pathReports -slackReports -numPaths 50 -prefix postRoute_opt_hold_setup -outDir ../report/postRouteOpt
  # 命令说明：输出 hold 修复后的 hold 时序路径和 slack 报告，确认 hold 是否收敛。
  timeDesign -postRoute -hold -pathReports -slackReports -numPaths 50 -prefix postRoute_opt_hold -outDir ../report/postRouteOpt
  # 命令说明：打印 post-route hold 修复完成提示。
  puts "INFO: postRoute hold fixing completed"
} else {
  # 命令说明：当 hold 修复开关关闭时，打印跳过 hold 修复提示。
  puts "INFO: postRoute hold fixing skipped"
}

# 命令说明：检查 post-route 优化后的连通性，输出最终连通性报告。
# 名词解释：再次检查 PG connect 和普通信号连通性，确认优化后没有把线改断。
# 初学者理解：post-route 优化可能会换单元、插 buffer、移动局部连线，
# 所以优化后必须重新检查连接是否完整。
verifyConnectivity -noSoftPGConnect -noAntenna -error 1000 -warning 500 -report ../report/postRouteOpt/verifyConnectivity.rpt
# 命令说明：执行 post-route 优化后的 DRC 检查，输出最终 DRC 报告。
verify_drc -limit 100000 -report ../report/postRouteOpt/verify_drc.rpt
# 命令说明：保存 post-route 优化后的 Innovus 数据库，作为下一步 chip finish/signoff 输入。
saveDesign ../database/$init_design.route_opt.enc
# 命令说明：执行工艺天线效应检查，并输出 antenna 检查报告。
# 名词解释：verifyProcessAntenna 用来正式检查天线效应是否违反工艺规则。
# 初学者理解：前面的 routeInsertAntennaDiode 是“尝试修”，
# 这里的 verifyProcessAntenna 是“正式查”。如果这里还有 violation，
# 说明仍然存在某些长金属线可能在制造过程中积累过多电荷，需要继续修复。
verifyProcessAntenna -report ../report/postRouteOpt/verify_antenna.rpt -error 1000

# 命令说明：向 runtime.log 追加 route 阶段结束时间。
echo "END : 05_route $rundate" >> ../report/runtime.log
# 命令说明：退出 Innovus 批处理运行。
exit
