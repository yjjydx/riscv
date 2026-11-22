# Step 4: CTS (Clock Tree Synthesis)
# Standalone script with all variables embedded (no external setup.tcl dependency)

# 生成当前运行时间戳，用于 runtime.log 中记录 CTS 阶段耗时。
set rundate [clock format [clock seconds] -format %Y_%m_%d_%I:%M_%p]

# 指定当前处理的顶层设计名称。
set init_design "riscv"

# 记录 CTS 阶段开始时间。
echo "START : 04_cts $rundate" >> ../report/runtime.log

# 读取 step3.place.tcl 保存的 placement 数据库，作为 CTS 输入。
source ../database/$init_design.place.enc

# 设置本地并行 CPU 数，提高 CTS/ccopt 和优化运行速度。
setMultiCpuUsage -localCpu 32

# 清理并重新创建 CTS 报告目录，避免旧报告干扰本次分析。
exec rm -rf ../report/cts
file mkdir ../report/cts

# 激活当前所有约束模式，后续 reset_ideal_network 等约束修改会作用到这些模式。
set_interactive_constraint_modes [all_constraint_modes -active]

# CTS 前取消 clk 的 ideal network 属性，让时钟网络可以被真正综合和优化。
reset_ideal_network clk

# 如果设计中存在 rst_n 端口，则取消 rst_n 的 ideal network 属性。
# 这样复位网络不会因为 ideal 属性影响后续真实网络分析。
if {[sizeof_collection [get_ports rst_n -quiet]] > 0} {
  reset_ideal_network [get_ports rst_n]
}

# 清空 interactive constraint mode，避免后续普通设置意外写入交互约束。
set_interactive_constraint_modes {}

# CTS target skew and max fanout
# 设置 CTS 目标 skew 为 0.1ns，指导 ccopt 平衡各 clock sink 的到达时间。
set_ccopt_mode -cts_target_skew 0.1

# 设置 ccopt 的目标 skew 属性，与上面的 cts_target_skew 保持一致。
set_ccopt_property target_skew 0.1

# 设置 CTS 时钟网络目标最大 transition 为 0.2ns。
set_ccopt_property target_max_trans 0.2

# 限制时钟树单级最大扇出为 30，避免单个 clock buffer 驱动过多 sink。
set_ccopt_property max_fanout 30

# CTS buffer and inverter cells
# 定义 CTS 可用的 clock buffer 候选单元，ccopt 会从这些单元中选择插入。
set cts_buffer_cells [list BUFFD16 BUFFD12 BUFFD8 BUFFD6 BUFFD4 BUFFD3 BUFFD2]

# 定义 CTS 可用的 clock inverter 候选单元。
set cts_inv_cells [list INVD16 INVD12 INVD8 INVD6 INVD4 INVD3 INVD2]

# CCOPT properties
# 允许 ccopt 使用 inverter 搭建时钟树。
set_ccopt_property use_inverters true

# 指定 clock inverter 候选单元列表。
set_ccopt_property inverter_cells $cts_inv_cells

# 指定 clock buffer 候选单元列表。
set_ccopt_property buffer_cells $cts_buffer_cells

# 允许复制时钟逻辑，降低负载并改善时钟网络拓扑。
set_ccopt_property clone_clock_logic true

# 允许复制 clock gate 单元，改善门控时钟网络的负载分布。
set_ccopt_property clone_clock_gates true

# 允许合并 clock gate 单元，减少不必要的门控结构。
set_ccopt_property merge_clock_gates true

# 允许合并普通时钟逻辑，优化时钟树结构。
set_ccopt_property merge_clock_logic true

# CCOPT clustering
# 当顶层时钟网络扇出达到 2000 以上时，使用 top routing 相关策略。
set_ccopt_property routing_top_min_fanout 2000

# Routing settings
# 设置详细布线使用高强度多切通孔，并关闭 litho-driven route。
setNanoRouteMode -drouteUseMultiCutViaEffort high -routeWithLithoDriven false

# 创建 CTS 使用的 NDR 规则：M4 到 M9 使用 2 倍线宽、2 倍间距，并生成对应通孔。
# NDR 可以降低时钟网络电阻、电容耦合和串扰风险，提高时钟可靠性。
add_ndr -name cts_ndr_2w2s \
  -width_multiplier {M4:M9 2} \
  -spacing_multiplier {M4:M9 2} \
  -generate_via

# 创建 top 层级时钟网络的 route type。
# 顶层时钟 trunk 使用较高金属层 M8-M9，并绑定 cts_ndr_2w2s。
create_route_type -name CLK_RULE_TOP \
  -top_preferred_layer M9 -bottom_preferred_layer M8 \
  -non_default_rule cts_ndr_2w2s

# 创建 trunk 层级时钟网络的 route type。
# 中间主干时钟线使用 M6-M7，并绑定 cts_ndr_2w2s。
create_route_type -name CLK_RULE_TRUNK \
  -top_preferred_layer M7 -bottom_preferred_layer M6 \
  -non_default_rule cts_ndr_2w2s

# 创建 leaf 层级时钟网络的 route type。
# 靠近 sink 的叶子时钟线使用 M2-M4，便于连接标准单元 clock pin。
create_route_type -name CLK_RULE_LEAF \
  -top_preferred_layer M4 -bottom_preferred_layer M2

# 将 top/trunk/leaf 三类 route type 分配给对应层级的时钟网络。
set_ccopt_property route_type CLK_RULE_TOP -net_type top
set_ccopt_property route_type CLK_RULE_TRUNK -net_type trunk
set_ccopt_property route_type CLK_RULE_LEAF -net_type leaf

# 分别设置不同层级时钟网络的最大 transition 目标。
# leaf/trunk 更靠近 sink，目标设置为 0.15ns；top 主干目标设置为 0.20ns。
set_ccopt_property -net_type leaf target_max_trans 0.15
set_ccopt_property -net_type trunk target_max_trans 0.15
set_ccopt_property -net_type top target_max_trans 0.20

# 删除旧的 clock tree spec，避免历史 CTS 设置影响本次结果。
delete_ccopt_clock_tree_spec

# 根据当前 ccopt_property 和 route type 生成新的 CTS 规格文件。
create_ccopt_clock_tree_spec -file cts.spec

# 读取生成的 cts.spec，让 CTS 规格正式生效。
source cts.spec

# 在真正执行 ccopt 前，先输出 clock tree 和 skew group 摘要，便于检查 CTS 目标和分组。
report_ccopt_clock_trees -summary -file ../report/cts/clock_tree.rpt
report_ccopt_skew_groups -summary -file ../report/cts/skew_groups_summary.rpt

# 执行 CTS/CCOpt：插入 clock buffer/inverter，构建真实时钟树，并优化 skew、latency 和 transition。
ccopt_design -expandedViews -outDir ../report/cts/ -prefix $init_design.cts

# 保存 CTS 完成后的数据库，方便需要时回退到未 post-CTS 优化的状态。
saveDesign ../database/$init_design.cts.enc

#### CTS optimization
# 激活当前约束模式，后续 propagated clock 和 uncertainty 设置会写入当前 active mode。
set_interactive_constraint_modes [all_constraint_modes -active]

# 将所有时钟设置为 propagated clock，后续时序分析使用 CTS 生成的真实时钟网络延迟。
set_propagated_clock [all_clocks]

# 设置 CTS 后 setup uncertainty 为 0.15ns，给后续布线和签核预留 setup 余量。
set_clock_uncertainty -setup 0.15 [all_clocks]

# 设置 CTS 后 hold uncertainty 为 0.05ns，给 hold 检查预留保守余量。
set_clock_uncertainty -hold 0.05 [all_clocks]

# 允许优化器修复 max capacitance、max transition 和 fanout/load 违例。
setOptMode -fixCap true -fixTran true -fixFanoutLoad true

# 执行 post-CTS 优化，主要修复 CTS 后 setup、DRV 和因真实时钟树引入的新问题。
optDesign -postCTS -expandedViews -outDir ../report/cts -prefix postcts_opt

##### Post-CTS hold fixing
# 默认关闭 post-CTS hold 修复；如果 CTS 后 hold WNS 较差，可改为 true。
set postcts_hold_fixing false

if {$postcts_hold_fixing} {
  puts "INFO: Starting post-CTS hold fixing..."
  puts "INFO: Hold fixing enabled due to reg2reg/reg2cgate WNS < -150ps"

  # 指定 hold 修复可使用的 inverter/delay 单元。
  set postcts_hold_fix_cells [list INVD16 INVD12 INVD8 INVD6 INVD4 INVD3 INVD2]

  # hold 修复时忽略部分不适合修 hold 的路径组，例如输入到寄存器、寄存器到输出和 feedthrough。
  set postcts_ignore_path_groups [list in2reg reg2out feedthr]

  # 设置 post-CTS hold 修复策略：
  # - 允许自动处理局部重叠和 resizing；
  # - 允许少量 setup TNS 退化换取 hold 修复；
  # - 指定 hold 修复单元和目标 slack；
  # - 忽略指定 path group；
  # - 进行 hold/setup aware 的面积回收。
  setOptMode \
    -fixHoldAllowOverlap auto \
    -fixHoldAllowSetupTnsDegrade true \
    -fixHoldAllowResizing true \
    -fixHoldOnExcludedClockNets false \
    -holdFixingCells $postcts_hold_fix_cells \
    -holdTargetSlack 0 \
    -holdSlackFixingThreshold -0.20 \
    -ignorePathGroupsForHold $postcts_ignore_path_groups \
    -reclaimArea default \
    -setupTargetSlack 0.04 \
    -postRouteAreaReclaim holdAndSetupAware

  # 执行 post-CTS hold 优化，插入/替换 delay cell 修复 hold violation。
  optDesign -postCTS -hold -expandedViews -outDir ../report/cts -prefix postcts_opt

  # 输出 hold 修复后的 setup 和 hold 报告，检查修 hold 是否破坏 setup。
  timeDesign -postCTS -pathReports -slackReports -numPaths 50 -prefix postCTS_opt_hold_setup -outDir ../report/postCTS
  timeDesign -postCTS -hold -pathReports -slackReports -numPaths 50 -prefix postCTS_opt_hold -outDir ../report/postCTS

  puts "INFO: Post-CTS hold fixing completed"
} else {
  puts "INFO: Post-CTS hold fixing skipped (postcts_hold_fixing = false)"
  puts "INFO: Hold WNS is acceptable (>= -150ps for reg2reg/reg2cgate)"
}

# 保存 CTS 优化后的数据库，作为后续 route 阶段输入。
saveDesign ../database/$init_design.cts_opt.enc

# 记录 CTS 阶段结束时间。
echo "END : 04_cts $rundate" >> ../report/runtime.log
