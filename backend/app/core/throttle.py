# 2026-10-02 — throttle login : 5 échecs -> verrouillage 15 minutes (en mémoire,
# suffisant en mono-instance ; à remplacer par table si clustering un jour).
import time
from collections import defaultdict

from app.core.settings import get_settings

_failures: dict[str, list[float]] = defaultdict(list)


def is_locked(matricule: str) -> int:
    """Retourne le nombre de secondes de verrouillage restantes (0 = non verrouillé)."""
    settings = get_settings()
    now = time.monotonic()
    window = settings.LOGIN_LOCK_MINUTES * 60
    _failures[matricule] = [t for t in _failures[matricule] if now - t < window]
    if len(_failures[matricule]) >= settings.LOGIN_MAX_FAILURES:
        oldest = _failures[matricule][0]
        return int(window - (now - oldest))
    return 0


def register_failure(matricule: str) -> None:
    _failures[matricule].append(time.monotonic())


def reset_failures(matricule: str) -> None:
    _failures.pop(matricule, None)
