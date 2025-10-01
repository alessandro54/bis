from typing import Any
from datetime import datetime
from sqlmodel import SQLModel, Field, Column, JSON, UniqueConstraint

class PvPSeason(SQLModel, table=True):
    __tablename__ = "pvp_seasons"

    id: int = Field(primary_key=True, index=True)
    name_json: dict[str, Any] = Field(
        default_factory=dict,
        sa_column=Column(JSON),
        description="Localized names for the PvP season",
    )
    is_current: bool = Field(default=False, index=True)
    updated_at: datetime = Field(default_factory=datetime.utcnow, index=True)
    raw_json: dict[str, Any] = Field(
        default_factory=dict,
        sa_column=Column(JSON),
        description="Raw JSON data from the API",
    )

    __table_args__ = (
        UniqueConstraint("id", name="uq_pvp_seasons_id"),
    )
