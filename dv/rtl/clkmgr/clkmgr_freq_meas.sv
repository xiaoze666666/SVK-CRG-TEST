/***********************************************************
 * clkmgr_freq_meas - Hardware clock frequency measurement
 *
 * Uses a slow reference clock (aon_clk, ~32kHz) to count cycles of a
 * fast target clock over a fixed window. If the count deviates from the
 * expected value by more than a configurable threshold (percent), raises
 * a recoverable / fatal error.
 *
 * Real chips implement this as a safety mechanism: if a PLL drifts or
 * a divider is misconfigured, downstream logic may fail timing. The
 * hardware measurement catches it before damage is done.
 *
 * Algorithm:
 *   1. On aon_clk, count a window of N cycles (window_size)
 *   2. Simultaneously count target_clk cycles during that window
 *   3. At window end: compare target_count vs expected_lo/expected_hi
 *   4. If outside [lo, hi], raise error flag
 *
 * Registers (driven from clkmgr reg file):
 *   - window_size   : number of aon_clk cycles per measurement
 *   - expected_count: nominal target_clk cycles per window
 *   - tolerance_pct : allowed deviation (0..50)
 *
 * BUG_007 (planted): when target_clk is stopped, the counter freezes
 *                    and the error flag is never raised (counter at 0
 *                    looks "within tolerance" if expected is also low).
 *                    This is a real bug class — clock-stop detection
 *                    needs a separate timeout.
 ************************************************************/
`ifndef CLKMGR_FREQ_MEAS__SV
`define CLKMGR_FREQ_MEAS__SV

module clkmgr_freq_meas (
    input  logic        aon_clk,        // slow reference (~32kHz typical)
    input  logic        rst_n,
    input  logic        target_clk,     // fast clock being measured
    input  logic        en,             // enable measurement
    input  logic [15:0] window_size,    // aon_clk cycles per window
    input  logic [31:0] expected_count, // nominal target cycles per window
    input  logic [6:0]  tolerance_pct,  // 0..50 (percent)
    output logic        meas_done,      // pulse at each window end
    output logic [31:0] measured_count, // last measurement
    output logic        recov_err,      // 1 if outside tolerance
    output logic        fatal_err       // 1 if target_clk stopped
);

    int     aon_cnt_q, aon_cnt_d;
    int     tgt_cnt_q, tgt_cnt_d;
    logic   busy_q, busy_d;
    logic   tgt_had_edge;

    // aon_clk-domain window counter
    always_ff @(posedge aon_clk or negedge rst_n) begin
        if (!rst_n) begin
            aon_cnt_q <= 0;
            busy_q   <= 1'b0;
        end else begin
            aon_cnt_q <= aon_cnt_d;
            busy_q   <= busy_d;
        end
    end

    always_comb begin
        aon_cnt_d = aon_cnt_q;
        busy_d = busy_q;
        if (!en) begin
            aon_cnt_d = 0;
            busy_d = 1'b0;
        end else if (!busy_q) begin
            // start new window
            aon_cnt_d = 1;
            busy_d = 1'b1;
        end else if (aon_cnt_q >= int'(window_size)) begin
            // window complete
            aon_cnt_d = 1;  // restart
            busy_d = 1'b1;
        end else begin
            aon_cnt_d = aon_cnt_q + 1;
        end
    end

    // target_clk counter (async, increments on target posedge)
    always_ff @(posedge target_clk or negedge rst_n) begin
        if (!rst_n) begin
            tgt_cnt_q <= 0;
            tgt_had_edge <= 1'b0;
        end else if (!en || !busy_q) begin
            tgt_cnt_q <= 0;
            tgt_had_edge <= 1'b0;
        end else begin
            tgt_cnt_q <= tgt_cnt_q + 1;
            tgt_had_edge <= 1'b1;
        end
    end

    // Measurement complete + comparison in aon_clk domain
    logic window_ended;
    assign window_ended = en && busy_q && (aon_cnt_q >= int'(window_size));

    always_ff @(posedge aon_clk or negedge rst_n) begin
        if (!rst_n) begin
            measured_count <= 0;
            meas_done      <= 1'b0;
            recov_err      <= 1'b0;
            fatal_err      <= 1'b0;
        end else begin
            meas_done <= 1'b0;
            if (window_ended) begin
                measured_count <= tgt_cnt_q;
                meas_done      <= 1'b1;
                // tolerance check
                begin : tol_check
                    int lo, hi, tol;
                    tol = int'(expected_count) * int'(tolerance_pct) / 100;
                    lo = int'(expected_count) - tol;
                    hi = int'(expected_count) + tol;
                    if (tgt_cnt_q < lo || tgt_cnt_q > hi)
                        recov_err <= 1'b1;
                    else
                        recov_err <= 1'b0;
                end
                // BUG_007: if target_clk never toggled (tgt_had_edge=0),
                //          tgt_cnt_q=0 which may be "within tolerance"
                //          if expected is also small. Real bug: need
                //          separate timeout to detect clock stop.
                if (!tgt_had_edge && int'(window_size) > 100)
                    fatal_err <= 1'b1;   // (this is the fix; bug would omit this)
                else
                    fatal_err <= 1'b0;
            end
        end
    end

endmodule
`endif
