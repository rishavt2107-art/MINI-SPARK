`timescale 1ns/1ps
//=============================================================================
// TB : tb_axi_lite_bus.v   Address decode and routing check
//   addr bit16 = 0 -> Slave 0 (accelerator)   bit16 = 1 -> Slave 1 (SRAM)
//=============================================================================
module tb_axi_lite_bus;
    reg clk = 0, rst = 1;
    reg  [31:0] m_awaddr, m_wdata, m_araddr;
    reg         m_awvalid, m_wvalid, m_arvalid;
    wire        m_awready, m_wready, m_bvalid, m_arready, m_rvalid;
    wire [1:0]  m_bresp, m_rresp;
    wire [31:0] m_rdata;

    wire [11:0] s0_awaddr, s0_araddr;
    wire        s0_awvalid, s0_wvalid, s0_arvalid, s0_bready, s0_rready;
    wire [31:0] s0_wdata;
    wire [7:0]  s1_addr;
    wire [31:0] s1_wdata;
    wire        s1_we, s1_re;

    integer fails = 0;
    always #5 clk = ~clk;

    axi_lite_bus dut (
        .clk(clk), .rst(rst),
        .m_awaddr(m_awaddr), .m_awvalid(m_awvalid), .m_awready(m_awready),
        .m_wdata(m_wdata),   .m_wvalid(m_wvalid),   .m_wready(m_wready),
        .m_bresp(m_bresp),   .m_bvalid(m_bvalid),   .m_bready(1'b1),
        .m_araddr(m_araddr), .m_arvalid(m_arvalid), .m_arready(m_arready),
        .m_rdata(m_rdata),   .m_rresp(m_rresp),
        .m_rvalid(m_rvalid), .m_rready(1'b1),
        .s0_awaddr(s0_awaddr), .s0_awvalid(s0_awvalid), .s0_awready(1'b1),
        .s0_wdata(s0_wdata),   .s0_wvalid(s0_wvalid),   .s0_wready(1'b1),
        .s0_bresp(2'b00),      .s0_bvalid(1'b1),        .s0_bready(s0_bready),
        .s0_araddr(s0_araddr), .s0_arvalid(s0_arvalid), .s0_arready(1'b1),
        .s0_rdata(32'hA5A5A5A5), .s0_rresp(2'b00),
        .s0_rvalid(1'b1),      .s0_rready(s0_rready),
        .s1_addr(s1_addr), .s1_wdata(s1_wdata),
        .s1_we(s1_we), .s1_re(s1_re), .s1_rdata(32'h5A5A5A5A)
    );

    initial begin
        $display("===== AXI-LITE BUS TESTBENCH =====");
        m_awaddr=0; m_wdata=0; m_araddr=0;
        m_awvalid=0; m_wvalid=0; m_arvalid=0;
        repeat(2) @(posedge clk); rst = 0;

        // Write to accelerator space (bit16 = 0)
        @(negedge clk);
        m_awaddr = 32'h0000_0008; m_wdata = 32'h1234_5678;
        m_awvalid = 1; m_wvalid = 1;
        #1;
        if (!s0_awvalid || s0_wvalid !== 1'b1 || s1_we !== 1'b0) begin
            $display("FAIL t1: accel write not routed (s0_awvalid=%b s1_we=%b)",
                     s0_awvalid, s1_we); fails = fails + 1;
        end else if (s0_awaddr !== 12'h008) begin
            $display("FAIL t1: s0_awaddr=%h exp 008", s0_awaddr); fails = fails + 1;
        end else $display("PASS t1: write to 0x00000008 routed to accelerator");

        // Write to SRAM space (bit16 = 1)
        @(negedge clk);
        m_awaddr = 32'h0001_0140; m_wdata = 32'hDEAD_BEEF;
        #1;
        if (s1_we !== 1'b1 || s0_awvalid !== 1'b0) begin
            $display("FAIL t2: sram write not routed (s1_we=%b s0_awvalid=%b)",
                     s1_we, s0_awvalid); fails = fails + 1;
        end else if (s1_addr !== 8'h50) begin
            $display("FAIL t2: s1_addr=%h exp 50", s1_addr); fails = fails + 1;
        end else $display("PASS t2: write to 0x00010140 routed to SRAM word 0x50");

        @(negedge clk); m_awvalid = 0; m_wvalid = 0;

        // Read from accelerator space
        @(negedge clk);
        m_araddr = 32'h0000_0004; m_arvalid = 1;
        #1;
        if (m_rdata !== 32'hA5A5A5A5) begin
            $display("FAIL t3: accel read data=%h exp A5A5A5A5", m_rdata);
            fails = fails + 1;
        end else $display("PASS t3: read from accelerator returns slave 0 data");

        // Read from SRAM space
        @(negedge clk);
        m_araddr = 32'h0001_0000;
        #1;
        if (m_rdata !== 32'h5A5A5A5A || s1_re !== 1'b1) begin
            $display("FAIL t4: sram read data=%h s1_re=%b", m_rdata, s1_re);
            fails = fails + 1;
        end else $display("PASS t4: read from SRAM returns slave 1 data");

        @(negedge clk); m_arvalid = 0;

        $display("===== AXI BUS: %0d failures =====", fails);
        if (fails == 0) $display("AXI LITE BUS FUNCTIONALLY VERIFIED");
        else            $display("AXI LITE BUS HAS FAILURES");
        $finish;
    end
endmodule
