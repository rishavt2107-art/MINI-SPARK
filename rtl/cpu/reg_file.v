`timescale 1ns/1ps
//=============================================================================
// MODULE : reg_file.v     PROJECT : Mini Spark SoC        PDK : GPDK045nm
// DESC   : 32 x 32-bit register file. x0 hardwired to zero.
//          Write-first forwarding resolves WB->ID same-cycle hazard.
//=============================================================================
module reg_file (
    input  wire        clk,
    input  wire        rst,
    input  wire [4:0]  rs1,
    input  wire [4:0]  rs2,
    input  wire [4:0]  rd,
    input  wire [31:0] wd,
    input  wire        we,
    output wire [31:0] rd1,
    output wire [31:0] rd2
);
    reg [31:0] regs [0:31];
    integer i;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            for (i = 0; i < 32; i = i + 1)
                regs[i] <= 32'd0;
        end else if (we && (rd != 5'd0)) begin
            regs[rd] <= wd;
        end
    end

    assign rd1 = (rs1 == 5'd0) ? 32'd0 :
                 ((we && (rd == rs1) && (rd != 5'd0)) ? wd : regs[rs1]);
    assign rd2 = (rs2 == 5'd0) ? 32'd0 :
                 ((we && (rd == rs2) && (rd != 5'd0)) ? wd : regs[rs2]);
endmodule
