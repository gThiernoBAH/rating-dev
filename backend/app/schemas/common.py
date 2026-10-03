# 2026-10-02 — schémas communs (réponses paginées, messages).
from pydantic import BaseModel


class MessageResponse(BaseModel):
    detail: str
