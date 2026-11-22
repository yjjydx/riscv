# =============================================================================
# PrimeTime 静态时序分析脚本（根据学姐脚本整理并补充中文注释）
#
# 当前脚本用途：
#   1. 读取布局布线后的门级网表；
#   2. 链接标准单元与 SRAM 时序库；
#   3. 读取 StarRC 提取的 SPEF 和后端 SDC；
#   4. 输出 setup、hold、DRV、寄生标注率和分析覆盖率报告；
#   5. 保存 PrimeTime session。
#
# 当前脚本默认关闭人为 OCV timing derate，按所读取的库、SPEF 和 SDC 直接分析。
# 重要限制：当前 setup 和 hold 共用同一套慢角库，因此 hold 结果只能作为
# 初步检查，不能作为严格的多角 signoff hold 结论。正式分析应为 hold 单独
# 配置快角标准单元库、快角 SRAM 库以及相应的 early/late derate。
# =============================================================================

# 设置 PrimeTime 最大并行核数。
set_host_options -max_cores 32

# 根据 pt.tcl 自身的位置定位 PT_test 根目录，避免运行命令所在目录不同导致
# report 重定向失败。目录结构约定如下：
#   PT_test/script/pt.tcl
#   PT_test/work/report/
set script_dir      [file dirname [file normalize [info script]]]
set pt_root_dir     [file dirname $script_dir]
set work_dir        [file join $pt_root_dir work]
set timing_dir      [file join $work_dir report timing]
set setup_report_dir [file join $timing_dir func_typical_setup]
set hold_report_dir  [file join $timing_dir func_typical_hold]
set session_dir      [file join $timing_dir pt_session]

# 在日志中打印最终报告路径，便于确认脚本定位是否正确。
puts "PT report directory: $timing_dir"

# 是否删除旧报告。默认关闭，防止误删历史结果；需要全新运行时再改为 true。
set clean_old_reports false
if {$clean_old_reports} {
  file delete -force $timing_dir
}

# Tcl 的 file mkdir 本身会递归创建父目录，不需要、也不支持 shell 风格的 -p。
file mkdir $setup_report_dir
file mkdir $hold_report_dir
file mkdir $session_dir

# 学姐原脚本屏蔽了这些消息。初次检查新 SPEF 时不建议屏蔽，避免遗漏
# 寄生参数未标注、RC 网络异常等关键信息；确认流程稳定后可按需恢复。
# suppress_message {RC-005 RC-008 RC-104 DBR-207 UITE-130}

# 指定设计链接所需的 SRAM 和标准单元时序库。
# 当前两者都是慢角/最差条件库：SRAM ss1p08v125c，标准单元 tcbn65lpwc。
set_app_var link_library [list \
  * \
  /home/project/cp_training_backend1/users/cpu26/target/SYN_FLOW/sram/ts1n65lpll2048x64m8_220a_ss1p08v125c.db \
  /home/library/tsmc65lp/std/TSMCHOME/digital/Front_End/timing_power_noise/NLDM/tcbn65lp_220a/tcbn65lpwc.db \
]

# 开启 PrimeTime SI 串扰分析。SPEF 必须保留耦合电容，且需要相应 PT-SI 许可。
set_app_var si_enable_analysis true

# 读取布局布线后的最终门级网表。该网表应包含 CTS 和后端 ECO 插入的单元。
read_verilog /home/project/cp_training_backend1/users/cpu26/target/PR_ydx/data/riscv.vg

# 设置并链接顶层设计，将网表中的 cell reference 解析到 link_library。
current_design riscv
link_design

# 读取 StarRC 提取的寄生 RC，并保留耦合电容以供 SI 分析。
# SPEF 必须与上面的 riscv.vg 来自同一次最终 PR 数据。
read_parasitics -keep_capacitive_coupling -format spef \
  /home/project/cp_training_backend1/users/cpu26/target/PT_test/starrc_flow/riscv_core_typical.spef

# 关闭自动 wire-load model 选择。由于已经读取 SPEF，实际连线应以寄生 RC 为准。
# 原脚本仍设置 top wire-load mode；它主要可能影响未被 SPEF 标注的网络，因此
# 必须结合 report_annotated_parasitics 检查是否存在大量未标注网络。
set auto_wire_load_selection false
set_wire_load_mode top

# 读取后端导出的 SDC。source 与 read_sdc 的本质都是执行 SDC Tcl 命令；
# -echo/-verbose 便于在日志中观察每条约束的执行情况。
source -echo -verbose \
  /home/project/cp_training_backend1/users/cpu26/target/PR_ydx/data/riscv_post_pr.sdc

# CTS 后使用 propagated clock，让时钟延迟来自真实时钟树和 SPEF，
# 而不是继续使用理想时钟。
set_propagated_clock [all_clocks]

# 是否启用人为 OCV derate。当前设为 false，因此不会执行原脚本中的
# clock late=1.08 和 data late=1.11；报告中的延时直接来自时序库与 SPEF。
# 如果后续拿到正式 OCV 规范，可改为 true，并补充匹配的 early/late 系数。
set enable_ocv_derate false
if {$enable_ocv_derate} {
  set_timing_derate -late 1.08 -clock
  set_timing_derate -late 1.11 -data
}

# 对所有时钟同时设置 40 ps 不确定度。若 setup/hold 要求不同，正式流程中应使用
# -setup 和 -hold 分别设置。
set_clock_uncertainty 0.04 [all_clocks]

# 检查时钟、约束和时序结构完整性。
# 原脚本的超长 -include 列表包含当前 PrimeTime 版本不识别的检查类型，
# 命令本体报错后被外层重定向统一显示为“Errors detected during redirect”。
# 这里改用兼容性更好的基础检查；并用 file join 明确构造输出文件名。
redirect -file [file join $setup_report_dir check_timing.rpt] {
  check_timing -verbose
}

# 检查 SPEF 寄生参数的标注情况，列出未标注的 pin-to-pin 网络。
report_annotated_parasitics -check -max_nets 1000 \
  -list_not_annotated -pin_to_pin_nets \
  > $setup_report_dir/report_annotated_parasitics.rpt

# 显式更新时序。多数 report 命令也会隐式更新，但单独执行更便于定位错误。
update_timing

# =============================================================================
# Setup（最大延时）报告
# =============================================================================

# 输出各时钟域的 setup 全局时序汇总。
report_global_timing -delay_type max -include {per_clock_violations} \
  > $setup_report_dir/report_global_timing_setup.rpt

# 输出电容、transition、fanout、脉宽、周期和 skew 等约束违例。
report_constraint -nosplit -all_violators -path_type end \
  -max_capacitance -max_transition -max_fanout -min_fanout \
  -min_pulse_width -min_period \
  -pulse_clock_min_width -pulse_clock_max_width \
  -pulse_clock_min_transition -pulse_clock_max_transition \
  -max_skew -significant_digits 3 \
  > $setup_report_dir/report_constraint.rpt

# 检查 setup、hold、recovery/removal、时钟门控等检查项的覆盖情况。
report_analysis_coverage -status_details {untested} \
  -check_type {setup hold recovery removal min_period clock_gating_setup clock_gating_hold max_skew out_setup out_hold} \
  -exclude_untested {constant_disabled false_paths} \
  -significant_digits 3 \
  > $setup_report_dir/report_analysis_coverage.rpt

# 输出设计规模和基本属性。
report_design > $setup_report_dir/report_design.rpt

# 以下四组报告只输出 slack < 0 的 setup 违例，并按路径类型分类。

# 寄存器到寄存器（r2r）。
report_timing -nosplit -crosstalk_delta -capacitance -input_pins \
  -include_hierarchical_pins -nets -transition_time -sort_by slack \
  -delay_type max -nworst 1 -max_paths 20000 \
  -path_type full_clock_expanded -slack_lesser_than 0 -significant_digits 3 \
  -exclude [get_ports] \
  > $setup_report_dir/report_timing.r2r.setup.rpt

# 输入端口到寄存器（i2r）。
report_timing -nosplit -crosstalk_delta -capacitance -input_pins \
  -include_hierarchical_pins -nets -transition_time -sort_by slack \
  -delay_type max -nworst 1 -max_paths 20000 \
  -path_type full_clock_expanded -slack_lesser_than 0 -significant_digits 3 \
  -from [all_inputs] -exclude [all_outputs] \
  > $setup_report_dir/report_timing.i2r.setup.rpt

# 寄存器到输出端口（r2o）。
report_timing -nosplit -crosstalk_delta -capacitance -input_pins \
  -include_hierarchical_pins -nets -transition_time -sort_by slack \
  -delay_type max -nworst 1 -max_paths 20000 \
  -path_type full_clock_expanded -slack_lesser_than 0 -significant_digits 3 \
  -to [all_outputs] -exclude [all_inputs] \
  > $setup_report_dir/report_timing.r2o.setup.rpt

# 输入端口到输出端口（i2o）。
report_timing -nosplit -crosstalk_delta -capacitance -input_pins \
  -include_hierarchical_pins -nets -transition_time -sort_by slack \
  -delay_type max -nworst 1 -max_paths 20000 \
  -path_type full_clock_expanded -slack_lesser_than 0 -significant_digits 3 \
  -from [all_inputs] -to [all_outputs] \
  > $setup_report_dir/report_timing.i2o.setup.rpt

# 保存 setup 报告完成时的 PrimeTime 会话。
save_session $session_dir/pt_session.func_typical_setup.session

# =============================================================================
# Hold（最小延时）报告
# =============================================================================
# 注意：这里没有切换到快角库，并且当前关闭 OCV derate，所以只是用当前慢角模型
# 报告 min delay。它可以帮助发现明显 hold 问题，但不能代替正式 hold signoff。

# 输出各时钟域的 hold 全局时序汇总。
report_global_timing -delay_type min -include {per_clock_violations} \
  > $hold_report_dir/report_global_timing_hold.rpt

# 寄存器到寄存器（r2r）hold 违例。
report_timing -nosplit -crosstalk_delta -capacitance -input_pins \
  -include_hierarchical_pins -nets -transition_time -sort_by slack \
  -delay_type min -nworst 1 -max_paths 20000 \
  -path_type full_clock_expanded -slack_lesser_than 0 -significant_digits 3 \
  -exclude [get_ports] \
  > $hold_report_dir/report_timing.r2r.hold.rpt

# 输入端口到寄存器（i2r）hold 违例。
report_timing -nosplit -crosstalk_delta -capacitance -input_pins \
  -include_hierarchical_pins -nets -transition_time -sort_by slack \
  -delay_type min -nworst 1 -max_paths 20000 \
  -path_type full_clock_expanded -slack_lesser_than 0 -significant_digits 3 \
  -from [all_inputs] -exclude [all_outputs] \
  > $hold_report_dir/report_timing.i2r.hold.rpt

# 寄存器到输出端口（r2o）hold 违例。
report_timing -nosplit -crosstalk_delta -capacitance -input_pins \
  -include_hierarchical_pins -nets -transition_time -sort_by slack \
  -delay_type min -nworst 1 -max_paths 20000 \
  -path_type full_clock_expanded -slack_lesser_than 0 -significant_digits 3 \
  -to [all_outputs] -exclude [all_inputs] \
  > $hold_report_dir/report_timing.r2o.hold.rpt

# 输入端口到输出端口（i2o）hold 违例。
report_timing -nosplit -crosstalk_delta -capacitance -input_pins \
  -include_hierarchical_pins -nets -transition_time -sort_by slack \
  -delay_type min -nworst 1 -max_paths 20000 \
  -path_type full_clock_expanded -slack_lesser_than 0 -significant_digits 3 \
  -from [all_inputs] -to [all_outputs] \
  > $hold_report_dir/report_timing.i2o.hold.rpt

# 保存包含 setup/hold 分析状态的最终会话。
save_session $session_dir/pt_session.func_typical.session

# 按需取消注释，让 batch 模式完成后自动退出。
# quit
