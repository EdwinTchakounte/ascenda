-- Garder le titre d'origine d'un chapitre quand on le corrige.
--
-- L'extraction laisse passer des titres cassés : numéro de page, bandeau de mise
-- en page, mot coupé, nom de fichier de numérisation. `app.outils.corriger_corpus`
-- les remplace par un titre lisible et range l'original ici. Rejouer la
-- correction ne réécrit jamais l'original.
--
-- Idempotente : rejouable sans dommage.

begin;

alter table chapter add column if not exists title_source text;

commit;
