.section .guest,"ax"
.global guest_start
guest_start:
 ldr x0, =guest_vectors
 msr vbar_el1, x0
 ldr x1, =0x08000000
 mov w0, #1
 str w0, [x1] // GICD_CTLR enable
 mov w0, #0x08000000
 str w0, [x1, #0x100] // GICD_ISENABLER0: virtual timer PPI27
 ldr x1, =0x08010000
 mov w0, #0xff
 str w0, [x1, #4] // GICC_PMR
 mov w0, #1
 str w0, [x1] // GICC_CTLR enable
 dsb sy
 mrs x0, cntfrq_el0
 mov x1, #100
 udiv x0, x0, x1 // 10ms
 msr cntv_tval_el0, x0
 mov x0, #1
 msr cntv_ctl_el0, x0
 isb
 msr daifclr, #2 // IRQ enabled
wait:
 nop // stay in guest until the physical virtual-timer IRQ exits to host
 b wait
irq_handler:
 ldr x1, =0x08010000
 ldr w0, [x1, #12] // GICC_IAR
 mov x2, #0
 msr cntv_ctl_el0, x2
 str w0, [x1, #16] // GICC_EOIR
 dsb sy
 mov x1, #0x100000
 str x0, [x1] // signal actual guest timer IRQ number to userspace
 b .
unexpected:
 mov x0, #0xbad
 mov x1, #0x100000
 str x0, [x1]
 b .
.ltorg
.balign 2048
guest_vectors:
.rept 5
 b unexpected
 .balign 128
.endr
 b irq_handler // current EL, SP_EL1, IRQ (offset0x280)
 .balign 128
.rept 10
 b unexpected
 .balign 128
.endr
