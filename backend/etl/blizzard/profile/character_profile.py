from typing import Any
from etl.blizzard.request import blizzard_get


async def fetch_character_profile_summary(
    region: str,
    realm_slug: str,
    character_name: str,
    locale: str = "en_US",
) -> dict[str, Any]:
    ns = f"profile-{region}"
    path = f"/profile/wow/character/{realm_slug}/{character_name.lower()}"
    r = await blizzard_get(region, path, {"namespace": ns, "locale": locale})
    r.raise_for_status()
    return r.json()


async def fetch_character_profile_status(
    region: str,
    realm_slug: str,
    character_name: str,
    locale: str = "en_US",
) -> dict[str, Any]:
    ns = f"profile-{region}"
    path = f"/profile/wow/character/{realm_slug}/{character_name.lower()}/status"
    r = await blizzard_get(region, path, {"namespace": ns, "locale": locale})
    r.raise_for_status()
    return r.json()
