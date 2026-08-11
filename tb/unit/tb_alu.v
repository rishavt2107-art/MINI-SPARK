`timescale 1ns/1ps
module tb_alu;
    reg  [31:0] a, b;
    reg  [3:0]  op;
    wire [31:0] result;
    wire        zero;
    integer fails = 0;
    integer tid = 0;

    alu dut (.a(a), .b(b), .alu_op(op), .result(result), .zero(zero));

    task chk;
        input [31:0] exp;
        input        exp_z;
        begin
            #1;
            tid = tid + 1;
            if (result !== exp) begin
                $display("FAIL t%0d: op=%b a=%0d b=%0d got=%0d exp=%0d",
                         tid, op, $signed(a), $signed(b), $signed(result), $signed(exp));
                fails = fails + 1;
            end else if (zero !== exp_z) begin
                $display("FAIL t%0d: zero got=%b exp=%b", tid, zero, exp_z);
                fails = fails + 1;
            end else begin
                $display("PASS t%0d: op=%b -> %0d (z=%b)", tid, op, $signed(result), zero);
            end
        end
    endtask

    initial begin
        $display("===== ALU TESTBENCH =====");
        a=32'd5;  b=32'd3;  op=4'b0000; chk(32'd8, 1'b0);
        a=32'd0;  b=32'd0;  op=4'b0000; chk(32'd0, 1'b1);
        a=32'd10; b=32'd4;  op=4'b0001; chk(32'd6, 1'b0);
        a=32'd7;  b=32'd7;  op=4'b0001; chk(32'd0, 1'b1);
        a=32'hF0; b=32'hFF; op=4'b0010; chk(32'hF0, 1'b0);
        a=32'hF0; b=32'h0F; op=4'b0011; chk(32'hFF, 1'b0);
        a=32'hFF; b=32'hFF; op=4'b0100; chk(32'd0, 1'b1);
        a=32'd1;  b=32'd4;  op=4'b0101; chk(32'd16, 1'b0);
        a=32'd16; b=32'd2;  op=4'b0110; chk(32'd4, 1'b0);
        a=-32'd8; b=32'd1;  op=4'b0111; chk(-32'd4, 1'b0);
        a=-32'd1; b=32'd1;  op=4'b1000; chk(32'd1, 1'b0);
        a=32'd5;  b=32'd3;  op=4'b1000; chk(32'd0, 1'b1);
        a=32'hFFFFFFFF; b=32'd1; op=4'b1001; chk(32'd0, 1'b1);
        a=32'd0; b=32'hDEAD0000; op=4'b1010; chk(32'hDEAD0000, 1'b0);

        $display("===== ALU: %0d tests, %0d failures =====", tid, fails);
        if (fails == 0) $display("ALU FUNCTIONALLY VERIFIED");
        else            $display("ALU HAS FAILURES");
        $finish;
    end
endmodule
