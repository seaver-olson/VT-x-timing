/* Placeholder for main VMX instruction tests. No VMX instructions yet. */
#include <stdio.h>
#include "vmx_calibration.h"

int main(void)
{
    printf("Main instructions stub: RDMSR(0x%x) overhead = %.1f TSC ticks\n",
           CALIBRATION_MSR, RDMSR_OVERHEAD_TSC_TICKS);
    return 0;
}
