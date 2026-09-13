/// Les données du cercle de lecteurs, telles que l'API les renvoie.
library;

DateTime? _date(dynamic v) => v == null ? null : DateTime.tryParse('$v')?.toLocal();

class CompteursCercle {
  const CompteursCercle({this.demandes = 0, this.messages = 0, this.encouragements = 0});

  final int demandes;
  final int messages;
  final int encouragements;

  int get total => demandes + messages + encouragements;

  factory CompteursCercle.depuisJson(Map<String, dynamic> j) => CompteursCercle(
        demandes: j['demandes'] as int? ?? 0,
        messages: j['messages'] as int? ?? 0,
        encouragements: j['encouragements'] as int? ?? 0,
      );
}

class CercleMoi {
  const CercleMoi({
    required this.code,
    required this.partageActivite,
    required this.compteurs,
    required this.messagePartage,
  });

  final String code;
  final bool partageActivite;
  final CompteursCercle compteurs;
  final String messagePartage;

  factory CercleMoi.depuisJson(Map<String, dynamic> j) => CercleMoi(
        code: '${j['code']}',
        partageActivite: j['partage_activite'] != false,
        compteurs: CompteursCercle.depuisJson((j['compteurs'] as Map?)?.cast<String, dynamic>() ?? {}),
        messagePartage: '${j['message_partage'] ?? ''}',
      );
}

class Lecteur {
  const Lecteur({required this.id, required this.nom});

  final String id;
  final String nom;

  String get initiale => nom.isEmpty ? '?' : String.fromCharCode(nom.runes.first).toUpperCase();

  factory Lecteur.depuisJson(Map<String, dynamic> j) => Lecteur(id: '${j['id']}', nom: '${j['nom'] ?? ''}');
}

class LectureAmi {
  const LectureAmi({
    required this.partage,
    this.seancesSemaine = 0,
    this.minutesSemaine = 0,
    this.joursActifs14 = 0,
    this.derniereActivite,
    this.lit,
  });

  final bool partage;
  final int seancesSemaine;
  final int minutesSemaine;
  final int joursActifs14;
  final DateTime? derniereActivite;
  final String? lit;

  factory LectureAmi.depuisJson(Map<String, dynamic> j) => LectureAmi(
        partage: j['partage'] == true,
        seancesSemaine: j['seances_semaine'] as int? ?? 0,
        minutesSemaine: j['minutes_semaine'] as int? ?? 0,
        joursActifs14: j['jours_actifs_14'] as int? ?? 0,
        derniereActivite: _date(j['derniere_activite']),
        lit: j['lit'] as String?,
      );
}

class Ami {
  const Ami({required this.lecteur, required this.nonLus, required this.lecture, this.amisDepuis});

  final Lecteur lecteur;
  final int nonLus;
  final LectureAmi lecture;
  final DateTime? amisDepuis;

  factory Ami.depuisJson(Map<String, dynamic> j) => Ami(
        lecteur: Lecteur.depuisJson(j),
        nonLus: j['non_lus'] as int? ?? 0,
        lecture: LectureAmi.depuisJson((j['lecture'] as Map?)?.cast<String, dynamic>() ?? {}),
        amisDepuis: _date(j['amis_depuis']),
      );
}

class DemandeAmi {
  const DemandeAmi({required this.id, required this.lecteur, this.le});

  final String id;
  final Lecteur lecteur;
  final DateTime? le;

  factory DemandeAmi.depuisJson(Map<String, dynamic> j) => DemandeAmi(
        id: '${j['id']}',
        lecteur: Lecteur.depuisJson((j['lecteur'] as Map).cast<String, dynamic>()),
        le: _date(j['le']),
      );
}

class Demandes {
  const Demandes({this.recues = const [], this.envoyees = const []});

  final List<DemandeAmi> recues;
  final List<DemandeAmi> envoyees;

  factory Demandes.depuisJson(Map<String, dynamic> j) => Demandes(
        recues: [for (final d in (j['recues'] as List? ?? [])) DemandeAmi.depuisJson((d as Map).cast())],
        envoyees: [for (final d in (j['envoyees'] as List? ?? [])) DemandeAmi.depuisJson((d as Map).cast())],
      );
}

class EvenementFil {
  const EvenementFil({
    required this.id,
    required this.genre,
    required this.texte,
    required this.lecteur,
    required this.encourage,
    this.ouvrage,
    this.le,
  });

  final String id;
  final String genre;
  final String texte;
  final Lecteur lecteur;
  final bool encourage;
  final String? ouvrage;
  final DateTime? le;

  EvenementFil encourageable(bool valeur) => EvenementFil(
      id: id, genre: genre, texte: texte, lecteur: lecteur, encourage: valeur, ouvrage: ouvrage, le: le);

  factory EvenementFil.depuisJson(Map<String, dynamic> j) => EvenementFil(
        id: '${j['id']}',
        genre: '${j['genre']}',
        texte: '${j['texte']}',
        lecteur: Lecteur.depuisJson((j['lecteur'] as Map).cast<String, dynamic>()),
        encourage: j['encourage'] == true,
        ouvrage: j['ouvrage'] as String?,
        le: _date(j['le']),
      );
}

class EncouragementRecu {
  const EncouragementRecu({
    required this.id,
    required this.genre,
    required this.message,
    required this.auteur,
    required this.nouveau,
    this.ouvrage,
    this.le,
  });

  final String id;
  final String genre;
  final String message;
  final Lecteur auteur;
  final bool nouveau;
  final String? ouvrage;
  final DateTime? le;

  factory EncouragementRecu.depuisJson(Map<String, dynamic> j) => EncouragementRecu(
        id: '${j['id']}',
        genre: '${j['genre']}',
        message: '${j['message']}',
        auteur: Lecteur.depuisJson((j['auteur'] as Map).cast<String, dynamic>()),
        nouveau: j['nouveau'] == true,
        ouvrage: j['ouvrage'] as String?,
        le: _date(j['le']),
      );
}

class Echange {
  const Echange({required this.id, required this.texte, required this.deMoi, required this.lu, this.le});

  final String id;
  final String texte;
  final bool deMoi;
  final bool lu;
  final DateTime? le;

  factory Echange.depuisJson(Map<String, dynamic> j) => Echange(
        id: '${j['id']}',
        texte: '${j['texte']}',
        deMoi: j['de_moi'] == true,
        lu: j['lu'] == true,
        le: _date(j['le']),
      );
}

class Conversation {
  const Conversation({required this.ami, required this.messages});

  final Lecteur ami;
  final List<Echange> messages;

  factory Conversation.depuisJson(Map<String, dynamic> j) => Conversation(
        ami: Lecteur.depuisJson((j['ami'] as Map).cast<String, dynamic>()),
        messages: [for (final m in (j['messages'] as List? ?? [])) Echange.depuisJson((m as Map).cast())],
      );
}

/// « il y a 3 h », « hier », « le 12/09 » : une date que l'on lit d'un coup
/// d'œil dans un fil, sans calcul.
String ilYA(DateTime? d, {DateTime? maintenant}) {
  if (d == null) return '';
  final m = maintenant ?? DateTime.now();
  final ecart = m.difference(d);
  if (ecart.inMinutes < 1) return "à l'instant";
  if (ecart.inMinutes < 60) return 'il y a ${ecart.inMinutes} min';
  if (ecart.inHours < 24 && m.day == d.day) return 'il y a ${ecart.inHours} h';
  final hier = DateTime(m.year, m.month, m.day).subtract(const Duration(days: 1));
  if (!d.isBefore(hier)) return 'hier';
  if (ecart.inDays < 7) return 'il y a ${ecart.inDays} jours';
  return 'le ${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';
}
