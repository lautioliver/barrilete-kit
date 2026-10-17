import pytest
from app import check

def test_check():
    with pytest.raises(ValueError):
        check(-1)
