# Step 6: Chip Finish
# Standalone script with all variables embedded (no external setup.tcl dependency)

# 命令说明：生成当前运行时间字符串，作为 chipfinish 阶段写入 runtime.log 的时间标记。
set rundate [clock format [clock seconds] -format %Y_%m_%d_%I:%M_%p]
# 命令说明：设置当前 Innovus 数据库对应的顶层设计名称。
set init_design "riscv"

# 命令说明：向 runtime.log 追加 chipfinish 阶段开始时间，便于统计每一步运行耗时。
echo "START : 06_chipfinish $rundate" >> ../report/runtime.log

# 命令说明：设置本地并行 CPU 数量为 32，提高 chip finish 阶段运行速度。
setMultiCpuUsage -local 32

# 命令说明：加载 route 优化后保存的设计数据库，chip finish 阶段从该数据库继续执行。
source ../database/$init_design.route_opt.enc

####### CHIP FINISH ######
# 命令说明：删除旧的 chipfinish 报告目录，避免新旧报告混在一起。
exec rm -rf ../report/chipfinish
# 命令说明：重新创建 chipfinish 报告目录，用于存放本轮 chip finish 相关报告。
file mkdir ../report/chipfinish

# Decap and filler cells (values embedded)
# 名词解释：decap cell 是去耦电容单元，本质上是放在芯片里的“小电容”。
# 初学者理解：电路高速翻转时会瞬间从电源网吸电流，可能让局部 VDD 电压抖动。
# decap 可以临时储存一部分电荷，在电源电压波动时补一点电，帮助降低 IR drop 和电源噪声。
# 名词解释：filler cell 是填充单元，本身不做逻辑功能。
# 初学者理解：标准单元行里不能留下随意空洞，filler 用来填满空隙，
# 让 Nwell、implant、电源轨等版图结构连续，也让后续 DRC/LVS 更容易通过。
# 命令说明：定义可插入的 decap 单元列表，decap 用于增强电源稳定性、降低局部电源噪声。
set decap_cells [list DCAP DCAP4 DCAP8 DCAP16 DCAP32 DCAP64]
# 命令说明：定义可插入的 filler 单元列表，filler 用于填满标准单元行空隙并保持井/电源连续。
set filler_cells [list FILL1 FILL2 FILL4 FILL8 FILL16 FILL32 FILL64]

# Add decap cell
# 命令说明：遍历 decap 单元列表，逐个解除 dont_use 限制，允许工具插入这些 decap 单元。
foreach libraryname $decap_cells {
  # 命令说明：把即将执行的 setDontUse 命令打印到日志，便于追踪当前处理的 decap 单元。
  echo "setDontUse $libraryname false"
  # 命令说明：允许当前 decap 单元被 addFiller 使用。
  setDontUse $libraryname false
}
# 命令说明：设置 filler 插入模式为插入 decap 单元，并启用 diffCellViol 和 DRC 检查。
#setFillerMode -diffCellViol true -doDRC true -corePrefix DeCap -core $decap_cells
# 命令说明：按当前 filler 模式插入 decap 单元。
#addFiller
# 命令说明：在保留已有布线的前提下做 ECO 方式布局细化，使新增 decap 单元位置合法。
# 名词解释：refinePlace 主要处理“器件位置”问题。
# 初学者理解：插入 decap 后，工具需要确认这些单元有没有重叠、有没有对齐到标准单元行、
# 有没有违反基本摆放规则。refinePlace 的重点是把单元摆合法，不是重新布完整金属线。
#refinePlace -preserveRouting true -eco true

# Add filler cells
# 命令说明：切换 filler 插入模式为普通 filler 单元。
setFillerMode -diffCellViol true -doDRC true -corePrefix Filler -core $filler_cells
# 命令说明：插入普通 filler 单元，填充标准单元行中的剩余空隙。
addFiller

# 命令说明：执行 ECO 布线，处理插入 decap/filler 后产生的局部连接或布线更新。
# 名词解释：ecoRoute 主要处理“金属连线”问题。
# 初学者理解：refinePlace 更像是在整理器件摆放位置，ecoRoute 更像是在修补局部金属线。
# 两者不是一回事：refinePlace 不负责完整连线，ecoRoute 不负责大规模重新布局。
# 在 chip finish 阶段，通常先插入 decap/filler 并用 refinePlace 保证位置合法，
# 再用 ecoRoute 对新增或受影响的连接做局部布线修复。
ecoRoute

# 命令说明：执行 DRC 检查，确认 chip finish 后版图规则是否仍然干净。
verify_drc

################################
# PG net creation
################################
# 命令说明：创建 VDD 电源网络；当前注释掉，表示沿用前面阶段已有的 PG 网络。
#create_pg_net -net VDD -type power
# 命令说明：创建 VSS 地网络；当前注释掉，表示沿用前面阶段已有的 PG 网络。
#create_pg_net -net VSS -type ground

# Global net connections
# 命令说明：把所有实例的 VSS pgpin 全局连接到 VSS 网络；当前注释掉，避免重复覆盖已有连接。
#globalNetConnect VSS -pin VSS -type pgpin -inst * -override
# 命令说明：把所有实例的 VDD pgpin 全局连接到 VDD 网络；当前注释掉，避免重复覆盖已有连接。
#globalNetConnect VDD -pin VDD -type pgpin -inst * -override

# Export netlist and DEF
# 命令说明：导出最终门级网表到 data 目录，用于后续仿真、LVS 或交付。
saveNetlist ../data/${init_design}.vg

write_sdf -version 3.0 \
    -min_view func_hold_view \
    -max_view func_setup_view \
    ../data/riscv_post_pr.sdf
# 命令说明：设置 DEF 输出版本为 5.8。
set lefDefOutVersion 5.8
# 命令说明：导出包含 floorplan、netlist 和 routing 信息的 DEF 文件。
defOut -floorplan -netlist -routing ../data/${init_design}.def

### GDS output settings (values embedded)
# 命令说明：指定 GDS streamOut 使用的层映射文件，把 Innovus 层名映射到 GDS 层号/数据类型。
set gds_map_file "/home/library/tsmc65lp/std/TSMCHOME/digital/Back_End/lef/tcbn65lp_200a/techfiles/Virtuoso/map/mapfiles/Vir65nm_9M_6X2Z_v1.4b.042508.map"
#set gds_map_file "/home/library/tsmc65lp/std/TSMCHOME/digital/Back_End/lef/tcbn65lp_200a/techfiles/Virtuoso/map/mapfiles/Virtuoso_9M_6X2Z_v1.4b.042508.map"
# 命令说明：指定 GDS 输出使用的库名。
set gds_lib_name "RISCV_65NM_LIB"

# 命令说明：设置 streamOut GDS 版本为 600。
setStreamOutMode -version 600
# 命令说明：设置 GDS 中标注文字大小为 0.1。
setStreamOutMode -textSize 0.1
# 命令说明：开启虚拟连接处理，便于 GDS 导出时识别部分逻辑连接关系。
setStreamOutMode -virtualConnection true
# 命令说明：开启单元名唯一化前缀，避免 streamOut 后出现重名 cell。
setStreamOutMode -uniquifyCellNamesPrefix true
# 命令说明：开启特殊 via 名称输出，保留 SE via 相关名称信息。
setStreamOutMode -SEvianames true

# 命令说明：导出最终 GDS2 版图文件，供版图检查、LVS/DRC 或最终交付使用。
streamOut ../output/${init_design}.gds2 -mapFile $gds_map_file -libName $gds_lib_name -units 1000 -mode ALL

#Optional: Extract timing models
# 命令说明：设置 setup 模型提取使用的分析视图名称。
set setup_view "func_setup_view"
# 命令说明：设置 hold 模型提取使用的分析视图名称。
set hold_view "func_hold_view"

# 命令说明：把 setup 和 hold 都切到 setup view，用于提取 setup 方向的时序模型。
set_analysis_view -setup $setup_view -hold $setup_view
# 命令说明：基于 setup view 提取 Liberty 时序模型，输出 setup lib。
do_extract_model -view $setup_view ../data/${init_design}_setup.lib

# 命令说明：把 setup 和 hold 都切到 hold view，用于提取 hold 方向的时序模型。
set_analysis_view -setup $hold_view -hold $hold_view
# 命令说明：基于 hold view 提取 Liberty 时序模型，输出 hold lib。
do_extract_model -view $hold_view ../data/${init_design}_hold.lib

# 命令说明：导出 LEF abstract，提取 block obstruction 和 M8/M9 电源 pin 信息。
write_lef_abstract -extractBlockObs -extractBlockPGPinLayers {M8 M9} -PGpinLayers {M8 M9} -stripePin -specifyTopLayer M9 -5.7 ../data/${init_design}.lef

# 命令说明：导出后端完成后的 SDC 约束文件，供后续验证或交付使用。
write_sdc ../data/riscv_post_pr.sdc

# 命令说明：以 tcon 方式保存 chipfinish 阶段最终 Innovus 数据库。
saveDesign -tcon ../database/$init_design.chipfinish.enc
