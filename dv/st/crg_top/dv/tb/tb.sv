/***********************************************************
 * crg_top ST tb - integrates clkmgr + rstmgr + pwrmgr
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
    logic osc_clk, xtal_clk;
    logic wdg_rst_n, dbg_rst_n, sw_rst_n;
    logic [3:0] wake_src;

    clk_rst_if apb_clk_if();
    clk_rst_if osc_if();
    clk_rst_if xtal_if();
    apb_if      apb_vif(.pclk(apb_clk), .preset_n(por_rst_n));

    assign apb_clk = apb_clk_if.clk;
    assign osc_clk = osc_if.clk;
    assign xtal_clk = xtal_if.clk;

    // DUT outputs
    logic pll_clk, cpu_clk, gpu_clk, ddr_clk;
    logic cpu_clk_g, gpu_clk_g, ddr_clk_g, pll_lock;
    logic cpu_rst_n, gpu_rst_n, ddr_rst_n;
    logic [31:0] rst_reason;
    logic iso_en, pwr_state;

    g100_crg_top dut (
        .apb_clk(apb_clk), .por_rst_n(por_rst_n),
        .psel(apb_vif.psel), .penable(apb_vif.penable),
        .pwrite(apb_vif.pwrite), .paddr(apb_vif.paddr), .pwdata(apb_vif.pwdata),
        .prdata(apb_vif.prdata), .pready(apb_vif.pready), .pslverr(apb_vif.pslverr),
        .osc_clk(osc_clk), .xtal_clk(xtal_clk),
        .wdg_rst_n(wdg_rst_n), .dbg_rst_n(dbg_rst_n), .sw_rst_n(sw_rst_n),
        .wake_src_i(wake_src),
        .pll_clk(pll_clk), .cpu_clk(cpu_clk), .gpu_clk(gpu_clk), .ddr_clk(ddr_clk),
        .cpu_clk_g(cpu_clk_g), .gpu_clk_g(gpu_clk_g), .ddr_clk_g(ddr_clk_g),
        .pll_lock(pll_lock),
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
        apb_clk_if.set_active(); osc_if.set_active(); xtal_if.set_active();
        por_rst_n = 0; wdg_rst_n = 1; dbg_rst_n = 1; sw_rst_n = 1;
        apb_clk_if.rst_n = 0;
        apb_vif.psel = 0; apb_vif.penable = 0; apb_vif.pwrite = 0;
        apb_vif.paddr = 0; apb_vif.pwdata = 0;
    end

    initial fork
        osc_if.start_clk(25.0);   // 40 MHz
        xtal_if.start_clk(20.0);  // 50 MHz
        apb_clk_if.start_clk(12.5);
    join_none

    initial begin
        #100ns;
        apb_clk_if.assert_reset(5);
        #200ns;
        por_rst_n = 1;
        #500ns;
    end

    initial begin
        uvm_config_db#(virtual apb_if)::set(null, "*", "vif", apb_vif);
        run_test();
    end

endmodule
