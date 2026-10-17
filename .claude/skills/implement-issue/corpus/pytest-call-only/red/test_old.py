from app import total

def test_parse():
    assert total([1]) == 1

def test_wrapper():
    test_parse()
