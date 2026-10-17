from app import total

class TestA:
    def test_x(self):
        assert total([1]) == 1

class TestB:
    def test_x(self):
        assert total([2]) == 2
