using System.Threading;
using System.Windows;
using Moongate.App;

namespace MoongateApp.Tests;

public class SettingsWindowSmokeTests
{
    [Fact]
    public void SettingsWindow_InitializesWithoutRangeBaseBindingFailure()
    {
        Exception? captured = null;
        var completed = new ManualResetEventSlim(false);

        var thread = new Thread(() =>
        {
            try
            {
                var app = Application.Current as App ?? new App();
                app.InitializeComponent();

                var window = new SettingsWindow(new MainViewModel());
                window.Close();
            }
            catch (Exception error)
            {
                captured = error;
            }
            finally
            {
                Application.Current?.Shutdown();
                completed.Set();
            }
        });

        thread.SetApartmentState(ApartmentState.STA);
        thread.Start();

        Assert.True(completed.Wait(TimeSpan.FromSeconds(15)), "Settings window initialization timed out.");
        Assert.Null(captured);
    }
}
