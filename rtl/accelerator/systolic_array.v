`timescale 1ns/1ps
//=============================================================================
// MODULE : systolic_array.v  PROJECT : Mini Spark SoC     PDK : GPDK045nm
// DESC   : 4x4 weight-stationary MAC array - the tensor engine of the SoC.
//
//   PHASE 1 - WEIGHT LOAD   (load_w = 1, exactly 4 clocks)
//     Weights enter each column at the north edge on w0..w3 and shift down
//     one PE per clock. Drive W[3][*] on the first clock and W[0][*] on the
//     fourth, so afterwards PE(r,c) holds W[r][c].
//
//   PHASE 2 - COMPUTE       (load_w = 0, en = 1, 1 clock)
//     Activation a<r> is applied to every PE in row r. Each column forms a
//     combinational 4-term MAC chain, and the result is registered once at
//     the south edge:
//         out_c = SUM over r of ( a_r * W[r][c] )
//     This is element c of the vector-matrix product a . W, i.e. one GEMV.
//     Results are valid one clock after en is asserted - no drain latency.
//
//   Implementation notes
//     Fully flattened explicit instantiation. No 2D arrays, no generate
//     blocks, no SystemVerilog. Compiles in Xcelium, Genus, Innovus, Icarus.
//
//   Wire naming
//     wRC : weight shift wire entering PE at row R, column C
//     sRC : partial sum entering PE at row R, column C
//=============================================================================
module systolic_array (
    input  wire        clk,
    input  wire        rst,
    input  wire        en,
    input  wire        load_w,
    input  wire [7:0]  a0, a1, a2, a3,
    input  wire [7:0]  w0, w1, w2, w3,
    output reg  [31:0] out0, out1, out2, out3
);
    // Weight shift chains - 5 nodes per column (4 PEs plus exit)
    wire [7:0] w00,w10,w20,w30,w40;
    wire [7:0] w01,w11,w21,w31,w41;
    wire [7:0] w02,w12,w22,w32,w42;
    wire [7:0] w03,w13,w23,w33,w43;

    // Combinational accumulation chains
    wire [31:0] s00,s10,s20,s30,s40;
    wire [31:0] s01,s11,s21,s31,s41;
    wire [31:0] s02,s12,s22,s32,s42;
    wire [31:0] s03,s13,s23,s33,s43;

    assign w00 = w0;
    assign w01 = w1;
    assign w02 = w2;
    assign w03 = w3;

    assign s00 = 32'd0;
    assign s01 = 32'd0;
    assign s02 = 32'd0;
    assign s03 = 32'd0;

    // Row 0 - activation a0
    pe pe00 (.clk(clk),.rst(rst),.load_w(load_w),.a_in(a0),.w_in(w00),.acc_in(s00),.w_out(w10),.acc_out(s10));
    pe pe01 (.clk(clk),.rst(rst),.load_w(load_w),.a_in(a0),.w_in(w01),.acc_in(s01),.w_out(w11),.acc_out(s11));
    pe pe02 (.clk(clk),.rst(rst),.load_w(load_w),.a_in(a0),.w_in(w02),.acc_in(s02),.w_out(w12),.acc_out(s12));
    pe pe03 (.clk(clk),.rst(rst),.load_w(load_w),.a_in(a0),.w_in(w03),.acc_in(s03),.w_out(w13),.acc_out(s13));

    // Row 1 - activation a1
    pe pe10 (.clk(clk),.rst(rst),.load_w(load_w),.a_in(a1),.w_in(w10),.acc_in(s10),.w_out(w20),.acc_out(s20));
    pe pe11 (.clk(clk),.rst(rst),.load_w(load_w),.a_in(a1),.w_in(w11),.acc_in(s11),.w_out(w21),.acc_out(s21));
    pe pe12 (.clk(clk),.rst(rst),.load_w(load_w),.a_in(a1),.w_in(w12),.acc_in(s12),.w_out(w22),.acc_out(s22));
    pe pe13 (.clk(clk),.rst(rst),.load_w(load_w),.a_in(a1),.w_in(w13),.acc_in(s13),.w_out(w23),.acc_out(s23));

    // Row 2 - activation a2
    pe pe20 (.clk(clk),.rst(rst),.load_w(load_w),.a_in(a2),.w_in(w20),.acc_in(s20),.w_out(w30),.acc_out(s30));
    pe pe21 (.clk(clk),.rst(rst),.load_w(load_w),.a_in(a2),.w_in(w21),.acc_in(s21),.w_out(w31),.acc_out(s31));
    pe pe22 (.clk(clk),.rst(rst),.load_w(load_w),.a_in(a2),.w_in(w22),.acc_in(s22),.w_out(w32),.acc_out(s32));
    pe pe23 (.clk(clk),.rst(rst),.load_w(load_w),.a_in(a2),.w_in(w23),.acc_in(s23),.w_out(w33),.acc_out(s33));

    // Row 3 - activation a3
    pe pe30 (.clk(clk),.rst(rst),.load_w(load_w),.a_in(a3),.w_in(w30),.acc_in(s30),.w_out(w40),.acc_out(s40));
    pe pe31 (.clk(clk),.rst(rst),.load_w(load_w),.a_in(a3),.w_in(w31),.acc_in(s31),.w_out(w41),.acc_out(s41));
    pe pe32 (.clk(clk),.rst(rst),.load_w(load_w),.a_in(a3),.w_in(w32),.acc_in(s32),.w_out(w42),.acc_out(s42));
    pe pe33 (.clk(clk),.rst(rst),.load_w(load_w),.a_in(a3),.w_in(w33),.acc_in(s33),.w_out(w43),.acc_out(s43));

    // Register the south edge results
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            out0 <= 32'd0;
            out1 <= 32'd0;
            out2 <= 32'd0;
            out3 <= 32'd0;
        end else if (en) begin
            out0 <= s40;
            out1 <= s41;
            out2 <= s42;
            out3 <= s43;
        end
    end
endmodule
