/***********************************************************
 * clkmgr UT tb - test harness
 *
 * Wires clkmgr_top as DUT, drives osc/xtal via clk_rst_if, drives APB
 * via apb_if. Samples internal clocks via probes (hierarchical refs).
 ************************************************************/
`timescale 1ns/1ps
`include "apb_if.sv"
`include "clk_rst_if.sv"
`include "clkmgr_top.sv"

module tb;
    import uvm_pkg::*;
    import apb_agent_pkg::*;
    import clkmgr_env_pkg::*;
    import clkmgr_test_pkg::*;

    logic osc_clk;
    logic xtal_clk;
    logic apb_clk;
    logic apb_rst_n;

    // Interfaces
    clk_rst_if osc_if();
    clk_rst_if xtal_if();
    clk_rst_if apb_clk_if();
    apb_if      apb_vif(.pclk(apb_clk), .preset_n(apb_rst_n));

    assign osc_clk    = osc_if.clk;
    assign xtal_clk   = xtal_if.clk;
    assign apb_clk    = apb_clk_if.clk;
    assign apb_rst_n  = apb_clk_if.rst_n;

    // pwrmgr handshake stub
    logic main_clk_en_w;
    logic main_clk_status_w;  // driven by DUT
    assign main_clk_en_w    = 1'b1;

    // DUT outputs
    logic pll_clk, div_clk, cpu_clk, gpu_clk, ddr_clk;
    logic cpu_clk_g, gpu_clk_g, ddr_clk_g;
    logic pll_lock;

    clkmgr_top dut (
        .apb_clk(apb_clk), .apb_rst_n(apb_rst_n),
        .psel(apb_vif.psel), .penable(apb_vif.penable),
        .pwrite(apb_vif.pwrite), .paddr(apb_vif.paddr), .pwdata(apb_vif.pwdata),
        .prdata(apb_vif.prdata), .pready(apb_vif.pready), .pslverr(apb_vif.pslverr),
        .osc_clk(osc_clk), .xtal_clk(xtal_clk), .osc_period_ns(25.0),
        .pwr_main_clk_en(main_clk_en_w), .pwr_main_clk_status(main_clk_status_w),
        .pll_clk(pll_clk), .div_clk(div_clk),
        .cpu_clk(cpu_clk), .gpu_clk(gpu_clk), .ddr_clk(ddr_clk),
        .cpu_clk_g(cpu_clk_g), .gpu_clk_g(gpu_clk_g), .ddr_clk_g(ddr_clk_g),
        .pll_lock(pll_lock)
    );

    // passive clock monitor: sample pll_clk periodically and push to scoreboard.
    // Measures period between two consecutive posedges, posts to sb.
    // Feeds BUG_002 detection (PLL frac freq mismatch).
    initial begin
        clkmgr_env_pkg::clkmgr_scoreboard sb;
        uvm_component c;

        forever begin
            if (sb == null) begin
                c = uvm_top.find("uvm_test_top.env.sb");
                if (c != null) $cast(sb, c);
            end
            #2000ns;
            begin
                clkmgr_env_pkg::clk_sample_tr tr = clkmgr_env_pkg::clk_sample_tr::type_id::create("tr");
                time t_start, t_end; int rise_count=0; real first_period=0;
                fork
                    begin
                        wait (pll_clk === 1'b0 || pll_clk === 1'b1);
                        @(posedge pll_clk);
                        t_start = $time;
                        @(posedge pll_clk);
                        t_end = $time;
                        first_period = real'(t_end - t_start);
                        rise_count = 2;
                    end
                    begin #1500ns; end
                join_any disable fork;
                tr.node = "pll_clk";
                tr.s.period_ns = (rise_count == 2) ? first_period : 0.0;
                tr.s.duty = 0.5;
                tr.s.glitch = 0;
                tr.s.stopped = (rise_count < 2);
                if (sb != null) sb.write(tr);
            end
        end
    end

    // initial drivers
    initial begin
        osc_if.set_active(); xtal_if.set_active(); apb_clk_if.set_active();
        osc_if.rst_n = 1'b1; xtal_if.rst_n = 1'b1;
        apb_clk_if.rst_n = 1'b0;
        apb_vif.psel = 0; apb_vif.penable = 0; apb_vif.pwrite = 0;
        apb_vif.paddr = 0; apb_vif.pwdata = 0;
    end

    // clocks
    initial fork
        osc_if.start_clk(25.0);    // 40 MHz
        xtal_if.start_clk(20.0);   // 50 MHz
        apb_clk_if.start_clk(12.5); // 80 MHz
    join_none

    // reset sequence
    initial begin
        #100ns;
        apb_clk_if.assert_reset(5);
        #200ns;
    end

    initial begin
        uvm_config_db#(virtual apb_if)::set(null, "*", "vif", apb_vif);
        run_test();
    end

    // global timeout safeguard
    initial begin
        #100000ns;
        $display("[TB] FATAL: global timeout at %0t", $time);
        $finish;
    end

endmodule
