/***********************************************************
 * crg_top ST tb - integrates 3-PLL clkmgr + rstmgr + pwrmgr
 ************************************************************/
`timescale 1ns/1ps
`include "apb_if.sv"
`include "clk_rst_if.sv"
`include "g100_crg_top.sv"

module tb;
    import uvm_pkg::*;
    import apb_agent_pkg::*;
    import clkmgr_env_pkg::*;
    import rstmgr_env_pkg::*;
    import pwrmgr_env_pkg::*;
    import crg_top_env_pkg::*;
    import crg_top_test_pkg::*;

    logic apb_clk;
    logic por_rst_n;
    logic osc_clk;
    logic gmac_rx_clk_i;
    logic wdg_rst_n, dbg_rst_n, sw_rst_n;
    logic [3:0] wake_src;

    clk_rst_if apb_clk_if();
    clk_rst_if osc_if();
    apb_if      apb_vif(.pclk(apb_clk), .preset_n(por_rst_n));

    assign apb_clk = apb_clk_if.clk;
    assign osc_clk = osc_if.clk;

    // GMAC RX external
    initial begin
        gmac_rx_clk_i = 1'b0;
        forever begin #(4.0); gmac_rx_clk_i = ~gmac_rx_clk_i; end
    end

    // DUT outputs
    logic pll_cpu_lock, pll_soc_lock, pll_peri_lock;
    logic cpu_core_clk, cpu_aclk, axi_main_clk, ddr_ref_clk;
    logic ahb_clk, apb_leaf_clk, periph_clk, gmac_tx_clk, gmac_rx_clk, qspi_ref_clk;
    logic cpu_rst_n, gpu_rst_n, ddr_rst_n;
    logic [31:0] rst_reason;
    logic iso_en, pwr_state;

    g100_crg_top dut (
        .apb_clk(apb_clk), .por_rst_n(por_rst_n),
        .psel(apb_vif.psel), .penable(apb_vif.penable),
        .pwrite(apb_vif.pwrite), .paddr(apb_vif.paddr), .pwdata(apb_vif.pwdata),
        .prdata(apb_vif.prdata), .pready(apb_vif.pready), .pslverr(apb_vif.pslverr),
        .osc_clk(osc_clk), .gmac_rx_clk_i(gmac_rx_clk_i),
        .wdg_rst_n(wdg_rst_n), .dbg_rst_n(dbg_rst_n), .sw_rst_n(sw_rst_n),
        .wake_src_i(wake_src),
        .pll_cpu_lock(pll_cpu_lock), .pll_soc_lock(pll_soc_lock), .pll_peri_lock(pll_peri_lock),
        .cpu_core_clk(cpu_core_clk), .cpu_aclk(cpu_aclk),
        .axi_main_clk(axi_main_clk), .ddr_ref_clk(ddr_ref_clk),
        .ahb_clk(ahb_clk), .apb_leaf_clk(apb_leaf_clk),
        .periph_clk(periph_clk), .gmac_tx_clk(gmac_tx_clk),
        .gmac_rx_clk(gmac_rx_clk), .qspi_ref_clk(qspi_ref_clk),
        .cpu_rst_n(cpu_rst_n), .gpu_rst_n(gpu_rst_n), .ddr_rst_n(ddr_rst_n),
        .rst_reason(rst_reason),
        .iso_en(iso_en), .pwr_state(pwr_state)
    );

    // wake source fire periodically
    initial begin
        wake_src = 0;
        forever begin
            #10000ns;
            wake_src = 4'b0001;
            #200ns;
            wake_src = 4'b0000;
        end
    end

    initial begin
        apb_clk_if.set_active(); osc_if.set_active();
        por_rst_n = 0; wdg_rst_n = 1; dbg_rst_n = 1; sw_rst_n = 1;
        apb_clk_if.rst_n = 0;
        apb_vif.psel = 0; apb_vif.penable = 0; apb_vif.pwrite = 0;
        apb_vif.paddr = 0; apb_vif.pwdata = 0;
    end

    initial fork
        osc_if.start_clk(25.0);
        apb_clk_if.start_clk(10.0);
    join_none

    initial begin
        #100ns;
        apb_clk_if.assert_reset(5);
        #500ns;
        por_rst_n = 1;
        #500ns;
    end

    initial begin
        uvm_config_db#(virtual apb_if)::set(null, "*", "vif", apb_vif);
        run_test();
    end

    // global timeout
    initial begin
        #200000ns;
        $display("[TB] FATAL: global timeout at %0t", $time);
        $finish;
    end

endmodule
