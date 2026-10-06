.section .gateway,"ax"
.global uh_gateway_start
uh_gateway_start:
.global uh_slot_0
uh_slot_0:
 stp x16, x17, [sp, #-32]!
 mov x16, #0
 str x16, [sp, #16]
 b dispatch
.global uh_slot_1
uh_slot_1:
 stp x16, x17, [sp, #-32]!
 mov x16, #1
 str x16, [sp, #16]
 b dispatch
.global uh_slot_2
uh_slot_2:
 stp x16, x17, [sp, #-32]!
 mov x16, #2
 str x16, [sp, #16]
 b dispatch
.global uh_slot_3
uh_slot_3:
 stp x16, x17, [sp, #-32]!
 mov x16, #3
 str x16, [sp, #16]
 b dispatch
.global uh_slot_4
uh_slot_4:
 stp x16, x17, [sp, #-32]!
 mov x16, #4
 str x16, [sp, #16]
 b dispatch
.global uh_slot_5
uh_slot_5:
 stp x16, x17, [sp, #-32]!
 mov x16, #5
 str x16, [sp, #16]
 b dispatch
.global uh_slot_6
uh_slot_6:
 stp x16, x17, [sp, #-32]!
 mov x16, #6
 str x16, [sp, #16]
 b dispatch
.global uh_slot_7
uh_slot_7:
 stp x16, x17, [sp, #-32]!
 mov x16, #7
 str x16, [sp, #16]
 b dispatch
.global uh_slot_8
uh_slot_8:
 stp x16, x17, [sp, #-32]!
 mov x16, #8
 str x16, [sp, #16]
 b dispatch
.global uh_slot_9
uh_slot_9:
 stp x16, x17, [sp, #-32]!
 mov x16, #9
 str x16, [sp, #16]
 b dispatch
.global uh_slot_10
uh_slot_10:
 stp x16, x17, [sp, #-32]!
 mov x16, #10
 str x16, [sp, #16]
 b dispatch
.global uh_slot_11
uh_slot_11:
 stp x16, x17, [sp, #-32]!
 mov x16, #11
 str x16, [sp, #16]
 b dispatch
.global uh_slot_12
uh_slot_12:
 stp x16, x17, [sp, #-32]!
 mov x16, #12
 str x16, [sp, #16]
 b dispatch
.global uh_slot_13
uh_slot_13:
 stp x16, x17, [sp, #-32]!
 mov x16, #13
 str x16, [sp, #16]
 b dispatch
.global uh_slot_14
uh_slot_14:
 stp x16, x17, [sp, #-32]!
 mov x16, #14
 str x16, [sp, #16]
 b dispatch
.global uh_slot_15
uh_slot_15:
 stp x16, x17, [sp, #-32]!
 mov x16, #15
 str x16, [sp, #16]
 b dispatch
dispatch:
 mrs x16, mpidr_el1
 and x17, x16, #3
 ubfx x16, x16, #8, #1
 orr x17, x17, x16, lsl #2
 movz w16, #22272
 movk w16, #0x8704, lsl #16
 add x17, x16, x17, lsl #8
 ldr x16, [sp, #16]
 cmp x16, #8
 b.ne route
 mrs x16, esr_el2
 lsr x16, x16, #26
 cmp x16, #0x16
 b.ne route
 movz w16, #0x4b56
 movk w16, #0xc300, lsl #16
 cmp x0, x16
 b.ne route
 ldr x16, [x17, #136]
 cbz x16, command
 mrs x16, vttbr_el2
 cbnz x16, route
command:
 cbz x1, diagnostic
 cmp x1, #1
 b.eq translation
 cmp x1, #2
 b.eq takeover
 cmp x1, #3
 b.eq restore
reject:
 mov x0, #-1
 b finish
diagnostic:
 mrs x2, hcr_el2
 mrs x3, mpidr_el1
 mrs x4, sctlr_el2
 mrs x5, vbar_el2
 b success
translation:
 mrs x2, ttbr0_el2
 mrs x3, tcr_el2
 mrs x4, mair_el2
 add x5, sp, #32
success:
 mrs x1, CurrentEL
 movz w0, #0x4b56
 movk w0, #0xc0de, lsl #16
finish:
 ldp x16, x17, [sp], #32
 eret
route:
 ldr x16, [x17, #136]
 cbz x16, native
 ldr x17, [sp, #16]
 add x17, x16, x17, lsl #7
 br x17
native:
 adr x16, native_targets
 ldr x17, [sp, #16]
 add x17, x16, x17, lsl #3
 br x17
.balign 8
native_targets:
 ldp x16, x17, [sp], #32
 b native_slot_0
 ldp x16, x17, [sp], #32
 b native_slot_1
 ldp x16, x17, [sp], #32
 b native_slot_2
 ldp x16, x17, [sp], #32
 b native_slot_3
 ldp x16, x17, [sp], #32
 b native_slot_4
 ldp x16, x17, [sp], #32
 b native_slot_5
 ldp x16, x17, [sp], #32
 b native_slot_6
 ldp x16, x17, [sp], #32
 b native_slot_7
 ldp x16, x17, [sp], #32
 b native_slot_8
 ldp x16, x17, [sp], #32
 b native_slot_9
 ldp x16, x17, [sp], #32
 b native_slot_10
 ldp x16, x17, [sp], #32
 b native_slot_11
 ldp x16, x17, [sp], #32
 b native_slot_12
 ldp x16, x17, [sp], #32
 b native_slot_13
 ldp x16, x17, [sp], #32
 b native_slot_14
 ldp x16, x17, [sp], #32
 b native_slot_15
takeover:
 ldr x16, [x17, #136]
 cbnz x16, reject
 mrs x16, ttbr0_el2
 movz w0, #0x2000
 movk w0, #0x8702, lsl #16
 cmp x16, x0
 b.ne reject
 tst x2, #3
 b.ne reject
 tst x3, #4095
 b.ne reject
 cbz x6, reject
 mrs x16, sctlr_el2
 str x16, [x17, #0]
 mrs x16, ttbr0_el2
 str x16, [x17, #8]
 mrs x16, tcr_el2
 str x16, [x17, #16]
 mrs x16, mair_el2
 str x16, [x17, #24]
 mrs x16, hcr_el2
 str x16, [x17, #32]
 mrs x16, vttbr_el2
 str x16, [x17, #40]
 mrs x16, vtcr_el2
 str x16, [x17, #48]
 mrs x16, mdcr_el2
 str x16, [x17, #56]
 mrs x16, cptr_el2
 str x16, [x17, #64]
 mrs x16, hstr_el2
 str x16, [x17, #72]
 mrs x16, cnthctl_el2
 str x16, [x17, #80]
 mrs x16, cntvoff_el2
 str x16, [x17, #88]
 mrs x16, tpidr_el2
 str x16, [x17, #96]
 mrs x16, vpidr_el2
 str x16, [x17, #104]
 mrs x16, vmpidr_el2
 str x16, [x17, #112]
 mrs x16, vbar_el2
 str x16, [x17, #120]
 add x16, sp, #32
 str x16, [x17, #128]
 str x6, [x17, #136]
 dc cvac, x17
 add x16, x17, #64
 dc cvac, x16
 add x16, x17, #128
 dc cvac, x16
 dsb sy
 mov x9, x2
 mov x0, x3
 mov x1, x4
 mov x2, x5
 ldp x16, x17, [sp], #32
 mov x10, #0x80000000
 msr hcr_el2, x10
 isb
 msr vttbr_el2, xzr
 mov x10, #3
 msr cnthctl_el2, x10
 msr cntvoff_el2, xzr
 mov x10, #0x33ff
 msr cptr_el2, x10
 msr hstr_el2, xzr
 mrs x10, pmcr_el0
 ubfx x10, x10, #11, #5
 msr mdcr_el2, x10
 mrs x10, midr_el1
 msr vpidr_el2, x10
 mrs x10, mpidr_el1
 msr vmpidr_el2, x10
 mrs x10, sctlr_el2
 bic x10, x10, #1
 dsb sy
 msr sctlr_el2, x10
 isb
 br x9
restore:
 ldr x16, [x17, #136]
 cbz x16, reject
 str xzr, [x17, #136]
 dc cvac, x17
 add x16, x17, #128
 dc cvac, x16
 dsb sy
 ldp x16, x0, [sp], #32
 mrs x0, sctlr_el2
 bic x0, x0, #1
 msr sctlr_el2, x0
 isb
 ldr x0, [x17, #8]
 msr ttbr0_el2, x0
 ldr x0, [x17, #16]
 msr tcr_el2, x0
 ldr x0, [x17, #24]
 msr mair_el2, x0
 ldr x0, [x17, #48]
 msr vtcr_el2, x0
 ldr x0, [x17, #56]
 msr mdcr_el2, x0
 ldr x0, [x17, #64]
 msr cptr_el2, x0
 ldr x0, [x17, #72]
 msr hstr_el2, x0
 ldr x0, [x17, #80]
 msr cnthctl_el2, x0
 ldr x0, [x17, #88]
 msr cntvoff_el2, x0
 ldr x0, [x17, #96]
 msr tpidr_el2, x0
 ldr x0, [x17, #104]
 msr vpidr_el2, x0
 ldr x0, [x17, #112]
 msr vmpidr_el2, x0
 ldr x0, [x17, #120]
 msr vbar_el2, x0
 ldr x0, [x17, #40]
 msr vttbr_el2, x0
 ldr x0, [x17, #32]
 msr hcr_el2, x0
 ldr x0, [x17, #128]
 mov sp, x0
 tlbi alle2
 dsb sy
 ldr x0, [x17]
 msr sctlr_el2, x0
 isb
 movz w0, #0x4b56
 movk w0, #0xc0de, lsl #16
 eret
.ltorg
