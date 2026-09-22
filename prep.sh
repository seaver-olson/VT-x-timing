#!/usr/bin/env bash
# prep.sh - put the machine in a stable state before VMX timing experiments.
#
# Usage:  sudo ./prep.sh [--cpu N] [--unload-kvm] [--no-smt] [--no-aslr]
#
#   --cpu N        core you'll pin measurements to (default: 3)
#   --unload-kvm   unload kvm_intel/kvm so your own code can do VMXON
#   --no-smt       turn off Hyper-Threading until next reboot
#   --no-aslr      disable address-space randomization until next reboot
#
# Every run writes a snapshot of the machine state to prep-logs/ so you can
# record the exact experimental conditions alongside your results.

CPU=3
UNLOAD_KVM=0
NO_SMT=0
NO_ASLR=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --cpu)        CPU="$2"; shift 2 ;;
        --unload-kvm) UNLOAD_KVM=1; shift ;;
        --no-smt)     NO_SMT=1; shift ;;
        --no-aslr)    NO_ASLR=1; shift ;;
        -h|--help)    sed -n '2,13p' "$0"; exit 0 ;;
        *) echo "Unknown option: $1 (try --help)"; exit 1 ;;
    esac
done

if [[ $EUID -ne 0 ]]; then
    echo "Run with sudo: sudo $0 $*"
    exit 1
fi

ok()   { printf '  \e[32m[ok]\e[0m   %s\n' "$1"; }
warn() { printf '  \e[33m[warn]\e[0m %s\n' "$1"; WARNINGS=$((WARNINGS + 1)); }
fail() { printf '  \e[31m[FAIL]\e[0m %s\n' "$1"; FAILURES=$((FAILURES + 1)); }
WARNINGS=0
FAILURES=0

echo "Hardware checks:"

if grep -qw vmx /proc/cpuinfo; then
    ok "VT-x (vmx) exposed"
else
    fail "vmx flag missing - enable Intel Virtualization Technology in the BIOS"
fi

if grep -qw constant_tsc /proc/cpuinfo && grep -qw nonstop_tsc /proc/cpuinfo; then
    ok "Invariant TSC (constant_tsc + nonstop_tsc)"
else
    fail "TSC is not invariant - rdtsc cycle counts will be unreliable"
fi

if [[ ! -d /sys/devices/system/cpu/cpu$CPU ]]; then
    fail "CPU $CPU does not exist"
fi

echo
echo "Frequency:"

if cpupower -c all frequency-set -g performance >/dev/null 2>&1; then
    ok "Governor set to performance"
else
    fail "Could not set governor (is cpupower installed?)"
fi

NO_TURBO=/sys/devices/system/cpu/intel_pstate/no_turbo
if [[ -w $NO_TURBO ]]; then
    echo 1 > "$NO_TURBO"
    [[ $(cat "$NO_TURBO") == 1 ]] && ok "Turbo Boost disabled" || fail "Turbo Boost still on"
else
    warn "intel_pstate/no_turbo not found - disable Turbo Boost in the BIOS instead"
fi

echo
echo "Noise reduction:"

if [[ -w /proc/sys/kernel/nmi_watchdog ]]; then
    echo 0 > /proc/sys/kernel/nmi_watchdog
    ok "NMI watchdog off (stops periodic NMIs and frees a perf counter)"
fi

if [[ -w /proc/sys/kernel/perf_event_paranoid ]]; then
    echo -1 > /proc/sys/kernel/perf_event_paranoid
    ok "perf_event_paranoid = -1 (full access to performance counters)"
fi

if (( NO_ASLR )); then
    echo 0 > /proc/sys/kernel/randomize_va_space
    ok "ASLR disabled"
fi

if (( NO_SMT )); then
    SMT_CTL=/sys/devices/system/cpu/smt/control
    if [[ -w $SMT_CTL ]]; then
        echo off > "$SMT_CTL" 2>/dev/null
        [[ $(cat "$SMT_CTL") == off ]] && ok "Hyper-Threading off" \
            || warn "Could not turn off SMT (state: $(cat "$SMT_CTL"))"
    else
        warn "SMT control unavailable - disable Hyper-Threading in the BIOS"
    fi
fi

ISOLATED=$(cat /sys/devices/system/cpu/isolated 2>/dev/null)
if [[ -n $ISOLATED ]]; then
    ok "Isolated CPUs: $ISOLATED"
else
    warn "No isolated CPUs - add isolcpus=$CPU nohz_full=$CPU to the kernel command line for the cleanest numbers"
fi

sync
echo 3 > /proc/sys/vm/drop_caches
ok "Page cache dropped"

echo
echo "VMX ownership:"

if lsmod | grep -q '^kvm_intel'; then
    if (( UNLOAD_KVM )); then
        if modprobe -r kvm_intel kvm 2>/dev/null; then
            ok "kvm_intel unloaded - VMX root mode is free"
        else
            fail "Could not unload kvm_intel (a VM may be running)"
        fi
    else
        warn "kvm_intel is loaded - it owns VMX. Rerun with --unload-kvm if your code does its own VMXON"
    fi
else
    ok "kvm_intel not loaded - VMX root mode is free"
fi

echo
echo "Current state of CPU $CPU:"

FREQ_FILE=/sys/devices/system/cpu/cpu$CPU/cpufreq/scaling_cur_freq
[[ -r $FREQ_FILE ]] && echo "  Frequency: $(( $(cat "$FREQ_FILE") / 1000 )) MHz"
echo "  Kernel:    $(uname -r)"
echo "  Pin runs:  taskset -c $CPU ./your_benchmark"

# Save a snapshot of the conditions for this session
LOG_DIR="${LOG_DIR:-$PWD/prep-logs}"
mkdir -p "$LOG_DIR"
LOG="$LOG_DIR/prep-$(date +%Y%m%d-%H%M%S).log"
{
    echo "date:              $(date -Is)"
    echo "kernel:            $(uname -r)"
    echo "cmdline:           $(cat /proc/cmdline)"
    echo "cpu model:         $(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2- | xargs)"
    echo "microcode:         $(grep -m1 microcode /proc/cpuinfo | cut -d: -f2- | xargs)"
    echo "governor:          $(cat /sys/devices/system/cpu/cpu$CPU/cpufreq/scaling_governor 2>/dev/null)"
    echo "no_turbo:          $(cat "$NO_TURBO" 2>/dev/null)"
    echo "smt:               $(cat /sys/devices/system/cpu/smt/control 2>/dev/null)"
    echo "isolated:          ${ISOLATED:-none}"
    echo "aslr:              $(cat /proc/sys/kernel/randomize_va_space)"
    echo "kvm_intel loaded:  $(lsmod | grep -q '^kvm_intel' && echo yes || echo no)"
    echo "measurement cpu:   $CPU"
    echo "cpu$CPU freq (kHz): $(cat "$FREQ_FILE" 2>/dev/null)"
    echo "warnings:          $WARNINGS"
    echo "failures:          $FAILURES"
} > "$LOG"
[[ -n ${SUDO_USER:-} ]] && chown -R "$SUDO_USER": "$LOG_DIR"

echo
if (( FAILURES )); then
    echo "Prep finished with $FAILURES failure(s) - fix these before trusting timing results."
    echo "Log: $LOG"
    exit 1
fi
echo "Ready. $WARNINGS warning(s). Log: $LOG"
