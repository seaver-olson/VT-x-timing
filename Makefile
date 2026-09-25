obj-m += rdmsr_bench.o
KDIR ?= /usr/lib/modules/$(shell uname -r)/build

.PHONY: all clean calibrate
all:
	$(MAKE) -C $(KDIR) M=$(CURDIR) MO=$(CURDIR)/build modules
clean:
	rm -rf -- $(CURDIR)/build

# One hook: validate CSV, generate shared calibration, build the three stubs.
calibrate:
	python3 calibrate.py "$(CSV)"
	$(CC) $(CPPFLAGS) $(CFLAGS) -Wall -Wextra -Ibuild vmx_main.c -o build/vmx_main
	$(CC) $(CPPFLAGS) $(CFLAGS) -Wall -Wextra -Ibuild vmx_entry_exit.c -o build/vmx_entry_exit
	$(CC) $(CPPFLAGS) $(CFLAGS) -Wall -Wextra -Ibuild vmx_other.c -o build/vmx_other
