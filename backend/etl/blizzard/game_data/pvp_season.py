from etl.blizzard.request import blizzard_get


async def fetch_seasons_index(region: str, locale: str = "en_US"):
    ns = f"dynamic-{region}"
    r = await blizzard_get(
        region,
        "/data/wow/pvp-season/index", {
            "namespace": ns,
            "locale": locale
        }
    )
    r.raise_for_status()
    return r.json().get("seasons", [])


async def fetch_season(region: str, pvp_season_id: int, locale: str = "en_US"):
    ns = f"dynamic-{region}"
    r = await blizzard_get(
        region,
        f"/data/wow/pvp-season/{pvp_season_id}", {
            "namespace": ns,
            "locale": locale
        }
    )
    r.raise_for_status()
    return r.json()


async def fetch_leaderboards_index(region: str, pvp_season_id: int, locale: str = "en_US"):
    pass

async def fetch_leaderboard(region: str, pvp_season_id: int, pvp_bracket: str, locale: str = "en_US"):
    pass
