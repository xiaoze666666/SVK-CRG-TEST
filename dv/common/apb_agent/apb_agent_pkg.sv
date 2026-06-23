/***********************************************************
 * apb_agent_pkg - Reusable APB UVC
 *
 * Used by all UT and ST envs. The agent exposes:
 *   - apb_sequencer for register sequences
 *   - uvm_reg_adapter (apb_reg_adapter) for uvm_reg frontdoor
 *   - analysis_port of apb_seq_item for monitors
 ************************************************************/
`ifndef APB_AGENT_PKG__SV
`define APB_AGENT_PKG__SV

`include "apb_if.sv"

package apb_agent_pkg;
    import uvm_pkg::*;

    // ---- Transaction ----
    class apb_seq_item extends uvm_sequence_item;
        rand bit        is_write;
        rand bit [31:0] addr;
        rand bit [31:0] wdata;
             bit [31:0] rdata;
             bit        slverr;
        `uvm_object_utils_begin(apb_seq_item)
            `uvm_field_int(is_write, UVM_ALL_ON)
            `uvm_field_int(addr,     UVM_ALL_ON)
            `uvm_field_int(wdata,    UVM_ALL_ON)
            `uvm_field_int(rdata,    UVM_ALL_ON)
        `uvm_object_utils_end
        function new(string name="apb_seq_item"); super.new(name); endfunction
        constraint addr_aligned_c { addr[1:0] == 2'b00; }
    endclass

    // ---- Sequencer ----
    class apb_sequencer extends uvm_sequencer #(apb_seq_item);
        `uvm_component_utils(apb_sequencer)
        function new(string name, uvm_component parent); super.new(name, parent); endfunction
    endclass

    // ---- Driver ----
    class apb_driver extends uvm_driver #(apb_seq_item);
        `uvm_component_utils(apb_driver)
        virtual apb_if vif;
        function new(string name, uvm_component parent); super.new(name, parent); endfunction
        function void build_phase(uvm_phase phase);
            if (!uvm_config_db#(virtual apb_if)::get(this, "", "vif", vif))
                `uvm_fatal("APB_DRV", "vif not set")
        endfunction
        task run_phase(uvm_phase phase);
            vif.drv_cb.psel <= 1'b0;
            vif.drv_cb.penable <= 1'b0;
            forever begin
                apb_seq_item req;
                seq_item_port.try_next_item(req);
                if (req == null) begin @(vif.drv_cb); continue; end
                @(vif.drv_cb);
                vif.drv_cb.psel <= 1'b1; vif.drv_cb.penable <= 1'b0;
                vif.drv_cb.pwrite <= req.is_write; vif.drv_cb.paddr <= req.addr;
                if (req.is_write) vif.drv_cb.pwdata <= req.wdata;
                @(vif.drv_cb);
                vif.drv_cb.penable <= 1'b1;
                do @(vif.drv_cb); while (!vif.drv_cb.pready);
                if (!req.is_write) req.rdata = vif.drv_cb.prdata;
                req.slverr = vif.drv_cb.pslverr;
                vif.drv_cb.psel <= 1'b0; vif.drv_cb.penable <= 1'b0;
                seq_item_port.item_done();
            end
        endtask
    endclass

    // ---- Monitor ----
    class apb_monitor extends uvm_monitor;
        `uvm_component_utils(apb_monitor)
        virtual apb_if vif;
        uvm_analysis_port #(apb_seq_item) ap;
        function new(string name, uvm_component parent);
            super.new(name, parent); ap = new("ap", this);
        endfunction
        function void build_phase(uvm_phase phase);
            if (!uvm_config_db#(virtual apb_if)::get(this, "", "vif", vif))
                `uvm_fatal("APB_MON", "vif not set")
        endfunction
        task run_phase(uvm_phase phase);
            forever begin
                @(vif.mon_cb);
                if (vif.mon_cb.psel && vif.mon_cb.penable && vif.mon_cb.pready) begin
                    apb_seq_item tr = apb_seq_item::type_id::create("tr");
                    tr.is_write = vif.mon_cb.pwrite;
                    tr.addr = vif.mon_cb.paddr;
                    tr.wdata = vif.mon_cb.pwdata;
                    tr.rdata = vif.mon_cb.prdata;
                    tr.slverr = vif.mon_cb.pslverr;
                    ap.write(tr);
                end
            end
        endtask
    endclass

    // ---- Agent ----
    class apb_agent extends uvm_agent;
        `uvm_component_utils(apb_agent)
        apb_sequencer sqr;
        apb_driver    drv;
        apb_monitor   mon;
        function new(string name, uvm_component parent); super.new(name, parent); endfunction
        function void build_phase(uvm_phase phase);
            mon = apb_monitor::type_id::create("mon", this);
            if (get_is_active() == UVM_ACTIVE) begin
                sqr = apb_sequencer::type_id::create("sqr", this);
                drv = apb_driver::type_id::create("drv", this);
            end
        endfunction
        function void connect_phase(uvm_phase phase);
            if (get_is_active() == UVM_ACTIVE)
                drv.seq_item_port.connect(sqr.seq_item_export);
        endfunction
    endclass

    // ---- Reg adapter ----
    class apb_reg_adapter extends uvm_reg_adapter;
        `uvm_object_utils(apb_reg_adapter)
        function new(string name="apb_reg_adapter");
            super.new(name);
            supports_byte_enable = 0; provides_responses = 0;
        endfunction
        virtual function uvm_sequence_item reg2bus(const ref uvm_reg_bus_op rw);
            apb_seq_item tr = apb_seq_item::type_id::create("tr");
            tr.is_write = (rw.kind == UVM_WRITE);
            tr.addr = rw.addr; tr.wdata = rw.data;
            return tr;
        endfunction
        virtual function void bus2reg(uvm_sequence_item bus_item, ref uvm_reg_bus_op rw);
            apb_seq_item tr;
            if (!$cast(tr, bus_item)) `uvm_fatal("ADAPT", "bad cast")
            rw.kind = tr.is_write ? UVM_WRITE : UVM_READ;
            rw.addr = tr.addr; rw.data = tr.rdata;
            rw.status = tr.slverr ? UVM_NOT_OK : UVM_IS_OK;
        endfunction
    endclass

endpackage : apb_agent_pkg
`endif
