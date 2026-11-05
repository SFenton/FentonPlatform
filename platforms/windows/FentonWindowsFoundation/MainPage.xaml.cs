using FentonWindowsFoundation.Foundation;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;

// To learn more about WinUI, the WinUI project structure,
// and more about our project templates, see: http://aka.ms/winui-project-info.

namespace FentonWindowsFoundation;

/// <summary>
/// The main content page displayed inside the application window.
/// Add your UI logic, event handlers, and data binding here.
/// </summary>
public sealed partial class MainPage : Page
{
    private WindowFoundationHost? _host;

    public MainPage()
    {
        InitializeComponent();
    }

    private void Page_Loaded(object sender, RoutedEventArgs e)
    {
        if (Parent is not Frame frame)
        {
            throw new InvalidOperationException("Foundation pages must be hosted by a Frame.");
        }

        _host = new WindowFoundationHost(
            frame,
            new NavigationRouteRegistry(Array.Empty<NavigationRoute>()));
    }

    private async void ShowDialogButton_Click(object sender, RoutedEventArgs e)
    {
        var dialog = new ContentDialog
        {
            Title = "Window-scoped modal",
            Content = "The dialog is owned by this page's XamlRoot.",
            PrimaryButtonText = "Close",
            CloseButtonText = "Cancel"
        };
        AutomationProperties.SetAutomationId(dialog, "WindowsFoundation.Dialog");
        AutomationProperties.SetName(dialog, "Foundation dialog");

        var host = _host ?? throw new InvalidOperationException("The page is not attached to a window.");
        await host.ShowModalAsync(dialog, XamlRoot, host.LifetimeToken);
        StatusText.Text = "Dialog closed";
    }

    protected override void OnNavigatedFrom(Microsoft.UI.Xaml.Navigation.NavigationEventArgs e)
    {
        _host?.Dispose();
        _host = null;
        base.OnNavigatedFrom(e);
    }
}
