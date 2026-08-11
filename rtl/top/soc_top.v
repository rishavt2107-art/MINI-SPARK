`timescale 1ns/1ps
//=============================================================================
// MODULE : soc_top.v      PROJECT : Mini Spark SoC        PDK : GPDK045nm
// DESC   : Top-level SoC. Integrates CPU, accelerator, AXI-Lite bus, SRAM,
//          and instruction ROM.
//
// MEMORY MAP (as seen by the CPU data port):
//   0x0000_0000 - 0x0000_0FFF   Accelerator control registers (Slave 0)
//   0x0001_0000 - 0x0001_03FF   Shared SRAM, 256 words        (Slave 1)
//
// The accelerator has a private SRAM port that takes priority over the CPU
// during GEMV compute. This avoids bus arbitration latency in the inner loop.
//=============================================================================
module soc_top (
    input  wire clk,
    input  wire rst,
    output wire done_irq
);
    //-------------------------------------------------------------------------
    // Instruction ROM
    //-------------------------------------------------------------------------
    reg [31:0] imem [0:255];
    integer k;
    initial begin
        for (k = 0; k < 256; k = k + 1)
            imem[k] = 32'h0000_0013;
        $readmemh("tb/vectors/firmware.hex", imem);
    end

    wire [31:0] imem_addr;
    wire [31:0] imem_rdata = imem[imem_addr[9:2]];

    //-------------------------------------------------------------------------
    // CPU data port
    //-------------------------------------------------------------------------
    wire [31:0] cpu_daddr;
    wire [31:0] cpu_dwdata;
    wire [31:0] cpu_drdata;
    wire        cpu_dwe;
    wire        cpu_dre;
    wire        cpu_dready;

    //-------------------------------------------------------------------------
    // Bus master side
    //-------------------------------------------------------------------------
    wire        m_awready, m_wready, m_bvalid, m_arready, m_rvalid;
    wire [1:0]  m_bresp, m_rresp;
    wire [31:0] m_rdata;

    assign cpu_drdata = m_rdata;
    assign cpu_dready = cpu_dre ? m_rvalid : (cpu_dwe ? m_bvalid : 1'b1);

    //-------------------------------------------------------------------------
    // Slave 0 - Accelerator
    //-------------------------------------------------------------------------
    wire [11:0] s0_awaddr;  wire s0_awvalid, s0_awready;
    wire [31:0] s0_wdata;   wire s0_wvalid,  s0_wready;
    wire [1:0]  s0_bresp;   wire s0_bvalid,  s0_bready;
    wire [11:0] s0_araddr;  wire s0_arvalid, s0_arready;
    wire [31:0] s0_rdata;   wire [1:0] s0_rresp;
    wire        s0_rvalid,  s0_rready;

    //-------------------------------------------------------------------------
    // Slave 1 - SRAM
    //-------------------------------------------------------------------------
    wire [7:0]  s1_addr;
    wire [31:0] s1_wdata;
    wire        s1_we, s1_re;
    wire [31:0] sram_rdata;

    //-------------------------------------------------------------------------
    // Accelerator private SRAM port
    //-------------------------------------------------------------------------
    wire [7:0]  ac_saddr;
    wire [31:0] ac_swdata;
    wire        ac_swe, ac_sre;

    //-------------------------------------------------------------------------
    // Instances
    //-------------------------------------------------------------------------
    axi_lite_bus u_bus (
        .clk(clk), .rst(rst),
        .m_awaddr(cpu_daddr),  .m_awvalid(cpu_dwe),  .m_awready(m_awready),
        .m_wdata(cpu_dwdata),  .m_wvalid(cpu_dwe),   .m_wready(m_wready),
        .m_bresp(m_bresp),     .m_bvalid(m_bvalid),  .m_bready(1'b1),
        .m_araddr(cpu_daddr),  .m_arvalid(cpu_dre),  .m_arready(m_arready),
        .m_rdata(m_rdata),     .m_rresp(m_rresp),
        .m_rvalid(m_rvalid),   .m_rready(1'b1),
        .s0_awaddr(s0_awaddr), .s0_awvalid(s0_awvalid), .s0_awready(s0_awready),
        .s0_wdata(s0_wdata),   .s0_wvalid(s0_wvalid),   .s0_wready(s0_wready),
        .s0_bresp(s0_bresp),   .s0_bvalid(s0_bvalid),   .s0_bready(s0_bready),
        .s0_araddr(s0_araddr), .s0_arvalid(s0_arvalid), .s0_arready(s0_arready),
        .s0_rdata(s0_rdata),   .s0_rresp(s0_rresp),
        .s0_rvalid(s0_rvalid), .s0_rready(s0_rready),
        .s1_addr(s1_addr),     .s1_wdata(s1_wdata),
        .s1_we(s1_we),         .s1_re(s1_re),
        .s1_rdata(sram_rdata)
    );

    accel_top u_accel (
        .clk(clk), .rst(rst),
        .s_awaddr(s0_awaddr), .s_awvalid(s0_awvalid), .s_awready(s0_awready),
        .s_wdata(s0_wdata),   .s_wvalid(s0_wvalid),   .s_wready(s0_wready),
        .s_bresp(s0_bresp),   .s_bvalid(s0_bvalid),   .s_bready(s0_bready),
        .s_araddr(s0_araddr), .s_arvalid(s0_arvalid), .s_arready(s0_arready),
        .s_rdata(s0_rdata),   .s_rresp(s0_rresp),
        .s_rvalid(s0_rvalid), .s_rready(s0_rready),
        .sram_addr(ac_saddr), .sram_wdata(ac_swdata),
        .sram_we(ac_swe),     .sram_re(ac_sre),
        .sram_rdata(sram_rdata),
        .done_irq(done_irq)
    );

    wire        sram_sel_accel = ac_swe | ac_sre;
    wire [7:0]  sram_addr_mux  = sram_sel_accel ? ac_saddr  : s1_addr;
    wire [31:0] sram_wdata_mux = ac_swe         ? ac_swdata : s1_wdata;

    sram_sp_256x32 u_sram (
        .clk(clk),
        .addr (sram_addr_mux),
        .wdata(sram_wdata_mux),
        .we   (ac_swe | s1_we),
        .re   (ac_sre | s1_re),
        .rdata(sram_rdata)
    );

    riscv_core u_cpu (
        .clk(clk), .rst(rst),
        .imem_addr(imem_addr),   .imem_rdata(imem_rdata),
        .dmem_addr(cpu_daddr),   .dmem_wdata(cpu_dwdata),
        .dmem_we(cpu_dwe),       .dmem_re(cpu_dre),
        .dmem_rdata(cpu_drdata), .dmem_ready(cpu_dready)
    );
endmodule
