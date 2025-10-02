import json
import pytest
from types import SimpleNamespace
from pathlib import Path

from etl.blizzard.game_data.pvp_season import fetch_seasons_index


class FakeResponse:
    def __init__(self, payload: dict, status_code: int = 200):
        self._payload = payload
        self.status_code = status_code

    def raise_for_status(self):
        if not (200 <= self.status_code < 300):
            raise RuntimeError(f"http error: {self.status_code}")

    def json(self):
        return self._payload


def _fixture_payload_or_fallback(region: str = "us") -> dict:
    """
    Try to load a realistic payload from a JSON fixture:
      backend/tests/fixtures/blizzard/seasons_index.json
    If it doesn't exist, fall back to a generated minimal-yet-realistic payload.
    """
    fixture_path = Path(__file__).parents[1] / "fixtures" / "blizzard" / "seasons_index.json"
    if fixture_path.exists():
        with fixture_path.open("r", encoding="utf-8") as f:
            data = json.load(f)
        # basic sanity: ensure keys exist, otherwise fallback
        if isinstance(data, dict) and "seasons" in data and isinstance(data["seasons"], list):
            return data

    return {
        "seasons": [
            {
                "key": {
                    "href": f"https://{region}.api.blizzard.com/data/wow/pvp-season/{i}?namespace=dynamic-{region}"
                },
                "id": i,
            }
            for i in range(22, 41)
        ]
    }


@pytest.mark.asyncio
async def test_fetch_seasons_index_success(monkeypatch):
    called = SimpleNamespace(region=None, path=None, params=None)
    payload = _fixture_payload_or_fallback("us")

    async def fake_blizzard_get(region, path, params, timeout=20.0):
        called.region = region
        called.path = path
        called.params = params
        return FakeResponse(payload)

    # Patch exactly where it's imported in the module under test
    monkeypatch.setattr("etl.blizzard.game_data.pvp_season.blizzard_get", fake_blizzard_get)

    # Act
    region = "us"
    seasons = await fetch_seasons_index(region, "en_US")

    # Assert: shape
    assert isinstance(seasons, list)
    assert seasons, "Expected at least one season in payload"
    assert all("id" in s and "key" in s and isinstance(s["key"], dict) and "href" in s["key"] for s in seasons)

    # Assert: IDs are unique and sorted ascending (Blizzard index is chronological)
    ids = [int(s["id"]) for s in seasons]
    assert len(ids) == len(set(ids)), "Season IDs should be unique"
    assert ids == sorted(ids), "Season IDs should be in ascending order"

    # Assert: href matches id and namespace
    for s in seasons:
        href = s["key"]["href"]
        assert f"/pvp-season/{s['id']}" in href
        assert f"namespace=dynamic-{region}" in href

    # Assert: request was constructed correctly
    assert called.region == region
    assert called.path == "/data/wow/pvp-season/index"
    assert called.params["namespace"] == f"dynamic-{region}"
    assert called.params["locale"] == "en_US"


@pytest.mark.asyncio
@pytest.mark.parametrize("region", ["us", "eu", "kr", "tw"])
async def test_fetch_seasons_index_namespace_per_region(monkeypatch, region):
    recorded = {}
    payload = _fixture_payload_or_fallback(region)

    async def fake_blizzard_get(r, path, params, timeout=20.0):
        recorded["path"] = path
        recorded["params"] = params
        return FakeResponse(payload)

    monkeypatch.setattr("etl.blizzard.game_data.pvp_season.blizzard_get", fake_blizzard_get)

    _ = await fetch_seasons_index(region, "en_US")
    assert recorded["path"] == "/data/wow/pvp-season/index"
    assert recorded["params"]["namespace"] == f"dynamic-{region}"
    assert recorded["params"]["locale"] == "en_US"


@pytest.mark.asyncio
async def test_fetch_seasons_index_http_error_bubbles(monkeypatch):
    async def fake_blizzard_get(*_args, **_kwargs):
        return FakeResponse({}, status_code=500)

    monkeypatch.setattr("etl.blizzard.game_data.pvp_season.blizzard_get", fake_blizzard_get)

    with pytest.raises(RuntimeError):
        await fetch_seasons_index("us")
