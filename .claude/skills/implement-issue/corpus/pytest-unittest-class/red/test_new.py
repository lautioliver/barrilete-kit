import unittest
from app import total

class T(unittest.TestCase):
    def test_total(self):
        self.assertEqual(total([1, 2]), 3)
