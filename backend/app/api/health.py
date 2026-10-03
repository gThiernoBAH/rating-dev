# 2026-10-02 — sonde de santé.
from fastapi import APIRouter

router = APIRouter(prefix="/api/health", tags=["Système"])


@router.get("")
def health():
    return {"status": "ok", "app": "EVALPOINT"}
