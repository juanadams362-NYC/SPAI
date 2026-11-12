"""Instrument reference endpoints — what SPAI knows about each instrument."""
from fastapi import APIRouter, HTTPException

from app import instruments

router = APIRouter(prefix="/instruments")


@router.get("")
def list_instruments() -> dict:
    """Every instrument the model can name, with its reference card."""
    cards = [info.as_dict() for info in instruments.all_instruments()]
    return {"count": len(cards), "instruments": cards}


@router.get("/{key}")
def get_instrument(key: str) -> dict:
    """One instrument's reference card, by key or by name."""
    info = instruments.lookup(key)
    if info is None:
        known = ", ".join(i.key for i in instruments.all_instruments())
        raise HTTPException(status_code=404, detail=f"Unknown instrument '{key}'. Known: {known}")
    return info.as_dict()
