`timescale 1ns/1ps
//=============================================================================
// MODULE : axi_lite_bus.v PROJECT : Mini Spark SoC        PDK : GPDK045nm
// DESC   : AXI-Lite crossbar. 1 master (CPU), 2 slaves.
//          Address bit [16] decodes the slave:
//             bit16 = 0  ->  Slave 0  Accelerator control registers
//             bit16 = 1  ->  Slave 1  Shared SRAM
//          SRAM is word-addressed via addr[9:2].
//          Purely combinational - synthesises to logic gates only.
//=============================================================================
module axi_lite_bus (
    input  wire        clk,
    input  wire        rst,
    input  wire [31:0] m_awaddr,
    input  wire        m_awvalid,
    output wire        m_awready,
    input  wire [31:0] m_wdata,
    input  wire        m_wvalid,
    output wire        m_wready,
    output wire [1:0]  m_bresp,
    output wire        m_bvalid,
    input  wire        m_bready,
    input  wire [31:0] m_araddr,
    input  wire        m_arvalid,
    output wire        m_arready,
    output wire [31:0] m_rdata,
    output wire [1:0]  m_rresp,
    output wire        m_rvalid,
    input  wire        m_rready,
    output wire [11:0] s0_awaddr,
    output wire        s0_awvalid,
    input  wire        s0_awready,
    output wire [31:0] s0_wdata,
    output wire        s0_wvalid,
    input  wire        s0_wready,
    input  wire [1:0]  s0_bresp,
    input  wire        s0_bvalid,
    output wire        s0_bready,
    output wire [11:0] s0_araddr,
    output wire        s0_arvalid,
    input  wire        s0_arready,
    input  wire [31:0] s0_rdata,
    input  wire [1:0]  s0_rresp,
    input  wire        s0_rvalid,
    output wire        s0_rready,
    output wire [7:0]  s1_addr,
    output wire [31:0] s1_wdata,
    output wire        s1_we,
    output wire        s1_re,
    input  wire [31:0] s1_rdata
);
    wire wr_sel = m_awaddr[16];
    wire rd_sel = m_araddr[16];

    assign s0_awaddr  = m_awaddr[11:0];
    assign s0_awvalid = m_awvalid & ~wr_sel;
    assign s0_wdata   = m_wdata;
    assign s0_wvalid  = m_wvalid  & ~wr_sel;
    assign s0_bready  = m_bready;

    assign s0_araddr  = m_araddr[11:0];
    assign s0_arvalid = m_arvalid & ~rd_sel;
    assign s0_rready  = m_rready;

    assign s1_addr  = m_awvalid ? m_awaddr[9:2] : m_araddr[9:2];
    assign s1_wdata = m_wdata;
    assign s1_we    = m_awvalid & m_wvalid & wr_sel;
    assign s1_re    = m_arvalid & rd_sel;

    assign m_awready = wr_sel ? 1'b1     : s0_awready;
    assign m_wready  = wr_sel ? 1'b1     : s0_wready;
    assign m_bvalid  = wr_sel ? s1_we    : s0_bvalid;
    assign m_bresp   = 2'b00;
    assign m_arready = rd_sel ? 1'b1     : s0_arready;
    assign m_rdata   = rd_sel ? s1_rdata : s0_rdata;
    assign m_rvalid  = rd_sel ? 1'b1     : s0_rvalid;
    assign m_rresp   = 2'b00;
endmodule
