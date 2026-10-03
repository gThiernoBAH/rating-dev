-- =============================================================================
-- HIF-RATING — schema PostgreSQL complet (ratingdb_dev / ratingdb)
-- 2026-10-02 — cahier des charges v2 §12. Aucun SQL dynamique générique.
-- =============================================================================
BEGIN;

CREATE TYPE statut_etape    AS ENUM ('En cours', 'Clôturée');
CREATE TYPE statut_global   AS ENUM ('En cours', 'Approuvé');
CREATE TYPE etape_eval      AS ENUM ('N', 'N+1');
CREATE TYPE decision_approb AS ENUM ('Approuvé', 'Approuvé avec réserves');
CREATE TYPE statut_campagne AS ENUM ('Brouillon', 'Ouverte', 'Clôturée');

-- ---------------------------------------------------------------- référentiel
CREATE TABLE sites (
    id      serial PRIMARY KEY,
    code    varchar(20)  NOT NULL UNIQUE,
    libelle varchar(120) NOT NULL
);

CREATE TABLE departements (
    id      serial PRIMARY KEY,
    code    varchar(20)  NOT NULL UNIQUE,
    libelle varchar(120) NOT NULL,
    site_id integer REFERENCES sites(id)
);

CREATE TABLE sections (
    id            serial PRIMARY KEY,
    code          varchar(20)  NOT NULL UNIQUE,
    libelle       varchar(120) NOT NULL,
    departement_id integer NOT NULL REFERENCES departements(id)
);

CREATE TABLE emplois (
    id      serial PRIMARY KEY,
    code    varchar(20)  NOT NULL UNIQUE,
    libelle varchar(120) NOT NULL,
    famille smallint NOT NULL CHECK (famille IN (1, 2, 3))  -- 1 Cadres / 2 AM / 3 Empl.-Ouvr.
);

CREATE TABLE categories (
    id      serial PRIMARY KEY,
    code    varchar(20)  NOT NULL UNIQUE,
    libelle varchar(120) NOT NULL
);

CREATE TABLE postes (
    id      serial PRIMARY KEY,
    code    varchar(20)  NOT NULL UNIQUE,
    libelle varchar(120) NOT NULL
);

CREATE TABLE criteres (
    id      serial PRIMARY KEY,
    code    varchar(20)  NOT NULL UNIQUE,
    libelle varchar(200) NOT NULL,
    actif   boolean NOT NULL DEFAULT true
);

-- Détail de critère : libellé descriptif (visible, coché en QCM) + valeur cachée
CREATE TABLE critere_details (
    id                 serial PRIMARY KEY,
    critere_id         integer NOT NULL REFERENCES criteres(id) ON DELETE CASCADE,
    libelle_descriptif varchar(300) NOT NULL,
    valeur             numeric(5,2) NOT NULL CHECK (valeur >= 0),
    ordre              integer NOT NULL DEFAULT 0
);
CREATE INDEX ix_critere_details_critere ON critere_details(critere_id, ordre);

CREATE TABLE profils (
    id      serial PRIMARY KEY,
    code    varchar(20)  NOT NULL UNIQUE,
    libelle varchar(120) NOT NULL
);

-- Profil = ensemble de critères pondérés (COEFF.)
CREATE TABLE profil_criteres (
    id          serial PRIMARY KEY,
    profil_id   integer NOT NULL REFERENCES profils(id) ON DELETE CASCADE,
    critere_id  integer NOT NULL REFERENCES criteres(id),
    coefficient numeric(5,2) NOT NULL CHECK (coefficient > 0),
    ordre       integer NOT NULL DEFAULT 0,
    UNIQUE (profil_id, critere_id)
);

-- Paramétrage fort profils <-> emplois (nombre libre, ordonnable)
CREATE TABLE emploi_profils (
    id        serial PRIMARY KEY,
    emploi_id integer NOT NULL REFERENCES emplois(id) ON DELETE CASCADE,
    profil_id integer NOT NULL REFERENCES profils(id),
    ordre     integer NOT NULL DEFAULT 0,
    UNIQUE (emploi_id, profil_id)
);

-- ------------------------------------------------------------------ salaries
CREATE TABLE salaries (
    id              serial PRIMARY KEY,
    matricule       varchar(20)  NOT NULL UNIQUE,          -- identifiant de connexion
    nom             varchar(120) NOT NULL,
    prenoms         varchar(120),
    site_id         integer REFERENCES sites(id),
    departement_id  integer REFERENCES departements(id),
    section_id      integer REFERENCES sections(id),
    emploi_id       integer REFERENCES emplois(id),
    categorie_id    integer REFERENCES categories(id),
    poste_id        integer REFERENCES postes(id),
    date_embauche   date,
    email           varchar(200),
    n1_id           integer REFERENCES salaries(id),       -- responsable direct (N+1)
    hors_evaluation boolean NOT NULL DEFAULT false,
    is_admin        boolean NOT NULL DEFAULT false,        -- rôle Admin (tout en lecture + CRUD)
    is_active       boolean NOT NULL DEFAULT true,
    must_change_password boolean NOT NULL DEFAULT false,   -- mot de passe provisoire migration
    password_hash   varchar(255),
    date_creation   timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ix_salaries_n1      ON salaries(n1_id);
CREATE INDEX ix_salaries_section ON salaries(section_id);

-- ----------------------------------------------------------------- campagnes
CREATE TABLE campagnes (
    id             serial PRIMARY KEY,
    nom            varchar(120) NOT NULL,
    exercice       integer NOT NULL,                        -- 2025, 2026…
    date_ouverture date,
    date_cloture   date,
    statut         statut_campagne NOT NULL DEFAULT 'Brouillon',
    created_at     timestamptz NOT NULL DEFAULT now(),
    UNIQUE (nom, exercice)
);

-- --------------------------------------------------------------- evaluations
-- 1 seule fiche par salarié et par campagne (contrainte SQL dure)
CREATE TABLE evaluations (
    id                serial PRIMARY KEY,
    campagne_id       integer NOT NULL REFERENCES campagnes(id),
    salarie_id        integer NOT NULL REFERENCES salaries(id),
    numero            varchar(20) NOT NULL UNIQUE,         -- ex. 26000610 : exercice + séquence
    date_evaluation   date,
    statut_n          statut_etape  NOT NULL DEFAULT 'En cours',
    statut_n1         statut_etape  NOT NULL DEFAULT 'En cours',
    statut_n2         statut_etape  NOT NULL DEFAULT 'En cours',
    statut_global     statut_global NOT NULL DEFAULT 'En cours',
    commentaire_global text,
    UNIQUE (campagne_id, salarie_id)
);
CREATE INDEX ix_evaluations_campagne ON evaluations(campagne_id);

-- Ligne de saisie par (fiche, profil, critère, étape).
-- Règle : commentaire obligatoire dès qu'un détail est coché (CHECK + service).
CREATE TABLE evaluation_lignes (
    id                serial PRIMARY KEY,
    evaluation_id     integer NOT NULL REFERENCES evaluations(id) ON DELETE CASCADE,
    profil_id         integer NOT NULL REFERENCES profils(id),
    critere_id        integer NOT NULL REFERENCES criteres(id),
    etape             etape_eval NOT NULL,
    critere_detail_id integer REFERENCES critere_details(id),
    commentaire       text,
    horodatage        timestamptz NOT NULL DEFAULT now(),
    UNIQUE (evaluation_id, profil_id, critere_id, etape),
    CHECK (critere_detail_id IS NULL OR commentaire IS NULL OR length(trim(commentaire)) > 0)
);
CREATE INDEX ix_eval_lignes_eval ON evaluation_lignes(evaluation_id, etape);

-- Approbation N+2 : Approuvé / Approuvé avec réserves + observation. Jamais de re-notation.
CREATE TABLE approbations (
    id            serial PRIMARY KEY,
    evaluation_id integer NOT NULL UNIQUE REFERENCES evaluations(id) ON DELETE CASCADE,
    decision      decision_approb NOT NULL,
    observation   text,
    auteur_id     integer NOT NULL REFERENCES salaries(id),
    horodatage    timestamptz NOT NULL DEFAULT now()
);

-- ------------------------------------------------------------ périphériques
CREATE TABLE notifications (
    id         serial PRIMARY KEY,
    salarie_id integer NOT NULL REFERENCES salaries(id) ON DELETE CASCADE,
    titre      varchar(200) NOT NULL,
    message    text NOT NULL,
    lu         boolean NOT NULL DEFAULT false,
    horodatage timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ix_notifications_salarie ON notifications(salarie_id, lu);

-- Audit renforcé : toute écriture tracée (auteur, avant/après, justification déverrouillage)
CREATE TABLE audit_log (
    id             serial PRIMARY KEY,
    auteur_id      integer REFERENCES salaries(id),
    action         varchar(60) NOT NULL,
    table_cible    varchar(60) NOT NULL,
    enregistrement_id integer,
    avant          jsonb,
    apres          jsonb,
    justification  text,
    horodatage     timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE params (
    cle         varchar(60) PRIMARY KEY,
    valeur      varchar(300) NOT NULL,
    description text
);

-- -------------------------------------------------------------------- VUES
-- v_notation : note, valeur = note x coeff, rate par ligne (§7)
CREATE OR REPLACE VIEW v_notation AS
SELECT
    l.evaluation_id,
    l.etape,
    l.profil_id,
    p.libelle            AS profil_libelle,
    l.critere_id,
    c.libelle            AS critere_libelle,
    pc.coefficient,
    d.valeur             AS note,
    round(d.valeur * pc.coefficient, 2) AS valeur,
    l.critere_detail_id,
    l.commentaire,
    least(5, greatest(1, ceil(d.valeur)))::int AS rate  -- étoiles 1..5
FROM evaluation_lignes l
JOIN profil_criteres pc ON pc.profil_id = l.profil_id AND pc.critere_id = l.critere_id
JOIN criteres c        ON c.id = l.critere_id
JOIN profils p         ON p.id = l.profil_id
LEFT JOIN critere_details d ON d.id = l.critere_detail_id
WHERE l.critere_detail_id IS NOT NULL;

-- v_notation_globale : note globale par étape (Σvaleur / Σcoeff) (§7)
CREATE OR REPLACE VIEW v_notation_globale AS
SELECT
    n.evaluation_id,
    n.etape,
    sum(n.valeur)                    AS total_valeur,
    sum(n.coefficient)               AS total_coeff,
    round(sum(n.valeur) / nullif(sum(n.coefficient), 0), 2) AS note_globale
FROM v_notation n
GROUP BY n.evaluation_id, n.etape;

-- v_benchmark_section : moyenne par critère de la section (§8)
CREATE OR REPLACE VIEW v_benchmark_section AS
SELECT
    e.campagne_id,
    s.section_id,
    n.critere_id,
    cc.libelle AS critere_libelle,
    round(avg(n.note), 2) AS moyenne_note
FROM v_notation n
JOIN evaluations e ON e.id = n.evaluation_id
JOIN salaries s    ON s.id = e.salarie_id
JOIN criteres cc   ON cc.id = n.critere_id
WHERE s.section_id IS NOT NULL
GROUP BY e.campagne_id, s.section_id, n.critere_id, cc.libelle;

-- v_avancement_campagne : % d'avancement par étape (§10)
CREATE OR REPLACE VIEW v_avancement_campagne AS
SELECT
    campagne_id,
    count(*)                                        AS total_fiches,
    count(*) FILTER (WHERE statut_n  = 'Clôturée')  AS cloturees_n,
    count(*) FILTER (WHERE statut_n1 = 'Clôturée')  AS cloturees_n1,
    count(*) FILTER (WHERE statut_n2 = 'Clôturée')  AS cloturees_n2,
    count(*) FILTER (WHERE statut_global = 'Approuvé') AS approuvees,
    round(100.0 * count(*) FILTER (WHERE statut_n  = 'Clôturée') / count(*), 1) AS pct_n,
    round(100.0 * count(*) FILTER (WHERE statut_n1 = 'Clôturée') / count(*), 1) AS pct_n1,
    round(100.0 * count(*) FILTER (WHERE statut_n2 = 'Clôturée') / count(*), 1) AS pct_n2
FROM evaluations
GROUP BY campagne_id;

COMMIT;
