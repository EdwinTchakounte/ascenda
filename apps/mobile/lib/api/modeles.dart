/// Les objets échangés avec l'API. Champs en français, comme l'API elle-même :
/// une seule langue d'un bout à l'autre évite les traductions silencieuses.
library;

int? _entier(dynamic v) => v == null ? null : (v is int ? v : int.tryParse('$v'));
double _reel(dynamic v) => v == null ? 0 : (v is num ? v.toDouble() : double.tryParse('$v') ?? 0);
List<String> _chaines(dynamic v) =>
    v is List ? v.map((e) => '$e').toList() : const <String>[];

class Utilisateur {
  const Utilisateur({
    required this.id,
    required this.email,
    required this.nom,
    required this.plan,
    this.acces,
  });

  final String id;
  final String? email;
  final String? nom;
  final String plan;

  /// Ce que le compte peut faire aujourd'hui. Le plan ne suffit plus à le
  /// dire : un code d'accès ou le lancement ouvrent des fonctions sans le
  /// changer.
  final AccesEffectif? acces;

  /// Abonné payant. Sert à ce qui concerne l'abonnement lui-même (prolonger,
  /// échéance), pas à décider si une fonction est ouverte.
  bool get estPremium => plan != 'free';

  /// Tout Ascension est ouvert, quelle qu'en soit la raison.
  bool get accesComplet => estPremium || (acces?.complet ?? false);

  /// Cette fonction précise est ouverte.
  bool aAcces(String fonction) =>
      accesComplet || (acces?.fonctions.contains(fonction) ?? false);

  factory Utilisateur.depuisJson(Map<String, dynamic> j) => Utilisateur(
        id: '${j['id']}',
        email: j['email'] as String?,
        nom: j['nom'] as String?,
        plan: '${j['plan'] ?? 'free'}',
        acces: j['acces'] is Map<String, dynamic>
            ? AccesEffectif.depuisJson(j['acces'] as Map<String, dynamic>)
            : null,
      );
}

/// L'accès effectif et d'où il vient : `abonnement`, `lancement`, `code` ou
/// `aucune`.
class AccesEffectif {
  const AccesEffectif({
    required this.complet,
    required this.fonctions,
    required this.source,
    required this.jusquAu,
    required this.codes,
  });

  final bool complet;
  final List<String> fonctions;
  final String source;
  final DateTime? jusquAu;
  final List<AccesCode> codes;

  factory AccesEffectif.depuisJson(Map<String, dynamic> j) => AccesEffectif(
        complet: j['complet'] == true,
        fonctions: _chaines(j['fonctions']),
        source: '${j['source'] ?? 'aucune'}',
        jusquAu: _date(j['jusqu_au']),
        codes: (j['codes'] as List? ?? [])
            .map((e) => AccesCode.depuisJson(e as Map<String, dynamic>))
            .toList(),
      );
}

/// Un accès ouvert par un code, tant qu'il court.
class AccesCode {
  const AccesCode({
    required this.code,
    required this.libelle,
    required this.niveau,
    required this.fonctions,
    required this.fin,
    required this.joursRestants,
  });

  final String code;
  final String libelle;

  /// `complet` ou `limite`.
  final String niveau;
  final List<String> fonctions;
  final DateTime? fin;
  final int joursRestants;

  bool get complet => niveau == 'complet';

  factory AccesCode.depuisJson(Map<String, dynamic> j) => AccesCode(
        code: '${j['code']}',
        libelle: '${j['libelle'] ?? ''}',
        niveau: '${j['niveau'] ?? 'limite'}',
        fonctions: _chaines(j['fonctions']),
        fin: _date(j['fin']),
        joursRestants: _entier(j['jours_restants']) ?? 0,
      );
}

/// Une réduction gagnée par un ambassadeur.
class BonReduction {
  const BonReduction({
    required this.pourcent,
    required this.statut,
    required this.expireLe,
    required this.utiliseLe,
    required this.gagneLe,
    required this.filleul,
    required this.nouveau,
  });

  final int pourcent;

  /// `disponible`, `utilise` ou `expire`.
  final String statut;
  final DateTime? expireLe;
  final DateTime? utiliseLe;
  final DateTime? gagneLe;

  /// Le prénom de la personne venue avec le code, et rien de plus.
  final String? filleul;

  /// Pas encore montré dans l'application.
  final bool nouveau;

  bool get disponible => statut == 'disponible';

  factory BonReduction.depuisJson(Map<String, dynamic> j) => BonReduction(
        pourcent: _entier(j['pourcent']) ?? 0,
        statut: '${j['statut'] ?? 'disponible'}',
        expireLe: _date(j['expire_le']),
        utiliseLe: _date(j['utilise_le']),
        gagneLe: _date(j['gagne_le']),
        filleul: j['filleul'] as String?,
        nouveau: j['nouveau'] == true,
      );
}

/// Tout ce que montre l'écran « Codes et avantages ».
class CodesEtAvantages {
  const CodesEtAvantages({
    required this.code,
    required this.programmeActif,
    required this.pourcent,
    required this.validiteJours,
    required this.filleuls,
    required this.messagePartage,
    required this.acces,
    required this.bons,
    required this.nouveaux,
    required this.reductionProchaine,
    required this.libellesFonctions,
  });

  final String code;
  final bool programmeActif;
  final int pourcent;
  final int validiteJours;
  final int filleuls;
  final String messagePartage;
  final AccesEffectif acces;
  final List<BonReduction> bons;
  final int nouveaux;

  /// Le pourcentage qui s'appliquera au prochain paiement, s'il y en a un.
  final int? reductionProchaine;
  final Map<String, String> libellesFonctions;

  List<BonReduction> get nouveauxBons => bons.where((b) => b.nouveau).toList();

  String libelle(String fonction) => libellesFonctions[fonction] ?? fonction.replaceAll('_', ' ');

  factory CodesEtAvantages.depuisJson(Map<String, dynamic> j) {
    final a = j['ambassadeur'] as Map<String, dynamic>? ?? const {};
    final r = j['reduction_prochaine'] as Map<String, dynamic>?;
    return CodesEtAvantages(
      code: '${a['code'] ?? ''}',
      programmeActif: a['actif'] == true,
      pourcent: _entier(a['pourcent']) ?? 0,
      validiteJours: _entier(a['validite_jours']) ?? 0,
      filleuls: _entier(a['filleuls']) ?? 0,
      messagePartage: '${a['message_partage'] ?? ''}',
      acces: AccesEffectif.depuisJson(j['acces'] as Map<String, dynamic>? ?? const {}),
      bons: (j['bons'] as List? ?? [])
          .map((e) => BonReduction.depuisJson(e as Map<String, dynamic>))
          .toList(),
      nouveaux: _entier(j['nouveaux']) ?? 0,
      reductionProchaine: r == null ? null : _entier(r['pourcent']),
      libellesFonctions: {
        for (final f in (j['fonctions'] as List? ?? []))
          '${(f as Map)['cle']}': '${f['libelle']}',
      },
    );
  }
}

class Axe {
  const Axe({
    required this.slug,
    required this.label,
    required this.nbOuvrages,
    required this.nbPages,
    required this.dureeMin,
    required this.premium,
    this.ouvragesExploitables = 0,
    this.parcoursPossible = true,
  });

  final String slug;
  final String label;
  final int nbOuvrages;
  final int nbPages;
  final int dureeMin;
  final bool premium;

  /// Nombre d'ouvrages dont les chapitres sont découpés. Sans eux, le
  /// planificateur n'a rien à répartir en séances.
  final int ouvragesExploitables;
  final bool parcoursPossible;

  factory Axe.depuisJson(Map<String, dynamic> j) => Axe(
        slug: '${j['slug']}',
        label: '${j['label']}',
        nbOuvrages: _entier(j['nb_ouvrages']) ?? 0,
        nbPages: _entier(j['nb_pages']) ?? 0,
        dureeMin: _entier(j['duree_estimee_min']) ?? 0,
        premium: j['premium'] == true,
        ouvragesExploitables: _entier(j['ouvrages_exploitables']) ?? 0,
        parcoursPossible: j['parcours_possible'] != false,
      );
}

class Ouvrage {
  const Ouvrage({
    required this.id,
    required this.titre,
    required this.auteurs,
    this.annee,
    this.pages,
    this.niveau,
    this.type,
    this.dureeMin,
    this.these,
    this.lectureIntegrale = false,
    this.aFiche = false,
    this.aQuiz = false,
    this.axes = const [],
    this.axeSlug,
  });

  final String id;
  final String titre;
  final List<String> auteurs;
  final int? annee;
  final int? pages;
  final String? niveau;
  final String? type;
  final int? dureeMin;
  final String? these;
  final bool lectureIntegrale;
  final bool aFiche;
  final bool aQuiz;
  final List<String> axes;

  /// Le raccourci du premier pôle, qui donne sa teinte à la carte.
  final String? axeSlug;

  String get auteursCourt => auteurs.isEmpty
      ? 'Auteur non renseigné'
      : (auteurs.length > 2 ? '${auteurs.take(2).join(', ')} et al.' : auteurs.join(', '));

  factory Ouvrage.depuisJson(Map<String, dynamic> j) => Ouvrage(
        id: '${j['id']}',
        titre: '${j['titre'] ?? 'Sans titre'}',
        auteurs: _chaines(j['auteurs']),
        annee: _entier(j['annee']),
        pages: _entier(j['pages']),
        niveau: j['niveau'] as String?,
        type: j['type'] as String?,
        dureeMin: _entier(j['duree_min']),
        these: j['these'] as String? ?? (j['pedagogie']?['these_centrale'] as String?),
        lectureIntegrale: j['lecture_integrale'] == true ||
            (j['droits']?['lecture_integrale'] == true),
        aFiche: j['a_fiche'] == true,
        aQuiz: j['a_quiz'] == true,
        axes: (j['axes'] as List?)?.map((a) => '${a['label']}').toList() ?? const [],
        axeSlug: (j['axes'] as List?)?.isNotEmpty == true
            ? '${(j['axes'] as List).first['slug']}'
            : null,
      );
}

class Seance {
  const Seance({
    required this.id,
    required this.objectif,
    required this.dureeMin,
    this.chronogrammeId,
    this.documentId,
    this.ouvrage,
    this.auteurs = const [],
    this.chapitreId,
    this.chapitre,
    this.pageDebut,
    this.pageFin,
    this.livrable,
    this.livrableId,
    this.prevueLe,
    this.statut = 'a_venir',
    this.enRetard = false,
    this.lectureIntegrale = false,
    this.axeLabel,
  });

  final String id;
  final String objectif;
  final int dureeMin;
  final String? chronogrammeId;
  final String? documentId;
  final String? ouvrage;
  final List<String> auteurs;
  final String? chapitreId;
  final String? chapitre;
  final int? pageDebut;
  final int? pageFin;
  final String? livrable;
  final String? livrableId;
  final DateTime? prevueLe;
  final String statut;
  final bool enRetard;
  final bool lectureIntegrale;
  final String? axeLabel;

  bool get faite => statut == 'fait';

  /// Le chapitre à afficher sous le titre de l'ouvrage. Vide quand il répète
  /// ce titre, ce qui arrive sur les pages de garde du corpus.
  String? get sousTitre {
    String net(String? x) =>
        (x ?? '').replaceAll('\u2019', "'").trim().toLowerCase();
    if (chapitre == null || net(chapitre) == net(ouvrage)) return null;
    return chapitre;
  }

  String get pages => pageDebut == null
      ? ''
      : (pageFin == null || pageFin == pageDebut ? 'p. $pageDebut' : 'p. $pageDebut à $pageFin');

  factory Seance.depuisJson(Map<String, dynamic> j) => Seance(
        id: '${j['id']}',
        objectif: '${j['objectif'] ?? ''}',
        dureeMin: _entier(j['duree_min']) ?? 30,
        chronogrammeId: j['chronogramme_id'] as String?,
        documentId: j['document_id'] as String?,
        ouvrage: j['ouvrage'] as String?,
        auteurs: _chaines(j['auteurs']),
        chapitreId: j['chapitre_id'] as String?,
        chapitre: j['chapitre'] as String?,
        pageDebut: _entier(j['page_debut']),
        pageFin: _entier(j['page_fin']),
        livrable: j['livrable'] as String?,
        livrableId: j['livrable_id'] as String?,
        prevueLe: j['prevue_le'] == null ? null : DateTime.tryParse('${j['prevue_le']}')?.toLocal(),
        statut: '${j['statut'] ?? 'a_venir'}',
        enRetard: j['en_retard'] == true,
        lectureIntegrale: j['lecture_integrale'] == true,
        axeLabel: j['axe_label'] as String?,
      );
}

class JourSemaine {
  const JourSemaine({required this.jour, required this.statut, required this.nb});
  final DateTime jour;
  final String statut;
  final int nb;

  factory JourSemaine.depuisJson(Map<String, dynamic> j) => JourSemaine(
        jour: DateTime.parse('${j['jour']}'),
        statut: '${j['statut']}',
        nb: _entier(j['nb']) ?? 0,
      );
}

class Aujourdhui {
  const Aujourdhui({this.seance, this.semaine = const [], this.notionsAReviser = 0});
  final Seance? seance;
  final List<JourSemaine> semaine;
  final int notionsAReviser;

  factory Aujourdhui.depuisJson(Map<String, dynamic> j) => Aujourdhui(
        seance: j['seance'] == null
            ? null
            : Seance.depuisJson(j['seance'] as Map<String, dynamic>),
        semaine: (j['semaine'] as List? ?? [])
            .map((e) => JourSemaine.depuisJson(e as Map<String, dynamic>))
            .toList(),
        notionsAReviser: _entier(j['notions_a_reviser']) ?? 0,
      );
}

class Chronogramme {
  const Chronogramme({
    required this.id,
    required this.axeLabel,
    required this.seances,
    required this.justification,
    this.adaptatif = false,
    this.statut = 'actif',
  });

  final String id;
  final String axeLabel;
  final List<Seance> seances;
  final String justification;
  final bool adaptatif;
  final String statut;

  int get faites => seances.where((s) => s.faite).length;
  double get avancement => seances.isEmpty ? 0 : faites / seances.length;
  /// Une séance prévue aujourd'hui n'est pas en retard : on compare les dates,
  /// pas les horodatages.
  int get enRetard => seances.where((s) {
        if (s.faite || s.prevueLe == null) return false;
        final j = DateTime.now();
        return DateTime(s.prevueLe!.year, s.prevueLe!.month, s.prevueLe!.day)
            .isBefore(DateTime(j.year, j.month, j.day));
      }).length;

  factory Chronogramme.depuisJson(Map<String, dynamic> j) => Chronogramme(
        id: '${j['id']}',
        axeLabel: '${j['axe_label'] ?? j['axe'] ?? ''}',
        justification: '${j['justification'] ?? ''}',
        adaptatif: j['adaptatif'] == true,
        statut: '${j['statut'] ?? 'actif'}',
        seances: (j['seances'] as List? ?? [])
            .map((e) => Seance.depuisJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class Passage {
  const Passage({
    required this.id,
    required this.texte,
    this.pageDebut,
    this.pageFin,
    this.tronque = false,
  });

  final String id;
  final String texte;
  final int? pageDebut;
  final int? pageFin;
  final bool tronque;

  factory Passage.depuisJson(Map<String, dynamic> j) => Passage(
        id: '${j['id']}',
        texte: '${j['texte'] ?? ''}',
        pageDebut: _entier(j['page_debut']),
        pageFin: _entier(j['page_fin']),
        tronque: j['tronque'] == true,
      );
}

class Citation {
  const Citation({
    required this.ouvrage,
    required this.extrait,
    this.page,
    this.chapitre,
    this.documentId,
    this.marque,
  });

  final String ouvrage;
  final String extrait;
  final int? page;
  final String? chapitre;
  final String? documentId;
  final int? marque;

  factory Citation.depuisJson(Map<String, dynamic> j) => Citation(
        ouvrage: '${j['ouvrage'] ?? ''}',
        extrait: '${j['extrait'] ?? j['texte'] ?? ''}',
        page: _entier(j['page']),
        chapitre: j['chapitre'] as String?,
        documentId: j['document_id'] as String?,
        marque: _entier(j['marque']),
      );
}

class MessageAgent {
  const MessageAgent({
    required this.role,
    required this.texte,
    this.citations = const [],
    this.degrade = false,
  });

  final String role;
  final String texte;
  final List<Citation> citations;
  final bool degrade;

  bool get deLUtilisateur => role == 'user';

  factory MessageAgent.depuisJson(Map<String, dynamic> j) => MessageAgent(
        role: '${j['role'] ?? 'assistant'}',
        texte: '${j['texte'] ?? j['reponse'] ?? ''}',
        citations: (j['citations'] as List? ?? [])
            .map((c) => Citation.depuisJson(c as Map<String, dynamic>))
            .toList(),
        degrade: j['degrade'] == true,
      );
}

class QuestionQuiz {
  const QuestionQuiz({
    required this.index,
    required this.question,
    required this.choix,
    this.niveau,
    this.page,
  });

  final int index;
  final String question;
  final List<String> choix;
  final String? niveau;
  final int? page;

  factory QuestionQuiz.depuisJson(Map<String, dynamic> j) => QuestionQuiz(
        index: _entier(j['index']) ?? 0,
        question: '${j['question']}',
        choix: _chaines(j['choix']),
        niveau: j['niveau'] as String?,
        page: _entier(j['page']),
      );
}

class CorrectionQuestion {
  const CorrectionQuestion({
    required this.index,
    required this.question,
    required this.juste,
    this.votreReponse,
    this.bonneReponse,
    this.explication,
    this.page,
    this.extrait,
    this.extraitPage,
  });

  final int index;
  final String question;
  final bool juste;
  final int? votreReponse;
  final int? bonneReponse;
  final String? explication;
  final int? page;
  final String? extrait;
  final int? extraitPage;

  factory CorrectionQuestion.depuisJson(Map<String, dynamic> j) => CorrectionQuestion(
        index: _entier(j['index']) ?? 0,
        question: '${j['question']}',
        juste: j['juste'] == true,
        votreReponse: _entier(j['votre_reponse']),
        bonneReponse: _entier(j['bonne_reponse']),
        explication: j['explication'] as String?,
        page: _entier(j['page']),
        extrait: j['extrait']?['texte'] as String?,
        extraitPage: _entier(j['extrait']?['page']),
      );
}

class Correction {
  const Correction({
    required this.score,
    required this.justes,
    required this.total,
    required this.details,
  });

  final double score;
  final int justes;
  final int total;
  final List<CorrectionQuestion> details;

  bool get reussi => score >= 0.7;

  factory Correction.depuisJson(Map<String, dynamic> j) => Correction(
        score: _reel(j['score']),
        justes: _entier(j['justes']) ?? 0,
        total: _entier(j['total']) ?? 0,
        details: (j['details'] as List? ?? [])
            .map((d) => CorrectionQuestion.depuisJson(d as Map<String, dynamic>))
            .toList(),
      );
}

class Notion {
  const Notion({
    required this.conceptId,
    required this.terme,
    this.definition,
    this.axe,
    this.revisions = 0,
    this.niveau = 'fragile',
  });

  final String conceptId;
  final String terme;
  final String? definition;
  final String? axe;
  final int revisions;
  final String niveau;

  factory Notion.depuisJson(Map<String, dynamic> j) => Notion(
        conceptId: '${j['concept_id']}',
        terme: '${j['terme']}',
        definition: j['definition'] as String?,
        axe: j['axe_label'] as String? ?? j['axe'] as String?,
        revisions: _entier(j['revisions']) ?? 0,
        niveau: '${j['niveau'] ?? 'fragile'}',
      );
}

class Progression {
  const Progression({
    required this.seancesTotal,
    required this.seancesFaites,
    required this.enRetard,
    required this.minutesLues,
    required this.avancement,
    this.scoreMoyen,
    this.tentatives = 0,
    this.ouvragesCommences = 0,
    this.ouvragesTermines = 0,
    this.notionsSuivies = 0,
    this.notionsMaitrisees = 0,
    this.notionsARevoir = 0,
  });

  final int seancesTotal;
  final int seancesFaites;
  final int enRetard;
  final int minutesLues;
  final double avancement;
  final double? scoreMoyen;
  final int tentatives;
  final int ouvragesCommences;
  final int ouvragesTermines;
  final int notionsSuivies;
  final int notionsMaitrisees;
  final int notionsARevoir;

  factory Progression.depuisJson(Map<String, dynamic> j) {
    final s = j['seances'] as Map<String, dynamic>? ?? {};
    final q = j['quiz'] as Map<String, dynamic>? ?? {};
    final o = j['ouvrages'] as Map<String, dynamic>? ?? {};
    final n = j['notions'] as Map<String, dynamic>? ?? {};
    return Progression(
      seancesTotal: _entier(s['total']) ?? 0,
      seancesFaites: _entier(s['faites']) ?? 0,
      enRetard: _entier(s['en_retard']) ?? 0,
      minutesLues: _entier(s['minutes_lues']) ?? 0,
      avancement: _reel(s['avancement']),
      scoreMoyen: q['score_moyen'] == null ? null : _reel(q['score_moyen']),
      tentatives: _entier(q['tentatives']) ?? 0,
      ouvragesCommences: _entier(o['commences']) ?? 0,
      ouvragesTermines: _entier(o['termines']) ?? 0,
      notionsSuivies: _entier(n['suivies']) ?? 0,
      notionsMaitrisees: _entier(n['maitrisees']) ?? 0,
      notionsARevoir: _entier(n['a_revoir']) ?? 0,
    );
  }
}

/// Une formule d'abonnement, telle que l'API la lit dans `plan_tarif`.
///
/// Le montant vient du serveur et jamais du téléphone : une grille tarifaire
/// recopiée dans l'application finit toujours par diverger de ce qui est
/// réellement débité.
class Formule {
  const Formule({
    required this.periodeMois,
    required this.montant,
    required this.devise,
    required this.libelle,
    required this.parMois,
    this.montantReduit,
  });

  final int periodeMois;
  final int montant;
  final String devise;
  final String libelle;
  final int parMois;

  /// Le montant après réduction ambassadeur, quand le lecteur en a une.
  final int? montantReduit;

  /// Ce qui sera réellement demandé.
  int get montantDu => montantReduit ?? montant;
  String get montantDuLisible => '${_millier(montantDu)} $devise';

  /// « 8 000 FCFA », séparateur d'une espace insécable fine comme il se doit.
  String get montantLisible => '${_millier(montant)} $devise';
  String get parMoisLisible => '${_millier(parMois)} $devise';

  /// Ce qu'on économise par rapport au tarif mensuel, en pourcentage.
  int economieContre(Formule mensuel) {
    if (periodeMois <= 1 || mensuel.montant <= 0) return 0;
    final plein = mensuel.montant * periodeMois;
    return ((plein - montant) * 100 / plein).round();
  }

  factory Formule.depuisJson(Map<String, dynamic> j) => Formule(
        periodeMois: _entier(j['periode_mois']) ?? 1,
        montant: _entier(j['montant']) ?? 0,
        devise: '${j['devise'] ?? 'XAF'}',
        libelle: '${j['libelle'] ?? ''}',
        parMois: _entier(j['par_mois']) ?? 0,
        montantReduit: _entier(j['montant_reduit']),
      );
}

class MoyenPaiement {
  const MoyenPaiement({required this.code, required this.libelle, required this.operateur});

  final String code;
  final String libelle;
  final String operateur;

  /// Le code que l'API attend pour `reseau`, en majuscules.
  String get reseau => code.toUpperCase();

  factory MoyenPaiement.depuisJson(Map<String, dynamic> j) => MoyenPaiement(
        code: '${j['code']}',
        libelle: '${j['libelle']}',
        operateur: '${j['operateur'] ?? ''}',
      );
}

class Tarifs {
  const Tarifs({
    required this.moyens,
    required this.formules,
    this.reductionPourcent,
    this.reductionExpire,
  });

  final List<MoyenPaiement> moyens;
  final List<Formule> formules;

  /// La réduction ambassadeur qui s'appliquera, lue par le serveur.
  final int? reductionPourcent;
  final DateTime? reductionExpire;

  Formule? get mensuel {
    for (final f in formules) {
      if (f.periodeMois == 1) return f;
    }
    return formules.isEmpty ? null : formules.first;
  }

  factory Tarifs.depuisJson(Map<String, dynamic> j) => Tarifs(
        moyens: (j['moyens'] as List? ?? [])
            .map((e) => MoyenPaiement.depuisJson(e as Map<String, dynamic>))
            .toList(),
        formules: (j['formules'] as List? ?? [])
            .map((e) => Formule.depuisJson(e as Map<String, dynamic>))
            .toList(),
        reductionPourcent: _entier((j['reduction'] as Map?)?['pourcent']),
        reductionExpire: _date((j['reduction'] as Map?)?['expire_le']),
      );
}

/// L'état d'un paiement en cours ou passé.
class Paiement {
  const Paiement({
    required this.id,
    required this.montant,
    required this.devise,
    required this.periodeMois,
    required this.statut,
    required this.message,
    required this.telephone,
    required this.reseau,
    required this.creeLe,
    this.montantBrut,
    this.reductionPourcent,
  });

  final String id;
  final int montant;

  /// Le tarif avant réduction, quand une réduction s'est appliquée.
  final int? montantBrut;
  final int? reductionPourcent;
  final String devise;
  final int periodeMois;

  /// `en_attente`, `valide` ou `rejete`.
  final String statut;

  /// Le texte que l'API destine à l'écran. On l'affiche tel quel plutôt que
  /// d'en écrire un second ici, qui dirait autre chose au premier changement.
  final String message;

  final String? telephone;
  final String? reseau;
  final DateTime? creeLe;

  bool get enAttente => statut == 'en_attente';
  bool get valide => statut == 'valide';
  bool get rejete => statut == 'rejete';

  String get montantLisible => '${_millier(montant)} $devise';

  factory Paiement.depuisJson(Map<String, dynamic> j) => Paiement(
        id: '${j['id']}',
        montant: _entier(j['montant']) ?? 0,
        devise: '${j['devise'] ?? 'XAF'}',
        periodeMois: _entier(j['periode_mois']) ?? 1,
        statut: '${j['statut'] ?? 'en_attente'}',
        message: '${j['message'] ?? ''}',
        telephone: j['telephone'] as String?,
        reseau: j['reseau'] as String?,
        creeLe: _date(j['cree_le']),
        montantBrut: _entier(j['montant_brut']),
        reductionPourcent: _entier(j['reduction_pourcent']),
      );
}

/// L'abonnement courant. `joursRestants` est la seule donnée que l'écran
/// affiche en gros : c'est la question que se pose un abonné.
class Abonnement {
  const Abonnement({
    required this.actif,
    required this.plan,
    required this.statut,
    required this.fin,
    required this.joursRestants,
    required this.periodeMois,
    required this.message,
  });

  final bool actif;
  final String plan;
  final String? statut;
  final DateTime? fin;
  final int? joursRestants;
  final int? periodeMois;
  final String? message;

  /// Sept jours ou moins : on le dit avant que l'accès ne se referme, pas après.
  bool get bientotEchu => actif && joursRestants != null && joursRestants! <= 7;

  factory Abonnement.depuisJson(Map<String, dynamic> j) => Abonnement(
        actif: j['actif'] == true,
        plan: '${j['plan'] ?? 'free'}',
        statut: j['statut'] as String?,
        fin: _date(j['fin']),
        joursRestants: _entier(j['jours_restants']),
        periodeMois: _entier(j['periode_mois']),
        message: j['message'] as String?,
      );
}

DateTime? _date(dynamic v) => v == null ? null : DateTime.tryParse('$v')?.toLocal();

/// 28000 devient « 28 000 ». Une espace insécable : un montant ne se coupe pas
/// en fin de ligne.
String _millier(int n) {
  final s = n.abs().toString();
  final tampon = StringBuffer(n < 0 ? '-' : '');
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) tampon.write(' ');
    tampon.write(s[i]);
  }
  return tampon.toString();
}
