# Step 2: Floorplan
# Standalone script with all variables embedded (no external setup.tcl dependency)

set rundate [clock format [clock seconds] -format %Y_%m_%d_%I:%M_%p]
set init_design "riscv"

# 记录 floorplan 阶段开始时间，便于后续统计每个阶段运行时间。
echo "START : 02_create_floorplan $rundate" >> ../report/runtime.log

# 读取 step1.init.tcl 生成的初始化数据库。
source ../database/$init_design.init.enc

# 清理并重新创建 floorplan 报告目录，避免旧报告混入本次结果。
exec rm -rf ../report/floorplan
file mkdir ../report/floorplan

# 设置 Innovus 本地并行 CPU 数，提高 floorplan 和电源网络生成速度。
setMultiCpuUsage -localCpu 32

# 计算芯片面积
# site{0.2 1.8}
# 创建芯片 floorplan：core site 为 core，die/core 尺寸为 610 x 450，四周边距均为 20。
floorPlan -site core -s 610 450 20 20 20 20

# Dont use cells
# 禁用匹配 G*TIE* 的 tie 单元，避免后续布局优化阶段自动使用这些单元。
set dontuse_ref [list G*TIE*]
foreach libraryname $dontuse_ref {
  setDontUse $libraryname true
}

########## place pin and IP/macro
# 开启 pin 批量编辑模式，降低多次 editPin 的交互开销。
setPinAssignMode -pinEditInBatch true
# 将所有输入端口放置到指定边上，使用 M4 层，间距 0.1um，起点坐标为 0 210。
editPin -fixOverlap 1 -unit MICRON -spreadDirection clockwise -edge 0 -layer 4 -spreadType start -spacing 0.1 -start 0 210 -pin [get_object_name [all_inputs ]]
# 将所有输出端口放置到指定边上，使用 M6 层，间距 0.1um，起点坐标为 0 210。
editPin -fixOverlap 1 -unit MICRON -spreadDirection clockwise -edge 0 -layer 6 -spreadType start -spacing 0.1 -start 0 210 -pin [get_object_name [all_outputs ]]
# 关闭 pin 批量编辑模式，使前面的 pin 放置设置生效。
setPinAssignMode -pinEditInBatch false

# SRAM / Macro 摆放说明：
# 这里原本直接读入学姐准备好的 dct_floorplan.def。该 DEF 通常会包含 SRAM/macro 的摆放坐标、
# orientation、fixed 状态、blockage 或其他 floorplan 约束。
# 如果你保持当前 floorPlan 尺寸不变，可以继续使用这个 DEF。
# 如果你自己修改了 floorPlan 的 core/die 尺寸，那么 DEF 里的 SRAM 坐标可能不再合适：
# - SRAM 可能离边界太近，影响 power ring/stripe；
# - SRAM 可能压缩标准单元可用区域，造成 placement/route 拥塞；
# - SRAM 周围 channel 可能变窄，后续 block ring、sroute、signal route 都会更难。
# 因此，改 floorPlan 尺寸后，建议重新检查并手动摆放 SRAM/macro。

# 模式 1：使用已有 DEF，适合复现学姐已经调好的 floorplan。
set use_predefined_sram_def true

if {$use_predefined_sram_def} {
  # 读入已有 DEF floorplan，用于导入 SRAM/macro 位置、block 信息或预定义物理约束。
  defIn ../data/dct_floorplan.def
} else {
  # 模式 2：自己重新摆放 SRAM/macro，适合修改 core 尺寸后重新做 floorplan。
  #
  # 手动摆放建议步骤：
  # 1. 先改上面的 floorPlan -s <core宽> <core高> <左边距> <下边距> <右边距> <上边距>。
  # 2. 在 Innovus 命令行查 SRAM/macro 实例名：
  #      dbGet [dbGet top.insts.cell.name *SRAM* -p2].name
  #      dbGet [dbGet top.insts.cell.name *sram* -p2].name
  #    如果 SRAM 命名不含 SRAM，可先查所有 block/macro：
  #      dbGet [dbGet top.insts.isBlock 1 -p].name
  # 3. 用 GUI 或 dbGet 查看 SRAM 尺寸，估算它与 core 边界、pin、power ring 的距离。
  # 4. 用 placeInstance 指定 SRAM 坐标和方向，并把它 fixed，避免后续 place 阶段移动。
  # 5. SRAM 摆好后，重新检查 utilization、congestion、PG connectivity、DRC。
  #
  # placeInstance 写法：
  #   placeInstance <SRAM实例名> <左下角X坐标> <左下角Y坐标> <方向> -fixed
  #
  # 方向常见取值：
  #   R0    ：不旋转
  #   R180  ：旋转 180 度
  #   MX/MY ：镜像，具体是否允许要看 macro LEF/工艺规则
  #
  # 示例：下面两行只是模板，使用前必须把实例名和坐标替换成你自己的。
  # placeInstance U_SRAM0 80 120 R0 -fixed
  # placeInstance U_SRAM1 360 120 R180 -fixed
  #
  # 推荐写法：把每个 SRAM/macro 的 {实例名 X Y 方向} 写到 manual_sram_places 中。
  # 注意：下面默认是空列表，避免在不知道真实 SRAM 实例名时误放置。
  set manual_sram_places [list]
  # lappend manual_sram_places [list U_SRAM0 80 120 R0]
  # lappend manual_sram_places [list U_SRAM1 360 120 R180]

  if {[llength $manual_sram_places] == 0} {
    puts "WARN: use_predefined_sram_def=false, but manual_sram_places is empty. Please fill SRAM instance placement first."
  }

  foreach sram_place $manual_sram_places {
    lassign $sram_place sram_inst sram_x sram_y sram_orient
    puts "INFO: Manually placing SRAM/macro $sram_inst at ($sram_x, $sram_y), orient=$sram_orient"
    placeInstance $sram_inst $sram_x $sram_y $sram_orient -fixed
  }
  #
  # 如果 SRAM 很靠近 core 边界或其他 macro，建议给它周围留 halo/blockage，
  # 防止标准单元贴得太近，导致 pin access 或 routing channel 不够。
  # 不同 Innovus 版本 addHaloToBlock 参数略有差异，如命令不兼容可在 GUI 中创建 halo。
  # addHaloToBlock 5 5 5 5 U_SRAM0
  # addHaloToBlock 5 5 5 5 U_SRAM1
  #
  # 手动摆放后，建议立刻检查：
  #   reportUtilization
  #   reportCongestion
  #   checkPlace
  #   verify_drc -limit 10000 -report ../report/floorplan/drc_after_manual_sram_place.rpt
}

# init global pg
# 将 tie-low/tie-high 类型连接到全局 VSS/VDD 网络。
globalNetConnect VSS -type tielo -inst * -pin VSS
globalNetConnect VDD -type tiehi -inst * -pin VDD

# 将所有实例的电源/地 pgpin 强制连接到全局 VDD/VSS，并允许覆盖网表连接。
globalNetConnect VDD -type pgpin -pin VDD -inst * -override -netlistOverride
globalNetConnect VSS -type pgpin -pin VSS -inst * -override -netlistOverride

### add ENDCAP&&WELLTAP
# 清除当前 DRC 标记，并删除旧的 CAP/FILL 实例，避免重复插入 endcap/filler。
clearDrc
deleteFiller -inst *CAP*
deleteFiller -inst *FILL*

# 重置 endcap 插入模式，防止继承旧设置。
setEndCapMode -reset

# 设置 core 四周边界使用的 endcap/filler 单元。
setEndCapMode \
  -topEdge {FILL1 FILL2 FILL4} \
  -bottomEdge {FILL1 FILL2 FILL4} \
  -leftEdge {FILL4} \
  -rightEdge {FILL2}

# 插入 endcap 单元并检查边界单元插入是否满足规则。
addEndCap
verifyEndCap

# 删除已有电源网络形状，为重新生成 power mesh 做准备。
editDelete -use power

############ create power mesh
# power ring
# 设置 core ring 生成规则：避免短路、跳过 crossing trunk，并允许从 M1 堆叠到 M9。
setAddRingMode -ring_target default -avoid_short 1 \
  -skip_crossing_trunks none -stacked_via_top_layer M9 -stacked_via_bottom_layer M1 \
  -orthogonal_only true

# 围绕 core 生成第一组 VDD/VSS 电源环：上下 M9、左右 M8。
addRing -nets {VDD VSS} -type core_rings -follow core \
  -layer {top M9 bottom M9 left M8 right M8} \
  -width {top 4 bottom 4 left 4 right 4} \
  -spacing {top 2 bottom 2 left 2 right 2} \
  -offset {top 2 bottom 2 left 2 right 2} \
  -center 0 -snap_wire_center_to_grid None

# 设置 block ring 生成规则，继续使用 M1 到 M9 的堆叠通孔范围。
setAddRingMode -ring_target default -avoid_short 1 \
  -stacked_via_top_layer M9 \
  -stacked_via_bottom_layer M1

# 为每个 macro/block 生成 VDD/VSS block ring：上下 M7、左右 M6。
addRing -type block_rings \
  -around each_block \
  -nets {VDD VSS} \
  -layer {top M7 bottom M7 left M6 right M6} \
  -width 2 \
  -spacing 1 \
  -offset 1

## power stripes
# 重新设置 ring 生成模式，用于生成另一组 core ring。
setAddRingMode -stacked_via_top_layer M9 -stacked_via_bottom_layer M1 -orthogonal_only true -ring_target default -avoid_short 1 -skip_crossing_trunks none

# 围绕 core 生成第二组 VDD/VSS 电源环：上下 M8、左右 M9。
addRing -nets {VDD VSS} -type core_rings -follow core \
  -layer {top M8 bottom M8 left M9 right M9} \
  -width 4 \
  -spacing 2 \
  -offset 2 \
  -center 0

# 设置电源条带生成规则：通孔从 M1 堆叠到 M9，遇到 block ring 时断开。
setAddStripeMode \
  -stacked_via_top_layer M9 \
  -stacked_via_bottom_layer M1 \
  -break_at block_ring

# 在 M9 上生成水平 VDD/VSS 电源条带，条带宽 2um、间距 1.8um、组间距 16um。
addStripe -nets {VDD VSS} -layer M9 -direction horizontal -width 2 -spacing 1.8 \
  -set_to_set_distance 16.0 -start_from bottom -start_offset 8.0 \
  -max_same_layer_jog_length 2

# 在 M8 上生成垂直 VDD/VSS 电源条带，条带宽 2um、间距 1.8um、组间距 16um。
addStripe -nets {VDD VSS} -layer M8 -direction vertical \
  -width 2 -spacing 1.8 \
  -set_to_set_distance 16 -start_from left -start_offset 8 \
  -switch_layer_over_obs false -max_same_layer_jog_length 2

#### power rail
# 连接标准单元电源 rail 到 VDD/VSS power mesh。
sroute -corePinTarget {firstAfterRowEnd} -allowJogging 1 -nets {VDD VSS} -allowLayerChange 1

# 专门把 Macro 的 Pin 连到 Block Ring 上
sroute -connect { blockPin } -nets {VDD VSS} -blockPinTarget { blockring } -allowJogging 1 -allowLayerChange 1

# 清除前序 DRC 标记，准备执行正式 floorplan 检查。
clearDrc

# 检查 VDD/VSS 电源网络连通性，并分别输出报告。
verifyConnectivity -noAntenna -noSoftPGConnect -noUnroutedNet -error 100000 -net VDD -report ../report/floorplan/vdd_connect.rpt
verifyConnectivity -noAntenna -noSoftPGConnect -noUnroutedNet -error 100000 -net VSS -report ../report/floorplan/vss_connect.rpt
# 检查电源/地短路问题，并输出 PG short 报告。
verify_PG_short -no_routing_blkg -report ../report/floorplan/pg_short.rpt
# 执行 floorplan 阶段 DRC 检查。
verify_drc -limit 10000 -report ../report/floorplan/drc.rpt

# 保存 floorplan 阶段完成后的 Innovus 数据库，并记录阶段结束时间。
saveDesign ../database/$init_design.floorplan.enc
echo "END : 02_create_floorplan $rundate" >> ../report/runtime.log
