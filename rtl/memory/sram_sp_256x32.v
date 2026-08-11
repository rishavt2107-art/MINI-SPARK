`timescale 1ns/1ps
//=============================================================================
// MODULE : sram_sp_256x32.v  PROJECT : Mini Spark SoC     PDK : GPDK045nm
// DESC   : 256-word x 32-bit single-port synchronous SRAM. 1-cycle read.
// NOTE   : Behavioural model. Synthesises to flip-flops in Genus, which is
//          acceptable for Phase 1 area/timing estimation. For real silicon,
//          replace with a GPDK045 SRAM compiler macro and treat as a black
//          box in synthesis (read_lef + set_dont_touch).
//=============================================================================
module sram_sp_256x32 (
    input  wire        clk,
    input  wire [7:0]  addr,
    input  wire [31:0] wdata,
    input  wire        we,
    input  wire        re,
    output reg  [31:0] rdata
);
    reg [31:0] mem [0:255];
    integer i;

    initial begin
        for (i = 0; i < 256; i = i + 1)
            mem[i] = 32'd0;
        rdata = 32'd0;
    end

    always @(posedge clk) begin
        if (we) mem[addr] <= wdata;
        if (re) rdata     <= mem[addr];
    end
endmodule
