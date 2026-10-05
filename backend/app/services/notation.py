# 2026-10-02 — moteur de notation (§7) : NOTE, VALEUR = NOTE x COEFF, totaux,
# note globale = Somme(VALEUR)/Somme(COEFF), étoiles, divergence N vs N+1.
# Les formules sont ici ET dans les vues SQL — golden tests (étape 7) garantissent l'équivalence.
def calc_valeur(note: float, coefficient: float) -> float:
    return round(note * coefficient, 2)


def calc_totale_valeur(lignes: list[tuple[float, float]]) -> float:
    """lignes = [(note, coefficient), ...] -> Somme(note x coeff)"""
    return round(sum(n * c for n, c in lignes), 2)


def calc_note_globale(lignes: list[tuple[float, float]]) -> float | None:
    """Somme(valeur) / Somme(coeff), arrondi à 2 décimales. None si vide."""
    total_coeff = sum(c for _, c in lignes)
    if not lignes or total_coeff == 0:
        return None
    return round(calc_totale_valeur(lignes) / total_coeff, 2)


def calc_rate(note: float | None) -> int | None:
    """Étoiles automatiques : 1 à 5 selon la note (plafonnée/bornée)."""
    if note is None:
        return None
    return max(1, min(5, int(note + 0.999)))  # arrondi supérieur borné 1..5


def est_divergente(note1: float | None, note2: float | None, seuil: float = 2) -> bool:
    """Badge divergence (annexe A.5) si |NOTE1-NOTE2| >= seuil."""
    if note1 is None or note2 is None:
        return False
    return abs(note1 - note2) >= seuil


# ================== PATCH 12 : normalisation des détails à intervalle ==================

def note_detail(detail, valeur_choisie=None) -> float:
    """Note /5 d'un détail coché. Valeur unique -> valeur brute.
    Intervalle (sens=2) -> valeur choisie (étoiles) normalisée par diviseur
    max/5 (ex. 7-9 sur 20 -> 7/4=1.75 .. 9/4=2.25 sur 5)."""
    v = valeur_choisie if valeur_choisie is not None else float(detail.valeur)
    sens = getattr(detail, "sens", 1) or 1
    vmax = getattr(detail, "valeur_max", None)
    if sens == 2 and vmax:
        return round(float(v) * 5.0 / float(vmax), 2)
    return round(float(v), 2)
