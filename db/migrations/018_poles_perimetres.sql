-- Pôles d'axes et périmètres de chapitres.
--
-- Jusqu'ici, un ouvrage entrait tout entier dans un axe. Le Mémento de
-- l'agronome (1 698 pages) couvre à la fois le développement rural, l'agronomie,
-- la protection des cultures, les cultures, l'élevage et la pisciculture : le
-- mettre entier dans chaque axe ferait lire l'aviculture à qui veut soigner son
-- maïs.
--
-- Deux ajouts :
--
-- - `axis.parent_id`, déjà présent, sert enfin : un pôle regroupe des
--   sous-axes. Le pôle n'a pas d'ouvrage à lui ; ses sous-axes en ont ;
-- - `axis_chapter` borne un ouvrage à certains de ses chapitres pour un axe.
--   Un ouvrage sans ligne ici pour cet axe y entre tout entier, comme avant.
--
-- Idempotente : rejouable sans dommage.

begin;

create table if not exists axis_chapter (
  axis_id    uuid not null references axis(id) on delete cascade,
  chapter_id uuid not null references chapter(id) on delete cascade,
  primary key (axis_id, chapter_id)
);
create index if not exists ix_axis_chapter_chapitre on axis_chapter (chapter_id);

insert into axis (slug, label, description, sort_order, parent_id) values
('12-agriculture-elevage', 'Agriculture et élevage',
 'Produire, protéger et valoriser : les savoirs agronomiques au service des exploitations.', 12, null)
on conflict (slug) do nothing;

insert into axis (slug, label, description, sort_order, parent_id)
select v.slug, v.label, v.description, v.ordre, p.id
  from (values
    ('12-1-developpement-rural', 'Développement rural et filières',
     'Diagnostiquer un territoire, monter un projet, organiser les producteurs, financer et former.', 121),
    ('12-2-agronomie-exploitation', 'Agronomie et exploitation',
     'Le sol, le climat, la fertilité, l''eau, les itinéraires techniques et la gestion d''une exploitation.', 122),
    ('12-3-protection-cultures', 'Protection des cultures',
     'Reconnaître maladies, ravageurs et mauvaises herbes, et choisir une lutte raisonnée.', 123),
    ('12-4-cultures-plantes', 'Cultures et plantes utiles',
     'Céréales, tubercules, légumineuses, fruitiers, légumes, cultures de rente, fourrages et plantes utiles, fiche par fiche.', 124),
    ('12-5-elevage-sante-animale', 'Élevage et santé animale',
     'Bovins, petits ruminants, porcs, volailles : alimentation, conduite des troupeaux et santé animale.', 125),
    ('12-6-pisciculture-petits-elevages', 'Pisciculture et petits élevages',
     'Élever des poissons en eau douce, et les élevages non conventionnels.', 126)
  ) as v(slug, label, description, ordre)
  cross join (select id from axis where slug = '12-agriculture-elevage') p
on conflict (slug) do nothing;

commit;
