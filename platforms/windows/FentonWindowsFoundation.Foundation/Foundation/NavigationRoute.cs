namespace FentonWindowsFoundation.Foundation;

/// <summary>
/// A consumer-owned route definition. The foundation only owns registration and navigation.
/// </summary>
public sealed record NavigationRoute(string Key, Type PageType);

public interface INavigationRouteRegistry
{
    IReadOnlyList<NavigationRoute> Routes { get; }

    bool TryGet(string key, out NavigationRoute route);
}

public sealed class NavigationRouteRegistry : INavigationRouteRegistry
{
    private readonly Dictionary<string, NavigationRoute> _routes;

    public NavigationRouteRegistry(IEnumerable<NavigationRoute> routes)
    {
        _routes = routes.ToDictionary(route => route.Key, StringComparer.Ordinal);
    }

    public IReadOnlyList<NavigationRoute> Routes => _routes.Values.ToArray();

    public bool TryGet(string key, out NavigationRoute route) => _routes.TryGetValue(key, out route!);
}
