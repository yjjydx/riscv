# Init-only setup for step1.init.tcl
# 本文件只保留设计导入阶段需要的变量和通用运行设置。

# 生成当前运行时间戳，用于 runtime.log 中标记各阶段开始/结束时间。
set rundate [clock format [clock seconds] -format %Y_%m_%d_%I:%M_%p]

#########################
########## init #########
#########################

# 指定本次 PR 流程的顶层设计名称。
set init_design "riscv"

# 指定综合后 Verilog 门级网表路径。
set init_netlist "../../SYN_test/output/riscv_20260611_1509.v"

# 指定综合后 SDC 约束文件路径。
set init_sdc "../../SYN_test/output/riscv_20260611_1509.sdc"

# 初始化 dont_use 单元列表；当前不预设禁用单元。
set init_dont_use {}

# 指定全局电源/地网络名称。
set init_pwr "VDD"
set init_gnd "VSS"

# 兼容 global.tcl 中 init_lef_file 对 tech_lef 的引用。
# 新库配置已统一写入 lib_lef 列表，因此这里保持为空。
set tech_lef {}

# 指定 Innovus 导入设计时使用的 LEF 文件列表。
# 包含 65nm 标准单元 tech/physical LEF 和 SRAM 宏单元 LEF。
set lib_lef [list \
  /home/library/tsmc65lp/std/TSMCHOME/digital/Back_End/lef/tcbn65lp_200a/lef/tcbn65lp_9lmT2.lef \
  /home/library/tsmc65lp/sram/ts1n65lpll2048x64m8_220a/LEF/ts1n65lpll2048x64m8_220a_5m.lef \
]

# OA/techlib 相关提示信息屏蔽，避免已知非关键消息干扰日志阅读。
set_message -id IMPOAX-332  -suppress
set_message -id IMPOAX-124  -suppress
set_message -id TECHLIB-320 -suppress
set_message -id TCLCMD-1142 -suppress
set_message -id IMPLF-200   -suppress
set_message -id IMPLF-201   -suppress

# 保留最近 500 条 Innovus 命令历史，便于调试和复盘。
history keep 500

### Report timing format

# 设置表格报告为固定宽度，提升文本报告可读性。
set_table_style -no_frame_fix_width

# 限制 report_timing 表格列宽，避免长路径或实例名破坏排版。
set_table_style -name report_timing -max_width {80,25,5,5,,,}

# 定义 report_timing 的输出字段，包含时序点、单元、负载、slew、延迟和物理位置信息。
set_global report_timing_format {timing_point cell fanout load slew user_derate total_derate incr_delay delay arrival phys_info pin_location}

# 设置 dbGet 查询结果以表格形式显示。
setDbGetMode -displayFormat table

# 设置本地并行 CPU 数，提高 Innovus 后端实现运行速度。
setMultiCpuUsage -localCpu 32

# 关闭 Innovus 二进制数据库保存模式，便于生成可移植的文本数据库。
set ::enc_save_binary 0

# 设置保存数据库或报告时的压缩等级。
setCompressLevel 1

# 切换命令日志记录模式，便于需要时输出更详细的命令信息。
proc pp {args} {
  setPreference CmdLogMode 2
}

# 恢复命令日志记录模式。
proc ppp {args} {
  setPreference CmdLogMode 1
}
