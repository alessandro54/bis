from typing import Any, Dict
from etl.blizzard.request import blizzard_get


async def fetch_character_specializations(
    region: str,
    realm_slug: str,
    character_name: str,
    locale: str = "en_US",
) -> Dict[str, Any]:
    """
    GET /profile/wow/character/{realmSlug}/{characterName}/specializations
    Returns a summary of a character's specializations.

    Parameters:
      - region: e.g. "us", "eu"
      - realm_slug: e.g. "tichondrius"
      - character_name: lower/upper case OK (will be forced to lower)
      - locale: e.g. "en_US"
    """
    ns = f"profile-{region}"
    path = f"/profile/wow/character/{realm_slug}/{character_name.lower()}/specializations"

    r = await blizzard_get(region, path, {"namespace": ns, "locale": locale})
    r.raise_for_status()
    return r.json()
