# MMMC setup for Innovus
# 本文件建立功能模式下的 best/worst 时序库、RC corner、delay corner 和 analysis view。

# 创建功能约束模式，并读取 init_setup.tcl 中 init_sdc 指向的 SDC 文件。
create_constraint_mode -name func -sdc_files $init_sdc

# 创建 best-case 时序库集合。
# bc 库通常用于 hold 分析，包含标准单元 bc lib 和 SRAM ff corner lib。
create_library_set -name lib_set_bc -timing {\
  /home/library/tsmc65lp/std/TSMCHOME/digital/Front_End/timing_power_noise/NLDM/tcbn65lp_220a/tcbn65lpbc.lib \
  /home/library/tsmc65lp/sram/ts1n65lpll2048x64m8_220a/SYNOPSYS/ts1n65lpll2048x64m8_220a_ff1p32vm40c.lib \
}

# 创建 worst-case 时序库集合。
# wc 库通常用于 setup 分析，包含标准单元 wc lib 和 SRAM ss corner lib。
create_library_set -name lib_set_wc -timing {\
  /home/library/tsmc65lp/std/TSMCHOME/digital/Front_End/timing_power_noise/NLDM/tcbn65lp_220a/tcbn65lpwc.lib \
  /home/library/tsmc65lp/sram/ts1n65lpll2048x64m8_220a/SYNOPSYS/ts1n65lpll2048x64m8_220a_ss1p08v125c.lib \
}

##############################
########## RC corner #########
##############################

# 创建 worst RC corner。
# 温度 125℃，使用 cworst cap table，通常对应 setup 分析中的慢速互连条件。
create_rc_corner -name rc_corner_worst \
  -T 125 \
  -cap_table "/home/library/tsmc65lp/std/TSMCHOME/digital/Back_End/lef/tcbn65lp_200a/techfiles/captable/cln65lp_1p09m+alrdl_top2_cworst.captable"

# 创建 best RC corner。
# 温度 -40℃，使用 cbest cap table，通常对应 hold 分析中的快速互连条件。
create_rc_corner -name rc_corner_best \
  -T -40 \
  -cap_table "/home/library/tsmc65lp/std/TSMCHOME/digital/Back_End/lef/tcbn65lp_200a/techfiles/captable/cln65lp_1p09m+alrdl_top2_cbest.captable"

#################################
########## Delay corner #########
#################################

# 将 worst-case 时序库与 worst RC corner 组合为 setup 使用的 delay corner。
create_delay_corner -name delay_corner_wc \
  -library_set lib_set_wc \
  -rc_corner rc_corner_worst

# 将 best-case 时序库与 best RC corner 组合为 hold 使用的 delay corner。
create_delay_corner -name delay_corner_bc \
  -library_set lib_set_bc \
  -rc_corner rc_corner_best

####################################
########## Analysis view ###########
####################################

# 创建 setup 分析视图，绑定 worst delay corner 和功能约束模式。
create_analysis_view -name func_setup_view \
  -delay_corner delay_corner_wc \
  -constraint_mode func

# 创建 hold 分析视图，绑定 best delay corner 和功能约束模式。
create_analysis_view -name func_hold_view \
  -delay_corner delay_corner_bc \
  -constraint_mode func

# 激活当前 MMMC 分析视图：setup 使用 worst view，hold 使用 best view。
set_analysis_view -setup [list func_setup_view] -hold [list func_hold_view]
