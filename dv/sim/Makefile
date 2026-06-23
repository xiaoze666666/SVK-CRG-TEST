# Makefile - G100 CRG verification (UT + ST)
#
# Usage:
#   source setup.sh
#   make ut_clkmgr_smoke        # run clkmgr smoke test
#   make ut_clkmgr_common       # run CSR three-set on clkmgr
#   make ut_rstmgr_smoke
#   make ut_pwrmgr_smoke
#   make st_lowpower
#   make ut_clkmgr_all          # run all clkmgr UT tests
#   make all                    # run everything

ifndef DV_ROOT
$(error DV_ROOT not set. Run: source setup.sh)
endif

VCS      ?= vcs
SEED      ?= 1
WORK      = work

VCS_OPTS  = -full64 -sverilog +vc -Mupdate -timescale=1ns/1ps
VCS_OPTS += -ntb_opts uvm-1.2 +incdir+$(UVM_HOME)/src +define+UVM_NO_DPI
VCS_OPTS += -cm line+cond+fsm+tgl+branch -cm_dir $(WORK)/crg.cm
VCS_OPTS += +warn=noUI +warn=noLCA +warn=noMMVCCM

SIM_OPTS  = +ntb_random_seed=$(SEED)
SIM_OPTS += -cm line+cond+fsm+tgl+branch -cm_dir $(WORK)/crg.cm
SIM_OPTS += +UVM_VERBOSITY=UVM_HIGH

# Map "make ut_clkmgr_smoke" -> filelist_ut_clkmgr.f + UVM_TESTNAME=clkmgr_smoke_test
UT_K_TESTS = smoke common div gate mux frequency stress
UT_R_TESTS = smoke common glitch sync reason stress
UT_P_TESTS = smoke common lowpower wake iso stress
ST_TESTS   = smoke lowpower reset_storm stress

# Pattern rules for individual tests
define MAKE_UT_RULE
ut_clkmgr_$(1): compile_ut_clkmgr
	cd $(WORK) && ./simv_ut_clkmgr $(SIM_OPTS) +UVM_TESTNAME=clkmgr_$(1)_test -l ut_clkmgr_$(1).log
endef
$(foreach t,$(UT_K_TESTS),$(eval $(MAKE_UT_RULE)))

define MAKE_UT_R_RULE
ut_rstmgr_$(1): compile_ut_rstmgr
	cd $(WORK) && ./simv_ut_rstmgr $(SIM_OPTS) +UVM_TESTNAME=rstmgr_$(1)_test -l ut_rstmgr_$(1).log
endef
$(foreach t,$(UT_R_TESTS),$(eval $(MAKE_UT_R_RULE)))

define MAKE_UT_P_RULE
ut_pwrmgr_$(1): compile_ut_pwrmgr
	cd $(WORK) && ./simv_ut_pwrmgr $(SIM_OPTS) +UVM_TESTNAME=pwrmgr_$(1)_test -l ut_pwrmgr_$(1).log
endef
$(foreach t,$(UT_P_TESTS),$(eval $(MAKE_UT_P_RULE)))

define MAKE_ST_RULE
st_$(1): compile_st
	cd $(WORK) && ./simv_st $(SIM_OPTS) +UVM_TESTNAME=crg_top_$(1)_test -l st_$(1).log
endef
$(foreach t,$(ST_TESTS),$(eval $(MAKE_ST_RULE)))

.PHONY: all clean compile_ut_clkmgr compile_ut_rstmgr compile_ut_pwrmgr compile_st
.PHONY: ut_clkmgr_all ut_rstmgr_all ut_pwrmgr_all st_all

all: ut_clkmgr_all ut_rstmgr_all ut_pwrmgr_all st_all

$(WORK):
	mkdir -p $(WORK)

compile_ut_clkmgr: $(WORK)
	cd $(WORK) && $(VCS) $(VCS_OPTS) -f $(DV_ROOT)/sim/filelist_ut_clkmgr.f -o simv_ut_clkmgr -l compile_ut_clkmgr.log

compile_ut_rstmgr: $(WORK)
	cd $(WORK) && $(VCS) $(VCS_OPTS) -f $(DV_ROOT)/sim/filelist_ut_rstmgr.f -o simv_ut_rstmgr -l compile_ut_rstmgr.log

compile_ut_pwrmgr: $(WORK)
	cd $(WORK) && $(VCS) $(VCS_OPTS) -f $(DV_ROOT)/sim/filelist_ut_pwrmgr.f -o simv_ut_pwrmgr -l compile_ut_pwrmgr.log

compile_st: $(WORK)
	cd $(WORK) && $(VCS) $(VCS_OPTS) -f $(DV_ROOT)/sim/filelist_st.f -o simv_st -l compile_st.log

ut_clkmgr_all: compile_ut_clkmgr
	@for t in $(UT_K_TESTS); do echo "#### ut_clkmgr_$$t"; $(MAKE) ut_clkmgr_$$t || true; done

ut_rstmgr_all: compile_ut_rstmgr
	@for t in $(UT_R_TESTS); do echo "#### ut_rstmgr_$$t"; $(MAKE) ut_rstmgr_$$t || true; done

ut_pwrmgr_all: compile_ut_pwrmgr
	@for t in $(UT_P_TESTS); do echo "#### ut_pwrmgr_$$t"; $(MAKE) ut_pwrmgr_$$t || true; done

st_all: compile_st
	@for t in $(ST_TESTS); do echo "#### st_$$t"; $(MAKE) st_$$t || true; done

clean:
	rm -rf $(WORK)
