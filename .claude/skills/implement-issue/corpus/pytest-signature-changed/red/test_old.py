from app import total

def test_total(tmp_path):
    assert total([1, 2]) == 3
