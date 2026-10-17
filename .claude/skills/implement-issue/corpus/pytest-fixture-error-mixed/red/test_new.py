import pytest
from app import total

@pytest.fixture
def broken():
    raise RuntimeError('setup')

def test_total():
    assert total([1, 2]) == 3

def test_fixture(broken):
    assert True
