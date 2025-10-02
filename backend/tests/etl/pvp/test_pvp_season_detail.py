import pytest
from etl.pvp.seasons import fetch_season_detail

class FakeResponse:
    def __init__(self, payload: dict, status_code: int = 200):
        self._payload = payload
        self.status_code = status_code
    def raise_for_status(self):
        if not (200 <= self.status_code < 300):
            raise RuntimeError(f"http error: {self.status_code}")
    def json(self):
        return self._payload

@pytest.mark.asyncio
async def test_get_pvp_season_detail_with_fixture(monkeypatch, load_fixture):
    payload = load_fixture("blizzard", "season_details.json")
    recorded = {}

    async def fake_blizzard_get(region, path, params, timeout=20.0):
        recorded["region"] = region
        recorded["path"] = path
        recorded["params"] = params
        return FakeResponse(payload)

    # Patch where the function imports it
    monkeypatch.setattr("etl.pvp.seasons.blizzard_get", fake_blizzard_get)

    out = await fetch_season_detail(region="us", pvp_season_id=40, locale="en_US")

    # Request correctness
    assert recorded["region"] == "us"
    assert recorded["path"] == "/data/wow/pvp-season/40"
    assert recorded["params"]["namespace"] == "dynamic-us"
    assert recorded["params"]["locale"] == "en_US"

    # Normalized shape from fixture
    assert out["id"] == 40
    assert out["season_name"] == "Player vs. Player (The War Within Season 3)"
    assert out["season_start_timestamp"] == 1755010800000
    assert out["leaderboards"]["href"].endswith("/pvp-leaderboard/?namespace=dynamic-us")
    assert out["rewards"]["href"].endswith("/pvp-reward/?namespace=dynamic-us")

@pytest.mark.asyncio
async def test_get_pvp_season_detail_http_error(monkeypatch):
    async def fake_blizzard_get(*_a, **_k):
        return FakeResponse({}, status_code=404)

    monkeypatch.setattr("etl.pvp.seasons.blizzard_get", fake_blizzard_get)

    with pytest.raises(RuntimeError):
        await fetch_season_detail("us", 999)
