SECTIONS { .guest 0x400000 : { *(.guest) } /DISCARD/ : { *(.comment) *(.note*) } }
