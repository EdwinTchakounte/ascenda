using System.Collections.ObjectModel;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using Ascenda.Noyau.Modeles;
using Ascenda.Noyau.Navigation;
using Ascenda.Noyau.Services;

namespace Ascenda.Noyau.VuesModeles;

public sealed record Proposition(int Index, string Lettre, string Texte, bool Retenue)
{
    public string Contour => Retenue ? "#D4A23F" : "#E3DCCC";
}

public partial class VmQuiz : VmBase
{
    private readonly ServiceQuiz _quiz;
    private readonly INavigateur _navigateur;
    private readonly Dictionary<int, int> _reponses = new();
    private DateTimeOffset _debut = DateTimeOffset.UtcNow;

    public VmQuiz(ServiceQuiz quiz, INavigateur navigateur)
    {
        _quiz = quiz;
        _navigateur = navigateur;
    }

    [ObservableProperty] private Quiz? _sujet;
    [ObservableProperty] private int _index;
    [ObservableProperty] private int? _choisi;
    [ObservableProperty] private Correction? _correction;
    [ObservableProperty] private string? _seanceId;

    public ObservableCollection<string> Choix { get; } = new();

    public ObservableCollection<Proposition> Propositions { get; } = new();

    public double Avancement => Sujet is null || Sujet.Nombre == 0
        ? 0 : (double)(Index + 1) / Sujet.Nombre;

    public Question? Question => Sujet is null || Index >= Sujet.Nombre ? null : Sujet.Questions[Index];

    public string Rang => Sujet is null ? "" : $"question {Index + 1} sur {Sujet.Nombre}";

    public bool DerniereQuestion => Sujet is not null && Index == Sujet.Nombre - 1;

    public string LibelleSuivant => DerniereQuestion ? "Voir ma correction" : "Suivant";

    public bool PeutAvancer => Choisi is not null;

    public async Task ChargerAsync(string quizId, string? seanceId = null)
    {
        SeanceId = seanceId;
        await TenterAsync(async () =>
        {
            Sujet = await _quiz.LireAsync(quizId);
            Index = 0;
            Choisi = null;
            _reponses.Clear();
            _debut = DateTimeOffset.UtcNow;
            PoserChoix();
        });
        Rafraichir();
    }

    [RelayCommand]
    private void Repondre(int choix)
    {
        if (Question is null) return;
        Choisi = choix;
        _reponses[Index] = choix;
    }

    [RelayCommand]
    private async Task AvancerAsync()
    {
        if (!PeutAvancer || Sujet is null) return;

        if (!DerniereQuestion)
        {
            Index++;
            Choisi = _reponses.TryGetValue(Index, out var dejaVu) ? dejaVu : null;
            PoserChoix();
            Rafraichir();
            return;
        }

        await TenterAsync(async () =>
        {
            var duree = (int)(DateTimeOffset.UtcNow - _debut).TotalSeconds;
            Correction = await _quiz.CorrigerAsync(Sujet.Id, _reponses, SeanceId, duree);
        });
        if (Correction is not null)
            await _navigateur.AllerAsync("correction");
    }

    [RelayCommand]
    private void Reculer()
    {
        if (Index == 0) return;
        Index--;
        Choisi = _reponses.TryGetValue(Index, out var dejaVu) ? dejaVu : null;
        PoserChoix();
        Rafraichir();
    }

    private void PoserChoix()
    {
        Choix.Clear();
        Propositions.Clear();
        var lettres = new[] { "A", "B", "C", "D", "E", "F" };
        var choix = Question?.Choix ?? Array.Empty<string>();
        for (var i = 0; i < choix.Count; i++)
        {
            Choix.Add(choix[i]);
            Propositions.Add(new Proposition(i, lettres[i % lettres.Length], choix[i],
                                             i == Choisi));
        }
    }

    private void MarquerChoix()
    {
        for (var i = 0; i < Propositions.Count; i++)
            Propositions[i] = Propositions[i] with { Retenue = i == Choisi };
    }

    private void Rafraichir()
    {
        OnPropertyChanged(nameof(Question));
        OnPropertyChanged(nameof(Rang));
        OnPropertyChanged(nameof(DerniereQuestion));
        OnPropertyChanged(nameof(LibelleSuivant));
        OnPropertyChanged(nameof(PeutAvancer));
        OnPropertyChanged(nameof(Avancement));
    }

    partial void OnChoisiChanged(int? value)
    {
        MarquerChoix();
        OnPropertyChanged(nameof(PeutAvancer));
    }
}
