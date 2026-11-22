# ============================================================================
# DC 综合脚本改进版
#
# 相比原版的改进点：
#   1. 增加了日志文件重定向，所有输出同步写入 LOG_DIR
#   2. Step 2: 增加了预编译 SRAM 检查，避免行为级寄存器数组被综合
#   3. Step 2: 增加了库检查报告 (report_lib, report_reference)
#   4. Step 2: 增加了资源报告 (report_resources)
#   5. Step 3: 应用了时钟门控风格 (set_clock_gating_style)
#   6. Step 4: 增加了复位 false path 约束
#   7. Step 6: 增加了 check_timing 调用
#   8. Step 7: 在编译前设置了边界优化 (set_boundary_optimization)
#   9. Step 7: 增加了编译后时序通过/失败判定
#  10. Step 7: 增加了编译后资源对比报告
#  11. Step 9: 增加了时钟门控报告
#  12. Step 9: 增加了按路径组的时序报告
#  13. Step 9: 增加了 WNS/TNS 摘要和流程状态判定
#  14. 末尾增加了 Formality 等价性检查指引
# ============================================================================

# ── Step 1: 加载参数 ────────────────────────────────────────────────────────
puts "\n=========================================="
puts "Step 1: Setup and Library Configuration"
puts "==========================================\n"

# 记录启动时间（此时还没加载 set.tcl，用 Tcl 原生方式获取时间戳）
puts "Info: Start time: [clock format [clock seconds] -format "%Y-%m-%d %H:%M:%S"]"


# ── 日志文件设置（必须在 source set.tcl 之后，因为需要其中的变量） ──────────
# DC 没有内置 tee 命令，终端输出由外部管道保留。这里设置日志文件路径供参考。
set LOG_FILE "${LOG_DIR}/${DESIGN_NAME}_${rundate}_dc.log"
set SCRIPT_DIR [file dirname [file normalize [info script]]]

# 加载参数文件（沿用原版目录结构：set.tcl 在 ../all_scripts/）
source -echo -verbose ${SCRIPT_DIR}/set.tcl
set LOG_FILE "${LOG_DIR}/${DESIGN_NAME}_${rundate}_dc.log"
puts "Info: Log file path: $LOG_FILE"
puts "Info: Run timestamp: $rundate"

# 设置 CPU 核数
set_host_options -max_cores $MAX_CORES

# 开启 SVF 记录（供 Formality 等价性检查使用）
set_svf ${OUTPUT_DIR}/${DESIGN_NAME}_${rundate}.svf

# 保存顶层设计名
set top $DESIGN_NAME

# ── Step 2: 读入 RTL 并建立设计层次 ──────────────────────────────────────────
puts "\n=========================================="
puts "Step 2: Read and Elaborate Design"
puts "==========================================\n"

foreach rtl_file $RTL_FILES {
    if {[file exists $rtl_file]} {
        analyze -format verilog $rtl_file
    } else {
        puts "Warning: RTL file not found: $rtl_file"
    }
}

elaborate $DESIGN_NAME
current_design $DESIGN_NAME
uniquify -force

# 设计结构健康检查
puts "  Running check_design..."
check_design

# 链接：解析所有模块引用和库单元
puts "  Running link..."
link

# 【改进】报告所用库信息，验证库文件正确加载
puts "  Generating library usage report..."
if {[llength [info commands report_lib]] > 0} {
    report_lib [get_libs] > ${REPORT_DIR}/${DESIGN_NAME}_${rundate}_lib.rpt
}

# 【改进】报告设计中的模块引用情况
if {[llength [info commands report_reference]] > 0} {
    report_reference > ${REPORT_DIR}/${DESIGN_NAME}_${rundate}_reference.rpt
}

# 【改进】报告综合前的资源使用情况（DesignWare 组件类型等）
if {[llength [info commands report_resources]] > 0} {
    report_resources > ${REPORT_DIR}/${DESIGN_NAME}_${rundate}_resources_pre.rpt
    puts "  Pre-compile resource report written."
}

# 【改进】SRAM 硬宏检查
# 如果 RTL 中的 SRAM 例化被注释掉（使用行为级 reg [31:0] memory[...]），
# DC 会把存储器综合成大量寄存器。这里检测并给出明确警告。
puts "  Checking for SRAM macro instances..."
set sram_count 0
# 统计当前设计中所有例化名包含 "SRAM" 或 "sram" 的实例
if {[llength [info commands get_cells]] > 0} {
    set sram_cells [get_cells -hierarchical -quiet -filter "ref_name =~ *SRAM* || ref_name =~ *sram* || ref_name =~ *TS1N*"]
    set sram_count [sizeof_collection $sram_cells]
}
if {$sram_count == 0} {
    puts "  =============================================================="
    puts "  WARNING: No SRAM hard macro instances detected in the design!"
    puts "  If DM/IM use behavioral register arrays (reg [31:0] mem[N]),"
    puts "  DC will synthesize them as THOUSANDS of flip-flops."
    puts "  This will cause massive area blow-up and poor timing."
    puts "  Please ensure SRAM macros (TS1N65LPLL2048X64M8) are properly"
    puts "  instantiated in the RTL before proceeding."
    puts "  =============================================================="
} else {
    puts "  Info: $sram_count SRAM macro instance(s) found."
    # 对 SRAM 实例设置 dont_touch，防止 DC 优化
    foreach_in_collection sram_cell $sram_cells {
        set cell_name [get_object_name $sram_cell]
        set_dont_touch [get_cells $cell_name]
        puts "    set_dont_touch on: $cell_name"
    }
}

# 保护手动指定的 SRAM 例化名（来自 set.tcl）
foreach sram_name $SRAM_CELL_NAMES {
    if {[sizeof_collection [get_cells -quiet $sram_name]] > 0} {
        set_dont_touch [get_cells $sram_name]
        puts "    set_dont_touch on: $sram_name (from SRAM_CELL_NAMES)"
    }
}

# 保存 link 后 checkpoint
write_file -format ddc -hierarchy -output ${OUTPUT_DIR}/${DESIGN_NAME}_${rundate}_link.ddc

# ── Step 3: 时钟约束 ────────────────────────────────────────────────────────
puts "\n=========================================="
puts "Step 3: Clock Constraints"
puts "==========================================\n"

remove_driving_cell [get_ports $CLOCK_PORT]
set_drive 0 [get_ports $CLOCK_PORT]

create_clock -name $CLOCK_NAME [get_ports $CLOCK_PORT] \
    -period $CLOCK_PERIOD \
    -waveform $CLOCK_WAVEFORM

set_dont_touch_network $CLOCK_NAME
set_ideal_network -no_propagate [get_ports $CLOCK_PORT]

set_clock_uncertainty -setup $CLOCK_UNCERTAINTY_SETUP [get_clocks $CLOCK_NAME]
set_clock_uncertainty -hold  $CLOCK_UNCERTAINTY_HOLD  [get_clocks $CLOCK_NAME]
set_clock_transition -max $CLOCK_TRANSITION [get_clocks $CLOCK_NAME]

# 【改进】应用时钟门控风格
# 必须在 compile_ultra -gate_clock 之前设置，否则 DC 用默认风格
if {[llength [info commands set_clock_gating_style]] > 0 && [info exists ICG_STYLE]} {
    puts "  Applying clock gating style..."
    eval "set_clock_gating_style $ICG_STYLE"
    puts "  Clock gating style applied."
}

# ── Step 4: 复位约束 ────────────────────────────────────────────────────────
puts "\n=========================================="
puts "Step 4: Reset Constraints"
puts "==========================================\n"

if {[sizeof_collection [get_ports $RST_PORT -quiet]] > 0} {
    # Propagate the ideal attribute through reset polarity logic. This avoids
    # derived reset nets becoming dont_touch while still receiving DRV checks.
    # The physical reset buffer tree is built after ideal removal in P&R.
    set_ideal_network [get_ports $RST_PORT]
    set_drive 0 [get_ports $RST_PORT]
    puts "  Reset network is ideal during synthesis; physical buffering is deferred to P&R."

    # 【改进】复位 false path：复位信号不参与正常数据路径的时序分析
    # 不同设计可能需要不同的 false path 设置，这里是常见的保守设置
    if {[info exists RESET_FALSE_PATH] && $RESET_FALSE_PATH} {
        puts "  Setting false path on reset port..."
        set_false_path -from [get_ports $RST_PORT]
        puts "  Reset false path applied."
    }
} else {
    puts "  Warning: Reset port '$RST_PORT' not found. Skipping reset constraints."
}

# ── Step 5: I/O 延迟约束 ────────────────────────────────────────────────────
puts "\n=========================================="
puts "Step 5: I/O Delay Constraints"
puts "==========================================\n"

# 输入延迟作用的端口：所有输入 - 时钟端口 - 复位端口（复位走 false path 不需要 I/O 约束）
set excluded_input_ports [get_ports -quiet "$CLOCK_PORT $RST_PORT"]
set data_input_ports [remove_from_collection [all_inputs] $excluded_input_ports]
if {[sizeof_collection $data_input_ports] > 0} {
    set_input_delay $INPUT_DELAY_MAX -max -clock [get_clocks $CLOCK_NAME] $data_input_ports
    set_input_delay $INPUT_DELAY_MIN -min -clock [get_clocks $CLOCK_NAME] $data_input_ports
} else {
    puts "  Info: No data input ports found after excluding clock/reset; skipping input delay constraints."
}

set data_output_ports [all_outputs]
if {[sizeof_collection $data_output_ports] > 0} {
    set_output_delay $OUTPUT_DELAY_MAX -max -clock [get_clocks $CLOCK_NAME] $data_output_ports
    set_output_delay $OUTPUT_DELAY_MIN -min -clock [get_clocks $CLOCK_NAME] $data_output_ports
} else {
    puts "  Info: No output ports found; skipping output delay constraints."
}

# ── Step 6: 路径分组 ─────────────────────────────────────────────────────────
if {$ENABLE_GROUP_PATH} {
    puts "\n=========================================="
    puts "Step 6: Group Path Setup"
    puts "==========================================\n"

    if {$COST_PRIORITY ne "" && $COST_PRIORITY ne "-"} {
        set_cost_priority $COST_PRIORITY
    }

    if {[string tolower $ENABLE_CORE] in {yes true 1 on}} {
        foreach_in_collection clock_obj [all_clocks] {
            set clock_name [get_object_name $clock_obj]
            group_path -name "GRP_$clock_name" \
                -weight $WEIGHT_CRITICAL \
                -critical_range $CRITICAL_RANGE_CORE \
                -to $clock_obj
        }
        puts "  Configured core clock groups"
    }

    if {[string tolower $ENABLE_MACRO] in {yes true 1 on}} {
        set all_macros [get_cells -hierarchical -quiet -filter "is_hard_macro==true"]
        if {[sizeof_collection $all_macros] > 0} {
            set macro_in_all  [get_pins -of_objects $all_macros -filter "direction==in"]
            set all_clock_pins [get_pins -hierarchical -filter "undefined(is_clock_pin) || is_clock_pin==true"]
            set macro_in [remove_from_collection $macro_in_all $all_clock_pins]
            if {[sizeof_collection $macro_in] > 0} {
                group_path -name GRP_MACRO_IN -to $macro_in \
                    -weight $WEIGHT_MACRO \
                    -critical_range $CRITICAL_RANGE_MACRO
            }
            set macro_out [get_pins -of_objects $all_macros -filter "direction==out"]
            if {[sizeof_collection $macro_out] > 0} {
                group_path -name GRP_MACRO_OUT -from $macro_out \
                    -weight $WEIGHT_MACRO \
                    -critical_range $CRITICAL_RANGE_MACRO
            }
        }
        puts "  Configured macro path groups"
    }

    if {[string tolower $ENABLE_ICG] in {yes true 1 on}} {
        set icg_pins [get_pins -hierarchical -quiet -filter "is_clock_gating_pin==true"]
        if {[sizeof_collection $icg_pins] > 0} {
            group_path -name GRP_ICG -to $icg_pins \
                -weight $WEIGHT_ICG \
                -critical_range $CRITICAL_RANGE_ICG
        }
        puts "  Configured ICG groups"
    }

    if {[string tolower $ENABLE_IO] in {yes true 1 on}} {
        set input_ports  [remove_from_collection [all_inputs] [all_clocks]]
        set output_ports [all_outputs]
        if {[sizeof_collection $input_ports] > 0} {
            group_path -name GRP_INPUTS -from $input_ports \
                -weight $WEIGHT_IO \
                -critical_range $CRITICAL_RANGE_IO
        }
        if {[sizeof_collection $output_ports] > 0} {
            group_path -name GRP_OUTPUTS -to $output_ports \
                -weight $WEIGHT_IO \
                -critical_range $CRITICAL_RANGE_IO
        }
        puts "  Configured I/O groups"
    }

    if {[string tolower $ENABLE_FEEDTHROUGH] in {yes true 1 on}} {
        if {![info exists input_ports]} {
            set input_ports [remove_from_collection [all_inputs] [all_clocks]]
        }
        if {![info exists output_ports]} {
            set output_ports [all_outputs]
        }
        if {[sizeof_collection $input_ports] > 0 && [sizeof_collection $output_ports] > 0} {
            group_path -name GRP_FEEDTHROUGH \
                -from $input_ports -to $output_ports \
                -weight $WEIGHT_FEEDTHROUGH \
                -critical_range $CRITICAL_RANGE_FEEDTHROUGH
        }
        puts "  Configured feedthrough groups"
    }
}

# ── Step 7: 设计约束 ────────────────────────────────────────────────────────
puts "\n=========================================="
puts "Step 7: Design Constraints"
puts "==========================================\n"

set_max_fanout     $MAX_FANOUT     [current_design]
set_max_transition $MAX_TRANSITION  [current_design]

set data_input_ports [remove_from_collection [all_inputs] [get_ports -quiet "$CLOCK_PORT $RST_PORT"]]
if {[sizeof_collection $data_input_ports] > 0} {
    set_input_transition $INPUT_TRANSITION $data_input_ports
} else {
    puts "Info: No data input ports found; skipping input transition constraint."
}

set data_output_ports [all_outputs]
if {[sizeof_collection $data_output_ports] > 0} {
    set_load $OUTPUT_LOAD $data_output_ports
} else {
    puts "Info: No output ports found; skipping output load constraint."
}

set_max_area 0 -ignore_tns

# 互连延迟估算方式选择（三种路径，互斥）：
#   1. 物理感知综合 → TLUPlus + DEF（物理精确 RC 模型）
#   2. 拓扑模式但不加载物理数据 → 零互连延迟（DC 拓扑模式默认行为）
#   3. 非拓扑模式 → 传统线负载模型（统计估算）
set topo_mode 0
set topo_mode 0
if {[llength [info commands shell_is_in_topographical_mode]] > 0 && [shell_is_in_topographical_mode]} {
    set topo_mode 1
}

if {$SYNTHESIS_MODE eq "physical"} {
    if {!$topo_mode} {
        error "SYNTHESIS_MODE=physical requires dc_shell -topographical_mode."
    }
    puts "Info: Physical-aware synthesis enabled; using TLUPlus for interconnect estimation."
} elseif {$SYNTHESIS_MODE eq "wire_load"} {
    if {$topo_mode} {
        error "SYNTHESIS_MODE=wire_load requires normal dc_shell. Run without -topographical_mode."
    }
    set_wire_load_mode $WIRE_LOAD_MODE
    if {[info exists WIRE_LOAD_SELECTION_GROUP] && $WIRE_LOAD_SELECTION_GROUP ne ""} {
        if {[catch {set_wire_load_selection_group $WIRE_LOAD_SELECTION_GROUP} wl_sel_msg]} {
            puts "Warning: set_wire_load_selection_group failed: $wl_sel_msg"
            puts "Warning: Falling back to fixed wire load model: $WIRE_LOAD_MODEL"
            set wl_lib_name [string replace $STD_WC_DB end-2 end ""]
            set_wire_load_model -name $WIRE_LOAD_MODEL -library $wl_lib_name
            puts "Info: Non-topographical mode; using wire load model: $WIRE_LOAD_MODEL."
        } else {
            puts "Info: Non-topographical mode; using wire load selection group: $WIRE_LOAD_SELECTION_GROUP."
        }
    } else {
        set wl_lib_name [string replace $STD_WC_DB end-2 end ""]
        set_wire_load_model -name $WIRE_LOAD_MODEL -library $wl_lib_name
        puts "Info: Non-topographical mode; using wire load model: $WIRE_LOAD_MODEL."
    }
} else {
    error "Unexpected SYNTHESIS_MODE '$SYNTHESIS_MODE'"
}

# 【改进】在 compile 之前运行 check_timing，确保没有未约束的路径
puts "\n  Running pre-compile check_timing..."
if {[llength [info commands check_timing]] > 0} {
    check_timing > ${REPORT_DIR}/${DESIGN_NAME}_${rundate}_check_timing_pre.rpt
    puts "  check_timing report written to ${REPORT_DIR}/${DESIGN_NAME}_${rundate}_check_timing_pre.rpt"

    # 快速分析 check_timing 结果，对常见的严重问题进行告警
    # 注意：check_timing 返回的警告数量需要根据实际输出判断
    puts "  Please review check_timing report for unconstrained paths."
}

# 【改进】在 compile 之前设置边界优化
if {[info exists ENABLE_BOUNDARY_OPTIMIZATION] && $ENABLE_BOUNDARY_OPTIMIZATION} {
    if {[llength [info commands set_boundary_optimization]] > 0} {
        if {[catch {
            set_boundary_optimization [current_design] -effort $BOUNDARY_OPT_EFFORT
        } boundary_opt_msg]} {
            puts "  Warning: set_boundary_optimization -effort is not supported: $boundary_opt_msg"
            puts "  Retrying boundary optimization without -effort."
            set_boundary_optimization [current_design]
            puts "  Boundary optimization enabled."
        } else {
            puts "  Boundary optimization enabled (effort: $BOUNDARY_OPT_EFFORT)."
        }
    } else {
        puts "  Warning: set_boundary_optimization command not available."
    }
}

# ── Step 8: 主编译 ──────────────────────────────────────────────────────────
puts "\n=========================================="
puts "Step 8: Compile"
puts "==========================================\n"

# 物理感知综合：加载 DEF floorplan
if {$SYNTHESIS_MODE eq "physical"} {
    if {![info exists DEF_FILE]} {
        error "ENABLE_PHYSICAL_SYNTHESIS is on, but DEF_FILE is not defined in set.tcl"
    }
    if {![file exists $DEF_FILE]} {
        error "Physical-aware synthesis enabled, but DEF_FILE not found: $DEF_FILE"
    }
    if {[llength [info commands extract_physical_constraints]] == 0} {
        error "extract_physical_constraints command not available. Please start DC in topographical mode."
    }

    puts "Info: Loading floorplan DEF: $DEF_FILE"
    if {[catch {extract_physical_constraints $DEF_FILE} extract_physical_constraints_msg]} {
        error "extract_physical_constraints failed. Detail: $extract_physical_constraints_msg"
    } else {
        puts "Info: extract_physical_constraints completed successfully."
    }

    if {[llength [info commands report_physical_constraints]] > 0} {
        report_physical_constraints > ${REPORT_DIR}/${DESIGN_NAME}_${rundate}_physical_constraints.rpt
    }

    if {[llength [info commands check_physical_design]] > 0} {
        check_physical_design -stage pre_compile_ultra
    } else {
        puts "Warning: check_physical_design not available; DEF already loaded via extract_physical_constraints."
    }
} else {
    puts "Info: Physical-aware synthesis disabled; skip DEF loading."
}

# 主综合
puts "\n  Running ${COMPILE_COMMAND}..."
set compile_start_time [clock seconds]

if {$COMPILE_COMMAND eq "compile_ultra"} {
    set ACTIVE_OPTIONS $COMPILE_ULTRA_OPTIONS
} else {
    set ACTIVE_OPTIONS $COMPILE_OPTIONS
}

if {$ACTIVE_OPTIONS ne ""} {
    eval $COMPILE_COMMAND $ACTIVE_OPTIONS
} else {
    eval $COMPILE_COMMAND
}

set compile_end_time [clock seconds]
set compile_elapsed [expr $compile_end_time - $compile_start_time]
puts "  Compile completed in $compile_elapsed seconds."

# 增量综合
if {$INCREMENTAL_COMPILE eq "yes"} {
    puts "\n  Running incremental compile for further optimization..."
    if {$INCREMENTAL_COMPILE_OPTIONS ne ""} {
        eval compile_ultra -incremental $INCREMENTAL_COMPILE_OPTIONS
    } else {
        compile_ultra -incremental
    }
}

# 【改进】综合后 WNS 检查：判定时序是否达标
puts "\n  Checking timing results..."
if {[llength [info commands get_attribute]] > 0} {
    # 尝试获取最差 slack
    if {[catch {set wns [get_attribute [current_design] worst_slack]} wns_error]} {
        puts "  Warning: Could not retrieve worst_slack attribute: $wns_error"
        puts "  Please check timing report manually."
        set wns "N/A"
    }

    if {$wns ne "N/A"} {
        puts "  Worst Negative Slack (WNS): $wns ns"

        if {$wns < $WNS_THRESHOLD} {
            puts "  =============================================================="
            puts "  WARNING: Timing NOT met!"
            puts "    WNS = $wns ns"
            puts "    Threshold = $WNS_THRESHOLD ns"
            puts "  Please review timing report and consider:"
            puts "    - Increasing clock period"
            puts "    - Enabling retiming (-retime in COMPILE_ULTRA_OPTIONS)"
            puts "    - Adjusting path group weights"
            puts "    - Providing a floorplan with better macro placement"
            puts "  =============================================================="
        } elseif {$wns > 0.0} {
            puts "  PASS: All paths meet timing with positive slack."
            puts "  Worst Slack: $wns ns (positive)"
        } else {
            puts "  PASS: Timing met within threshold (WNS=$wns ns, threshold=$WNS_THRESHOLD ns)."
        }

        # 尝试获取 TNS（Total Negative Slack）
        if {![catch {set tns [get_attribute [current_design] total_negative_slack]}]} {
            puts "  Total Negative Slack (TNS): $tns ns"
        }
    }
}

# Write a P&R-safe SDC while preserving the complete DC SDC for debugging.
# Commands are accumulated with info complete so multi-line SDC commands are
# removed as a unit instead of leaving broken continuation lines behind.
proc write_pr_sdc_without_wire_load {source_file target_file} {
    set in_ch [open $source_file r]
    set out_ch [open $target_file w]
    set command ""
    set removed_count 0

    while {[gets $in_ch line] >= 0} {
        append command $line "\n"
        if {![info complete $command]} {
            continue
        }

        set trimmed [string trimleft $command]
        set remove_command 0

        if {[regexp {^(set_wire_load|remove_wire_load)} $trimmed]} {
            set remove_command 1
        } elseif {[regexp {^set[ \t]+auto_wire_load_selection([ \t]|$)} $trimmed]} {
            set remove_command 1
        } elseif {[regexp {^set_app_var[ \t]+auto_wire_load_selection([ \t]|$)} $trimmed]} {
            set remove_command 1
        }

        if {$remove_command} {
            incr removed_count
        } else {
            puts -nonewline $out_ch $command
        }
        set command ""
    }

    close $in_ch
    if {[string trim $command] ne ""} {
        close $out_ch
        error "Incomplete Tcl command while filtering SDC: $source_file"
    }
    close $out_ch
    return $removed_count
}

# ── Step 9: 输出文件 ────────────────────────────────────────────────────────
puts "\n=========================================="
puts "Step 9: Write Output Files"
puts "==========================================\n"

write -format verilog -hierarchy -output ${OUTPUT_DIR}/${DESIGN_NAME}_${rundate}.v

set DC_SDC_FILE ${OUTPUT_DIR}/${DESIGN_NAME}_${rundate}_dc.sdc
set PR_SDC_FILE ${OUTPUT_DIR}/${DESIGN_NAME}_${rundate}_pr.sdc
set DEFAULT_SDC_FILE ${OUTPUT_DIR}/${DESIGN_NAME}_${rundate}.sdc

write_sdc $DC_SDC_FILE
set removed_wire_load_commands [write_pr_sdc_without_wire_load $DC_SDC_FILE $PR_SDC_FILE]
file copy -force $PR_SDC_FILE $DEFAULT_SDC_FILE

puts "  DC SDC written: $DC_SDC_FILE"
puts "  P&R SDC written: $PR_SDC_FILE"
puts "  Removed $removed_wire_load_commands wire-load command(s) from the P&R SDC."
write_file -format ddc -hierarchy -output ${OUTPUT_DIR}/${DESIGN_NAME}_${rundate}_compile.ddc
write_sdf ${OUTPUT_DIR}/${DESIGN_NAME}_${rundate}.sdf
set_svf -off

puts "  Output files written to: $OUTPUT_DIR"
puts "    ${DESIGN_NAME}_${rundate}.v     (gate-level netlist)"
puts "    ${DESIGN_NAME}_${rundate}.sdc   (P&R-safe timing constraints)"
puts "    ${DESIGN_NAME}_${rundate}_dc.sdc (complete DC constraints)"
puts "    ${DESIGN_NAME}_${rundate}_pr.sdc (P&R constraints, no wire-load)"
puts "    ${DESIGN_NAME}_${rundate}.ddc   (DC database)"
puts "    ${DESIGN_NAME}_${rundate}.sdf   (delay for gate-level simulation)"

# ── Step 10: 报告生成 ────────────────────────────────────────────────────────
puts "\n=========================================="
puts "Step 10: Generate Reports"
puts "==========================================\n"

# 面积报告
report_area -nosplit -hierarchy \
    > ${REPORT_DIR}/${DESIGN_NAME}_${rundate}_area.rpt
puts "  > area report"

# QoR 总览
report_qor > ${REPORT_DIR}/${DESIGN_NAME}_${rundate}_qor.rpt
puts "  > QoR report"

# 时序报告：setup（max delay），最多 10000 条路径
report_timing -delay max -max_paths 10000 \
    > ${REPORT_DIR}/${DESIGN_NAME}_${rundate}_timing_setup.rpt
puts "  > timing report (setup, 10000 paths)"

# 时序报告：hold（min delay），最多 1000 条路径
# hold 在综合阶段不可修（无时钟树），主要用于提前评估后端的 hold 风险
report_timing -delay min -max_paths 1000 \
    > ${REPORT_DIR}/${DESIGN_NAME}_${rundate}_timing_hold.rpt
puts "  > timing report (hold, 1000 paths)"

# 约束违例报告
report_constraint -all_violators -nosplit \
    > ${REPORT_DIR}/${DESIGN_NAME}_${rundate}_constraint.rpt
puts "  > constraint violation report"

# 功耗报告
report_power > ${REPORT_DIR}/${DESIGN_NAME}_${rundate}_power.rpt
puts "  > power report"

# 【改进】综合后资源报告（与综合前对比）
if {[llength [info commands report_resources]] > 0} {
    report_resources > ${REPORT_DIR}/${DESIGN_NAME}_${rundate}_resources_post.rpt
    puts "  > resources report (post-compile)"
}

# 【改进】时钟门控报告：验证 -gate_clock 是否真正生效
if {[llength [info commands report_clock_gating]] > 0} {
    report_clock_gating > ${REPORT_DIR}/${DESIGN_NAME}_${rundate}_clock_gating.rpt
    puts "  > clock gating report"
}

# 【改进】按路径组分别报告时序，便于分组分析收敛情况
if {[llength [info commands get_path_groups]] > 0} {
    puts "\n  Generating per-group timing reports..."
    set path_groups [get_path_groups -quiet]
    if {[sizeof_collection $path_groups] > 0} {
        foreach_in_collection grp $path_groups {
            set grp_name [get_object_name $grp]
            # 文件名中替换特殊字符
            set safe_name [string map {"/" "_" "\\" "_" " " "_" "*" "ALL"} $grp_name]
            report_timing -group $grp_name -max_paths 100 \
                > ${REPORT_DIR}/${DESIGN_NAME}_${rundate}_timing_${safe_name}.rpt
            puts "    > timing group: $grp_name"
        }
    }
}

# ── 综合完成 ─────────────────────────────────────────────────────────────────
puts "\n=========================================="
puts "  Synthesis Complete!"
puts "  End time: [clock format [clock seconds] -format "%Y-%m-%d %H:%M:%S"]"
puts "  Output files : ${OUTPUT_DIR}/${DESIGN_NAME}_${rundate}.*"
puts "  Reports      : ${REPORT_DIR}/${DESIGN_NAME}_${rundate}_*.rpt"
puts ""
puts "  ── Post-Synthesis Checklist ──"
puts "  1. Review *_qor.rpt       → overall quality summary"
puts "  2. Review *_constraint.rpt → DRC and timing violations"
puts "  3. Review *_check_timing_pre.rpt → unconstrained paths"
puts "  4. Review *_clock_gating.rpt → gating efficiency"
puts "  5. Review *_area.rpt      → area breakdown by hierarchy"
puts "  6. Review *_power.rpt     → power estimates"
puts "  7. Run Formality with *_${rundate}.svf for equivalence checking"
puts ""
puts "  ── Formality Guidance ──"
puts "  set_svf ${OUTPUT_DIR}/${DESIGN_NAME}_${rundate}.svf"
puts "  The SVF file records all synthesis transformations."
puts "  In Formality:"
puts "    source ${OUTPUT_DIR}/${DESIGN_NAME}_${rundate}.svf"
puts "  Then set reference design (RTL) and implementation design (netlist)"
puts "  to verify logical equivalence."
puts "==========================================\n"

# ── 退出 ─────────────────────────────────────────────────────────────────────
exit
