/***********************************************************
 * clkmgr UT tb - 3-PLL clock tree, 10-leaf monitor
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
    logic apb_clk;
    logic apb_rst_n;
    logic gmac_rx_clk;

    clk_rst_if osc_if();
    clk_rst_if apb_clk_if();
    apb_if      apb_vif(.pclk(apb_clk), .preset_n(apb_rst_n));

    assign osc_clk   = osc_if.clk;
    assign apb_clk   = apb_clk_if.clk;
    assign apb_rst_n = apb_clk_if.rst_n;

    // GMAC RX external clock (125MHz)
    initial begin
        gmac_rx_clk = 1'b0;
        forever begin #(4.0); gmac_rx_clk = ~gmac_rx_clk; end
    end

    // pwrmgr handshake stub
    logic main_clk_en_w;
    logic main_clk_status_w;
    assign main_clk_en_w = 1'b1;

    // DUT outputs
    logic pll_cpu_lock, pll_soc_lock, pll_peri_lock;
    logic cpu_core_clk, cpu_aclk, axi_main_clk, ddr_ref_clk;
    logic ahb_clk, apb_leaf_clk, periph_clk, gmac_tx_clk, gmac_rx_clk_o, qspi_ref_clk;

    clkmgr_top dut (
        .apb_clk(apb_clk), .apb_rst_n(apb_rst_n),
        .psel(apb_vif.psel), .penable(apb_vif.penable),
        .pwrite(apb_vif.pwrite), .paddr(apb_vif.paddr), .pwdata(apb_vif.pwdata),
        .prdata(apb_vif.prdata), .pready(apb_vif.pready), .pslverr(apb_vif.pslverr),
        .osc_clk(osc_clk), .osc_period_ns(25.0),
        .gmac_rx_clk_i(gmac_rx_clk),
        .pwr_main_clk_en(main_clk_en_w), .pwr_main_clk_status(main_clk_status_w),
        .pll_cpu_lock(pll_cpu_lock), .pll_soc_lock(pll_soc_lock), .pll_peri_lock(pll_peri_lock),
        .cpu_core_clk(cpu_core_clk), .cpu_aclk(cpu_aclk),
        .axi_main_clk(axi_main_clk), .ddr_ref_clk(ddr_ref_clk),
        .ahb_clk(ahb_clk), .apb_leaf_clk(apb_leaf_clk),
        .periph_clk(periph_clk), .gmac_tx_clk(gmac_tx_clk),
        .gmac_rx_clk(gmac_rx_clk_o), .qspi_ref_clk(qspi_ref_clk)
    );

    // ---- 10-leaf monitor: sample each leaf periodically, post to sb ----
    // leaf ids match clkmgr_env_pkg::leaf_e
    task automatic sample_leaf(input int id, input logic sig, input clkmgr_env_pkg::clkmgr_scoreboard sb);
        clkmgr_env_pkg::clk_sample_tr tr;
        time t0, t1; int rc; real p;
        tr = clkmgr_env_pkg::clk_sample_tr::type_id::create("tr");
        fork
            begin
                wait (sig === 1'b0 || sig === 1'b1);
                @(posedge sig); t0 = $time;
                @(posedge sig); t1 = $time;
                p = real'(t1 - t0); rc = 2;
            end
            begin #1500ns; end
        join_any disable fork;
        tr.leaf_id = id;
        tr.period_ns = (rc == 2) ? p : 0.0;
        tr.glitch = 0; tr.stopped = (rc < 2);
        sb.write(tr);
    endtask

    initial begin
        clkmgr_env_pkg::clkmgr_scoreboard sb;
        uvm_component c;
        // wait env built
        #1;
        forever begin
            if (sb == null) begin
                c = uvm_top.find("uvm_test_top.env.sb");
                if (c != null) $cast(sb, c);
            end
            #2500ns;
            if (sb != null) begin
                sample_leaf(clkmgr_env_pkg::LEAF_CPU_CORE, cpu_core_clk, sb);
                sample_leaf(clkmgr_env_pkg::LEAF_AXI_MAIN, axi_main_clk, sb);
                sample_leaf(clkmgr_env_pkg::LEAF_DDR_REF,  ddr_ref_clk, sb);
                sample_leaf(clkmgr_env_pkg::LEAF_AHB,      ahb_clk, sb);
                sample_leaf(clkmgr_env_pkg::LEAF_PERIPH,   periph_clk, sb);
                sample_leaf(clkmgr_env_pkg::LEAF_GMAC_TX,  gmac_tx_clk, sb);
                sample_leaf(clkmgr_env_pkg::LEAF_QSPI_REF, qspi_ref_clk, sb);
            end
        end
    end

    // initial drivers
    initial begin
        osc_if.set_active(); apb_clk_if.set_active();
        apb_clk_if.rst_n = 1'b0;
        apb_vif.psel = 0; apb_vif.penable = 0; apb_vif.pwrite = 0;
        apb_vif.paddr = 0; apb_vif.pwdata = 0;
    end

    // clocks
    initial fork
        osc_if.start_clk(25.0);    // 40 MHz (will PLL up)
        apb_clk_if.start_clk(10.0); // 100 MHz
    join_none

    initial begin
        #100ns;
        apb_clk_if.assert_reset(5);
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
