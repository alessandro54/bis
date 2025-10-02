from typing import Any
import pytest
from pathlib import Path
from etl.blizzard.profile.character_specializations import fetch_character_specializations

class FakeResponse:
    def __init__(self, payload: dict[str, Any], status_code: int = 200):
        self._payload = payload
        self.status_code = status_code

    def raise_for_status(self) -> None:
        if not (200 <= self.status_code < 300):
            raise RuntimeError(f"http error: {self.status_code}")

    def json(self) -> dict[str, Any]:
        return self._payload

@pytest.mark.asyncio
async def test_fetch_character_specializations(monkeypatch, load_fixture):
    data = load_fixture("blizzard", "profile/character_specializations/character_specializations_summary.json")

    async def fake_blizzard_get(*_a, **_kw):
        return FakeResponse(data)

    monkeypatch.setattr(
        "etl.blizzard.profile.character_specializations.blizzard_get",
        fake_blizzard_get
    )

    result = await fetch_character_specializations("us", "illidan", "nystinn")
    assert "specializations" in result
    assert result["specializations"][0]["specialization"]["name"] == "Outlaw"
