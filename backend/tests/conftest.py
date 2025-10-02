import json
import pathlib
import pytest

FIXTURES = pathlib.Path(__file__).parent / "fixtures"

@pytest.fixture
def load_fixture():
    def _load(*parts):
        with open(FIXTURES.joinpath(*parts), "r", encoding="utf-8") as f:
            return json.load(f)
    return _load
