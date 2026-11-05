namespace FentonWindowsFoundation.Foundation;

/// <summary>
/// Owns a cancellable lifetime and propagates cancellation to child work.
/// </summary>
public sealed class CancellationScope : IDisposable
{
    private readonly CancellationTokenSource _source;
    private bool _isDisposed;

    public CancellationScope(CancellationToken parent = default)
    {
        _source = parent.CanBeCanceled
            ? CancellationTokenSource.CreateLinkedTokenSource(parent)
            : new CancellationTokenSource();
    }

    public CancellationToken Token => _source.Token;

    public bool IsCancellationRequested => _source.IsCancellationRequested;

    public CancellationScope CreateChild()
    {
        ThrowIfDisposed();
        return new CancellationScope(Token);
    }

    public void Cancel()
    {
        ThrowIfDisposed();
        _source.Cancel();
    }

    public void Dispose()
    {
        if (_isDisposed)
        {
            return;
        }

        _isDisposed = true;
        _source.Cancel();
        _source.Dispose();
    }

    private void ThrowIfDisposed()
    {
        ObjectDisposedException.ThrowIf(_isDisposed, this);
    }
}
