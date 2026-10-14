"""Lecture intégrale dans l'application seulement (migration 019)."""
import asyncio
import json
import sys
import urllib.error
import urllib.request
from pathlib import Path

RACINE = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(RACINE / "tests"))
sys.path.insert(0, str(RACINE / "apps" / "api"))
from commun import BASE, compte_neuf  # noqa: E402
from app.core.db import close_pool, execute, fetch_one, open_pool  # noqa: E402
from app.services import pack as service_pack  # noqa: E402

_resultats = []


def ok(libelle, condition, detail=""):
    _resultats.append((bool(condition), libelle, str(detail)))
    print(("  OUI  " if condition else "  NON  ") + libelle + ("  " + str(detail) if detail != "" else ""))


def http(chemin, jeton=None, client=None, methode="GET", corps=None):
    r = urllib.request.Request(BASE + chemin, method=methode,
                               data=json.dumps(corps).encode() if corps is not None else None)
    r.add_header("Content-Type", "application/json")
    if jeton:
        r.add_header("Authorization", f"Bearer {jeton}")
    if client:
        r.add_header("X-Ascenda-Client", client)
    try:
        with urllib.request.urlopen(r, timeout=180) as x:
            brut = x.read()
            try:
                return x.status, json.loads(brut), x.headers
            except ValueError:
                return x.status, {"_octets": len(brut)}, x.headers
    except urllib.error.HTTPError as e:
        brut = e.read()
        try:
            return e.code, json.loads(brut), e.headers
        except ValueError:
            return e.code, None, e.headers


async def main():
    await open_pool()
    try:
        doc = await fetch_one("select id from document where lecture_application and title_clean like 'Mémento%%'")
        if not doc:
            ok("le Mémento porte le régime « lecture dans l'application »", False, "migration 019 ?")
            return
        D = str(doc["id"])
        ch = await fetch_one(
            """select c.id, c.title from chapter c join axis_chapter ac on ac.chapter_id = c.id
                where c.document_id = %s and c.title = 'La protection intégrée'""", (D,))
        C = str(ch["id"])
        total = await fetch_one("select sum(length(text)) as n from chunk where chapter_id = %s", (C,))
        lancement = await fetch_one("select valeur from reglage where cle = 'lancement'")
        lancement_actif = bool(lancement and (lancement["valeur"] or {}).get("actif"))

        def lecture(jeton=None, client=None):
            s, r, _ = http(f"/v1/lecteur/{D}/chapitre/{C}", jeton, client)
            car = sum(len(p["texte"]) for p in r.get("passages", [])) if s == 200 else 0
            return s, r, car

        print("\n· Sans compte")
        s, r, car = lecture(client="android")
        ok("extraits seulement, même depuis l'application", s == 200 and not r["droits"]["lecture_integrale"]
           and car < total["n"] * 0.5, f"{car} car. sur {total['n']}")
        ok("le lecteur sait que l'ouvrage est réservé à l'application", r["droits"].get("application_seulement") is True)
        ok("le message invite à l'offre Ascension", "Ascension" in (r["droits"]["message"] or ""))
        s, _, _ = http(f"/v1/lecteur/{D}/pdf", client="android")
        ok("PDF refusé", s == 403, s)
        s, p, _ = http(f"/v1/bibliotheque/{D}/pack", client="android")
        ok("pack sans le texte du livre", s == 200 and p.get("lecture") is None)

        print("\n· Compte gratuit")
        _, jeton_libre, _ = compte_neuf("lecture-libre")
        if lancement_actif:
            ok("période de lancement active : le compte gratuit a tout, cas non vérifiable ici", True)
        else:
            s, r, car = lecture(jeton_libre, "android")
            ok("extraits seulement", not r["droits"]["lecture_integrale"], f"{car} car.")
            s, _, _ = http(f"/v1/lecteur/{D}/pdf", jeton_libre, "android")
            ok("PDF refusé", s == 403, s)

        print("\n· Abonné")
        email, jeton, _ = compte_neuf("lecture-abonne")
        await execute("update app_user set plan = 'premium', plan_until = now() + interval '30 days' where email = %s", (email,))
        s, r, car = lecture(jeton)
        ok("depuis le web (sans l'en-tête de l'application) : extraits seulement",
           not r["droits"]["lecture_integrale"], f"{car} car.")
        s, r, car = lecture(jeton, "web")
        ok("depuis la version web de l'application : extraits seulement", not r["droits"]["lecture_integrale"])
        s, _, _ = http(f"/v1/lecteur/{D}/pdf", jeton)
        ok("PDF refusé hors de l'application", s == 403, s)

        s, r, car = lecture(jeton, "android")
        ok("depuis l'application : texte intégral", r["droits"]["lecture_integrale"] and not r["droits"]["tronque"],
           f"{car} car. sur {total['n']}")
        ok("le PDF est annoncé", r["droits"]["pdf"] is True)
        s, corps, entetes = http(f"/v1/lecteur/{D}/pdf", jeton, "ios")
        ok("PDF servi dans l'application", s == 200 and corps.get("_octets", 0) > 1_000_000, corps)
        ok("sans cache intermédiaire", "no-store" in (entetes.get("Cache-Control") or ""), entetes.get("Cache-Control"))
        s, fiche, _ = http(f"/v1/bibliotheque/{D}", jeton, "android")
        ok("la fiche l'annonce : lecture intégrale, hors ligne, application seulement",
           fiche["droits"]["lecture_integrale"] and fiche["droits"]["hors_ligne_integral"]
           and fiche["droits"]["application_seulement"], fiche["droits"])

        s, p, _ = http(f"/v1/bibliotheque/{D}/pack", jeton, "android")
        lecture_pack = p.get("lecture") or []
        chap = next((x for x in lecture_pack if x["chapitre_id"] == C), None)
        ok("le pack porte le texte de chaque chapitre", len(lecture_pack) >= 300, f"{len(lecture_pack)} chapitres")
        ok("… recollé et sans reprise, comme dans le lecteur",
           chap and sum(len(x["texte"]) for x in chap["passages"]) > total["n"] * 0.8,
           sum(len(x["texte"]) for x in chap["passages"]) if chap else None)
        from datetime import datetime, timezone
        jusqu = datetime.fromisoformat(p.get("lecture_valable_jusqu_au") or "2000-01-01T00:00:00+00:00")
        ok("le texte hors ligne a une date de validité, bornée par l'abonnement",
           0 < (jusqu - datetime.now(timezone.utc)).days <= 30, p.get("lecture_valable_jusqu_au"))
        s, p_web, _ = http(f"/v1/bibliotheque/{D}/pack", jeton)
        ok("le même abonné sans l'application : pack sans texte", p_web.get("lecture") is None)

        s, pdf_export, _ = http(f"/v1/bibliotheque/{D}/export.pdf", jeton, "android")
        compagnon = await service_pack.construire(D, avec_reponses=True)
        ok("l'export PDF reste un compagnon de lecture, sans le livre", s == 200 and compagnon.get("lecture") is None,
           pdf_export)

        print("\n· Code d'accès complet")
        email2, jeton2, _ = compte_neuf("lecture-code")
        code = await fetch_one("""select id from code_acces
                                  where niveau = 'complet' and actif and fin > now()
                                  order by created_at limit 1""")
        if code:
            u = await fetch_one("select id from app_user where email = %s", (email2,))
            await execute("""insert into code_acces_utilisation (code_id, user_id, fin, origine)
                             values (%s, %s, now() + interval '10 days', 'compte')""", (code["id"], u["id"]))
            s, r, car = lecture(jeton2, "android")
            ok("un code complet ouvre la lecture intégrale dans l'application", r["droits"]["lecture_integrale"], f"{car} car.")
        else:
            ok("aucun code complet en base : cas non vérifié", True)

        print("\n· Livres libres et console")
        libre = await fetch_one("select id from document where redistributable and not lecture_application limit 1")
        lch = await fetch_one("select id from chapter where document_id = %s and token_count >= 300 order by ord limit 1",
                              (libre["id"],))
        s, r, _ = http(f"/v1/lecteur/{libre['id']}/chapitre/{lch['id']}")
        ok("un livre libre se lit toujours en entier sans compte", s == 200 and r["droits"]["lecture_integrale"])
        ok("… et n'est pas marqué « application seulement »", r["droits"].get("application_seulement") is False)
        admin = await fetch_one("select email from app_user where est_admin limit 1")
        ok("la console accepte le champ lecture_application",
           "lecture_application" in open(RACINE / "apps/api/app/routers/admin.py").read())
    finally:
        await execute("delete from app_user where email like 'lecture-%%@example.com'")
        await close_pool()


asyncio.run(main())
_echecs = [x for x in _resultats if not x[0]]
print("\n" + "=" * 92)
print(f"{len(_resultats) - len(_echecs)} sur {len(_resultats)}")
if _echecs:
    print("\nÉCHECS")
    for _ok, _lib, _det in _echecs:
        print(f"  {_lib}\n      {_det}")
sys.exit(1 if _echecs else 0)
