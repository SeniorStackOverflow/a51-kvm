"""Exercise firmware rejection and branch encoding boundaries without Samsung firmware."""
import sys
from pathlib import Path
import struct
import unittest
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
from uh_image import branch, branch_target, normalize_original, CANONICAL_SIZE, PARTITION_SIZE

class ImageGuards(unittest.TestCase):
    def test_foreign_firmware_is_rejected(self):
        for size in [0, 100, CANONICAL_SIZE, PARTITION_SIZE]:
            with self.subTest(size=size), self.assertRaises(ValueError):
                normalize_original(bytes(size))

    def test_branch_forward_backward_and_boundaries(self):
        for distance in [0, 4, -4, -(1 << 27), (1 << 27)-4]:
            encoded = struct.unpack('<I', branch(0x8701c000, 0x8701c000+distance))[0]
            self.assertEqual(branch_target(encoded, 0x8701c000), 0x8701c000+distance)
        for distance in [1, 2, -(1 << 27)-4, 1 << 27]:
            with self.subTest(distance=distance), self.assertRaises(ValueError):
                branch(0x8701c000, 0x8701c000+distance)

    def test_nonbranch_is_rejected(self):
        with self.assertRaises(ValueError):
            branch_target(0xd503201f, 0x8701c000)

if __name__ == '__main__':
    unittest.main()
