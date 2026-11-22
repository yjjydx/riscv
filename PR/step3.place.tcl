# Step 3: Placement
# Standalone script with all variables embedded (no external setup.tcl dependency)

# 生成当前运行时间戳，用于 runtime.log 中记录 place_opt 阶段耗时。
set rundate [clock format [clock seconds] -format %Y_%m_%d_%I:%M_%p]

# 指定当前处理的顶层设计名称。
set init_design "riscv"

# 记录 placement 阶段开始时间。
echo "START : 03_place_opt $rundate" >> ../report/runtime.log

# 读取 step2.fp.tcl 保存的 floorplan 数据库。
source ../database/$init_design.floorplan.enc

# 清理并重新创建 placement 报告目录，避免旧报告影响本次结果判断。
exec rm -rf ../report/place_opt
file mkdir ../report/place_opt

# Place mode settings (values embedded)
# 设置全局布局拥塞优化力度为 medium。
setPlaceMode -place_global_cong_effort medium

# 开启全局布局均匀密度控制，使单元分布更加均衡。
setPlaceMode -place_global_uniform_density true

# 设置全局布局时序优化力度为 medium。
setPlaceMode -place_global_timing_effort medium

# 清空 place_opt 后置 Tcl hook，不额外调用自定义后处理脚本。
setPlaceMode -place_opt_post_place_tcl ""

# 关闭 no-diffusion one-site filler 强制策略，使用常规详细布局处理方式。
setPlaceMode -place_detail_use_no_diffusion_one_site_filler false

# 设置详细布局合法化时实例之间保留 2 个 site 的间隔。
setPlaceMode -place_detail_legalization_inst_gap 2

# 全局布局阶段忽略 scan chain 信息。
setPlaceMode -place_global_ignore_scan true

# 关闭全局布局阶段 scan reorder。
setPlaceMode -place_global_reorder_scan false

# 不允许布局阶段自动重摆 IO pin，保留 floorplan 阶段的 pin 位置。
setPlaceMode -place_global_place_io_pins false

# 详细布局时尊重 instance padding 约束。
setPlaceMode -place_detail_honor_inst_pad true

# Design mode settings
# 设置设计功耗优化力度为 high。
setDesignMode -powerEffort high

# Opt mode settings
# 设置 leakage/dynamic power 权重比例，指导优化器进行功耗权衡。
setOptMode -leakageToDynamicRatio 1

# 设置优化器功耗优化力度为 high。
setOptMode -powerEffort high

# Route mode settings
# 设置早期全局布线估算时可使用的最低金属层为 M2。
setRouteMode -earlyGlobalMinRouteLayer 2

# 设置早期全局布线估算时可使用的最高金属层为 M9。
setRouteMode -earlyGlobalMaxRouteLayer 9

# 清除已有 path group 和 path group 选项，避免继承旧设置。
reset_path_group -all
resetPathGroupOptions

# 加载路径分组脚本，用于建立 in2reg、reg2reg、reg2out 等优化路径组。
source ../script/group_path.tcl

# 打印当前 path group 配置，便于检查路径分组是否正确生效。
reportPathGroupOptions

# Early clock flow (enabled by default)
# 当前默认关闭 early clock flow；如需在 placement 阶段提前建立 clock 结构，可改为 true。
set early_clock_flow false
if {$early_clock_flow} {
  source ../script/early_clock_flow.tcl
}

# 执行 placement 和布局阶段优化，并将 expanded view 报告输出到 place_opt 目录。
place_opt_design -expanded_views -out_dir ../report/place_opt -prefix $init_design.place

# Tie Hi/Lo cells
# 指定 tie-low 和 tie-high 单元，用于连接逻辑常量 0/1。
set tie_low_cell TIEL
set tie_high_cell TIEH

# 设置 tie 单元插入规则：最大距离 100，最大扇出 10。
setTieHiLoMode -cell "$tie_low_cell $tie_high_cell" -maxDistance 100 -maxFanout 10

# 自动插入 tie high/low 单元。
addTieHiLo

# 报告扇出不小于 40 的高扇出网络，便于后续检查是否需要 buffer 或特殊处理。
report_net -min_fanout 40 -output ../report/place_opt/$init_design.place.repoet_net.rpt

# 报告被工具忽略的网络，便于排查优化或时序分析覆盖范围。
reportIgnoredNets -outfile ../report/place_opt/$init_design.place.reportIgnoredNets.rpt  

# 检查 placement 合法性并输出报告。
checkPlace ../report/place_opt/$init_design.checkplace.rpt

# 对布局结果做细化合法化和局部调整。
refinePlace

# 输出布局后的线长统计报告。
reportWire -summary ../report/place_opt/wirelength.rpt

# 输出布局后的功耗报告。
reportPower -outfile ../report/place_opt/$init_design.place.power.rpt

# 执行 pre-CTS 时序分析，评估 CTS 前的 setup/hold 和路径质量。
timeDesign -preCTS -outDir ../report/place_opt/$init_design.place.timeDesign.rpt

# PreCTS optimization (enabled by default)
# 默认开启 CTS 前优化，用于修复 DRV 并改善 pre-CTS setup 时序。
set preCTS_opt true
if {$preCTS_opt} {
  puts "INFO: Starting preCTS optimization..."
  puts "INFO: Performing setup and DRV optimization before CTS"

  # 开启电容、transition 和 fanout/load 违例修复。
  setOptMode -fixCap true -fixTran true -fixFanoutLoad true

  # 先修复 DRV，再进行 pre-CTS setup 时序优化。
  optDesign -preCTS -drv
  optDesign -preCTS

  # 输出第一次 pre-CTS 优化后的时序、DRV 和 slack 报告。
  timeDesign -preCTS -idealClock -pathReports -drvReports -slackReports -numPaths 50 -prefix preCTS_opt -outDir ../report/preCTS

  # 继续进行一次增量优化，提高时序和 DRV 收敛质量。
  setOptMode -fixCap true -fixTran true -fixFanoutLoad true
  optDesign -preCTS -incr

  # 输出增量优化后的时序、DRV 和 slack 报告。
  timeDesign -preCTS -idealClock -pathReports -drvReports -slackReports -numPaths 50 -prefix preCTS_opt_incr -outDir ../report/preCTS
  puts "INFO: preCTS optimization completed"
} else {
  puts "INFO: preCTS optimization skipped"
}

# 保存 placement 阶段完成后的 Innovus 数据库。
saveDesign ../database/$init_design.place.enc

# 记录 placement 阶段结束时间。
echo "END : 03_place_opt $rundate" >> ../report/runtime.log
