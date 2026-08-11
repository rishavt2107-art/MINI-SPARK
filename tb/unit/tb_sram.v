`timescale 1ns/1ps
module tb_sram;
    reg clk = 0;
    reg [7:0]  addr;
    reg [31:0] wdata;
    reg        we, re;
    wire [31:0] rdata;
    integer fails = 0;
    integer i;

    always #5 clk = ~clk;

    sram_sp_256x32 dut (.clk(clk), .addr(addr), .wdata(wdata),
                        .we(we), .re(re), .rdata(rdata));

    task wr;
        input [7:0] a;
        input [31:0] d;
        begin
            @(negedge clk); addr=a; wdata=d; we=1; re=0;
            @(posedge clk); #1; we=0;
        end
    endtask

    task rdchk;
        input [7:0] a;
        input [31:0] exp;
        input integer tid;
        begin
            @(negedge clk); addr=a; re=1; we=0;
            @(posedge clk); #1; re=0;
            if (rdata !== exp) begin
                $display("FAIL t%0d: mem[%0d] got %h exp %h", tid, a, rdata, exp);
                fails = fails + 1;
            end else $display("PASS t%0d: mem[%0d] = %h", tid, a, rdata);
        end
    endtask

    initial begin
        $display("===== SRAM TESTBENCH =====");
        we=0; re=0; addr=0; wdata=0;
        @(posedge clk);

        wr(8'd0, 32'hDEADBEEF);   rdchk(8'd0,   32'hDEADBEEF, 1);
        wr(8'd1, 32'hCAFEBABE);   rdchk(8'd1,   32'hCAFEBABE, 2);
        wr(8'd10, 32'h12345678);  rdchk(8'd10,  32'h12345678, 3);
        wr(8'd255, 32'hFFFFFFFF); rdchk(8'd255, 32'hFFFFFFFF, 4);
        wr(8'd0, 32'h00000001);   rdchk(8'd0,   32'h00000001, 5);

        for (i = 0; i < 256; i = i + 1) wr(i[7:0], i*4);
        for (i = 0; i < 256; i = i + 1) begin
            @(negedge clk); addr=i[7:0]; re=1; we=0;
            @(posedge clk); #1; re=0;
            if (rdata !== i*4) begin
                $display("FAIL t6: mem[%0d]=%0d exp %0d", i, rdata, i*4);
                fails = fails + 1;
            end
        end
        $display("PASS t6: all 256 locations verified");

        $display("===== SRAM: %0d failures =====", fails);
        if (fails == 0) $display("SRAM FUNCTIONALLY VERIFIED");
        $finish;
    end
endmodule
