### init

# 指定 Innovus 导入设计时使用的顶层模块名称，取自 init_setup.tcl 中的 init_design。
set init_top_cell              $init_design

# 指定 Innovus 导入设计时读取的综合后 Verilog 网表，取自 init_setup.tcl 中的 init_netlist。
set init_verilog               $init_netlist

# 指定 Innovus 导入设计时使用的 LEF 文件列表。
# 当前 65nm 配置已在 init_setup.tcl 的 lib_lef 中统一列出标准单元和 SRAM LEF。
set init_lef_file              "$lib_lef"

# 指定 MMMC 配置脚本路径，用于建立 constraint mode、library set、RC corner 和 analysis view。
set init_mmmc_file             "../script/mmmc.tcl"

# 指定全局电源/地网络名称，分别取自 init_setup.tcl 中的 init_pwr 和 init_gnd。
set init_pwr_net               $init_pwr
set init_gnd_net               $init_gnd

# 设置层次化实例名称分隔符为斜杠，便于保持网表层次路径一致。
set defHieChar                 {/}

# 设置时序分析的时间单位为 1ns。
set timing_time_unit           {1ns}

# 关闭 Innovus 数据库二进制保存模式，便于生成文本形式数据库。
set ::enc_save_binary          0

# 使用默认 floorplan core control 设置。
set fp_core_cntl               {}

# 当前流程不额外设置 OpenAccess 库搜索路径。
set init_oa_search_lib         {}

# 设置 OCP/时序相关增益倍率为 1.000，表示不额外放大或缩小。
set lsgOCPGainMult             1.000

# 设置 IO 默认方向为 R0，即不旋转。
set conf_ioOri                 {R0}


#### define global vary

# 开启 clock-to-data CPPR，降低公共时钟路径带来的悲观量。
set_global timing_cppr_remove_clock_to_data_crp             true

# 同时传播 rising/falling 时钟相位，用于更完整的时序相位分析。
set_global timing_clock_phase_propagation                   both

# 开启时钟重汇聚悲观量移除，提高时序分析精度。
set_global timing_remove_clock_reconvergence_pessimism      true

# 允许锁存器进行 time borrowing 分析。
set_global timing_use_latch_time_borrow                     true

# 关闭顺序逻辑传播中的 case analysis 自动传播。
set_global timing_case_analysis_for_sequential_propagation  false

# 设置报告数值精度为小数点后三位。
set_global report_precision                                 3

# 将 report_timing 报告头信息设置为 extended 扩展格式。
set_global timing_report_timing_header_detail_info          extended

# 关闭对 primary input 的默认 assertion 假设。
set_global timing_apply_default_primary_input_assertion     false

# 保持库中 data-to-data timing check 有效。
set_global timing_disable_library_data_to_data_checks       false

# 保持用户自定义 data-to-data timing check 有效。
set_global timing_disable_user_data_to_data_checks          false
