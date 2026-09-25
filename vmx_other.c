/* Placeholder for the third test category; its purpose is still undecided. */
#include <stdio.h>
#include "vmx_calibration.h"

int main(void)
{
    printf("Third category stub: RDMSR(0x%x) overhead = %.1f TSC ticks\n",
           CALIBRATION_MSR, RDMSR_OVERHEAD_TSC_TICKS);
    return 0;
}
