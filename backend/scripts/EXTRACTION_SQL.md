# Ré-extractions SQL Server requises (2026-10-02)

Adapte les noms de tables/colonnes à ton schéma Delphi, exporte chaque résultat
en .xlsx (une feuille, sans en-tête, colonnes dans l'ordre indiqué).

## CritereDetails.xlsx — RE-EXTRAIRE (valeur + lien critère manquants)
    SELECT d.ID, d.CritereID, d.Libelle, d.Valeur
    FROM DetailCriteres d
    ORDER BY d.CritereID, d.ID
    -- colonnes : num, critere_num, libelle, valeur

## ProfilCriteres.xlsx
    SELECT pc.ProfilID, pc.CritereID, pc.Coefficient, pc.Ordre
    FROM ProfilCriteres pc
    ORDER BY pc.ProfilID, pc.Ordre
    -- colonnes : profil_num, critere_num, coefficient, ordre

## EmploiProfils.xlsx
    SELECT ep.EmploiCode, ep.ProfilID, ep.Ordre
    FROM EmploiProfils ep
    ORDER BY ep.EmploiCode, ep.Ordre
    -- colonnes : emploi_code, profil_num, ordre

## Salaries.xlsx
    SELECT s.Matricule, s.Nom, s.Prenoms,
           s.CodeSite, s.CodeDept, s.CodeSection, s.CodeEmploi,
           s.CodeCategorie, s.CodePoste,
           s.DateEmbauche, s.Email,
           n1.Matricule,              -- N+1 par MATRICULE (pas besoin des ids)
           s.HorsEvaluation
    FROM Salaries s
    LEFT JOIN Salaries n1 ON s.N1ID = n1.ID
    -- colonnes : matricule, nom, prenoms, site_code, dept_code, section_code,
    --   emploi_code, categorie_code, poste_code, date_embauche, email,
    --   n1_matricule, hors_evaluation
