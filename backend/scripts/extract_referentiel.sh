#!/bin/bash
# extract_referentiel.sh — extraction SQL Server -> CSV (séparateur |)
OUT=extract_referentiel
mkdir -p "$OUT"

read -s -p "Mot de passe SA : " SAPWD; echo

q() {  # q <NomFichier> <requête>
  sqlcmd -S localhost -U SA -P "$SAPWD" -C -d R_SIVOP -W -s "|" -Q "SET NOCOUNT ON; $2" \
    | grep -v '^$' | tail -n +3 > "$OUT/$1.csv"
  echo "  $OUT/$1.csv : $(wc -l < "$OUT/$1.csv") lignes"
}

# 1. Référentiel simple
q Sites          "SELECT SITE, LIBELLE FROM R_SIVOPb ORDER BY SITE;"
q Departements   "SELECT DEPARTEMENT, LIBELLE FROM R_SIVOPd ORDER BY DEPARTEMENT;"
q Sections       "SELECT SECTION, LIBELLE, DEPART FROM R_SIVOPs ORDER BY SECTION;"
q Categories     "SELECT CATEGORIE FROM R_SIVOPc ORDER BY CATEGORIE;"
q Postes         "SELECT POSTE, LIBELLE FROM R_SIVOPa ORDER BY POSTE;"
q Emplois        "SELECT EMPLOI, LIBELLE FROM R_SIVOPe ORDER BY EMPLOI;"

# 2. Critères et détails
q Criteres       "SELECT NUM_CRITERE, DESCRIPTIF FROM R_SIVOPt ORDER BY NUM_CRITERE;"
q CritereDetails "SELECT x.NUM_DETAIL_CRITERE, v.NUM_CRITERE, x.DESCRIPTIF, x.VALEUR FROM R_SIVOPx x JOIN R_SIVOPv v ON v.NUM_DETAIL_CRITERE = x.NUM_DETAIL_CRITERE ORDER BY v.NUM_CRITERE, x.VALEUR;"

# 3. Profils
q Profils        "SELECT NUM_PROFIL, DESCRIPTIF FROM R_SIVOPp ORDER BY NUM_PROFIL;"
q ProfilCriteres "SELECT q.NUM_PROFIL, q.NUM_CRITERE, t.COEFFICIENT, 0 FROM R_SIVOPq q JOIN R_SIVOPt t ON t.NUM_CRITERE = q.NUM_CRITERE ORDER BY q.NUM_PROFIL, q.NUM_CRITERE;"

# 4. Emplois <-> Profils (via LETTRE)
q EmploiProfils  "SELECT e.EMPLOI, k.PROFIL, ISNULL(k.NUM, 0) FROM R_SIVOPe e JOIN R_SIVOPk k ON k.LETRRE = e.LETTRE ORDER BY e.EMPLOI, k.NUM;"

# 5. Salariés actifs
q Salaries       "SELECT CAST(j.MATRICULE AS varchar(20)), j.NOM, j.PRENOM, j.SITE, j.DEPARTEMENT, j.SECTION, j.EMPLOI, j.CATEGORIE, j.POSTE, CONVERT(varchar(10), j.DATENT, 120), '', CAST(j.SN1 AS varchar(20)), CASE WHEN j.ACTIF = 0 THEN 1 ELSE 0 END FROM R_SIVOPj j WHERE j.ACTIF = 1 AND j.DATESORT IS NULL ORDER BY j.MATRICULE;"

echo "Terminé."