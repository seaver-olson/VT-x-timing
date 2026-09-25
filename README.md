# RDMSR timing on Skylake

To feed a saved CSV into the three future VMX test stubs, use one command:

```sh
make calibrate CSV=results/your-rdmsr-test.csv
```

This validates the CSV and generates `build/vmx_calibration.h`, which all
three C files include through the same hook. It also builds three programs:
`build/vmx_main`, `build/vmx_entry_exit`, and `build/vmx_other`. They only
print the calibration; no VMX tests are implemented. The third category
is intentionally unnamed until its purpose is decided.

`RDMSR_OVERHEAD_TSC_TICKS` is median RDMSR bracket minus median empty bracket
(90 TSC ticks for the initial saved run). The header also records the MSR,
CPU, sample count, and empty-bracket median. Re-run calibration on each
machine and rebuild the stubs whenever you change the input CSV.
This value characterizes RDMSR cost; do not automatically subtract it once
or twice from VMX timings. A future timing harness must measure its own
bracket overhead, and APERF deltas are not in the same units as TSC ticks.
Generated headers and executables stay in `build/`; `make clean` removes them.

This starting benchmark measures native `RDMSR IA32_APERF` (`0xE8`) in
kernel mode on one logical CPU. It measures instruction execution, excluding
syscall, `/dev/cpu/N/msr`, and cross-CPU request overhead.

Build against the running kernel's headers, then run from this directory:

```sh
make
bash run.sh                    # CPU 3, 10000 samples, MSR 0xe8
bash run.sh 3 10000 0xe7        # optional MPERF comparison
bash run.sh 3 10000 0x10        # optional TSC MSR comparison
```

Generated module files stay in `build/`; `make clean` removes that directory.
The `pahole version differs` warning means the installed debug-information
tool (1.32 here) differs from the one used to build the kernel (1.31).
It did not prevent this module from building successfully. A warning alone
does not mean the build failed; check for actual errors and the make exit status.

The runner needs working `sudo` authentication to load/unload the module and
read its root-only `/proc/rdmsr_bench` file. It saves CSV in `results/`, prints
statistics, and unloads the module on exit. Loading an out-of-tree module
taints the kernel; module signing/lockdown policy may prevent loading it.
No MSRs are written and no VMX instructions are executed. KVM need not be
unloaded for this test. Rebuild after changing kernels.

Each insertion performs 1000 warmup pairs, then collects the requested number
of pairs (1–1000000). Measurements run on the selected online CPU with
preemption and local maskable interrupts disabled for each pair, restoring
them between pairs. The order alternates to reduce ordering bias. An MSR
fault-safe probe precedes the bare instruction measurements. Only the three
MSRs listed above are allowed; advertised virtual machines are rejected.

The measurement bracket is:

```text
LFENCE; RDTSC; LFENCE
save start EDX:EAX to registers
load MSR index into ECX
RDMSR                         # omitted in the empty bracket
LFENCE; RDTSC; LFENCE
```

Raw elapsed times include bracket overhead. The summary reports min, median,
p95, max, and the difference between the RDMSR and empty medians. Subtraction
is an estimate of incremental cost in this sequence, not an exact universal
instruction latency. Inspect the distributions and repeat runs. NMI, SMI,
SMT contention, power management and thermal effects can still affect results.
MSR-specific timing can differ: do not generalize APERF timing to all RDMSRs.

## Which counter to use for VMX calibration

`0xE8` is `IA32_APERF`, which advances in proportion to actual performance
while active. `0xE7` is `IA32_MPERF`, the corresponding fixed-rate reference
counter. APERF/MPERF deltas are useful for checking average effective frequency
over a sufficiently long active interval. Neither read is free, and a pair
of APERF reads also needs carefully defined instruction ordering.

Start with ordered TSC reads for short VMX timing intervals. An invariant TSC
counts reference-time ticks, **not changing core clock cycles**. Only convert
to core cycles with a verified frequency relationship:

```text
elapsed_seconds = delta_TSC / TSC_frequency
core_cycles ≈ delta_TSC * core_frequency / TSC_frequency
```

For direct unhalted core-cycle counts, a later extension can use a properly
configured PMU counter and ordered `RDPMC`, with Linux perf managing counter
ownership. Do not assume a fixed counter is already enabled or overwrite
Linux's PMU configuration.

VMX timings depend on the particular instruction, VMCS state, success/failure
path, and cache state. VM entry/exit need timestamps across the actual guest/
host transition; timing a failing VMLAUNCH is not measuring successful entry.
These data calibrate a timing model; they are not required merely to implement
functional VMX semantics in gem5.

See Intel's [Software Developer's Manuals](https://www.intel.com/content/www/us/en/developer/articles/technical/intel-sdm.html),
especially RDTSC/RDMSR/LFENCE in Volume 2, timekeeping and performance monitoring
in Volume 3, and IA32_APERF/IA32_MPERF in Volume 4.

## Review of prep.sh

The script is a useful starting point, but successful execution does not
guarantee constant core frequency. `performance` plus turbo disabled still
needs frequency/throttling verification. Keep the SMT sibling idle or disable
SMT, and verify the selected CPU remains online afterward. CPU isolation helps
but does not eliminate hardware interrupts or firmware activity.

Dropping page caches is unnecessary for this warm kernel instruction test.
Disabling ASLR and relaxing `perf_event_paranoid` are also unnecessary here.
Some writes in the script report success without checking their result, so
review the saved snapshot and read settings back before trusting a run.

At initial inspection this host was an i7-6700K, microcode 0xf0, kernel
7.2.6-arch2-1, with CPUs 3 and 7 isolated by the boot command line. The current
governor on CPU 3 was `powersave` and `intel_pstate/no_turbo` was `0`, so prep
settings were not currently active. `prep.sh` was not changed or run as part
of creating this benchmark.
