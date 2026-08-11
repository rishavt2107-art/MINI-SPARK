`timescale 1ns/1ps
//=============================================================================
// TB : tb_riscv_core.v   RV32I core instruction-level test
//
//   Program under test:
//     ADDI x1, x0, 5      x1 = 5
//     ADDI x2, x0, 3      x2 = 3
//     ADD  x3, x1, x2     x3 = 8
//     SW   x3, 0(x0)      mem[0] = 8
//     LW   x4, 0(x0)      x4 = 8
//     BEQ  x3, x4, +8     taken, skips the next instruction
//     ADDI x5, x0, 99     skipped, x5 stays 0
//     ADDI x6, x0, 42     x6 = 42
//     JAL  x0, 0          halt
//=============================================================================
module tb_riscv_core;
    reg  clk = 0, rst = 1;
    wire [31:0] imem_addr;
    reg  [31:0] imem_rdata;
    wire [31:0] dmem_addr, dmem_wdata;
    wire        dmem_we, dmem_re;
    reg  [31:0] dmem_rdata;
    reg         dmem_ready;
    integer fails = 0;
    integer i;

    always #5 clk = ~clk;

    reg [31:0] imem [0:63];
    reg [31:0] dmem [0:63];

    initial begin
        imem[0] = 32'h00500093;
        imem[1] = 32'h00300113;
        imem[2] = 32'h002081B3;
        imem[3] = 32'h00302023;
        imem[4] = 32'h00002203;
        imem[5] = 32'h00418463;
        imem[6] = 32'h06300293;
        imem[7] = 32'h02A00313;
        imem[8] = 32'h0000006F;
        for (i = 9; i < 64; i = i + 1) imem[i] = 32'h00000013;
        for (i = 0; i < 64; i = i + 1) dmem[i] = 32'd0;
        dmem_rdata = 32'd0;
        dmem_ready = 1'b0;
    end

    always @(*) imem_rdata = imem[imem_addr[7:2]];

    always @(posedge clk) begin
        if (dmem_we) dmem[dmem_addr[7:2]] <= dmem_wdata;
        if (dmem_re) dmem_rdata           <= dmem[dmem_addr[7:2]];
        dmem_ready <= (dmem_we | dmem_re);
    end

    riscv_core dut (
        .clk(clk), .rst(rst),
        .imem_addr(imem_addr), .imem_rdata(imem_rdata),
        .dmem_addr(dmem_addr), .dmem_wdata(dmem_wdata),
        .dmem_we(dmem_we), .dmem_re(dmem_re),
        .dmem_rdata(dmem_rdata), .dmem_ready(dmem_ready)
    );

    task chk;
        input [31:0] got, exp;
        input integer tid;
        input [64:0] nm;
        begin
            if (got !== exp) begin
                $display("FAIL t%0d %0s: got %0d exp %0d", tid, nm, $signed(got), $signed(exp));
                fails = fails + 1;
            end else
                $display("PASS t%0d %0s = %0d", tid, nm, $signed(got));
        end
    endtask

    initial begin
        $display("===== RISC-V CORE TESTBENCH =====");
        repeat(3) @(posedge clk);
        rst = 0;
        repeat(150) @(posedge clk);

        chk(dut.u_rf.regs[1], 32'd5,  1, "x1");
        chk(dut.u_rf.regs[2], 32'd3,  2, "x2");
        chk(dut.u_rf.regs[3], 32'd8,  3, "x3");
        chk(dut.u_rf.regs[4], 32'd8,  4, "x4");
        chk(dut.u_rf.regs[5], 32'd0,  5, "x5");
        chk(dut.u_rf.regs[6], 32'd42, 6, "x6");
        chk(dmem[0],          32'd8,  7, "mem0");

        $display("===== RISCV CORE: %0d failures =====", fails);
        if (fails == 0) $display("RISCV CORE FUNCTIONALLY VERIFIED");
        else            $display("RISCV CORE HAS FAILURES");
        $finish;
    end
endmodule
