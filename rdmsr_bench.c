// SPDX-License-Identifier: GPL-2.0
/* Native Intel x86-64 RDMSR timing. No MSR writes or VMX state changes. */
#include <linux/module.h>
#include <linux/cpu.h>
#include <linux/proc_fs.h>
#include <linux/seq_file.h>
#include <linux/slab.h>
#include <asm/msr.h>
#include <asm/processor.h>

static unsigned int cpu = 3;
static unsigned int samples = 10000;
static unsigned int msr = 0xe8;
module_param(cpu, uint, 0444);
module_param(samples, uint, 0444);
module_param(msr, uint, 0444);
MODULE_PARM_DESC(msr, "Read-only target: 0xe8 APERF, 0xe7 MPERF, or 0x10 TSC");

struct sample { u64 empty, rdmsr; };
static struct sample *results;
static struct proc_dir_entry *entry;

/* One asm block prevents compiler motion into the measured interval.
 * LFENCE before the ending RDTSC waits for RDMSR to complete. The two
 * variants have identical brackets and ECX setup; only RDMSR differs.
 * Start timestamp register copies and fences are included in both.
 */
#define MEASURE(body) do { \
	u32 lo, hi, start_lo, start_hi; \
	asm volatile("lfence\n\trdtsc\n\tlfence\n\t" \
		     "movl %%eax, %2\n\tmovl %%edx, %3\n\t" \
		     "movl %4, %%ecx\n\t" body \
		     "lfence\n\trdtsc\n\tlfence" \
		     : "=&a" (lo), "=&d" (hi), \
		       "=&r" (start_lo), "=&r" (start_hi) \
		     : "r" (msr) : "rcx", "memory"); \
	return (((u64)hi << 32) | lo) - (((u64)start_hi << 32) | start_lo); \
} while (0)

static noinline u64 measure_empty(void) { MEASURE(""); }
static noinline u64 measure_rdmsr(void) { MEASURE("rdmsr\n\t"); }

static long collect(void *unused)
{
	unsigned int i;
	unsigned long flags;
	u64 value;

	/* Fault-safe probe before using bare RDMSR in the timed path. */
	if (rdmsrq_safe(msr, &value))
		return -EIO;
	for (i = 0; i < samples + 1000; i++) {
		struct sample s;
		/* Only a pair of measurements with interrupts disabled at a time.
		 * NMI/SMI noise remains visible in the raw distribution.
		 */
		preempt_disable();
		local_irq_save(flags);
		if (i & 1) {
			s.rdmsr = measure_rdmsr();
			s.empty = measure_empty();
		} else {
			s.empty = measure_empty();
			s.rdmsr = measure_rdmsr();
		}
		local_irq_restore(flags);
		preempt_enable();
		if (i >= 1000)
			results[i - 1000] = s;
		cond_resched();
	}
	return 0;
}

static int bench_show(struct seq_file *m, void *unused)
{
	unsigned int i;
	seq_printf(m, "# cpu=%u msr=0x%x samples=%u units=tsc_ticks\n", cpu, msr, samples);
	seq_puts(m, "sample,empty_ticks,rdmsr_ticks\n");
	for (i = 0; i < samples; i++)
		seq_printf(m, "%u,%llu,%llu\n", i, results[i].empty, results[i].rdmsr);
	return 0;
}
DEFINE_PROC_SHOW_ATTRIBUTE(bench);

static int __init bench_init(void)
{
	long ret;
	if (boot_cpu_data.x86_vendor != X86_VENDOR_INTEL ||
	    boot_cpu_has(X86_FEATURE_HYPERVISOR) ||
	    !boot_cpu_has(X86_FEATURE_MSR) || !boot_cpu_has(X86_FEATURE_TSC))
		return -ENODEV;
	if (!samples || samples > 1000000 ||
	    (msr != 0xe8 && msr != 0xe7 && msr != 0x10))
		return -EINVAL;
	results = kcalloc(samples, sizeof(*results), GFP_KERNEL);
	if (!results)
		return -ENOMEM;
	cpus_read_lock();
	if (cpu >= nr_cpu_ids || !cpu_online(cpu))
		ret = -EINVAL;
	else
		ret = work_on_cpu(cpu, collect, NULL);
	cpus_read_unlock();
	if (ret)
		goto free_results;
	entry = proc_create("rdmsr_bench", 0400, NULL, &bench_proc_ops);
	if (!entry) {
		ret = -ENOMEM;
		goto free_results;
	}
	pr_info("rdmsr_bench: %u samples on CPU %u, MSR 0x%x; /proc/rdmsr_bench\n",
		samples, cpu, msr);
	return 0;
free_results:
	kfree(results);
	return ret;
}

static void __exit bench_exit(void)
{
	proc_remove(entry);
	kfree(results);
}
module_init(bench_init);
module_exit(bench_exit);
MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("Ordered TSC measurement of native RDMSR and empty brackets");
