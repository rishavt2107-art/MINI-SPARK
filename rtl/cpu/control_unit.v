`timescale 1ns/1ps
//=============================================================================
// MODULE : control_unit.v PROJECT : Mini Spark SoC        PDK : GPDK045nm
// DESC   : RV32I instruction decoder. Fully combinational.
//          All outputs assigned defaults first - no latches inferred.
//=============================================================================
module control_unit (
    input  wire [6:0] opcode,
    input  wire [2:0] funct3,
    input  wire [6:0] funct7,
    output reg        reg_write,
    output reg        mem_read,
    output reg        mem_write,
    output reg        branch,
    output reg        jump,
    output reg        jalr,
    output reg [1:0]  wb_sel,
    output reg        alu_src,
    output reg [3:0]  alu_op
);
    always @(*) begin
        reg_write = 1'b0;
        mem_read  = 1'b0;
        mem_write = 1'b0;
        branch    = 1'b0;
        jump      = 1'b0;
        jalr      = 1'b0;
        wb_sel    = 2'b00;
        alu_src   = 1'b0;
        alu_op    = 4'b0000;

        case (opcode)
        7'b0110011: begin
            reg_write = 1'b1;
            case ({funct7[5], funct3})
                4'b0000: alu_op = 4'b0000;
                4'b1000: alu_op = 4'b0001;
                4'b0111: alu_op = 4'b0010;
                4'b0110: alu_op = 4'b0011;
                4'b0100: alu_op = 4'b0100;
                4'b0001: alu_op = 4'b0101;
                4'b0101: alu_op = 4'b0110;
                4'b1101: alu_op = 4'b0111;
                4'b0010: alu_op = 4'b1000;
                4'b0011: alu_op = 4'b1001;
                default: alu_op = 4'b0000;
            endcase
        end
        7'b0010011: begin
            reg_write = 1'b1;
            alu_src   = 1'b1;
            case (funct3)
                3'b000:  alu_op = 4'b0000;
                3'b111:  alu_op = 4'b0010;
                3'b110:  alu_op = 4'b0011;
                3'b100:  alu_op = 4'b0100;
                3'b001:  alu_op = 4'b0101;
                3'b101:  alu_op = funct7[5] ? 4'b0111 : 4'b0110;
                3'b010:  alu_op = 4'b1000;
                3'b011:  alu_op = 4'b1001;
                default: alu_op = 4'b0000;
            endcase
        end
        7'b0000011: begin
            reg_write = 1'b1;
            mem_read  = 1'b1;
            alu_src   = 1'b1;
            wb_sel    = 2'b01;
            alu_op    = 4'b0000;
        end
        7'b0100011: begin
            mem_write = 1'b1;
            alu_src   = 1'b1;
            alu_op    = 4'b0000;
        end
        7'b1100011: begin
            branch = 1'b1;
            case (funct3)
                3'b000:  alu_op = 4'b0001;
                3'b001:  alu_op = 4'b0001;
                3'b100:  alu_op = 4'b1000;
                3'b101:  alu_op = 4'b1000;
                3'b110:  alu_op = 4'b1001;
                3'b111:  alu_op = 4'b1001;
                default: alu_op = 4'b0001;
            endcase
        end
        7'b1101111: begin
            jump      = 1'b1;
            reg_write = 1'b1;
            wb_sel    = 2'b10;
        end
        7'b1100111: begin
            jalr      = 1'b1;
            reg_write = 1'b1;
            alu_src   = 1'b1;
            alu_op    = 4'b0000;
            wb_sel    = 2'b10;
        end
        7'b0110111: begin
            reg_write = 1'b1;
            alu_src   = 1'b1;
            alu_op    = 4'b1010;
            wb_sel    = 2'b00;
        end
        7'b0010111: begin
            reg_write = 1'b1;
            alu_src   = 1'b1;
            wb_sel    = 2'b11;
        end
        default: ;
        endcase
    end
endmodule
