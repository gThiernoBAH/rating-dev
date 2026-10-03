# 2026-10-02 — point d'entrée FastAPI : tous les routeurs (étapes 3 à 10).
# Dev : uvicorn app.main:app --reload --port 8003. Swagger : /docs
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.api import (
    auth, campagnes, dashboard, espace, evaluations, health, navigation,
    notifications, notations, referentiel,
)
from app.core.settings import get_settings

settings = get_settings()

app = FastAPI(
    title=settings.APP_NAME,
    version="1.0.0",
    docs_url="/docs",
    redoc_url="/redoc",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_list,   # vide en prod (nginx relaie /api/)
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(health.router)
app.include_router(auth.router)             # M1 connexion
app.include_router(referentiel.router)      # M5 référentiel (Admin)
app.include_router(campagnes.router)        # M6 campagnes (Admin)
app.include_router(evaluations.router)      # M3 tableau + M4 fiche
app.include_router(notations.router)        # M4bis notations
app.include_router(navigation.router)      # M3bis GRAPHE/RECAP/benchmark
app.include_router(dashboard.router)        # M7 avancement
app.include_router(notifications.router)    # cloche notifications
app.include_router(espace.router)           # M2 Mon espace
