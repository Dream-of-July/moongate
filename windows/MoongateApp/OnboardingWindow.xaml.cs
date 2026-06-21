using System.Windows;
using System.Windows.Controls;
using Moongate.Core;

namespace Moongate.App;

/// <summary>首次启动引导：分阶段选择基础偏好，不强制配置 API 或下载本地 ASR 模型。</summary>
public partial class OnboardingWindow : Window
{
    private enum OnboardingStep
    {
        Language,
        SubtitleSource,
        TranslationMethod,
        Readiness,
    }

    private readonly MainViewModel _main;
    private readonly OnboardingStep[] _steps =
    {
        OnboardingStep.Language,
        OnboardingStep.SubtitleSource,
        OnboardingStep.TranslationMethod,
        OnboardingStep.Readiness,
    };
    private int _stepIndex;

    public OnboardingWindow(MainViewModel main)
    {
        _main = main;
        InitializeComponent();
        ThemeManager.ApplyWindowTheme(this);
        AppLanguageBox.SelectedIndex = main.Settings.AppLanguage switch
        {
            "zh-Hans" => 1,
            "zh-Hant" => 2,
            "en" => 3,
            _ => 0,
        };

        TargetLanguageBox.SelectedIndex = main.Settings.TranslationTargetLanguage switch
        {
            "zh-Hant" => 1,
            "en" => 2,
            _ => 0,
        };
        TranslationProviderBox.SelectedIndex = main.Settings.AIProvider switch
        {
            TranslationProvider.Openai => 1,
            _ => 0,
        };
        PreferLocalSpeechRecognitionBox.IsChecked = main.Settings.LocalAsrEnabled;
        ShowStep(OnboardingStep.Language);
    }

    private string SelectedAppLanguage => AppLanguageBox.SelectedIndex switch
    {
        1 => "zh-Hans",
        2 => "zh-Hant",
        3 => "en",
        _ => "auto",
    };

    private string SelectedTargetLanguage => TargetLanguageBox.SelectedIndex switch
    {
        1 => "zh-Hant",
        2 => "en",
        _ => "zh-Hans",
    };

    private TranslationProvider SelectedTranslationProvider => TranslationProviderBox.SelectedIndex switch
    {
        1 => TranslationProvider.Openai,
        _ => TranslationProvider.Anthropic,
    };

    private void OnBackClick(object sender, RoutedEventArgs e)
    {
        if (_stepIndex <= 0) return;
        _stepIndex -= 1;
        ShowStep(_steps[_stepIndex]);
    }

    private void OnNextClick(object sender, RoutedEventArgs e)
    {
        if (_stepIndex >= _steps.Length - 1) return;
        _stepIndex += 1;
        ShowStep(_steps[_stepIndex]);
    }

    private void ShowStep(OnboardingStep step)
    {
        _stepIndex = Array.IndexOf(_steps, step);
        if (_stepIndex < 0) _stepIndex = 0;

        LanguagePanel.Visibility = step == OnboardingStep.Language ? Visibility.Visible : Visibility.Collapsed;
        SubtitleSourcePanel.Visibility = step == OnboardingStep.SubtitleSource ? Visibility.Visible : Visibility.Collapsed;
        TranslationMethodPanel.Visibility = step == OnboardingStep.TranslationMethod ? Visibility.Visible : Visibility.Collapsed;
        ReadinessPanel.Visibility = step == OnboardingStep.Readiness ? Visibility.Visible : Visibility.Collapsed;

        LanguageStepLabel.FontWeight = step == OnboardingStep.Language ? FontWeights.SemiBold : FontWeights.Normal;
        SubtitleSourceStepLabel.FontWeight = step == OnboardingStep.SubtitleSource ? FontWeights.SemiBold : FontWeights.Normal;
        TranslationMethodStepLabel.FontWeight = step == OnboardingStep.TranslationMethod ? FontWeights.SemiBold : FontWeights.Normal;
        ReadinessStepLabel.FontWeight = step == OnboardingStep.Readiness ? FontWeights.SemiBold : FontWeights.Normal;

        BackButton.IsEnabled = _stepIndex > 0;
        NextButton.Visibility = step == OnboardingStep.Readiness ? Visibility.Collapsed : Visibility.Visible;
        StartButton.Visibility = step == OnboardingStep.Readiness ? Visibility.Visible : Visibility.Collapsed;
        ErrorText.Text = "";

        if (step == OnboardingStep.Readiness)
        {
            UpdateSummary();
        }
    }

    private void UpdateSummary()
    {
        SummaryAppLanguage.Text = SelectedComboBoxText(AppLanguageBox);
        SummaryTargetLanguage.Text = SelectedComboBoxText(TargetLanguageBox);
        SummaryTranslationMethod.Text = SelectedComboBoxText(TranslationProviderBox);
        SummarySubtitleSource.Text = PreferLocalSpeechRecognitionBox.IsChecked == true
            ? Loc.S("L.Onboarding.LocalSpeechSummary")
            : Loc.S("L.Onboarding.PlatformSubtitleSummary");
    }

    private static string SelectedComboBoxText(ComboBox box)
    {
        if (box.SelectedItem is ComboBoxItem item)
        {
            return item.Content?.ToString() ?? "";
        }
        return box.Text;
    }

    private void OnStartClick(object sender, RoutedEventArgs e)
    {
        try
        {
            var settings = _main.Settings with
            {
                AppLanguage = SelectedAppLanguage,
                TranslationTargetLanguage = SelectedTargetLanguage,
                AIProvider = SelectedTranslationProvider,
                TranslationProvider = SelectedTranslationProvider,
                AIBaseUrl = SelectedTranslationProvider.DefaultBaseUrl(),
                TranslationBaseUrl = SelectedTranslationProvider.DefaultBaseUrl(),
                TranslationFollowsDefault = true,
                LocalAsrEnabled = PreferLocalSpeechRecognitionBox.IsChecked == true,
                OnboardingCompleted = true,
            };
            settings.Save();
            _main.Settings = settings;
            LocalizationManager.Apply(settings.AppLanguage);
            DialogResult = true;
        }
        catch (Exception error)
        {
            ErrorText.Text = Loc.F("L.Settings.SaveFailedFmt", error.Message);
        }
    }
}
