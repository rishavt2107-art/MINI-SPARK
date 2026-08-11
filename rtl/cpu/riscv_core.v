`timescale 1ns/1ps
//=============================================================================
// MODULE : riscv_core.v   PROJECT : Mini Spark SoC        PDK : GPDK045nm
// DESC   : RV32I multi-cycle processor. 5 states: IF ID EX MEM WB.
//          Branch resolution is funct3-based. JALR clears LSB.
//          AUIPC writes PC + imm_u. dmem_ready handshake supported.
//=============================================================================
module riscv_core (
    input  wire        clk,
    input  wire        rst,
    output wire [31:0] imem_addr,
    input  wire [31:0] imem_rdata,
    output reg  [31:0] dmem_addr,
    output reg  [31:0] dmem_wdata,
    output reg         dmem_we,
    output reg         dmem_re,
    input  wire [31:0] dmem_rdata,
    input  wire        dmem_ready
);
    localparam ST_IF  = 3'd0;
    localparam ST_ID  = 3'd1;
    localparam ST_EX  = 3'd2;
    localparam ST_MEM = 3'd3;
    localparam ST_WB  = 3'd4;

    reg [2:0]  state;
    reg [31:0] pc;
    reg [31:0] ir;
    reg [31:0] a_reg;
    reg [31:0] b_reg;
    reg [31:0] alu_out;
    reg [31:0] mem_data;

    reg [31:0] wb_data;
    reg        wb_we;
    reg [4:0]  wb_rd;

    wire [6:0] opcode = ir[6:0];
    wire [4:0] rs1_f  = ir[19:15];
    wire [4:0] rs2_f  = ir[24:20];
    wire [4:0] rd_f   = ir[11:7];
    wire [2:0] funct3 = ir[14:12];
    wire [6:0] funct7 = ir[31:25];

    wire [31:0] imm_i = {{20{ir[31]}}, ir[31:20]};
    wire [31:0] imm_s = {{20{ir[31]}}, ir[31:25], ir[11:7]};
    wire [31:0] imm_b = {{19{ir[31]}}, ir[31], ir[7], ir[30:25], ir[11:8], 1'b0};
    wire [31:0] imm_u = {ir[31:12], 12'd0};
    wire [31:0] imm_j = {{11{ir[31]}}, ir[31], ir[19:12], ir[20], ir[30:21], 1'b0};

    wire reg_write, mem_read, mem_write, branch, jump, jalr;
    wire [1:0] wb_sel;
    wire       alu_src;
    wire [3:0] alu_op;

    control_unit u_cu (
        .opcode(opcode), .funct3(funct3), .funct7(funct7),
        .reg_write(reg_write), .mem_read(mem_read), .mem_write(mem_write),
        .branch(branch), .jump(jump), .jalr(jalr),
        .wb_sel(wb_sel), .alu_src(alu_src), .alu_op(alu_op)
    );

    wire [31:0] rf_rd1, rf_rd2;
    reg_file u_rf (
        .clk(clk), .rst(rst),
        .rs1(rs1_f), .rs2(rs2_f), .rd(wb_rd),
        .wd(wb_data), .we(wb_we),
        .rd1(rf_rd1), .rd2(rf_rd2)
    );

    wire [31:0] imm_sel = (opcode == 7'b0100011) ? imm_s :
                          ((opcode == 7'b0110111) || (opcode == 7'b0010111)) ? imm_u :
                          imm_i;
    wire [31:0] alu_b = alu_src ? imm_sel : b_reg;
    wire [31:0] alu_result;
    wire        alu_zero;

    alu u_alu (
        .a(a_reg), .b(alu_b), .alu_op(alu_op),
        .result(alu_result), .zero(alu_zero)
    );

    reg branch_taken;
    always @(*) begin
        branch_taken = 1'b0;
        if (branch) begin
            case (funct3)
                3'b000: branch_taken =  alu_zero;
                3'b001: branch_taken = ~alu_zero;
                3'b100: branch_taken =  alu_result[0];
                3'b101: branch_taken = ~alu_result[0];
                3'b110: branch_taken =  alu_result[0];
                3'b111: branch_taken = ~alu_result[0];
                default: branch_taken = 1'b0;
            endcase
        end
    end

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            pc         <= 32'd0;
            state      <= ST_IF;
            ir         <= 32'd0;
            a_reg      <= 32'd0;
            b_reg      <= 32'd0;
            alu_out    <= 32'd0;
            mem_data   <= 32'd0;
            wb_data    <= 32'd0;
            wb_we      <= 1'b0;
            wb_rd      <= 5'd0;
            dmem_addr  <= 32'd0;
            dmem_wdata <= 32'd0;
            dmem_we    <= 1'b0;
            dmem_re    <= 1'b0;
        end else begin
            wb_we   <= 1'b0;
            dmem_we <= 1'b0;
            dmem_re <= 1'b0;

            case (state)
            ST_IF: begin
                ir    <= imem_rdata;
                state <= ST_ID;
            end
            ST_ID: begin
                a_reg <= rf_rd1;
                b_reg <= rf_rd2;
                state <= ST_EX;
            end
            ST_EX: begin
                alu_out <= alu_result;
                if (mem_read || mem_write) begin
                    dmem_addr  <= alu_result;
                    dmem_wdata <= b_reg;
                    dmem_we    <= mem_write;
                    dmem_re    <= mem_read;
                    state      <= ST_MEM;
                end else begin
                    state <= ST_WB;
                end
            end
            ST_MEM: begin
                if (dmem_ready) begin
                    mem_data <= dmem_rdata;
                    state    <= ST_WB;
                end else begin
                    dmem_we <= mem_write;
                    dmem_re <= mem_read;
                end
            end
            ST_WB: begin
                case (wb_sel)
                    2'b00:   wb_data <= alu_out;
                    2'b01:   wb_data <= mem_data;
                    2'b10:   wb_data <= pc + 32'd4;
                    2'b11:   wb_data <= pc + imm_u;
                    default: wb_data <= alu_out;
                endcase
                wb_we <= reg_write;
                wb_rd <= rd_f;

                if (jump)
                    pc <= pc + imm_j;
                else if (jalr)
                    pc <= (a_reg + imm_i) & 32'hFFFFFFFE;
                else if (branch_taken)
                    pc <= pc + imm_b;
                else
                    pc <= pc + 32'd4;

                state <= ST_IF;
            end
            default: state <= ST_IF;
            endcase
        end
    end

    assign imem_addr = pc;
endmodule
