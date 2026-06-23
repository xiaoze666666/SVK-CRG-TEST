#!/bin/bash
cd /mnt/d/SVK-CRG-TEST/dv/sim/work
for entry in "simv_ut_clkmgr clkmgr_smoke_test" \
             "simv_ut_rstmgr rstmgr_smoke_test" \
             "simv_ut_pwrmgr pwrmgr_smoke_test" \
             "simv_st crg_top_smoke_test"; do
    sim=$(echo $entry | awk '{print $1}')
    t=$(echo $entry | awk '{print $2}')
    echo "=== $sim  $t ==="
    timeout 60 ./$sim +UVM_TESTNAME=$t +ntb_random_seed=1 +UVM_NO_RELNOTES +UVM_VERBOSITY=UVM_LOW 2>&1 \
        | grep -E "UVM_ERROR|UVM_FATAL|finish at" | head -5
done
