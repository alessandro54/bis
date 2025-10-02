import asyncio
import json
from pathlib import Path

from etl.pvp.seasons import fetch_season_details

print("Fetching PvP seasons index...")

async def main():
    seasons = await fetch_season_details("us", 40)

    # Choose an output file (repo root or etl/data)
    output_file = Path(__file__).parent / "seasons_index.json"

    with output_file.open("w", encoding="utf-8") as f:
        json.dump(seasons, f, indent=2, ensure_ascii=False)

    print(f"✅ Wrote {len(seasons)} seasons to {output_file}")

if __name__ == "__main__":
    asyncio.run(main())
