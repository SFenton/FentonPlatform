using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace FentonWindowsFoundation.Foundation;

/// <summary>
/// Keeps navigation and modal ownership scoped to one window.
/// </summary>
public sealed class WindowFoundationHost : IDisposable
{
    private readonly Frame _frame;
    private readonly INavigationRouteRegistry _routes;
    private readonly CancellationScope _lifetime = new();
    private bool _isDisposed;

    public WindowFoundationHost(Frame frame, INavigationRouteRegistry routes)
    {
        _frame = frame ?? throw new ArgumentNullException(nameof(frame));
        _routes = routes ?? throw new ArgumentNullException(nameof(routes));
    }

    public Frame NavigationFrame
    {
        get
        {
            ThrowIfDisposed();
            return _frame;
        }
    }

    public CancellationToken LifetimeToken => _lifetime.Token;

    public bool Navigate(string routeKey, object? parameter = null)
    {
        ThrowIfDisposed();
        if (!_routes.TryGet(routeKey, out var route))
        {
            return false;
        }

        return _frame.Navigate(route.PageType, parameter);
    }

    public async Task<ContentDialogResult> ShowModalAsync(
        ContentDialog dialog,
        XamlRoot ownerRoot,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(dialog);
        ArgumentNullException.ThrowIfNull(ownerRoot);
        ThrowIfDisposed();
        cancellationToken.ThrowIfCancellationRequested();

        var hostRoot = _frame.XamlRoot;
        if (hostRoot is null || !ReferenceEquals(hostRoot, ownerRoot))
        {
            throw new InvalidOperationException("The modal owner must belong to this window's loaded XamlRoot.");
        }

        dialog.XamlRoot = hostRoot;
        using var linked = CancellationTokenSource.CreateLinkedTokenSource(
            _lifetime.Token,
            cancellationToken);
        using var registration = linked.Token.Register(() =>
            _frame.DispatcherQueue.TryEnqueue(dialog.Hide));
        return await dialog.ShowAsync();
    }

    public void Dispose()
    {
        if (_isDisposed)
        {
            return;
        }

        _isDisposed = true;
        _lifetime.Dispose();
    }

    private void ThrowIfDisposed()
    {
        ObjectDisposedException.ThrowIf(_isDisposed, this);
    }
}
