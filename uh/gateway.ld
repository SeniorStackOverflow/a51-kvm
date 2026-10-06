SECTIONS {
 .gateway 0x8701b190 : { *(.gateway) }
 .publish 0x8701b700 : { *(.publish) }
 .marker 0x8701b780 : { *(.marker) }
 native_uh_init = 0x870129c0;
 /DISCARD/ : { *(.comment) *(.note*) }
 ASSERT(SIZEOF(.gateway) <= 0x570, "gateway overlaps publisher")
}
native_slot_0 = 0x8701c784;
native_slot_1 = 0x8701c850;
native_slot_2 = 0x8701c91c;
native_slot_3 = 0x8701c9e8;
native_slot_4 = 0x8701cab4;
native_slot_5 = 0x8701cb80;
native_slot_6 = 0x8701cc4c;
native_slot_7 = 0x8701cd18;
native_slot_8 = 0x8701cde4;
native_slot_9 = 0x8701ceec;
native_slot_10 = 0x8701cfb8;
native_slot_11 = 0x8701d084;
native_slot_12 = 0x8701d150;
native_slot_13 = 0x8701d21c;
native_slot_14 = 0x8701d2e8;
native_slot_15 = 0x8701d3b4;
