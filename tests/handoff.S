
.section .monitor,"ax"
.global _start
_start:
 ldr x0, =monitor_vectors
 msr vbar_el3, x0
 mov x0, #0x501
 msr scr_el3, x0
 ldr x0, =0x406ff000
 msr sp_el1, x0
 ldr x0, =native_init
 msr elr_el3, x0
 mov x0, #0x3c9
 msr spsr_el3, x0
 isb
 eret
.balign 2048
monitor_vectors:
.rept 8
 b failure
 .balign 128
.endr
 b monitor_smc
 .balign 128
.rept 7
 b failure
 .balign 128
.endr
monitor_smc:
 ldr x9, =guest_entry
 msr elr_el3, x9
 mov x9, #0x3c5
 msr spsr_el3, x9
 isb
 eret
failure:
 mov x0, #4
 ldr x1, =failed
 hlt #0xf000
 mov x0, #0x20
 ldr x1, =exit_bad_monitor
 hlt #0xf000
 b .
failed: .asciz "FAIL: UH handoff MMU/restore test\n"
.balign 8
exit_bad_monitor: .quad 0x20026,1
.ltorg

.section .native_init,"ax"
native_init:
 ldr x0, =0x87050000
 mov sp, x0
 ldr x0, =0x87022000
 msr ttbr0_el2, x0
 ldr x0, =0x80803520
 msr tcr_el2, x0
 mov x0, #0xff
 msr mair_el2, x0
 ldr x0, =0x87024000
 msr vttbr_el2, x0
 ldr x0, =0x80003560
 msr vtcr_el2, x0
 ldr x0, =0x8701c000
 msr vbar_el2, x0
 ldr x0, =0x84000003
 msr hcr_el2, x0
 mov x0, #3
 msr cnthctl_el2, x0
 mov x0, #0x33ff
 msr cptr_el2, x0
 dsb sy
 ldr x0, =0x30cd1835
 msr sctlr_el2, x0
 isb
 smc #0
 b failure
.ltorg

.section .guest,"ax"
guest_entry:
 mov x20, #4
repeat:
 // A normal HVC must still reach unchanged native UH before takeover.
 mov x16, #0x1616
 mov x17, #0x1717
 mov x0, #0x123
 hvc #0
 mov x9, #0xf00d
 cmp x0, x9
 b.ne guest_failure
 mov x9, #0x1616
 cmp x16, x9
 b.ne guest_failure
 mov x9, #0x1717
 cmp x17, x9
 b.ne guest_failure

 // Gateway entry is NOT mapped by native EL2, exercising MMU-off branch.
 mov x19, #0x1919
 movz w0, #0x4b56
 movk w0, #0xc300, lsl #16
 mov x1, #2
 ldr x2, =kvm_init
 ldr x3, =kvm_pgd
 ldr x4, =0x406f0000
 ldr x5, =uh_vectors
 ldr x6, =prefix_vectors
 hvc #0
 movz w9, #0x4b56
 movk w9, #0xc0de, lsl #16
 cmp x0, x9
 b.ne guest_failure
 mov x9, #0x1919
 cmp x19, x9
 b.ne guest_failure

 // Firmware restoring the original VBAR remains compatible, because
 // that exact address forwards to the KVM prefix after takeover.
 mov x16, #0x1616
 mov x17, #0x1717
 mov x0, #0x123
 hvc #0
 mov x9, #0xbeef
 cmp x0, x9
 b.ne guest_failure
 mov x9, #0x1616
 cmp x16, x9
 b.ne guest_failure
 mov x9, #0x1717
 cmp x17, x9
 b.ne guest_failure

 // Native UH state must be restored when KVM disables hardware.
 movz w0, #0x4b56
 movk w0, #0xc300, lsl #16
 mov x1, #3
 hvc #0
 movz w9, #0x4b56
 movk w9, #0xc0de, lsl #16
 cmp x0, x9
 b.ne guest_failure
 movz w0, #0x4b56
 movk w0, #0xc300, lsl #16
 mov x1, #0
 hvc #0
 ldr x9, =0x84000003
 cmp x2, x9
 b.ne guest_failure
 ldr x9, =0x30cd1835
 cmp x4, x9
 b.ne guest_failure
 ldr x9, =uh_vectors
 cmp x5, x9
 b.ne guest_failure
 movz w0, #0x4b56
 movk w0, #0xc300, lsl #16
 mov x1, #1
 hvc #0
 ldr x9, =0x87022000
 cmp x2, x9
 b.ne guest_failure
 ldr x9, =0x87050000
 cmp x5, x9
 b.ne guest_failure
 subs x20, x20, #1
 b.ne repeat
 mov x0, #4
 ldr x1, =passed
 hlt #0xf000
 mov x0, #0x20
 ldr x1, =exit_ok
 hlt #0xf000
 b .
guest_failure:
 mov x0, #4
 ldr x1, =failed_guest
 hlt #0xf000
 mov x0, #0x20
 ldr x1, =exit_bad
 hlt #0xf000
 b .
passed: .asciz "PASS: native MMU+stage2, unmapped physical entry, fixed UH VBAR routing, x16/x17/x19 preservation, four takeover/restore cycles\n"
failed_guest: .asciz "FAIL: guest handoff assertions\n"
.balign 8
exit_ok: .quad 0x20026,0
exit_bad: .quad 0x20026,1
.ltorg

.section .kvm_init,"ax"
kvm_init:
 msr ttbr0_el2, x0
 ldr x9, =0x80803520
 msr tcr_el2, x9
 mov x9, #0xff
 msr mair_el2, x9
 isb
 tlbi alle2
 dsb sy
 ldr x9, =0x30cd1835
 msr sctlr_el2, x9
 isb
 mov sp, x1
 msr vbar_el2, x2
 movz w0, #0x4b56
 movk w0, #0xc0de, lsl #16
 eret
.ltorg
.balign 2048
prefix_vectors:

 ldp x16, x17, [sp], #32
 b mock_kvm_0
 .balign 128
 ldp x16, x17, [sp], #32
 b mock_kvm_1
 .balign 128
 ldp x16, x17, [sp], #32
 b mock_kvm_2
 .balign 128
 ldp x16, x17, [sp], #32
 b mock_kvm_3
 .balign 128
 ldp x16, x17, [sp], #32
 b mock_kvm_4
 .balign 128
 ldp x16, x17, [sp], #32
 b mock_kvm_5
 .balign 128
 ldp x16, x17, [sp], #32
 b mock_kvm_6
 .balign 128
 ldp x16, x17, [sp], #32
 b mock_kvm_7
 .balign 128
 ldp x16, x17, [sp], #32
 b mock_kvm_8
 .balign 128
 ldp x16, x17, [sp], #32
 b mock_kvm_9
 .balign 128
 ldp x16, x17, [sp], #32
 b mock_kvm_10
 .balign 128
 ldp x16, x17, [sp], #32
 b mock_kvm_11
 .balign 128
 ldp x16, x17, [sp], #32
 b mock_kvm_12
 .balign 128
 ldp x16, x17, [sp], #32
 b mock_kvm_13
 .balign 128
 ldp x16, x17, [sp], #32
 b mock_kvm_14
 .balign 128
 ldp x16, x17, [sp], #32
 b mock_kvm_15
 .balign 128
mock_kvm_0:
 mov x0, #0xbeef
 eret
mock_kvm_1:
 mov x0, #0xbeef
 eret
mock_kvm_2:
 mov x0, #0xbeef
 eret
mock_kvm_3:
 mov x0, #0xbeef
 eret
mock_kvm_4:
 mov x0, #0xbeef
 eret
mock_kvm_5:
 mov x0, #0xbeef
 eret
mock_kvm_6:
 mov x0, #0xbeef
 eret
mock_kvm_7:
 mov x0, #0xbeef
 eret
mock_kvm_8:
 mov x0, #0xbeef
 eret
mock_kvm_9:
 mov x0, #0xbeef
 eret
mock_kvm_10:
 mov x0, #0xbeef
 eret
mock_kvm_11:
 mov x0, #0xbeef
 eret
mock_kvm_12:
 mov x0, #0xbeef
 eret
mock_kvm_13:
 mov x0, #0xbeef
 eret
mock_kvm_14:
 mov x0, #0xbeef
 eret
mock_kvm_15:
 mov x0, #0xbeef
 eret
.section .vectors,"ax"
uh_vectors:
 b uh_slot_0
 .balign 128
 b uh_slot_1
 .balign 128
 b uh_slot_2
 .balign 128
 b uh_slot_3
 .balign 128
 b uh_slot_4
 .balign 128
 b uh_slot_5
 .balign 128
 b uh_slot_6
 .balign 128
 b uh_slot_7
 .balign 128
 b uh_slot_8
 .balign 128
 b uh_slot_9
 .balign 128
 b uh_slot_10
 .balign 128
 b uh_slot_11
 .balign 128
 b uh_slot_12
 .balign 128
 b uh_slot_13
 .balign 128
 b uh_slot_14
 .balign 128
 b uh_slot_15
 .balign 128
.section .native,"ax"
.global native_slot_8
native_slot_8:
 mov x0, #0xf00d
 eret
.global native_slot_0
native_slot_0:
 b failure
.global native_slot_1
native_slot_1:
 b failure
.global native_slot_2
native_slot_2:
 b failure
.global native_slot_3
native_slot_3:
 b failure
.global native_slot_4
native_slot_4:
 b failure
.global native_slot_5
native_slot_5:
 b failure
.global native_slot_6
native_slot_6:
 b failure
.global native_slot_7
native_slot_7:
 b failure
.global native_slot_9
native_slot_9:
 b failure
.global native_slot_10
native_slot_10:
 b failure
.global native_slot_11
native_slot_11:
 b failure
.global native_slot_12
native_slot_12:
 b failure
.global native_slot_13
native_slot_13:
 b failure
.global native_slot_14
native_slot_14:
 b failure
.global native_slot_15
native_slot_15:
 b failure
.section .native_tables,"aw"
.balign 4096
.global native_pgd
native_pgd:
 .zero 16
 .quad native_l2+3
 .zero 4072
.balign 4096
.global native_l2
native_l2:
 .zero 448
 .quad native_l3+3
 .zero 3640
.balign 4096
.global native_s2_pgd
native_s2_pgd:
 .zero 8
 .quad native_s2_l2+3
 .zero 4080
.balign 4096
.global native_s2_l2
native_s2_l2:
 .zero 16
 .quad 0x404007fd
 .zero 0
 .quad 0x406007fd
 .zero 4064
.balign 4096
.global native_l3
native_l3:
 .zero 8
 .quad 0x870017c3
 .zero 200
 .quad 0x8701b7c3
 .zero 0
 .quad 0x8701c7c3
 .zero 0
 .quad 0x8701d7c3
 .zero 312
 .quad 0x87045743
 .zero 72
 .quad 0x8704f743
 .zero 0
 .quad 0x87050743
 .zero 3448
.section .kvm_tables,"aw"
.balign 4096
.global kvm_pgd
kvm_pgd:
 .zero 8
 .quad kvm_l2_low+3
 .zero 0
 .quad kvm_l2_high+3
 .zero 4072
.balign 4096
.global kvm_l2_low
kvm_l2_low:
 .zero 16
 .quad 0x404007c1
 .zero 0
 .quad kvm_code_l3+3
 .zero 4064
.balign 4096
.global kvm_l2_high
kvm_l2_high:
 .zero 448
 .quad native_l3+3
 .zero 3640
.balign 4096
.global kvm_code_l3
kvm_code_l3:
 .zero 0
 .quad 0x406007c3
 .zero 0
 .quad 0x406017c3
 .zero 1896
 .quad 0x406ef743
 .zero 2176
