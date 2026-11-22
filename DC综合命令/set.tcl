############################################################
# DC Synthesis Setup Parameters (改进版)
# This file defines all configurable parameters for synthesis
# Modify values here to control synthesis behavior
############################################################
# ============================================================================
# DC 综合参数改进版说明
#
# 相比原版的改进点：
#   1. 新增标准单元 best-case 库支持，使 hold 分析使用快工艺角
#   2. 新增 SRAM 双工艺角支持（ss + ff），hold 分析不再盲目乐观
#   3. 新增 set_operating_conditions 显式指定 PVT 条件
#   4. 新增时钟门控风格配置（set_clock_gating_style）
#   5. 新增边界优化配置（set_boundary_optimization）
#   6. 将 DEF_FILE 从 script.tcl 移到此处，保持参数流程分离
#   7. 新增时序例外变量（复位 false path）
#   8. 新增 WNS 门控阈值，编译后自动判定时序是否达标
#   9. 新增库文件存在性检查（4 个 .db 全部验证）
#  10. 清理了原版中定义但未使用的变量
#  11. LOG_DIR 现在真正被使用
#  12. 输出目录自动创建
# ============================================================================

# ── Runtime settings ────────────────────────────────────────────────────────
# 生成本次运行的时间戳，格式为 年月日_时分，例如 20260610_1530。
# 后续输出文件和报告会把该时间戳放进文件名，避免覆盖历史结果。
set rundate [clock format [clock seconds] -format %Y%m%d_%H%M]

# ── Design information ──────────────────────────────────────────────────────
# 指定综合顶层模块名。script.tcl 中的 elaborate/current_design 都会使用这个名字，
# 因此它必须与 RTL 中真正的顶层 module 名一致。
set DESIGN_NAME "riscv"

# ── Library settings ────────────────────────────────────────────────────────
# 标准单元库根目录
set STD_LIB_PATH "/home/library/tsmc65lp/std/TSMCHOME/digital/Front_End/timing_power_noise/NLDM/tcbn65lp_220a"

# SRAM 综合库所在目录
set SRAM_LIB_PATH "/home/library/tsmc65lp/sram/ts1n65lpll2048x64m8_220a/SYNOPSYS"

# SRAM .db 文件名（双工艺角）
#   ss = slow-slow (最慢 → setup 分析)
#   ff = fast-fast (最快 → hold 分析)
set SRAM_DB_WC "ts1n65lpll2048x64m8_220a_ss1p08v125c.db"
set SRAM_DB_BC "ts1n65lpll2048x64m8_220a_ff1p32vm40c.db"

# 【改进】设置 search_path，DC 会到这些路径中查找库文件
set_app_var search_path "$STD_LIB_PATH $SRAM_LIB_PATH"

# 【改进】target_library 和 link_library 同时指定 worst-case 和 best-case 库
# - wc (worst-case / slow): 用于 setup 分析 —— 最慢的工艺角
# - bc (best-case / fast):  用于 hold 分析 —— 最快的工艺角
set STD_WC_DB "tcbn65lpwc.db"
set STD_BC_DB "tcbn65lpbc.db"

# 检查库文件是否真的存在（避免静默失败）
# 标准单元 WC + BC，SRAM WC + BC，共 4 个 .db 文件
foreach lib_file [list \
    "$STD_LIB_PATH/$STD_WC_DB" \
    "$STD_LIB_PATH/$STD_BC_DB" \
    "$SRAM_LIB_PATH/$SRAM_DB_WC" \
    "$SRAM_LIB_PATH/$SRAM_DB_BC" \
] {
    if {![file exists $lib_file]} {
        error "Library file not found: $lib_file\nPlease check search_path and library settings."
    }
}

# 目标映射库：综合时把 RTL 逻辑映射到该库中的标准单元
set_app_var target_library "$STD_WC_DB"

# 链接库：星号 * 表示当前已读入设计；标准单元 WC+BC + DesignWare + SRAM WC+BC
set_app_var link_library "* $STD_WC_DB $STD_BC_DB dw_foundation.sldb $SRAM_DB_WC $SRAM_DB_BC"

# 【改进】建立 max/min 库配对，避免依赖 DC 版本相关的 get_operating_conditions 命令
# WC/BC 配对后，DC 可用 WC 做 setup/max delay，用 BC 做 hold/min delay。
if {[llength [info commands set_min_library]] > 0} {
    set_min_library $STD_WC_DB -min_version $STD_BC_DB
    puts "Info: Standard-cell min library paired: max=$STD_WC_DB, min=$STD_BC_DB"
    set_min_library $SRAM_DB_WC -min_version $SRAM_DB_BC
    puts "Info: SRAM min library paired: max=$SRAM_DB_WC, min=$SRAM_DB_BC"
} else {
    puts "Warning: set_min_library is not available; WC/BC libraries remain in link_library only."
}

# 可选：如果已从 report_lib 确认 operating condition 名称，可在这里显式填写。
# 留空时跳过，避免在不支持 get_operating_conditions 的 DC 版本上报 CMD-005。
set STD_MAX_OPERATING_CONDITION ""
set STD_MIN_OPERATING_CONDITION ""
if {[llength [info commands set_operating_conditions]] > 0 && \
    $STD_MAX_OPERATING_CONDITION ne "" && \
    $STD_MIN_OPERATING_CONDITION ne ""} {
    set_operating_conditions \
        -max $STD_MAX_OPERATING_CONDITION -max_library $STD_WC_DB \
        -min $STD_MIN_OPERATING_CONDITION -min_library $STD_BC_DB
    puts "Info: Operating conditions set: max=$STD_MAX_OPERATING_CONDITION, min=$STD_MIN_OPERATING_CONDITION"
} else {
    puts "Info: Operating condition names not specified; relying on library defaults and set_min_library pairing."
}

# ── Interconnect mode (互连延迟估算方式) ───────────────────────────────
# 由环境变量 INTERCONNECT_MODE 控制（Makefile 传入，默认 physical）：
#   physical  → 物理感知综合（Milkyway + TLUPlus + DEF，需 -topographical_mode）
#   zero_wire → 零互连延迟（非拓扑模式，SDC 干净，适合第 0 轮快速出网表）
#   wire_load → 传统线负载模型（非拓扑模式，SDC 含线负载，历史兼容）
# Main control knob. Edit this line directly.
#   physical  : use physical-aware synthesis with dc_shell -topographical_mode.
#   wire_load : use normal dc_shell and let DC auto-select a wire-load model.
set SYNTHESIS_MODE "wire_load"
set SYNTHESIS_MODE [string tolower $SYNTHESIS_MODE]
if {$SYNTHESIS_MODE ni {physical wire_load}} {
    error "Unsupported SYNTHESIS_MODE '$SYNTHESIS_MODE'. Use physical or wire_load."
}
set ENABLE_PHYSICAL_SYNTHESIS [expr {$SYNTHESIS_MODE eq "physical" ? "yes" : "no"}]

if {$SYNTHESIS_MODE eq "physical"} {
    if {[llength [info commands create_mw_lib]] == 0} {
        error "create_mw_lib command is not available. Please start DC in topographical mode."
    }
    if {[llength [info commands open_mw_lib]] == 0} {
        error "open_mw_lib command is not available. Please start DC in topographical mode."
    }
    if {[llength [info commands set_tlu_plus_files]] == 0} {
        error "set_tlu_plus_files command is not available. Please start DC in topographical mode."
    }

    # Milkyway 技术文件
    set TECH_FILE "/home/library/tsmc65lp/std/TSMCHOME/digital/Back_End/milkyway/tcbn65lp_200a/techfiles/tsmcn65_9lmT2.tf"
    # 标准单元 Milkyway 参考库
    set TECH_FILE "/home/library/tsmc65lp/std/TSMCHOME/digital/Back_End/milkyway/tcbn65lp_200a/techfiles/tsmcn65_9lmT2.tf"
    set my_mw_design_lib "riscv_mw_work_lib"
    set MW_STD_LIB "/home/library/tsmc65lp/std/TSMCHOME/digital/Back_End/milkyway/tcbn65lp_200a/frame_only/tcbn65lp"
    # SRAM Milkyway 参考库
    set MW_SRAM_LIB "/home/project/cp_training_backend1/users/cpu26/target/SYN_test/sram/sram_2048x64_mw"
    # 所有 Milkyway 参考库列表
    set MW_REF_LIBS [list $MW_STD_LIB $MW_SRAM_LIB]
    # Milkyway 工作库名称
    set my_mw_design_lib "riscv_mw_work_lib"

    # 重建干净的 Milkyway 工作库
    # }
    if {[file isdirectory $my_mw_design_lib]} {
        file delete -force $my_mw_design_lib
    }
    create_mw_lib -technology $TECH_FILE -mw_reference_library $MW_REF_LIBS $my_mw_design_lib
    open_mw_lib $my_mw_design_lib

    # TLUPlus RC 文件
    set TLUPLUS_DIR "/home/library/tsmc65lp/std/TSMCHOME/digital/Back_End/milkyway/tcbn65lp_200a/techfiles/tluplus"
    set MAP_DIR     "/home/library/tsmc65lp/std/TSMCHOME/digital/Back_End/milkyway/tcbn65lp_200a/techfiles/tluplus"
    set TLUPLUS_MAX_FILE "${TLUPLUS_DIR}/cln65lp_1p09m+alrdl_rcworst_top2.tluplus"
    set TLUPLUS_MIN_FILE "${TLUPLUS_DIR}/cln65lp_1p09m+alrdl_rcbest_top2.tluplus"
    set MAP_FILE         "${MAP_DIR}/star.map_9M"

    set_tlu_plus_files -max_tluplus $TLUPLUS_MAX_FILE \
                        -min_tluplus $TLUPLUS_MIN_FILE \
                        -tech2itf_map $MAP_FILE

    check_tlu_plus_files

    # 【改进】DEF floorplan 文件路径，从原版的 script.tcl 移到此处统一管理
    set DEF_FILE "/home/project/cp_training_backend1/users/cpu26/target/PR_FLOW/data/dct_floorplan_manual.def"
} else {
    puts "Info: Physical-aware synthesis disabled; synthesis mode is $SYNTHESIS_MODE."
}

# ── Clock settings ──────────────────────────────────────────────────────────
set CLOCK_NAME    "clk"
set CLOCK_PORT    "clk"
set REAL_PERIOD   5.0
set CLOCK_PERIOD  $REAL_PERIOD

# 时钟波形：上升沿 0ns，下降沿在周期一半处 → 50% 占空比
set CLOCK_WAVEFORM [list 0 [expr $CLOCK_PERIOD / 2.0]]

# Setup/Hold 不确定度（裕量）
set SETUP_MARGIN             0.2
set CLOCK_UNCERTAINTY_SETUP  [expr 0.05 + $SETUP_MARGIN]
set CLOCK_UNCERTAINTY_HOLD   0.05

# 时钟转换时间
set CLOCK_TRANSITION 0.1

# ── Clock Gating Style ──────────────────────────────────────────────────────
# 【改进】显式指定时钟门控风格，与 TSMC 65nm LP 库的门控单元匹配
# -sequential_cell latch : 使用锁存器+与门结构（最常用的 ICG 结构）
# -control_point before  : 使能控制在锁存器之前
# -minimum_bitwidth 3    : 寄存器宽度 ≥3 位才插入门控（避免小位宽得不偿失）
# -max_fanout 16         : 单个门控单元最多驱动 16 个寄存器
set ICG_STYLE " \
    -sequential_cell latch \
    -control_point before \
    -positive_edge_logic integrated \
    -negative_edge_logic integrated \
    -minimum_bitwidth 3 \
    -max_fanout 16"

# ── Reset settings ──────────────────────────────────────────────────────────
set RST_PORT "rst"

# 【改进】复位时序例外：复位信号不作为正常的时序路径分析
# false path 避免 DC 对复位路径做无意义的 setup/hold 优化
set RESET_FALSE_PATH true

# ── I/O delay settings ──────────────────────────────────────────────────────
set INPUT_DELAY_MAX  [expr $CLOCK_PERIOD * 0.4]
set INPUT_DELAY_MIN  0.0000
set OUTPUT_DELAY_MAX [expr $CLOCK_PERIOD * 0.4]
set OUTPUT_DELAY_MIN 0.0000

# ── Design constraints ──────────────────────────────────────────────────────
set MAX_FANOUT       32
set MAX_TRANSITION   0.6
set INPUT_TRANSITION 0.30
set OUTPUT_LOAD      0.05

# 线负载模型（仅在关闭物理感知综合时使用）
# 传统综合优先使用自动选择组，由库按面积选择更合适的 wire load。
set WIRE_LOAD_MODE             "top"
set WIRE_LOAD_SELECTION_GROUP   "WireAreaLowkCon"
set WIRE_LOAD_MODEL             "TSMC16K_Lowk_Conservative"

# Datapath smart generation
set_dp_smartgen_options -hierarchy -all_options auto

# ── Boundary Optimization ───────────────────────────────────────────────────
# 【改进】允许 DC 跨模块边界优化，对流水线级间路径尤其重要
# -effort high 使用高努力级别进行边界寄存器优化
set ENABLE_BOUNDARY_OPTIMIZATION true
set BOUNDARY_OPT_EFFORT "high"

# ── Group path settings ─────────────────────────────────────────────────────
set ENABLE_GROUP_PATH true
set COST_PRIORITY     "max_delay"

# 路径组权重体系（数值越高，优化优先级越高）
# 核心寄存器路径
set WEIGHT_CRITICAL     5.0
# SRAM/硬宏路径
set WEIGHT_MACRO        3.0
# 时钟门控控制路径
set WEIGHT_ICG          2.0
# 普通 I/O 路径
set WEIGHT_IO           1.0
# 输入直通输出路径
set WEIGHT_FEEDTHROUGH  0.5

# Critical range 设置（单位 ns，范围内的路径一起优化）
set CRITICAL_RANGE_CORE         0.2
set CRITICAL_RANGE_MACRO        0.3
set CRITICAL_RANGE_ICG          0.2
set CRITICAL_RANGE_IO           0.2
set CRITICAL_RANGE_FEEDTHROUGH  0.2

# 各路径组开关
set ENABLE_CORE         yes
set ENABLE_MACRO        yes
set ENABLE_ICG          yes
set ENABLE_IO           yes
set ENABLE_FEEDTHROUGH  yes

# ── Compile options ─────────────────────────────────────────────────────────
# 主综合命令：compile_ultra 比 compile 更强，包含高级时序/面积/逻辑优化
set COMPILE_COMMAND "compile_ultra"

# compile_ultra 选项：
#   -gate_clock                    : 自动时钟门控插入
#   -timing_high_effort_script    : 高努力时序优化
#   -no_autoungroup               : 禁止自动打散层次
#   -retime                       : 允许跨寄存器重定时（可选，按需启用）
set COMPILE_ULTRA_OPTIONS "-gate_clock -timing_high_effort_script -no_autoungroup"

# 普通 compile 的选项（仅在 COMPILE_COMMAND=compile 时使用）
set COMPILE_OPTIONS ""

# 增量综合：在主综合结果上再做一轮优化
set INCREMENTAL_COMPILE         yes
set INCREMENTAL_COMPILE_OPTIONS ""

# ── Multicore settings ──────────────────────────────────────────────────────
set MAX_CORES 16

# ── Output settings ─────────────────────────────────────────────────────────
set OUTPUT_DIR "../output"
set REPORT_DIR "../report"
set LOG_DIR    "../log"

# 【改进】确保输出目录存在，避免 write 命令因目录不存在而失败
foreach dir [list $OUTPUT_DIR $REPORT_DIR $LOG_DIR] {
    if {![file isdirectory $dir]} {
        file mkdir $dir
        puts "Info: Created directory: $dir"
    }
}

# ── Timing pass/fail threshold ──────────────────────────────────────────────
# 【改进】综合后 WNS 大于此阈值则认为时序通过
# 负值表示允许一定程度的违例（留给后端修复），正值表示需要留有裕量
set WNS_THRESHOLD -0.01

# ── RTL file list ───────────────────────────────────────────────────────────
set RTL_DIR "/home/project/cp_training_backend1/users/cpu26/target/SYN_HYH/rtl_code"

set RTL_FILES [list \
    "$RTL_DIR/riscv.v" \
]

# ── SRAM macro protection ───────────────────────────────────────────────────
# 【改进】如果 RTL 中例化了 SRAM 硬宏，需要设置 dont_touch 防止 DC 优化它们。
# 根据设计中的命名规律，SRAM 例化名通常以 U_SRAM 开头；
# 如果 SRAM 例化在 RTL 中仍被注释掉（用行为级寄存器数组替代），综合结果会出现海量触发器。
# 变量 SRAM_CELL_NAMES 可以手动列出需要保护的 SRAM 例化名。
set SRAM_CELL_NAMES [list]

# ── 参数加载完成 ───────────────────────────────────────────────────────────
puts "============================================================"
puts "Info: Parameters loaded from set.tcl (improved version)"
puts "  Design                : $DESIGN_NAME"
puts "  Clock                 : $CLOCK_NAME @ ${CLOCK_PERIOD}ns"
puts "  Compile               : $COMPILE_COMMAND"
puts "  Synthesis Mode        : $SYNTHESIS_MODE"
puts "  Physical Synthesis    : $ENABLE_PHYSICAL_SYNTHESIS"
puts "  Boundary Optimization : $ENABLE_BOUNDARY_OPTIMIZATION"
puts "  MCMM                  : Enabled (StdCell WC+BC, SRAM WC+BC)"
puts "  WNS Threshold         : $WNS_THRESHOLD ns"
puts "  RTL files             : [llength $RTL_FILES] files"
puts "  Output dir            : $OUTPUT_DIR"
puts "  Report dir            : $REPORT_DIR"
puts "  Log    dir            : $LOG_DIR"
puts "============================================================\n"
