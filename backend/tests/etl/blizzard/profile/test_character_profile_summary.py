import pytest
from typing import Any, Dict

# Adjust the import if your module path differs
from etl.blizzard.profile.character_profile import fetch_character_profile_summary


class FakeResponse:
    def __init__(self, payload: Dict[str, Any], status_code: int = 200):
        self._payload = payload
        self.status_code = status_code

    def raise_for_status(self) -> None:
        if not (200 <= self.status_code < 300):
            raise RuntimeError(f"http error: {self.status_code}")

    def json(self) -> Dict[str, Any]:
        return self._payload


@pytest.mark.asyncio
async def test_fetch_character_profile_summary_with_fixture(monkeypatch, load_fixture):
    # Load real-ish payload from fixture
    payload = load_fixture("blizzard", "profile/character_profile/character_profile_summary.json")
    recorded: Dict[str, Any] = {}

    async def fake_blizzard_get(region: str, path: str, params: Dict[str, Any], timeout: float = 20.0):
        recorded["region"] = region
        recorded["path"] = path
        recorded["params"] = params
        return FakeResponse(payload)

    # Patch where the function imports it
    monkeypatch.setattr("etl.blizzard.profile.character_profile.blizzard_get", fake_blizzard_get)

    # Use a mixed-case name to ensure `.lower()` is applied
    out = await fetch_character_profile_summary(
        region="us", realm_slug="illidan", character_name="Nystinn", locale="en_US"
    )

    # Request correctness
    assert recorded["region"] == "us"
    assert recorded["path"] == "/profile/wow/character/illidan/nystinn"
    assert recorded["params"]["namespace"] == "profile-us"
    assert recorded["params"]["locale"] == "en_US"

    # Shape checks (a few important fields)
    assert out["id"] == 225762911
    assert out["name"] == "Nystinn"
    assert out["realm"]["slug"] == "illidan"
    assert out["character_class"]["id"] == 4
    assert out["active_spec"]["id"] == 260
    assert out["faction"]["type"] in {"HORDE", "ALLIANCE"}

    # Response is exactly the payload we returned from the fake client
    assert out == payload


@pytest.mark.asyncio
async def test_fetch_character_profile_summary_http_error(monkeypatch):
    class FakeResponse:
        def __init__(self, payload, status_code):
            self._payload = payload
            self.status_code = status_code
        def raise_for_status(self):
            if not (200 <= self.status_code < 300):
                raise RuntimeError(f"http error: {self.status_code}")
        def json(self):
            return self._payload

    async def fake_blizzard_get(*_a, **_k):
        return FakeResponse({}, status_code=404)

    monkeypatch.setattr("etl.blizzard.profile.character_profile.blizzard_get", fake_blizzard_get)

    with pytest.raises(RuntimeError):
        await fetch_character_profile_summary("us", "illidan", "nystinn")
