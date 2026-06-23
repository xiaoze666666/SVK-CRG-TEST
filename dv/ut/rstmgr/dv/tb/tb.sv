/***********************************************************
 * rstmgr UT tb - 8-domain reset tree
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

    logic apb_clk, apb_rst_n;
    logic por_rst_n, wdg_rst_n, dbg_rst_n, sw_rst_n, low_volt_n, sec_rst_n;

    // 8 domain clocks
    logic cpu_core_clk, cpu_aclk, axi_main_clk, ddr_ref_clk;
    logic ahb_clk, periph_clk, gmac_clk, qspi_clk;

    clk_rst_if apb_clk_if();
    clk_rst_if d0_clk_if();
    clk_rst_if d1_clk_if();
    clk_rst_if d2_clk_if();
    clk_rst_if d3_clk_if();
    clk_rst_if d4_clk_if();
    clk_rst_if d5_clk_if();
    clk_rst_if d6_clk_if();
    clk_rst_if d7_clk_if();
    apb_if      apb_vif(.pclk(apb_clk), .preset_n(apb_rst_n));

    assign apb_clk    = apb_clk_if.clk;
    assign apb_rst_n  = apb_clk_if.rst_n;
    assign cpu_core_clk = d0_clk_if.clk;
    assign cpu_aclk     = d1_clk_if.clk;
    assign axi_main_clk = d2_clk_if.clk;
    assign ddr_ref_clk  = d3_clk_if.clk;
    assign ahb_clk      = d4_clk_if.clk;
    assign periph_clk   = d5_clk_if.clk;
    assign gmac_clk     = d6_clk_if.clk;
    assign qspi_clk     = d7_clk_if.clk;

    logic [7:0] domain_rst_n;
    logic [31:0] rst_reason;

    rstmgr_top dut (
        .apb_clk(apb_clk), .apb_rst_n(apb_rst_n),
        .psel(apb_vif.psel), .penable(apb_vif.penable),
        .pwrite(apb_vif.pwrite), .paddr(apb_vif.paddr), .pwdata(apb_vif.pwdata),
        .prdata(apb_vif.prdata), .pready(apb_vif.pready), .pslverr(apb_vif.pslverr),
        .por_rst_n(por_rst_n), .wdg_rst_n(wdg_rst_n),
        .dbg_rst_n(dbg_rst_n), .sw_rst_n(sw_rst_n),
        .low_volt_n(low_volt_n), .sec_rst_n(sec_rst_n),
        .cpu_core_clk(cpu_core_clk), .cpu_aclk(cpu_aclk),
        .axi_main_clk(axi_main_clk), .ddr_ref_clk(ddr_ref_clk),
        .ahb_clk(ahb_clk), .periph_clk(periph_clk),
        .gmac_clk(gmac_clk), .qspi_clk(qspi_clk),
        .domain_rst_n(domain_rst_n),
        .rst_reason_o(rst_reason)
    );

    initial begin
        apb_clk_if.set_active();
        for (int i = 0; i < 8; i++) begin
            case (i)
                0: d0_clk_if.set_active();
                1: d1_clk_if.set_active();
                2: d2_clk_if.set_active();
                3: d3_clk_if.set_active();
                4: d4_clk_if.set_active();
                5: d5_clk_if.set_active();
                6: d6_clk_if.set_active();
                7: d7_clk_if.set_active();
            endcase
        end
        por_rst_n = 0; wdg_rst_n = 1; dbg_rst_n = 1; sw_rst_n = 1;
        low_volt_n = 1; sec_rst_n = 1;
        apb_clk_if.rst_n = 0;
        apb_vif.psel = 0; apb_vif.penable = 0; apb_vif.pwrite = 0;
        apb_vif.paddr = 0; apb_vif.pwdata = 0;
    end

    initial fork
        apb_clk_if.start_clk(10.0);
        d0_clk_if.start_clk(5.0);    // cpu_core 200MHz
        d1_clk_if.start_clk(4.0);    // cpu_aclk 250MHz
        d2_clk_if.start_clk(6.0);    // axi 166MHz
        d3_clk_if.start_clk(3.0);    // ddr 333MHz
        d4_clk_if.start_clk(8.0);    // ahb 125MHz
        d5_clk_if.start_clk(20.0);   // periph 50MHz
        d6_clk_if.start_clk(16.0);   // gmac 62.5MHz
        d7_clk_if.start_clk(12.0);   // qspi 83MHz
    join_none

    initial begin
        #100ns;
        apb_clk_if.assert_reset(5);
        #200ns;
        por_rst_n = 1;
        #200ns;
    end

    initial begin
        uvm_config_db#(virtual apb_if)::set(null, "*", "vif", apb_vif);
        run_test();
    end

    initial begin
        #200000ns;
        $display("[TB] FATAL: global timeout at %0t", $time);
        $finish;
    end

endmodule
