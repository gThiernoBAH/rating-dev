# 2026-10-02 — golden tests du moteur de notation (annexe A.7) : les formules
# COEFF./NOTE/VALEUR/total/note globale/étoiles doivent être exactes.
from app.services.notation import (
    calc_note_globale, calc_rate, calc_totale_valeur, calc_valeur,
    est_divergente,
)


def test_valeur_egale_note_x_coeff():
    # cas réel : note 2, coeff 3 -> VALEUR 6
    assert calc_valeur(2, 3) == 6.0
    assert calc_valeur(2.5, 2) == 5.0


def test_total_valeur():
    lignes = [(2, 3), (5, 1), (1, 2)]
    # 2x3 + 5x1 + 1x2 = 13
    assert calc_totale_valeur(lignes) == 13.0


def test_note_globale_somme_valeur_sur_somme_coeff():
    lignes = [(2, 3), (5, 1), (1, 2)]   # total coeff 6, total valeur 13
    assert calc_note_globale(lignes) == round(13 / 6, 2)


def test_note_globale_vide_est_none():
    assert calc_note_globale([]) is None
    assert calc_note_globale([(1, 0)]) is None


def test_rate_etoiles_1_a_5():
    assert calc_rate(None) is None
    assert calc_rate(0.5) == 1
    assert calc_rate(2) == 2
    assert calc_rate(3.4) == 4      # arrondi supérieur
    assert calc_rate(5) == 5
    assert calc_rate(9) == 5       # plafonné


def test_divergence_n_vs_n1():
    assert est_divergente(2, 5) is True      # |2-5| = 3 >= seuil 2
    assert est_divergente(3, 4) is False
    assert est_divergente(None, 5) is False


def test_cas_reel_capture():               # exemple du cahier des charges §7
    # NOTE1=2 / NOTE2=5 sur coeff 2 -> VALEUR1=4, VALEUR2=10, divergence
    assert calc_valeur(2, 2) == 4.0
    assert calc_valeur(5, 2) == 10.0
    assert est_divergente(2, 5)
