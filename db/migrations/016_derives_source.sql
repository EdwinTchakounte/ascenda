-- Garder le contenu d'origine d'un dérivé quand on le retouche.
--
-- Les quiz et les commentaires de citations ont été rédigés sans accents.
-- `app.outils.corriger_corpus` les réaccentue à partir de l'usage du corpus et
-- range ici le contenu tel qu'il était. La retouche ne change ni l'identité du
-- dérivé ni l'ordre des réponses : une question déjà passée reste la même.
--
-- Idempotente : rejouable sans dommage.

begin;

alter table derivative add column if not exists content_source jsonb;

commit;
