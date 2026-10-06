SHELL := /bin/bash
CROSS ?= aarch64-linux-gnu-
BUILD ?= build
AS := $(CROSS)as
LD := $(CROSS)ld
OBJCOPY := $(CROSS)objcopy
OBJDUMP := $(CROSS)objdump
NM := $(CROSS)nm
CC := $(CROSS)gcc

.PHONY: all gateway probes test check
all: gateway probes
gateway: $(BUILD)/gateway.bin $(BUILD)/publisher.bin $(BUILD)/marker.bin $(BUILD)/symbols.txt
probes: $(BUILD)/kvm-guest-probe $(BUILD)/kvm-timer-probe $(BUILD)/kvm-timer-guest.bin

$(BUILD):
	mkdir -p "$@"
$(BUILD)/gateway.o: uh/gateway.S | $(BUILD)
	$(AS) $< -o $@
$(BUILD)/publisher.o: uh/publisher.S | $(BUILD)
	$(AS) $< -o $@
$(BUILD)/gateway.elf: $(BUILD)/gateway.o $(BUILD)/publisher.o uh/gateway.ld
	$(LD) -T uh/gateway.ld $(BUILD)/gateway.o $(BUILD)/publisher.o -o $@
$(BUILD)/gateway.bin: $(BUILD)/gateway.elf
	$(OBJCOPY) -O binary --only-section=.gateway $< $@
$(BUILD)/publisher.bin: $(BUILD)/gateway.elf
	$(OBJCOPY) -O binary --only-section=.publish $< $@
$(BUILD)/marker.bin: $(BUILD)/gateway.elf
	$(OBJCOPY) -O binary --only-section=.marker $< $@
$(BUILD)/symbols.txt: $(BUILD)/gateway.elf
	$(NM) $< > $@
$(BUILD)/handoff.o: tests/handoff.S | $(BUILD)
	$(AS) $< -o $@
$(BUILD)/handoff.elf: $(BUILD)/handoff.o $(BUILD)/gateway.o tests/handoff.ld
	$(LD) -T tests/handoff.ld $(BUILD)/handoff.o $(BUILD)/gateway.o -o $@
$(BUILD)/test-gateway.bin: $(BUILD)/handoff.elf
	$(OBJCOPY) -O binary --only-section=.gateway $< $@
$(BUILD)/kvm-guest-probe: probes/guest.c | $(BUILD)
	$(CC) -static -O2 -Wall -Wextra $< -o $@.tmp
	mv $@.tmp $@
$(BUILD)/kvm-timer-probe: probes/timer.c | $(BUILD)
	$(CC) -static -O2 -Wall -Wextra $< -o $@.tmp
	mv $@.tmp $@
$(BUILD)/timer-guest.o: probes/timer-guest.S | $(BUILD)
	$(AS) $< -o $@
$(BUILD)/timer-guest.elf: $(BUILD)/timer-guest.o probes/timer-guest.ld
	$(LD) -T probes/timer-guest.ld $< -o $@
$(BUILD)/kvm-timer-guest.bin: $(BUILD)/timer-guest.elf
	$(OBJCOPY) -O binary --only-section=.guest $< $@

test: gateway $(BUILD)/test-gateway.bin
	timeout 20s qemu-system-aarch64 -machine virt,secure=on,virtualization=on,gic-version=2 -cpu cortex-a53 -m 2048M -nographic -monitor none -serial none -semihosting-config enable=on,target=native -device loader,file=$(BUILD)/handoff.elf,cpu-num=0 > $(BUILD)/handoff-result.txt 2>&1
	cat $(BUILD)/handoff-result.txt
	grep -q '^PASS:' $(BUILD)/handoff-result.txt
	python3 tools/uh_image.py check-gateway --build $(BUILD)
	python3 -m unittest discover -s tests -p 'test_*.py' -v

check: all test
	python3 -m py_compile tools/*.py
