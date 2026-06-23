/***********************************************************
 * csr_utils_pkg - Standard CSR compliance sequences (simplified cip_lib)
 *
 *   csr_hw_reset_seq : after reset, read every CSR; must equal spec reset
 *   csr_bit_bash_seq : for each RW bit, write 1 then 0, read back, verify
 *   csr_aliasing_seq : write all-1s and all-0s to each CSR, no aliasing
 *
 * uvm_reg::write/read signature:
 *   write(status, value, path, map, parent, prior, ext, fname, lineno)
 ************************************************************/
`ifndef CSR_UTILS_PKG__SV
`define CSR_UTILS_PKG__SV

package csr_utils_pkg;
    import uvm_pkg::*;

    // helper: compute RW mask of a reg by OR-ing its RW fields' bit-ranges
    function automatic uvm_reg_data_t reg_field_mask(uvm_reg rg);
        uvm_reg_field flds[$];
        uvm_reg_data_t m = 0;
        rg.get_fields(flds);
        foreach (flds[i]) begin
            if (flds[i].get_access() == "RO") continue;
            for (int b = flds[i].get_lsb_pos();
                 b < flds[i].get_lsb_pos() + flds[i].get_n_bits(); b++)
                m[b] = 1'b1;
        end
        return m;
    endfunction

    // ---- csr_hw_reset_seq ----
    class csr_hw_reset_seq extends uvm_sequence;
        `uvm_object_utils(csr_hw_reset_seq)
        `uvm_declare_p_sequencer(uvm_sequencer)
        uvm_reg_block rm;
        function new(string name="csr_hw_reset_seq"); super.new(name); endfunction
        task body();
            uvm_reg regs[$];
            uvm_status_e status;
            rm.get_registers(regs);
            foreach (regs[i]) begin
                regs[i].mirror(status, UVM_CHECK, UVM_FRONTDOOR, null, this);
            end
        endtask
    endclass

    // ---- csr_bit_bash_seq ----
    class csr_bit_bash_seq extends uvm_sequence;
        `uvm_object_utils(csr_bit_bash_seq)
        `uvm_declare_p_sequencer(uvm_sequencer)
        uvm_reg_block rm;
        function new(string name="csr_bit_bash_seq"); super.new(name); endfunction
        task body();
            uvm_reg regs[$];
            uvm_status_e status;
            uvm_reg_data_t mask, wval, rdat;
            rm.get_registers(regs);
            foreach (regs[i]) begin
                if (regs[i].get_rights() == "RO") continue;
                mask = reg_field_mask(regs[i]);
                for (int b = 0; b < 32; b++) begin
                    if (!mask[b]) continue;
                    wval = (1 << b);
                    regs[i].write(status, wval, UVM_FRONTDOOR, null, this);
                    regs[i].read(status, rdat, UVM_FRONTDOOR, null, this);
                    if ((rdat & mask) !== (wval & mask))
                        `uvm_error("CSR_BB", $sformatf("%s bit %0d: wrote %h, read %h",
                            regs[i].get_name(), b, wval & mask, rdat & mask))
                    regs[i].write(status, 0, UVM_FRONTDOOR, null, this);
                end
            end
        endtask
    endclass

    // ---- csr_aliasing_seq ----
    class csr_aliasing_seq extends uvm_sequence;
        `uvm_object_utils(csr_aliasing_seq)
        `uvm_declare_p_sequencer(uvm_sequencer)
        uvm_reg_block rm;
        function new(string name="csr_aliasing_seq"); super.new(name); endfunction
        task body();
            uvm_reg regs[$];
            uvm_status_e status;
            uvm_reg_data_t mask, v;
            uvm_reg_data_t others[$];
            int k;
            rm.get_registers(regs);
            foreach (regs[i]) begin
                if (regs[i].get_rights() == "RO") continue;
                mask = reg_field_mask(regs[i]);
                others.delete();
                foreach (regs[j]) begin
                    if (i == j) continue;
                    regs[j].read(status, v, UVM_FRONTDOOR, null, this);
                    others.push_back(v);
                end
                regs[i].write(status, 32'hFFFF_FFFF & mask, UVM_FRONTDOOR, null, this);
                regs[i].write(status, 32'h0, UVM_FRONTDOOR, null, this);
                k = 0;
                foreach (regs[j]) begin
                    if (i == j) continue;
                    regs[j].read(status, v, UVM_FRONTDOOR, null, this);
                    if (v !== others[k])
                        `uvm_error("CSR_AL", $sformatf("%s aliased when bashing %s",
                            regs[j].get_name(), regs[i].get_name()))
                    k++;
                end
            end
        endtask
    endclass

endpackage : csr_utils_pkg
`endif
