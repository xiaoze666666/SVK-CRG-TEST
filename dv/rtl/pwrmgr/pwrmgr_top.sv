/***********************************************************
 * pwrmgr_top - Power manager IP top
 *
 * Low-power FSM + wakeup arbitration + isolation control.
 *
 * FSM states (one-hot):
 *   ACTIVE    -> normal operation
 *   ISO_ON    -> enable isolation before power down
 *   PD_ENTER  -> request clkmgr to gate, rstmgr to assert
 *   PD_WAIT   -> wait for ack
 *   PD        -> powered down (only wakeup can exit)
 *   WAKE_CLK  -> request clkmgr to ungated
 *   WAKE_RST  -> request rstmgr to release
 *   ISO_OFF   -> disable isolation
 *   ACTIVE
 *
 * Interfaces to clkmgr (pwr_main_clk_en / status) and rstmgr
 * (pwr_rst_req / status). The SoC top wires these together; in pwrmgr
 * UT they are stubbed by the testbench.
 *
 * BUG_006 (planted): on WAKE_CLK->WAKE_RST transition, iso_en is dropped
 * one cycle too early -> isolation disabled while reset still asserting.
 * Caught by pwrmgr_lowpower_vseq + SVA.
 ************************************************************/
`ifndef PWRMGR_TOP__SV
`define PWRMGR_TOP__SV

`include "../crg_reg_map.sv"

module pwrmgr_top (
    input  logic        apb_clk,
    input  logic        apb_rst_n,

    input  logic        psel,
    input  logic        penable,
    input  logic        pwrite,
    input  logic [31:0] paddr,
    input  logic [31:0] pwdata,
    output logic [31:0] prdata,
    output logic        pready,
    output logic        pslverr,

    // External wake sources
    input  logic [3:0]  wake_src_i,

    // Handshake to clkmgr
    output logic        main_clk_en_o,
    input  logic        main_clk_status_i,

    // Handshake to rstmgr
    output logic        rst_req_o,
    input  logic        rst_status_i,

    // Isolation control
    output logic        iso_en_o,
    output logic        pwr_state_o       // 1 = active, 0 = powered down
);

    import crg_reg_map_pkg::*;

    // ---- Registers ----
    logic [31:0] pwr_ctrl_q,      pwr_ctrl_next;
    logic [31:0] wake_cfg_q,      wake_cfg_next;
    logic [31:0] wake_status_q;
    logic [31:0] iso_cfg_q,       iso_cfg_next;

    logic wr_access, rd_access;
    logic [31:0] addr_off;
    assign addr_off  = {paddr[11:2], 2'b00};
    assign wr_access = psel & penable & pwrite;
    assign rd_access = psel & penable & ~pwrite;
    assign pready    = 1'b1;
    assign pslverr   = 1'b0;

    always_comb begin
        pwr_ctrl_next = pwr_ctrl_q;
        wake_cfg_next = wake_cfg_q;
        iso_cfg_next  = iso_cfg_q;
        if (wr_access) begin
            case (addr_off)
                32'h00: pwr_ctrl_next = pwdata;
                32'h04: wake_cfg_next = pwdata;
                32'h0C: iso_cfg_next  = pwdata;
                default: ;
            endcase
        end
    end

    always_ff @(posedge apb_clk or negedge apb_rst_n) begin
        if (!apb_rst_n) begin
            pwr_ctrl_q <= PWR_CTRL_RST;
            wake_cfg_q <= WAKE_CFG_RST;
            iso_cfg_q  <= ISO_CFG_RST;
        end else begin
            pwr_ctrl_q <= pwr_ctrl_next;
            wake_cfg_q <= wake_cfg_next;
            iso_cfg_q  <= iso_cfg_next;
        end
    end

    // Wake status: latched when any enabled wake source fires
    always_ff @(posedge apb_clk or negedge apb_rst_n) begin
        if (!apb_rst_n) begin
            wake_status_q <= WAKE_STATUS_RST;
        end else begin
            for (int i = 0; i < 4; i++)
                if (wake_src_i[i] && wake_cfg_q[i])
                    wake_status_q[i] <= 1'b1;
            // software clear
            if (wr_access && addr_off == 32'h08)
                wake_status_q <= wake_status_q & ~pwdata;
        end
    end

    always_comb begin
        prdata = 32'h0;
        if (rd_access) begin
            case (addr_off)
                32'h00: prdata = pwr_ctrl_q;
                32'h04: prdata = wake_cfg_q;
                32'h08: prdata = wake_status_q;
                32'h0C: prdata = iso_cfg_q;
                default: prdata = 32'h0;
            endcase
        end
    end

    logic        lowpower_req    = pwr_ctrl_q[0];
    logic [3:0]  wake_enable     = wake_cfg_q[3:0];
    logic        any_wake;
    assign any_wake = |(wake_src_i & wake_enable) || |wake_status_q[3:0];

    // ---- Low-power FSM ----
    typedef enum logic [3:0] {
        S_ACTIVE   = 4'd0,
        S_ISO_ON   = 4'd1,
        S_PD_ENTER = 4'd2,
        S_PD_WAIT  = 4'd3,
        S_PD       = 4'd4,
        S_WAKE_CLK = 4'd5,
        S_WAKE_RST = 4'd6,
        S_ISO_OFF  = 4'd7
    } state_e;

    state_e state_q, state_d;
    int     wait_cnt_q, wait_cnt_d;
    localparam int HANDSHAKE_WAIT = 8;

    always_comb begin
        state_d       = state_q;
        wait_cnt_d    = wait_cnt_q;
        main_clk_en_o = 1'b1;
        rst_req_o     = 1'b0;
        iso_en_o      = 1'b0;
        pwr_state_o   = 1'b1;

        case (state_q)
            S_ACTIVE: begin
                if (lowpower_req) begin
                    state_d    = S_ISO_ON;
                    wait_cnt_d = HANDSHAKE_WAIT;
                end
            end
            S_ISO_ON: begin
                iso_en_o = 1'b1;
                if (wait_cnt_q == 0) state_d = S_PD_ENTER;
                else                 wait_cnt_d = wait_cnt_q - 1;
            end
            S_PD_ENTER: begin
                iso_en_o      = 1'b1;
                main_clk_en_o = 1'b0;
                rst_req_o     = 1'b1;
                state_d       = S_PD_WAIT;
                wait_cnt_d    = HANDSHAKE_WAIT;
            end
            S_PD_WAIT: begin
                iso_en_o      = 1'b1;
                main_clk_en_o = 1'b0;
                rst_req_o     = 1'b1;
                pwr_state_o   = 1'b0;
                if (main_clk_status_i == 1'b0 && rst_status_i == 1'b1) state_d = S_PD;
            end
            S_PD: begin
                iso_en_o      = 1'b1;
                main_clk_en_o = 1'b0;
                rst_req_o     = 1'b1;
                pwr_state_o   = 1'b0;
                if (any_wake) begin
                    state_d    = S_WAKE_CLK;
                    wait_cnt_d = HANDSHAKE_WAIT;
                end
            end
            S_WAKE_CLK: begin
                iso_en_o      = 1'b1;
                main_clk_en_o = 1'b1;
                rst_req_o     = 1'b1;   // hold reset while clocks come back
                if (main_clk_status_i == 1'b1) begin
                    state_d = S_WAKE_RST;
                    // BUG_006: dropping iso too early
                    iso_en_o = 1'b0;
                end
            end
            S_WAKE_RST: begin
                main_clk_en_o = 1'b1;
                rst_req_o     = 1'b0;
                iso_en_o      = 1'b0;
                if (rst_status_i == 1'b0) begin
                    state_d    = S_ISO_OFF;
                    wait_cnt_d = HANDSHAKE_WAIT;
                end
            end
            S_ISO_OFF: begin
                main_clk_en_o = 1'b1;
                iso_en_o      = 1'b0;
                if (wait_cnt_q == 0) state_d = S_ACTIVE;
                else                 wait_cnt_d = wait_cnt_q - 1;
            end
            default: state_d = S_ACTIVE;
        endcase
    end

    always_ff @(posedge apb_clk or negedge apb_rst_n) begin
        if (!apb_rst_n) begin
            state_q    <= S_ACTIVE;
            wait_cnt_q <= 0;
        end else begin
            state_q    <= state_d;
            wait_cnt_q <= wait_cnt_d;
        end
    end

endmodule
`endif
