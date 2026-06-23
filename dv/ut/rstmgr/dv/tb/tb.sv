/***********************************************************
 * rstmgr UT tb - test harness
 ************************************************************/
`timescale 1ns/1ps
`include "apb_if.sv"
`include "clk_rst_if.sv"
`include "rstmgr_top.sv"

module tb;
    import uvm_pkg::*;
    import apb_agent_pkg::*;
    import rstmgr_env_pkg::*;
    import rstmgr_test_pkg::*;

    logic apb_clk;
    logic apb_rst_n;
    logic por_rst_n;
    logic wdg_rst_n, dbg_rst_n, sw_rst_n;
    logic cpu_clk, gpu_clk, ddr_clk;

    clk_rst_if apb_clk_if();
    clk_rst_if cpu_clk_if();
    clk_rst_if gpu_clk_if();
    clk_rst_if ddr_clk_if();
    apb_if      apb_vif(.pclk(apb_clk), .preset_n(apb_rst_n));

    assign apb_clk    = apb_clk_if.clk;
    assign apb_rst_n  = apb_clk_if.rst_n;
    assign cpu_clk    = cpu_clk_if.clk;
    assign gpu_clk    = gpu_clk_if.clk;
    assign ddr_clk    = ddr_clk_if.clk;

    logic cpu_rst_n, gpu_rst_n, ddr_rst_n;
    logic [31:0] rst_reason;

    rstmgr_top dut (
        .apb_clk(apb_clk), .apb_rst_n(apb_rst_n),
        .psel(apb_vif.psel), .penable(apb_vif.penable),
        .pwrite(apb_vif.pwrite), .paddr(apb_vif.paddr), .pwdata(apb_vif.pwdata),
        .prdata(apb_vif.prdata), .pready(apb_vif.pready), .pslverr(apb_vif.pslverr),
        .por_rst_n(por_rst_n), .wdg_rst_n(wdg_rst_n),
        .dbg_rst_n(dbg_rst_n), .sw_rst_n(sw_rst_n),
        .cpu_clk(cpu_clk), .gpu_clk(gpu_clk), .ddr_clk(ddr_clk),
        .cpu_rst_n(cpu_rst_n), .gpu_rst_n(gpu_rst_n), .ddr_rst_n(ddr_rst_n),
        .rst_reason_o(rst_reason)
    );

    initial begin
        apb_clk_if.set_active(); cpu_clk_if.set_active();
        gpu_clk_if.set_active(); ddr_clk_if.set_active();
        por_rst_n = 0; wdg_rst_n = 1; dbg_rst_n = 1; sw_rst_n = 1;
        apb_clk_if.rst_n = 0;
        apb_vif.psel = 0; apb_vif.penable = 0; apb_vif.pwrite = 0;
        apb_vif.paddr = 0; apb_vif.pwdata = 0;
    end

    initial fork
        apb_clk_if.start_clk(10.0);  // 100 MHz
        cpu_clk_if.start_clk(5.0);   // 200 MHz
        gpu_clk_if.start_clk(4.0);   // 250 MHz
        ddr_clk_if.start_clk(7.5);   // 133 MHz
    join_none

    initial begin
        #100ns;
        apb_clk_if.assert_reset(5);
        #200ns;
        por_rst_n = 1; // release POR
        #200ns;
    end

    initial begin
        uvm_config_db#(virtual apb_if)::set(null, "*", "vif", apb_vif);
        run_test();
    end

endmodule
