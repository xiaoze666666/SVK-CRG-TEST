/***********************************************************
 * apb_if - Minimal APB3 interface
 ************************************************************/
`ifndef APB_IF__SV
`define APB_IF__SV

interface apb_if (input logic pclk, input logic preset_n);
    logic        psel;
    logic        penable;
    logic        pwrite;
    logic [31:0] paddr;
    logic [31:0] pwdata;
    logic [31:0] prdata;
    logic        pready;
    logic        pslverr;

    clocking drv_cb @(posedge pclk);
        output psel, penable, pwrite, paddr, pwdata;
        input  prdata, pready, pslverr;
    endclocking

    clocking mon_cb @(posedge pclk);
        input psel, penable, pwrite, paddr, pwdata, prdata, pready, pslverr;
    endclocking

    modport drv_mp (clocking drv_cb);
    modport mon_mp (clocking mon_cb);
endinterface
`endif
