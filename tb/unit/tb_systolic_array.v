`timescale 1ns/1ps
//=============================================================================
// TB : tb_systolic_array.v   Weight-stationary 4x4 array
//
//  Protocol:
//    1. Assert load_w for 4 cycles, pushing W[3][c], W[2][c], W[1][c], W[0][c]
//       into column c from the north edge (last pushed lands in row 0).
//    2. Deassert load_w, assert en, drive activations a0..a3, run 2N-1 cycles.
//    3. out_c = sum over r of ( a_r * W[r][c] )
//=============================================================================
module tb_systolic_array;
    reg clk = 0, rst = 1, en = 0, load_w = 0;
    reg  [7:0] a0,a1,a2,a3, w0,w1,w2,w3;
    wire [31:0] out0,out1,out2,out3;
    integer fails = 0;

    always #5 clk = ~clk;

    systolic_array dut (.clk(clk),.rst(rst),.en(en),.load_w(load_w),
        .a0(a0),.a1(a1),.a2(a2),.a3(a3),
        .w0(w0),.w1(w1),.w2(w2),.w3(w3),
        .out0(out0),.out1(out1),.out2(out2),.out3(out3));

    // Load a 4x4 weight matrix. wm[r][c] ends up in pe[r][c].
    // Push order: row 3 first, row 0 last.
    task load_weights;
        input [7:0] m30,m31,m32,m33;
        input [7:0] m20,m21,m22,m23;
        input [7:0] m10,m11,m12,m13;
        input [7:0] m00,m01,m02,m03;
        begin
            @(negedge clk); load_w = 1;
            w0=m30; w1=m31; w2=m32; w3=m33; @(posedge clk);
            @(negedge clk);
            w0=m20; w1=m21; w2=m22; w3=m23; @(posedge clk);
            @(negedge clk);
            w0=m10; w1=m11; w2=m12; w3=m13; @(posedge clk);
            @(negedge clk);
            w0=m00; w1=m01; w2=m02; w3=m03; @(posedge clk);
            @(negedge clk); load_w = 0;
        end
    endtask

    task compute;
        input [7:0] v0,v1,v2,v3;
        begin
            a0=v0; a1=v1; a2=v2; a3=v3;
            @(negedge clk); en = 1;
            repeat(1) @(posedge clk);      // 1 cycle - combinational MAC chain
            @(negedge clk); en = 0;
            repeat(2) @(posedge clk); #1;
        end
    endtask

    task do_reset;
        begin
            rst = 1; en = 0; load_w = 0;
            repeat(2) @(posedge clk);
            @(negedge clk); rst = 0;
        end
    endtask

    task chk;
        input [31:0] e0,e1,e2,e3;
        input integer tid;
        begin
            if (out0!==e0 || out1!==e1 || out2!==e2 || out3!==e3) begin
                $display("FAIL t%0d: got [%0d,%0d,%0d,%0d] exp [%0d,%0d,%0d,%0d]",
                    tid, $signed(out0),$signed(out1),$signed(out2),$signed(out3),
                    $signed(e0),$signed(e1),$signed(e2),$signed(e3));
                fails = fails + 1;
            end else
                $display("PASS t%0d: out = [%0d,%0d,%0d,%0d]",
                    tid, $signed(out0),$signed(out1),$signed(out2),$signed(out3));
        end
    endtask

    initial begin
        $display("===== SYSTOLIC ARRAY TESTBENCH (weight-stationary) =====");
        a0=0;a1=0;a2=0;a3=0; w0=0;w1=0;w2=0;w3=0;

        // T1: W = Identity, x = [1,2,3,4]  ->  y = [1,2,3,4]
        do_reset;
        load_weights(8'd0,8'd0,8'd0,8'd1,
                     8'd0,8'd0,8'd1,8'd0,
                     8'd0,8'd1,8'd0,8'd0,
                     8'd1,8'd0,8'd0,8'd0);
        compute(8'd1,8'd2,8'd3,8'd4);
        chk(32'd1, 32'd2, 32'd3, 32'd4, 1);

        // T2: W = 2*Identity, x = [1,1,1,1]  ->  y = [2,2,2,2]
        do_reset;
        load_weights(8'd0,8'd0,8'd0,8'd2,
                     8'd0,8'd0,8'd2,8'd0,
                     8'd0,8'd2,8'd0,8'd0,
                     8'd2,8'd0,8'd0,8'd0);
        compute(8'd1,8'd1,8'd1,8'd1);
        chk(32'd2, 32'd2, 32'd2, 32'd2, 2);

        // T3: W all ones, x = [1,2,3,4]  ->  y = [10,10,10,10]
        do_reset;
        load_weights(8'd1,8'd1,8'd1,8'd1,
                     8'd1,8'd1,8'd1,8'd1,
                     8'd1,8'd1,8'd1,8'd1,
                     8'd1,8'd1,8'd1,8'd1);
        compute(8'd1,8'd2,8'd3,8'd4);
        chk(32'd10, 32'd10, 32'd10, 32'd10, 3);

        // T4: negative weights, W = -1*Identity, x = [1,2,3,4] -> y = [-1,-2,-3,-4]
        do_reset;
        load_weights(8'd0,8'd0,8'd0,8'hFF,
                     8'd0,8'd0,8'hFF,8'd0,
                     8'd0,8'hFF,8'd0,8'd0,
                     8'hFF,8'd0,8'd0,8'd0);
        compute(8'd1,8'd2,8'd3,8'd4);
        chk(-32'd1, -32'd2, -32'd3, -32'd4, 4);

        // T5: general matrix
        //   W = [[1,2,3,4],[5,6,7,8],[1,1,1,1],[2,2,2,2]]  x = [1,1,1,1]
        //   y_c = W[0][c]+W[1][c]+W[2][c]+W[3][c] = [9,11,13,15]
        do_reset;
        load_weights(8'd2,8'd2,8'd2,8'd2,
                     8'd1,8'd1,8'd1,8'd1,
                     8'd5,8'd6,8'd7,8'd8,
                     8'd1,8'd2,8'd3,8'd4);
        compute(8'd1,8'd1,8'd1,8'd1);
        chk(32'd9, 32'd11, 32'd13, 32'd15, 5);

        $display("===== SYSTOLIC ARRAY: %0d failures =====", fails);
        if (fails == 0) $display("SYSTOLIC ARRAY FUNCTIONALLY VERIFIED");
        else            $display("SYSTOLIC ARRAY HAS FAILURES");
        $finish;
    end
endmodule
