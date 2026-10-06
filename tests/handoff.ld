ENTRY(_start)
SECTIONS {
 .monitor 0x40400000 : { *(.monitor) }
 .guest 0x40500000 : { *(.guest) }
 .kvm_init 0x40600000 : { *(.kvm_init) }
 .kvm_tables 0x40700000 : { *(.kvm_tables) }
 .native_init 0x87001000 : { *(.native_init) }
 .gateway 0x8701b190 : { *(.gateway) }
 .vectors 0x8701c000 : { *(.vectors) }
 .native 0x8701d800 : { *(.native) }
 .native_tables 0x87022000 : { *(.native_tables) }
 /DISCARD/ : { *(.comment) *(.note*) }
}
