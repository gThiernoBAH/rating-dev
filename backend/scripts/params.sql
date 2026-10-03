-- Paramètres applicatifs par défaut (jamais en dur dans le code)
INSERT INTO params (cle, valeur, description) VALUES
 ('cutoff_anciennete_mois', '3',  'Ancienneté minimale (mois) à la clôture pour être évalué'),
 ('palier_insuffisant',    '0;2;Insuffisant 😞',       'Appréciation : note < borne haute'),
 ('palier_moyen',          '2;3;Moyen — Marge de progression 😐', 'Appréciation : 2 à <3'),
 ('palier_bien',           '3;4;Bien 🙂',              'Appréciation : 3 à <4'),
 ('palier_excellent',      '4;5.01;Excellent 😃',       'Appréciation : >= 4'),
 ('seuil_divergence',      '2',  'Badge divergence si |NOTE1-NOTE2| >= seuil');
