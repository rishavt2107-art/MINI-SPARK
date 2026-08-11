`timescale 1ns/1ps
module tb_control_unit;
    reg [6:0] opcode;
    reg [2:0] funct3;
    reg [6:0] funct7;
    wire rw, mr, mw, br, jm, jr;
    wire [1:0] wbs;
    wire src;
    wire [3:0] aop;
    integer fails = 0;
    integer tid = 0;

    control_unit dut (.opcode(opcode), .funct3(funct3), .funct7(funct7),
        .reg_write(rw), .mem_read(mr), .mem_write(mw), .branch(br),
        .jump(jm), .jalr(jr), .wb_sel(wbs), .alu_src(src), .alu_op(aop));

    task chk;
        input e_rw, e_mr, e_mw, e_br, e_jm, e_jr;
        input [1:0] e_wbs;
        input e_src;
        input [3:0] e_aop;
        begin
            #1;
            tid = tid + 1;
            if (rw!==e_rw || mr!==e_mr || mw!==e_mw || br!==e_br ||
                jm!==e_jm || jr!==e_jr || wbs!==e_wbs || src!==e_src || aop!==e_aop) begin
                $display("FAIL t%0d op=%b: got rw=%b mr=%b mw=%b br=%b jm=%b jr=%b wbs=%b src=%b aop=%b",
                    tid, opcode, rw, mr, mw, br, jm, jr, wbs, src, aop);
                $display("            exp rw=%b mr=%b mw=%b br=%b jm=%b jr=%b wbs=%b src=%b aop=%b",
                    e_rw, e_mr, e_mw, e_br, e_jm, e_jr, e_wbs, e_src, e_aop);
                fails = fails + 1;
            end else $display("PASS t%0d: opcode %b decoded correctly", tid, opcode);
        end
    endtask

    initial begin
        $display("===== CONTROL UNIT TESTBENCH =====");
        opcode=7'b0110011; funct3=3'b000; funct7=7'b0000000; chk(1,0,0,0,0,0,2'b00,1'b0,4'b0000);
        opcode=7'b0110011; funct3=3'b000; funct7=7'b0100000; chk(1,0,0,0,0,0,2'b00,1'b0,4'b0001);
        opcode=7'b0110011; funct3=3'b111; funct7=7'b0000000; chk(1,0,0,0,0,0,2'b00,1'b0,4'b0010);
        opcode=7'b0010011; funct3=3'b000; funct7=7'b0000000; chk(1,0,0,0,0,0,2'b00,1'b1,4'b0000);
        opcode=7'b0000011; funct3=3'b010; funct7=7'b0000000; chk(1,1,0,0,0,0,2'b01,1'b1,4'b0000);
        opcode=7'b0100011; funct3=3'b010; funct7=7'b0000000; chk(0,0,1,0,0,0,2'b00,1'b1,4'b0000);
        opcode=7'b1100011; funct3=3'b000; funct7=7'b0000000; chk(0,0,0,1,0,0,2'b00,1'b0,4'b0001);
        opcode=7'b1101111; funct3=3'b000; funct7=7'b0000000; chk(1,0,0,0,1,0,2'b10,1'b0,4'b0000);
        opcode=7'b1100111; funct3=3'b000; funct7=7'b0000000; chk(1,0,0,0,0,1,2'b10,1'b1,4'b0000);
        opcode=7'b0110111; funct3=3'b000; funct7=7'b0000000; chk(1,0,0,0,0,0,2'b00,1'b1,4'b1010);
        opcode=7'b0010111; funct3=3'b000; funct7=7'b0000000; chk(1,0,0,0,0,0,2'b11,1'b1,4'b0000);

        $display("===== CTRL UNIT: %0d tests, %0d failures =====", tid, fails);
        if (fails == 0) $display("CONTROL UNIT FUNCTIONALLY VERIFIED");
        $finish;
    end
endmodule
