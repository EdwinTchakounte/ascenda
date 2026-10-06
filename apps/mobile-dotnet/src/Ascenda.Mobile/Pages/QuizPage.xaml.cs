using Ascenda.Noyau.VuesModeles;

namespace Ascenda.Mobile.Pages;

[QueryProperty(nameof(QuizId), "quiz")]
[QueryProperty(nameof(SeanceId), "seance")]
public partial class QuizPage : ContentPage
{
    private readonly VmQuiz _vm;

    public QuizPage(VmQuiz vm)
    {
        InitializeComponent();
        _vm = vm;
        BindingContext = vm;
    }

    public string? QuizId { get; set; }
    public string? SeanceId { get; set; }

    protected override async void OnAppearing()
    {
        base.OnAppearing();
        if (!string.IsNullOrEmpty(QuizId) && _vm.Sujet is null)
            await _vm.ChargerAsync(QuizId, SeanceId);
    }

    private void SurChoix(object? envoyeur, TappedEventArgs e)
    {
        if (e.Parameter is int index)
            _vm.RepondreCommand.Execute(index);
    }
}
