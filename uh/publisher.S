/* Run native UH init unchanged; advertise the extension only after success.
 * The shared log is accessible from EL1; UH code is not.
 */
.section .publish,"ax"
.global uh_publish_stamp
.extern native_uh_init
.extern diagnostic_marker
uh_publish_stamp:
    stp x19, x30, [sp, #-16]!
    bl native_uh_init
    cbnz x0, finished
    movz w17, #0
    movk w17, #0x8710, lsl #16
    adr x16, diagnostic_marker
    ldp x19, x16, [x16]
    stp x19, x16, [x17]
    dsb sy
finished:
    ldp x19, x30, [sp], #16
    ret

.section .marker,"a"
.global diagnostic_marker
diagnostic_marker:
    .asciz "KVMEL2HAND_V1"
    .balign 16, 0
