-- Lecture intégrale dans l'application seulement.
--
-- Entre « redistributable » (le texte peut circuler librement) et « extraits
-- seulement », un troisième régime : l'ouvrage se lit en entier, texte et PDF,
-- mais uniquement dans l'application mobile, par un abonné, et hors ligne dans
-- l'espace chiffré de l'application. Jamais depuis le web, jamais en fichier
-- exportable. C'est le régime retenu pour le Mémento de l'agronome.
--
-- Idempotente : rejouable sans dommage.

begin;

alter table document add column if not exists lecture_application boolean not null default false;

update document set lecture_application = true
 where sha256 = 'f3ab9e20051cf571bbc84d48eb06318b318d70837cc31b07c4d9d495ed762ebd'
   and not lecture_application;

commit;
