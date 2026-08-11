`timescale 1ns/1ps
//===========================================================================
// MODULE : imem_rom.v      PROJECT : Mini Spark SoC      LIB : gsclib045
// DESC   : Synthesisable instruction ROM.
//
//   The previous design used  reg [31:0] imem [0:255];  with $readmemh
//   inside an initial block. Genus ignores initial blocks, so imem had no
//   driver, the fetched instruction became a constant, and constant
//   propagation optimised the entire SoC away - 0 leaf cells.
//
//   This version encodes the firmware directly as a combinational case
//   statement, which is exactly how a real hard-coded boot ROM is built.
//   Genus maps it to a few hundred gates and the rest of the chip survives.
//
//   Word-addressed. Unused locations return NOP (32'h00000013 = ADDI x0,x0,0)
//===========================================================================
module imem_rom (
    input  wire [7:0]  addr,
    output reg  [31:0] data
);
    always @(*) begin
        case (addr)
            8'd0   : data = 32'h000102B7;
            8'd1   : data = 32'h00100313;
            8'd2   : data = 32'h1062A023;
            8'd3   : data = 32'h1062A223;
            8'd4   : data = 32'h1062A423;
            8'd5   : data = 32'h1062A623;
            8'd6   : data = 32'h00200313;
            8'd7   : data = 32'h00000393;
            8'd8   : data = 32'h1462A023;
            8'd9   : data = 32'h1472A223;
            8'd10  : data = 32'h1472A423;
            8'd11  : data = 32'h1472A623;
            8'd12  : data = 32'h1472A823;
            8'd13  : data = 32'h1462AA23;
            8'd14  : data = 32'h1472AC23;
            8'd15  : data = 32'h1472AE23;
            8'd16  : data = 32'h1672A023;
            8'd17  : data = 32'h1672A223;
            8'd18  : data = 32'h1662A423;
            8'd19  : data = 32'h1672A623;
            8'd20  : data = 32'h1672A823;
            8'd21  : data = 32'h1672AA23;
            8'd22  : data = 32'h1672AC23;
            8'd23  : data = 32'h1662AE23;
            8'd24  : data = 32'h00000513;
            8'd25  : data = 32'h04000313;
            8'd26  : data = 32'h00652423;
            8'd27  : data = 32'h05000313;
            8'd28  : data = 32'h00652623;
            8'd29  : data = 32'h06000313;
            8'd30  : data = 32'h00652823;
            8'd31  : data = 32'h00400313;
            8'd32  : data = 32'h00652A23;
            8'd33  : data = 32'h00100313;
            8'd34  : data = 32'h00652023;
            8'd35  : data = 32'h00452303;
            8'd36  : data = 32'h00237E13;
            8'd37  : data = 32'hFE0E0CE3;
            8'd38  : data = 32'h0000006F;
            default : data = 32'h00000013;  // NOP
        endcase
    end
endmodule


