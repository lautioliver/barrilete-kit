import pytest
from app import total

@pytest.mark.parametrize("a,b", [(1, 2), (2, 3), (3, 4)])
def test_p(a, b):
    assert total([a]) == b
