/***********************************************************
 * pwrmgr UT tb
 ************************************************************/
`timescale 1ns/1ps
`include "apb_if.sv"
`include "clk_rst_if.sv"
`include "pwrmgr_top.sv"

module tb;
    import uvm_pkg::*;
    import apb_agent_pkg::*;
    import pwrmgr_env_pkg::*;
    import pwrmgr_test_pkg::*;

    logic apb_clk;
    logic apb_rst_n;
    logic [3:0] wake_src;

    clk_rst_if apb_clk_if();
    apb_if      apb_vif(.pclk(apb_clk), .preset_n(apb_rst_n));

    assign apb_clk    = apb_clk_if.clk;
    assign apb_rst_n  = apb_clk_if.rst_n;

    logic main_clk_en_w, main_clk_status_w;
    logic rst_req_w, rst_status_w;
    logic iso_en, pwr_state;
    assign main_clk_status_w = main_clk_en_w;
    assign rst_status_w = 0;

    pwrmgr_top dut (
        .apb_clk(apb_clk), .apb_rst_n(apb_rst_n),
        .psel(apb_vif.psel), .penable(apb_vif.penable),
        .pwrite(apb_vif.pwrite), .paddr(apb_vif.paddr), .pwdata(apb_vif.pwdata),
        .prdata(apb_vif.prdata), .pready(apb_vif.pready), .pslverr(apb_vif.pslverr),
        .wake_src_i(wake_src),
        .main_clk_en_o(main_clk_en_w), .main_clk_status_i(main_clk_status_w),
        .rst_req_o(rst_req_w), .rst_status_i(rst_status_w),
        .iso_en_o(iso_en), .pwr_state_o(pwr_state)
    );

    // auto fire wake source periodically (simulates wake from external)
    initial begin
        wake_src = 0;
        forever begin
            #8000ns;
            wake_src = 4'b0001;
            #200ns;
            wake_src = 4'b0000;
        end
    end

    initial begin
        apb_clk_if.set_active();
        apb_clk_if.rst_n = 0;
        apb_vif.psel = 0; apb_vif.penable = 0; apb_vif.pwrite = 0;
        apb_vif.paddr = 0; apb_vif.pwdata = 0;
    end

    initial fork
        apb_clk_if.start_clk(10.0);
    join_none

    initial begin
        #100ns;
        apb_clk_if.assert_reset(5);
        #200ns;
    end

    initial begin
        uvm_config_db#(virtual apb_if)::set(null, "*", "vif", apb_vif);
        run_test();
    end

endmodule
