using Ascenda.Noyau.Api;
using Ascenda.Noyau.Modeles;
using Xunit;

namespace Ascenda.Noyau.Tests;

public class ModelesTests
{
    [Theory]
    [InlineData(45, "45 min")]
    [InlineData(60, "1 h")]
    [InlineData(90, "1 h 30")]
    [InlineData(331, "5 h 31")]
    public void La_duree_se_lit_en_heures(int minutes, string attendu) =>
        Assert.Equal(attendu, Duree.EnHeures(minutes));

    [Fact]
    public void Un_abonne_a_tous_les_droits_sans_les_nommer()
    {
        var u = new Utilisateur("u1", "a@b.c", "Awa Ndiaye", "premium",
            new Acces(true, Array.Empty<string>(), "abonnement", null));

        Assert.True(u.ADroit("export_pdf"));
        Assert.Equal("Awa", u.Prenom);
    }

    [Fact]
    public void Un_compte_gratuit_n_a_que_les_fonctions_nommees()
    {
        var u = new Utilisateur("u1", "a@b.c", null, "free",
            new Acces(false, new[] { "quiz_generated" }, "aucun", null));

        Assert.True(u.ADroit("quiz_generated"));
        Assert.False(u.ADroit("export_pdf"));
        Assert.Equal("lecteur", u.Prenom);
    }

    [Fact]
    public void Une_seance_non_faite_et_datee_d_hier_est_en_retard()
    {
        var maintenant = new DateTimeOffset(2026, 10, 18, 9, 0, 0, TimeSpan.Zero);
        var seance = new Seance("s1", 1, "d1", "Mémento", null, null, 10, 20,
            maintenant.AddDays(-2), 30, "quiz", null, EtatSeance.AVenir);

        Assert.True(seance.EnRetard(maintenant));
        Assert.Equal("p. 10 à 20", seance.Pages);
    }

    [Fact]
    public void Une_seance_faite_n_est_jamais_en_retard()
    {
        var maintenant = new DateTimeOffset(2026, 10, 18, 9, 0, 0, TimeSpan.Zero);
        var seance = new Seance("s1", 1, "d1", "Mémento", null, null, 10, 20,
            maintenant.AddDays(-9), 30, "quiz", null, EtatSeance.Faite);

        Assert.False(seance.EnRetard(maintenant));
    }

    [Fact]
    public void La_mention_suit_le_score()
    {
        Correction Avec(int justes, int total) =>
            new(justes, total, Array.Empty<Verdict>());

        Assert.Equal("Acquis", Avec(9, 10).Mention);
        Assert.Equal("Presque", Avec(7, 10).Mention);
        Assert.Equal("À retravailler", Avec(5, 10).Mention);
        Assert.Equal("À reprendre", Avec(2, 10).Mention);
    }

    [Fact]
    public void La_correction_se_recompose_quand_le_service_ne_compte_pas()
    {
        var dto = new CorrectionDto
        {
            Details =
            {
                new DetailDto { Index = 0, Juste = true, BonneReponse = 1, VotreReponse = 1 },
                new DetailDto { Index = 1, Juste = false, BonneReponse = 0, VotreReponse = 2,
                                Extrait = new ExtraitDto { Texte = "Sur un sol nu…", Page = 245 } },
            },
        };

        var correction = dto.Vers();

        Assert.Equal(2, correction.Total);
        Assert.Equal(1, correction.Justes);
        Assert.Equal(245, correction.Verdicts[1].Page);
        Assert.Equal("Sur un sol nu…", correction.Verdicts[1].Citation);
    }

    [Fact]
    public void L_avancement_d_un_chronogramme_se_deduit_des_seances()
    {
        var seances = Enumerable.Range(0, 10).Select(i => new Seance(
            $"s{i}", i, "d1", "Mémento", null, null, 1, 2,
            DateTimeOffset.UtcNow.AddDays(i), 30, "quiz", null,
            i < 4 ? EtatSeance.Faite : EtatSeance.AVenir)).ToList();

        var chrono = new Chronogramme("c1", "axe", "Axe", "", 10, 4, seances);

        Assert.Equal(0.4, chrono.Avancement, 3);
    }
}
