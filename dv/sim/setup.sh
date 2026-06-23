#!/bin/bash
# setup.sh - VCS/UVM environment setup for WSL
set -e

if [ -z "$VCS_HOME" ]; then
    for cand in /opt/Synopsys/vcs/V-2023.12-SP1 /opt/Synopsys/vcs/* /opt/vcs/* /usr/local/synopsys/vcs/*; do
        if [ -x "$cand/bin/vcs" ]; then
            export VCS_HOME="$cand"
            break
        fi
    done
fi
if [ -z "$VCS_HOME" ]; then
    echo "ERROR: VCS_HOME not set." >&2
    return 1 2>/dev/null || exit 1
fi
export PATH="$VCS_HOME/bin:$PATH"

if [ -z "$UVM_HOME" ]; then
    if [ -d "$VCS_HOME/etc/uvm/src" ]; then
        export UVM_HOME="$VCS_HOME/etc/uvm"
    elif [ -d "$VCS_HOME/etc/uvm" ]; then
        export UVM_HOME="$VCS_HOME/etc/uvm"
    fi
fi

echo "VCS_HOME  = $VCS_HOME"
echo "UVM_HOME  = $UVM_HOME"
echo "vcs path  = $(command -v vcs)"

export DV_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
echo "DV_ROOT   = $DV_ROOT"
