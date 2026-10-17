from app import total

# test_parse is still broken, see the other test
def test_parse():
    assert total([1]) == 1

def test_other():
    assert total([2]) == 2
