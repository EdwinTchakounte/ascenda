-- Migration 004 : libellés d'axes sans tiret cadratin.
-- La migration 002 avait introduit « IA - Fondamentaux... » avec un tiret
-- cadratin, contraire à la règle de rédaction d'ASCENDA. On reformule pour que
-- chaque libellé se lise seul. Idempotente.
UPDATE axis SET label = v.label FROM (VALUES
  ('01-ia-fondamentaux-vulgarisation',     'Fondamentaux de l''IA'),
  ('02-ia-technique-academique',           'IA technique et académique'),
  ('03-ia-outils-pratique-prompting',      'Outils, pratique et prompting'),
  ('04-ia-societe-ethique-philosophie',    'IA, société et éthique'),
  ('05-ia-education-pedagogie',            'IA, éducation et pédagogie'),
  ('06-ia-travail-management-metiers',     'IA, travail et métiers'),
  ('07-afrique-histoire-pensee',           'Afrique, histoire et pensée'),
  ('08-litterature-romans',                'Littérature et romans'),
  ('09-developpement-personnel-influence', 'Développement personnel et influence'),
  ('10-economie-entrepreneuriat-finance',  'Économie, entrepreneuriat et finance'),
  ('11-sciences-environnement',            'Sciences et environnement')
) AS v(slug, label) WHERE axis.slug = v.slug;
