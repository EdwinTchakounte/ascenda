using System.Net;
using Ascenda.Noyau.Api;
using Ascenda.Noyau.Navigation;
using Ascenda.Noyau.Services;
using Ascenda.Noyau.VuesModeles;
using Xunit;

namespace Ascenda.Noyau.Tests;

public class VuesModelesTests
{
    private static (ClientApi Api, FauxTransport Transport) Monter()
    {
        var transport = new FauxTransport();
        var http = new HttpClient(transport) { BaseAddress = new Uri("https://exemple.test") };
        return (new ClientApi(http, new StockageMemoire()), transport);
    }

    [Fact]
    public async Task Une_adresse_incomplete_arrete_la_connexion_avant_l_appel()
    {
        var (api, transport) = Monter();
        var nav = new NavigateurMuet();
        var vm = new VmConnexion(new ServiceSession(api), nav) { Email = "awa", MotDePasse = "x" };

        await vm.ValiderCommand.ExecuteAsync(null);

        Assert.Empty(transport.Demandes);
        Assert.Equal("Cette adresse ne semble pas valide.", vm.Erreur);
        Assert.Empty(nav.Routes);
    }

    [Fact]
    public async Task Un_mot_de_passe_trop_court_bloque_l_inscription()
    {
        var (api, transport) = Monter();
        var vm = new VmConnexion(new ServiceSession(api), new NavigateurMuet())
        {
            Email = "awa@exemple.test",
            MotDePasse = "court",
            Inscription = true,
        };

        await vm.ValiderCommand.ExecuteAsync(null);

        Assert.Empty(transport.Demandes);
        Assert.Contains("huit caractères", vm.Erreur);
    }

    [Fact]
    public async Task Une_connexion_reussie_mene_a_la_journee()
    {
        var (api, transport) = Monter();
        transport.Repond(HttpStatusCode.OK,
            @"{""jetons"":{""access_token"":""a"",""refresh_token"":""r""},
               ""utilisateur"":{""id"":""u1"",""email"":""a@b.c"",""plan"":""free"",
                                ""acces"":{""complet"":false,""fonctions"":[],""source"":""aucun""}}}");
        var nav = new NavigateurMuet();
        var vm = new VmConnexion(new ServiceSession(api), nav)
        {
            Email = "a@b.c",
            MotDePasse = "motdepasse",
        };

        await vm.ValiderCommand.ExecuteAsync(null);

        Assert.Null(vm.Erreur);
        Assert.Equal(new[] { "//jour" }, nav.Routes);
    }

    [Fact]
    public async Task Un_refus_du_service_s_affiche_sans_quitter_l_ecran()
    {
        var (api, transport) = Monter();
        transport.Repond(HttpStatusCode.Unauthorized,
            @"{""message"":""Adresse ou mot de passe incorrect.""}");
        var nav = new NavigateurMuet();
        var vm = new VmConnexion(new ServiceSession(api), nav)
        {
            Email = "a@b.c",
            MotDePasse = "motdepasse",
        };

        await vm.ValiderCommand.ExecuteAsync(null);

        Assert.Equal("Adresse ou mot de passe incorrect.", vm.Erreur);
        Assert.Empty(nav.Routes);
    }

    [Fact]
    public async Task Le_quiz_avance_question_par_question_puis_corrige()
    {
        var (api, transport) = Monter();
        transport.Repond(HttpStatusCode.OK,
            @"{""id"":""q1"",""chapitre"":""L'érosion"",
               ""questions"":[{""index"":0,""q"":""Première ?"",""choix"":[""a"",""b""]},
                              {""index"":1,""q"":""Seconde ?"",""choix"":[""c"",""d""]}]}")
                 .Repond(HttpStatusCode.OK,
            @"{""score"":1.0,""justes"":2,""total"":2,
               ""details"":[{""index"":0,""juste"":true,""bonne_reponse"":0,""votre_reponse"":0},
                            {""index"":1,""juste"":true,""bonne_reponse"":1,""votre_reponse"":1}]}");
        var nav = new NavigateurMuet();
        var vm = new VmQuiz(new ServiceQuiz(api), nav);

        await vm.ChargerAsync("q1", "s1");
        Assert.Equal("question 1 sur 2", vm.Rang);
        Assert.False(vm.PeutAvancer);

        vm.RepondreCommand.Execute(0);
        Assert.True(vm.PeutAvancer);
        await vm.AvancerCommand.ExecuteAsync(null);

        Assert.Equal(1, vm.Index);
        Assert.Equal("Voir ma correction", vm.LibelleSuivant);
        Assert.False(vm.PeutAvancer);

        vm.RepondreCommand.Execute(1);
        await vm.AvancerCommand.ExecuteAsync(null);

        Assert.NotNull(vm.Correction);
        Assert.Equal("Acquis", vm.Correction!.Mention);
        Assert.Equal(new[] { "correction" }, nav.Routes);
    }

    [Fact]
    public async Task Revenir_en_arriere_retrouve_la_reponse_deja_donnee()
    {
        var (api, transport) = Monter();
        transport.Repond(HttpStatusCode.OK,
            @"{""id"":""q1"",""questions"":[{""index"":0,""q"":""A ?"",""choix"":[""a"",""b""]},
                                            {""index"":1,""q"":""B ?"",""choix"":[""c"",""d""]}]}");
        var vm = new VmQuiz(new ServiceQuiz(api), new NavigateurMuet());
        await vm.ChargerAsync("q1");

        vm.RepondreCommand.Execute(1);
        await vm.AvancerCommand.ExecuteAsync(null);
        vm.ReculerCommand.Execute(null);

        Assert.Equal(0, vm.Index);
        Assert.Equal(1, vm.Choisi);
    }

    [Fact]
    public async Task La_journee_affiche_la_seance_et_la_semaine()
    {
        var (api, transport) = Monter();
        transport.Repond(HttpStatusCode.OK,
            @"{""seance"":{""id"":""s1"",""document_id"":""d1"",""ouvrage"":""Mémento"",
                           ""chapitre"":""L'érosion"",""page_debut"":244,""page_fin"":247,
                           ""prevue_le"":""2026-10-18T00:00:00Z"",""duree_min"":24,
                           ""livrable"":""quiz"",""statut"":""a_venir""},
               ""semaine"":[{""jour"":""2026-10-17"",""statut"":""fait"",""nb"":1},
                            {""jour"":""2026-10-18"",""statut"":""a_venir"",""nb"":1}],
               ""notions_a_reviser"":9}")
                 .Repond(HttpStatusCode.OK,
            @"{""seances"":{""total"":106,""faites"":11,""minutes_lues"":331},
               ""quiz"":{""tentatives"":6,""score_moyen"":0.753},
               ""ouvrages"":{""termines"":2},""notions"":{""suivies"":7,""a_revoir"":7}}");
        var session = new ServiceSession(api);
        var vm = new VmJour(new ServiceParcours(api), session, new NavigateurMuet());

        await vm.ChargerAsync();

        Assert.NotNull(vm.Seance);
        Assert.Equal("p. 244 à 247", vm.Seance!.Pages);
        Assert.Equal(9, vm.NotionsARevoir);
        Assert.Equal(2, vm.Semaine.Count);
        Assert.Equal("5 h 31", vm.Progression!.HeuresLues);
        Assert.False(vm.RienAFaire);
    }

    [Fact]
    public async Task Une_coupure_reseau_laisse_un_message_et_aucune_donnee()
    {
        var http = new HttpClient(new TransportCoupe()) { BaseAddress = new Uri("https://exemple.test") };
        var api = new ClientApi(http, new StockageMemoire());
        var vm = new VmJour(new ServiceParcours(api), new ServiceSession(api), new NavigateurMuet());

        await vm.ChargerAsync();

        Assert.True(vm.EnEchec);
        Assert.Contains("Pas de connexion", vm.Erreur);
        Assert.Null(vm.Seance);
        Assert.False(vm.Occupe);
    }

    [Fact]
    public async Task La_bibliotheque_filtre_sur_le_titre_et_l_auteur()
    {
        var (api, transport) = Monter();
        transport.Repond(HttpStatusCode.OK,
            @"{""total"":3,""page"":1,""ouvrages"":[
                 {""id"":""d1"",""titre"":""Mémento de l'agronome"",""auteurs"":[""CIRAD""],
                  ""pages"":1698,""duree_min"":5443},
                 {""id"":""d2"",""titre"":""ChatGPT, le guide"",""auteurs"":[""Éric Sarrion""],
                  ""pages"":240,""duree_min"":519},
                 {""id"":""d3"",""titre"":""Nations nègres et culture"",""auteurs"":[""Cheikh Anta Diop""],
                  ""pages"":560,""duree_min"":1200}]}");
        var vm = new VmBibliotheque(new ServiceCorpus(api), new NavigateurMuet())
        {
            Recherche = "diop",
        };

        await vm.ChargerAsync();

        Assert.Single(vm.Ouvrages);
        Assert.Equal("Nations nègres et culture", vm.Ouvrages[0].Titre);
        Assert.Equal("1 sur 3 ouvrages", vm.Compteur);
    }

    [Theory]
    [InlineData(8, "Bonjour")]
    [InlineData(11, "Bonjour")]
    [InlineData(12, "Bon après-midi")]
    [InlineData(17, "Bon après-midi")]
    [InlineData(18, "Bonsoir")]
    [InlineData(23, "Bonsoir")]
    public void La_salutation_suit_l_heure(int heure, string attendu) =>
        Assert.Equal(attendu, VmJour.Moment(heure));

    private sealed class TransportCoupe : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request,
                                                               CancellationToken cancellationToken)
            => throw new HttpRequestException("réseau absent");
    }
}
