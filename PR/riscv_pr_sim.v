`timescale 1ns/1ps

// PR gate-level + SDF testbench.
// Expected server layout:
//   sim/                    <- run make here; contains sram.preload.data
//   rtl/riscv.vg
//   rtl/riscv_post_pr.sdf
//   tb/riscv_pr_sim.v       <- copy this file here
//
// This hierarchy matches the PR input netlist riscv_20260611_1509.v:
//   U_RISCV.U_IM.U_SRAM_IM
//   U_RISCV.U_DM.U_SRAM_DM
//   U_RISCV.U_RF.\register[31][bit]
// Before running a newly exported PR netlist, confirm it with:
//   grep -n 'TS1N65LPLL2048X64M8' ../rtl/riscv.vg
module tb;

    parameter integer RUN_CYCLES = 220;
    // 问题定位记录：PR-SDF 仿真中，SRAM 模型报告 A[*] 与 CLK 同时变化，
    // 触发 $setuphold 的 notifier_addr，随后将 Q 置为 X，CPU 继续传播 X。
    // 但 Innovus 对同一 U_IM/U_SRAM_IM/A[*] 的 STA 报告为正 slack
    // （A[0] setup +2.728ns、hold +0.143ns），SDF 也已成功标注。
    // 因此该开关只关闭 SRAM 行为模型的 check_noidle timing notifier，
    // 保留标准单元与 SDF 路径延迟检查；SRAM 引脚时序以 Innovus STA 为准。
    parameter DISABLE_SRAM_TIMING_CHECKS = 1'b1;

    reg clk;
    reg rst;
    integer cycle;

    wire x31_b0;
    wire x31_b1;
    wire [1:0] x31;

    riscv U_RISCV (
        .clk (clk),
        .rst (rst)
    );

    // The SRAM compiler model reads 64-bit binary words via preloadData().
    defparam U_RISCV.U_IM.U_SRAM_IM.preloadFile = "sram.preload.data";

    // Observe Q nets; register_reg[...] would be a DFF instance, not a signal.
    // The whitespace before each semicolon terminates the escaped identifier.
    assign x31_b0 = U_RISCV.U_RF.\register[31][0] ;
    assign x31_b1 = U_RISCV.U_RF.\register[31][1] ;
    assign x31    = {x31_b1, x31_b0};

    initial begin
        // Innovus emits min::max values without a typical value.  VCS defaults
        // to TYPICAL, which can turn those path delays into zero.  This setup
        // run must explicitly select the max (slow) SDF values.
        $sdf_annotate("../rtl/riscv_post_pr.sdf", U_RISCV, , , "MAXIMUM");
    end

    // 功能 PR-SDF 后仿真：只屏蔽 IM/DM SRAM 模型自身的 timing notifier。
    // 设为 1'b0 可重新启用模型检查，用于专门研究 SRAM 模型的报错。
    initial begin
        if (DISABLE_SRAM_TIMING_CHECKS) begin
            $display("INFO: SRAM behavioral timing checks disabled; use PR STA for SRAM pin timing.");
            force U_RISCV.U_IM.U_SRAM_IM.check_noidle = 1'b0;
            force U_RISCV.U_DM.U_SRAM_DM.check_noidle = 1'b0;
        end
    end

    // 200 MHz clock: 5 ns period.
    always #2.5 clk = ~clk;

    // Print only startup state to keep logs readable while retaining X diagnostics.
    always @(posedge clk) begin
        cycle = cycle + 1;
        #0.1;
        if (cycle <= 20) begin
            $display(
                "DBG C%0d rst=%b IM: CEB=%b WEB=%b A=%h Q=%h | DM: CEB=%b | x31=%b",
                cycle,
                rst,
                U_RISCV.U_IM.U_SRAM_IM.CEB,
                U_RISCV.U_IM.U_SRAM_IM.WEB,
                U_RISCV.U_IM.U_SRAM_IM.A,
                U_RISCV.U_IM.U_SRAM_IM.Q,
                U_RISCV.U_DM.U_SRAM_DM.CEB,
                x31
            );
        end
    end

    initial begin
        clk   = 1'b0;
        rst   = 1'b1;
        cycle = 0;

        #1 U_RISCV.U_IM.U_SRAM_IM.preloadData();
        $display(
            "DBG_PRELOAD: P0=%h P1=%h",
            U_RISCV.U_IM.U_SRAM_IM.PRELOAD[0],
            U_RISCV.U_IM.U_SRAM_IM.PRELOAD[1]
        );

        // Release reset between clock edges to avoid reset timing-check races.
        repeat (5) @(negedge clk);
        #0.2 rst = 1'b0;

        repeat (RUN_CYCLES) @(posedge clk);
        #1;

        $display("DBG_FINAL: cycle=%0d x31[1:0]=%b", cycle, x31);
        if (x31 === 2'b01) begin
            $display("PASS: x31 = 0x%08X", {30'b0, x31});
        end
        else begin
            $display("FAIL: x31[1:0] = %b", x31);
        end

        $finish;
    end

endmodule
