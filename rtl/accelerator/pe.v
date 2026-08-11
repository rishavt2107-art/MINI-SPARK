`timescale 1ns/1ps
//=============================================================================
// MODULE : pe.v           PROJECT : Mini Spark SoC        PDK : GPDK045nm
// DESC   : Weight-stationary Processing Element (MAC cell).
//
//   WEIGHT LOAD (load_w = 1)
//     The PE behaves as one stage of a per-column shift register:
//         w_reg <= w_in           (take value from the PE above)
//         w_out  = w_reg          (combinational, so one clock = one stage)
//     Pushing 4 values into a column from the north edge fills all 4 PEs.
//     Push W[3][c] first and W[0][c] last so PE(r,c) ends up holding W[r][c].
//
//   COMPUTE (load_w = 0)
//     The weight register holds. The multiply-accumulate is combinational:
//         acc_out = acc_in + (a_in * w_reg)
//     Four PEs chained vertically form one column dot-product. The array
//     registers the result once at the south edge, giving exact single-cycle
//     semantics with no re-accumulation.
//
//   Arithmetic: INT8 x INT8 -> signed 16-bit product, sign-extended to 32-bit.
//=============================================================================
module pe (
    input  wire        clk,
    input  wire        rst,
    input  wire        load_w,
    input  wire [7:0]  a_in,
    input  wire [7:0]  w_in,
    input  wire [31:0] acc_in,
    output wire [7:0]  w_out,
    output wire [31:0] acc_out
);
    reg [7:0] w_reg;

    wire signed [7:0]  a_s = a_in;
    wire signed [7:0]  w_s = w_reg;
    wire signed [15:0] product     = a_s * w_s;
    wire        [31:0] product_ext = {{16{product[15]}}, product};

    // Combinational accumulation down the column
    assign acc_out = acc_in + product_ext;

    // Combinational weight pass-down: PE below sees this PE's current weight,
    // so one clock shifts the whole column by exactly one stage.
    assign w_out = w_reg;

    // Weight shift register
    always @(posedge clk or posedge rst) begin
        if (rst)
            w_reg <= 8'd0;
        else if (load_w)
            w_reg <= w_in;
    end
endmodule
