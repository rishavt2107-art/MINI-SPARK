`timescale 1ns/1ps
//=============================================================================
// TB : tb_soc_top.v   Full SoC integration test
//
//  The firmware writes an activation vector and a weight matrix into the
//  shared SRAM, programs the accelerator, starts it, then polls the status
//  register until the done bit is set.
//
//  Test data
//    a = [1, 1, 1, 1]
//    W = 2 * Identity
//    Expected y[c] = SUM over r of a[r]*W[r][c] = [2, 2, 2, 2]
//=============================================================================
module tb_soc_top;
    reg  clk = 0;
    reg  rst = 1;
    wire done_irq;
    integer i;
    integer fails = 0;
    reg [31:0] res;

    always #5 clk = ~clk;

    soc_top dut (.clk(clk), .rst(rst), .done_irq(done_irq));

    initial begin
        $dumpfile("sim_out/soc_top.vcd");
        $dumpvars(0, tb_soc_top);
    end

    initial begin
        $display("========================================");
        $display(" MINI SPARK SOC - INTEGRATION TESTBENCH");
        $display("========================================");
        repeat(4) @(posedge clk);
        rst = 0;
        $display("[%0t] Reset released, CPU running firmware", $time);

        fork
            begin
                wait (done_irq === 1'b1);
                repeat(4) @(posedge clk);
                $display("[%0t] DONE_IRQ asserted - GEMV complete", $time);

                $display("---- SRAM output region (word 0x60) ----");
                for (i = 0; i < 4; i = i + 1) begin
                    res = dut.u_sram.mem[8'h60 + i[7:0]];
                    $display("   y[%0d] = %0d", i, $signed(res));
                    if (res !== 32'd2) fails = fails + 1;
                end

                if (fails == 0) begin
                    $display("========================================");
                    $display(" RESULT: y = [2,2,2,2]  CORRECT");
                    $display(" SIMULATION PASSED");
                    $display("========================================");
                end else begin
                    $display(" SIMULATION FAILED - %0d wrong words", fails);
                end
                $finish;
            end
            begin
                #2000000;
                $display("[%0t] TIMEOUT - done_irq never asserted", $time);
                $display("  CPU pc    = %h", dut.u_cpu.pc);
                $display("  accel fsm = %0d", dut.u_accel.fsm);
                $display("  status    = %h", dut.u_accel.stat_r);
                $display(" SIMULATION FAILED");
                $finish;
            end
        join
    end
endmodule
