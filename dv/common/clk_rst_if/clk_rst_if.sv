/***********************************************************
 * clk_rst_if - clock+reset interface
 *
 * Active-driver style (set_active() flips into drive mode). Used by every
 * UT and ST tb.
 ************************************************************/
`ifndef CLK_RST_IF__SV
`define CLK_RST_IF__SV

interface clk_rst_if;
    logic clk;
    logic rst_n;
    bit   is_active = 0;

    // Driver helpers
    function void set_active();
        is_active = 1;
    endfunction

    task automatic start_clk(input real period_ns);
        if (!is_active) return;
        clk = 1'b0;
        forever begin
            #(period_ns/2.0);
            clk = ~clk;
        end
    endtask

    task automatic assert_reset(input int cycles);
        if (!is_active) return;
        rst_n = 1'b0;
        repeat(cycles) @(posedge clk);
        rst_n = 1'b1;
    endtask

    task automatic set_reset(input bit v);
        if (!is_active) return;
        rst_n = ~v;
    endtask

    // Glitch injection: drive rst_n low for glitch_ns then back high
    task automatic inject_glitch(input real glitch_ns);
        if (!is_active) return;
        rst_n = 1'b0;
        #(glitch_ns);
        rst_n = 1'b1;
    endtask

endinterface
`endif
