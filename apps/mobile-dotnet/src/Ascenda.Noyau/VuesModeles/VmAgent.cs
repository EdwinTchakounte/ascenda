using System.Collections.ObjectModel;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using Ascenda.Noyau.Modeles;
using Ascenda.Noyau.Services;

namespace Ascenda.Noyau.VuesModeles;

public partial class VmAgent : VmBase
{
    private readonly ServiceAgent _agent;

    public VmAgent(ServiceAgent agent)
    {
        _agent = agent;
        Titre = "L'agent";
    }

    [ObservableProperty] private string _question = "";

    public ObservableCollection<Echange> Echanges { get; } = new();

    public bool PeutDemander => !Occupe && Question.Trim().Length >= 3;

    [RelayCommand]
    private async Task DemanderAsync()
    {
        var posee = Question.Trim();
        if (posee.Length < 3) return;

        Echanges.Add(new Echange("user", posee, Array.Empty<Source>()));
        Question = "";

        await TenterAsync(async () => Echanges.Add(await _agent.DemanderAsync(posee)));

        if (EnEchec)
            Echanges.Add(new Echange("assistant", Erreur!, Array.Empty<Source>(), true));
    }

    partial void OnQuestionChanged(string value) => OnPropertyChanged(nameof(PeutDemander));

    protected override void OnPropertyChanged(System.ComponentModel.PropertyChangedEventArgs e)
    {
        base.OnPropertyChanged(e);
        if (e.PropertyName == nameof(Occupe))
            base.OnPropertyChanged(
                new System.ComponentModel.PropertyChangedEventArgs(nameof(PeutDemander)));
    }
}
