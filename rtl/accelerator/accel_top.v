`timescale 1ns/1ps
//=============================================================================
// MODULE : accel_top.v    PROJECT : Mini Spark SoC        PDK : GPDK045nm
// DESC   : GEMV accelerator. AXI-Lite slave + 4x4 MAC array + control FSM.
//
//  REGISTER MAP (byte offsets from the accelerator base address)
//    0x000  ctrl    W   bit0 = start (write 1 to launch a GEMV)
//    0x004  status  R   bit0 = busy, bit1 = done
//    0x008  base_a  RW  SRAM word address of the 4-element activation vector
//    0x00C  base_w  RW  SRAM word address of the 4x4 weight matrix
//    0x010  base_o  RW  SRAM word address of the 4-element output vector
//    0x014  dim     RW  matrix dimension N (fixed at 4 for this build)
//
//  SRAM DATA LAYOUT (one INT8 value per 32-bit word, low byte used)
//    base_a + 0 .. 3       activation vector a[0..3]
//    base_w + 0 .. 15      weight matrix in row-major order
//                          W[r][c] lives at base_w + r*4 + c
//    base_o + 0 .. 3       result vector y[0..3]
//
//  RESULT
//    y[c] = SUM over r of ( a[r] * W[r][c] )
//
//  FSM SEQUENCE
//    IDLE   wait for a rising edge on ctrl bit0
//    RDW    read all 16 weights from SRAM into a local buffer (3 clocks each:
//           drive address, wait for the 1-cycle SRAM latency, capture data)
//    RDA    read the 4 activations from SRAM into registers (3 clocks each)
//    LDW    shift 4 rows of weights into the array, W[3][*] first
//    RUN    assert en for one clock, latching the dot products
//    WAIT   one clock for the array output registers to settle
//    WRO    write the 4 results back to SRAM
//    DONE   set status done, return to IDLE
//=============================================================================
module accel_top (
    input  wire        clk,
    input  wire        rst,
    // AXI-Lite slave
    input  wire [11:0] s_awaddr,
    input  wire        s_awvalid,
    output reg         s_awready,
    input  wire [31:0] s_wdata,
    input  wire        s_wvalid,
    output reg         s_wready,
    output wire [1:0]  s_bresp,
    output reg         s_bvalid,
    input  wire        s_bready,
    input  wire [11:0] s_araddr,
    input  wire        s_arvalid,
    output reg         s_arready,
    output reg  [31:0] s_rdata,
    output wire [1:0]  s_rresp,
    output reg         s_rvalid,
    input  wire        s_rready,
    // Private SRAM port
    output reg  [7:0]  sram_addr,
    output reg  [31:0] sram_wdata,
    output reg         sram_we,
    output reg         sram_re,
    input  wire [31:0] sram_rdata,
    // Completion interrupt
    output wire        done_irq
);
    //-------------------------------------------------------------------------
    // Control and status registers
    //-------------------------------------------------------------------------
    reg [31:0] ctrl_r, stat_r, base_a_r, base_w_r, base_o_r, dim_r;
    reg [11:0] awaddr_lat;
    reg        start_pulse;

    // The CPU presents the write address and the write data in the same
    // cycle. Use the live address when it is valid, otherwise fall back to
    // the latched copy. This avoids decoding against a stale awaddr_lat.
    wire [11:0] wr_addr = s_awvalid ? s_awaddr : awaddr_lat;

    assign s_bresp  = 2'b00;
    assign s_rresp  = 2'b00;
    assign done_irq = stat_r[1];

    //-------------------------------------------------------------------------
    // AXI-Lite write channel
    //-------------------------------------------------------------------------
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            s_awready   <= 1'b0;
            s_wready    <= 1'b0;
            s_bvalid    <= 1'b0;
            awaddr_lat  <= 12'd0;
            ctrl_r      <= 32'd0;
            base_a_r    <= 32'h0000_0040;
            base_w_r    <= 32'h0000_0050;
            base_o_r    <= 32'h0000_0060;
            dim_r       <= 32'd4;
            start_pulse <= 1'b0;
        end else begin
            start_pulse <= 1'b0;

            if (s_awvalid && !s_awready) begin
                s_awready  <= 1'b1;
                awaddr_lat <= s_awaddr;
            end else begin
                s_awready <= 1'b0;
            end

            if (s_wvalid && !s_wready) begin
                s_wready <= 1'b1;
                s_bvalid <= 1'b1;
                case (wr_addr)
                    12'h000: begin
                        ctrl_r <= s_wdata;
                        if (s_wdata[0]) start_pulse <= 1'b1;
                    end
                    12'h008: base_a_r <= s_wdata;
                    12'h00C: base_w_r <= s_wdata;
                    12'h010: base_o_r <= s_wdata;
                    12'h014: dim_r    <= s_wdata;
                    default: ;
                endcase
            end else begin
                s_wready <= 1'b0;
            end

            if (s_bvalid && s_bready) s_bvalid <= 1'b0;
        end
    end

    //-------------------------------------------------------------------------
    // AXI-Lite read channel
    //-------------------------------------------------------------------------
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            s_arready <= 1'b0;
            s_rvalid  <= 1'b0;
            s_rdata   <= 32'd0;
        end else begin
            if (s_arvalid && !s_arready) begin
                s_arready <= 1'b1;
                s_rvalid  <= 1'b1;
                case (s_araddr)
                    12'h000: s_rdata <= ctrl_r;
                    12'h004: s_rdata <= stat_r;
                    12'h008: s_rdata <= base_a_r;
                    12'h00C: s_rdata <= base_w_r;
                    12'h010: s_rdata <= base_o_r;
                    12'h014: s_rdata <= dim_r;
                    default: s_rdata <= 32'hDEAD_BEEF;
                endcase
            end else begin
                s_arready <= 1'b0;
            end
            if (s_rvalid && s_rready) s_rvalid <= 1'b0;
        end
    end

    //-------------------------------------------------------------------------
    // Weight buffer - 16 registers holding W[r][c]
    //-------------------------------------------------------------------------
    reg [7:0] wbuf [0:15];
    reg [7:0] abuf0, abuf1, abuf2, abuf3;

    //-------------------------------------------------------------------------
    // MAC array
    //-------------------------------------------------------------------------
    reg  [7:0]  sa_w0, sa_w1, sa_w2, sa_w3;
    reg         sa_en, sa_load, sa_rst;
    wire [31:0] sa_out0, sa_out1, sa_out2, sa_out3;

    systolic_array u_sa (
        .clk(clk), .rst(sa_rst), .en(sa_en), .load_w(sa_load),
        .a0(abuf0), .a1(abuf1), .a2(abuf2), .a3(abuf3),
        .w0(sa_w0), .w1(sa_w1), .w2(sa_w2), .w3(sa_w3),
        .out0(sa_out0), .out1(sa_out1), .out2(sa_out2), .out3(sa_out3)
    );

    //-------------------------------------------------------------------------
    // Control FSM
    //-------------------------------------------------------------------------
    localparam S_IDLE = 3'd0;
    localparam S_RDW  = 3'd1;
    localparam S_RDA  = 3'd2;
    localparam S_LDW  = 3'd3;
    localparam S_RUN  = 3'd4;
    localparam S_WRO  = 3'd5;
    localparam S_DONE = 3'd6;
    localparam S_WAIT = 3'd7;

    reg [2:0] fsm;
    reg [4:0] idx;
    reg [1:0] ldrow;
    reg [1:0] phase;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            fsm        <= S_IDLE;
            idx        <= 5'd0;
            ldrow      <= 2'd0;
            phase      <= 2'd0;
            sa_en      <= 1'b0;
            sa_load    <= 1'b0;
            sa_rst     <= 1'b1;
            sram_addr  <= 8'd0;
            sram_wdata <= 32'd0;
            sram_we    <= 1'b0;
            sram_re    <= 1'b0;
            sa_w0      <= 8'd0;
            sa_w1      <= 8'd0;
            sa_w2      <= 8'd0;
            sa_w3      <= 8'd0;
            abuf0      <= 8'd0;
            abuf1      <= 8'd0;
            abuf2      <= 8'd0;
            abuf3      <= 8'd0;
            stat_r     <= 32'd0;
        end else begin
            sram_we <= 1'b0;
            sram_re <= 1'b0;
            sa_en   <= 1'b0;
            sa_load <= 1'b0;
            sa_rst  <= 1'b0;

            case (fsm)
            //-----------------------------------------------------------------
            S_IDLE: begin
                if (start_pulse) begin
                    stat_r <= 32'h0000_0001;
                    idx    <= 5'd0;
                    phase  <= 2'd0;
                    sa_rst <= 1'b1;
                    fsm    <= S_RDW;
                end
            end

            //-----------------------------------------------------------------
            // Read 16 weights from SRAM into wbuf
            //-----------------------------------------------------------------
            S_RDW: begin
                case (phase)
                2'd0: begin
                    // Drive the address and the read strobe
                    sram_addr <= base_w_r[7:0] + {3'd0, idx};
                    sram_re   <= 1'b1;
                    phase     <= 2'd1;
                end
                2'd1: begin
                    // SRAM is sampling the address this cycle
                    phase <= 2'd2;
                end
                default: begin
                    // sram_rdata is now valid
                    wbuf[idx[3:0]] <= sram_rdata[7:0];
                    phase          <= 2'd0;
                    if (idx == 5'd15) begin
                        idx <= 5'd0;
                        fsm <= S_RDA;
                    end else begin
                        idx <= idx + 5'd1;
                    end
                end
                endcase
            end

            //-----------------------------------------------------------------
            // Read 4 activations from SRAM
            //-----------------------------------------------------------------
            S_RDA: begin
                case (phase)
                2'd0: begin
                    sram_addr <= base_a_r[7:0] + {3'd0, idx};
                    sram_re   <= 1'b1;
                    phase     <= 2'd1;
                end
                2'd1: begin
                    phase <= 2'd2;
                end
                default: begin
                    case (idx[1:0])
                        2'd0: abuf0 <= sram_rdata[7:0];
                        2'd1: abuf1 <= sram_rdata[7:0];
                        2'd2: abuf2 <= sram_rdata[7:0];
                        2'd3: abuf3 <= sram_rdata[7:0];
                    endcase
                    phase <= 2'd0;
                    if (idx == 5'd3) begin
                        idx   <= 5'd0;
                        ldrow <= 2'd3;
                        fsm   <= S_LDW;
                    end else begin
                        idx <= idx + 5'd1;
                    end
                end
                endcase
            end

            //-----------------------------------------------------------------
            // Shift weights into the array, row 3 first down to row 0
            //-----------------------------------------------------------------
            S_LDW: begin
                sa_w0   <= wbuf[{ldrow, 2'd0}];
                sa_w1   <= wbuf[{ldrow, 2'd1}];
                sa_w2   <= wbuf[{ldrow, 2'd2}];
                sa_w3   <= wbuf[{ldrow, 2'd3}];
                sa_load <= 1'b1;
                if (ldrow == 2'd0) begin
                    fsm <= S_RUN;
                end else begin
                    ldrow <= ldrow - 2'd1;
                end
            end

            //-----------------------------------------------------------------
            // One compute clock latches all four dot products
            //-----------------------------------------------------------------
            S_RUN: begin
                // Assert the compute enable. The array registers all four dot
                // products at the end of the NEXT clock, so pass through one
                // wait state before sampling sa_out*.
                sa_en <= 1'b1;
                idx   <= 5'd0;
                fsm   <= S_WAIT;
            end

            //-----------------------------------------------------------------
            // One clock for the array output registers to settle
            //-----------------------------------------------------------------
            S_WAIT: begin
                fsm <= S_WRO;
            end

            //-----------------------------------------------------------------
            // Write the 4 results back to SRAM
            //-----------------------------------------------------------------
            S_WRO: begin
                sram_addr <= base_o_r[7:0] + {3'd0, idx};
                case (idx[1:0])
                    2'd0: sram_wdata <= sa_out0;
                    2'd1: sram_wdata <= sa_out1;
                    2'd2: sram_wdata <= sa_out2;
                    2'd3: sram_wdata <= sa_out3;
                endcase
                sram_we <= 1'b1;
                if (idx == 5'd3) begin
                    fsm <= S_DONE;
                end else begin
                    idx <= idx + 5'd1;
                end
            end

            //-----------------------------------------------------------------
            S_DONE: begin
                stat_r <= 32'h0000_0003;
                fsm    <= S_IDLE;
            end

            default: fsm <= S_IDLE;
            endcase
        end
    end
endmodule
