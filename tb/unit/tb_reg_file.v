`timescale 1ns/1ps
module tb_reg_file;
    reg clk = 0, rst = 1;
    reg [4:0] rs1, rs2, rd;
    reg [31:0] wd;
    reg we;
    wire [31:0] rd1, rd2;
    integer fails = 0;
    integer i;

    always #5 clk = ~clk;

    reg_file dut (.clk(clk), .rst(rst), .rs1(rs1), .rs2(rs2),
                  .rd(rd), .wd(wd), .we(we), .rd1(rd1), .rd2(rd2));

    task wr;
        input [4:0] r;
        input [31:0] d;
        begin
            @(negedge clk); rd = r; wd = d; we = 1;
            @(posedge clk); #1; we = 0;
        end
    endtask

    initial begin
        $display("===== REG FILE TESTBENCH =====");
        we=0; rs1=0; rs2=0; rd=0; wd=0;
        repeat(2) @(posedge clk);
        rst = 0;
        @(negedge clk);

        wr(5'd1, 32'd42);
        @(negedge clk); rs1 = 5'd1; #1;
        if (rd1 !== 32'd42) begin $display("FAIL t1: x1=%0d exp 42", rd1); fails=fails+1; end
        else $display("PASS t1: x1 = %0d", rd1);

        wr(5'd2, 32'd100);
        @(negedge clk); rs1 = 5'd2; #1;
        if (rd1 !== 32'd100) begin $display("FAIL t2: x2=%0d exp 100", rd1); fails=fails+1; end
        else $display("PASS t2: x2 = %0d", rd1);

        wr(5'd0, 32'hDEADBEEF);
        @(negedge clk); rs1 = 5'd0; #1;
        if (rd1 !== 32'd0) begin $display("FAIL t3: x0=%0h exp 0", rd1); fails=fails+1; end
        else $display("PASS t3: x0 stays 0");

        @(negedge clk); rs1 = 5'd1; rs2 = 5'd2; #1;
        if (rd1 !== 32'd42 || rd2 !== 32'd100) begin
            $display("FAIL t4: dual read x1=%0d x2=%0d", rd1, rd2); fails=fails+1;
        end else $display("PASS t4: dual port read OK");

        for (i = 1; i < 32; i = i + 1) wr(i[4:0], i*10);
        for (i = 1; i < 32; i = i + 1) begin
            @(negedge clk); rs1 = i[4:0]; #1;
            if (rd1 !== i*10) begin
                $display("FAIL t5: x%0d=%0d exp %0d", i, rd1, i*10); fails=fails+1;
            end
        end
        if (fails == 0) $display("PASS t5: all 31 registers verified");

        @(negedge clk); rd = 5'd7; wd = 32'd999; we = 1; rs1 = 5'd7; #1;
        if (rd1 !== 32'd999) begin
            $display("FAIL t6: forwarding rd1=%0d exp 999", rd1); fails=fails+1;
        end else $display("PASS t6: write forwarding works");
        @(posedge clk); we = 0;

        $display("===== REGFILE: %0d failures =====", fails);
        if (fails == 0) $display("REG FILE FUNCTIONALLY VERIFIED");
        $finish;
    end
endmodule
