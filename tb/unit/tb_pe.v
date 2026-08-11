`timescale 1ns/1ps
//=============================================================================
// TB : tb_pe.v   Weight-stationary MAC cell
//   Verifies weight loading, the shift-down path, and signed INT8 MAC.
//=============================================================================
module tb_pe;
    reg clk = 0, rst = 1, load_w = 0;
    reg  [7:0]  a_in, w_in;
    reg  [31:0] acc_in;
    wire [7:0]  w_out;
    wire [31:0] acc_out;
    integer fails = 0;
    integer tid = 0;

    always #5 clk = ~clk;

    pe dut (.clk(clk), .rst(rst), .load_w(load_w),
            .a_in(a_in), .w_in(w_in), .acc_in(acc_in),
            .w_out(w_out), .acc_out(acc_out));

    task load;
        input [7:0] wv;
        begin
            @(negedge clk); load_w = 1; w_in = wv;
            @(posedge clk);
            @(negedge clk); load_w = 0;
        end
    endtask

    task chk;
        input [31:0] exp;
        begin
            #1;
            tid = tid + 1;
            if (acc_out !== exp) begin
                $display("FAIL t%0d: a=%0d w=%0d acc_in=%0d -> got %0d exp %0d",
                    tid, $signed(a_in), $signed(dut.w_reg), $signed(acc_in),
                    $signed(acc_out), $signed(exp));
                fails = fails + 1;
            end else
                $display("PASS t%0d: acc_out = %0d", tid, $signed(acc_out));
        end
    endtask

    initial begin
        $display("===== PE TESTBENCH (weight-stationary MAC) =====");
        a_in = 0; w_in = 0; acc_in = 0;
        repeat(2) @(posedge clk);
        @(negedge clk); rst = 0;

        // 3 * 2 = 6
        load(8'd3);  a_in = 8'd2;  acc_in = 32'd0;  chk(32'd6);
        // accumulate with incoming partial sum
        acc_in = 32'd10;                            chk(32'd16);
        // negative weight: -1 * 5 = -5
        load(8'hFF); a_in = 8'd5;  acc_in = 32'd0;  chk(-32'd5);
        // negative x negative: -3 * -4 = 12
        load(8'hFC); a_in = 8'hFD; acc_in = 32'd0;  chk(32'd12);
        // max positive: 127 * 127 = 16129
        load(8'd127); a_in = 8'd127; acc_in = 32'd0; chk(32'd16129);
        // min negative: -128 * -128 = 16384
        load(8'h80); a_in = 8'h80; acc_in = 32'd0;  chk(32'd16384);
        // zero weight gives zero product
        load(8'd0);  a_in = 8'd99; acc_in = 32'd7;  chk(32'd7);

        // weight shift-down path exposes the held weight
        load(8'd55);
        #1;
        tid = tid + 1;
        if (w_out !== 8'd55) begin
            $display("FAIL t%0d: w_out=%0d exp 55", tid, w_out);
            fails = fails + 1;
        end else $display("PASS t%0d: w_out shift path = %0d", tid, w_out);

        $display("===== PE: %0d tests, %0d failures =====", tid, fails);
        if (fails == 0) $display("PE FUNCTIONALLY VERIFIED");
        else            $display("PE HAS FAILURES");
        $finish;
    end
endmodule
