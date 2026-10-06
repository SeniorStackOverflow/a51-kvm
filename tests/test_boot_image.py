"""Malformed boot containers must be rejected before any output is created."""
import sys
from pathlib import Path
import struct
import unittest
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'tools'))
from boot_image import parse

class BootGuards(unittest.TestCase):
    def test_truncated_and_foreign_containers(self):
        for data in [b'', b'ANDROID!', bytes(4096)]:
            with self.subTest(length=len(data)), self.assertRaises(ValueError):
                parse(data)

    def test_unsupported_header_or_page_layout(self):
        for version, page in [(0, 2048), (1, 2048), (3, 4096), (2, 4096)]:
            data = bytearray(4096)
            data[:8] = b'ANDROID!'
            struct.pack_into('<10I', data, 8, 64, 0, 64, 0, 0, 0, 0, page, version, 0)
            with self.subTest(version=version, page=page), self.assertRaises(ValueError):
                parse(data)

if __name__ == '__main__':
    unittest.main()
