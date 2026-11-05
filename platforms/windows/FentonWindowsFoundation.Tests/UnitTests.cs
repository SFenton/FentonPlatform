using FentonWindowsFoundation.Foundation;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace FentonWindowsFoundationTests;

[TestClass]
public sealed class FoundationTests
{
    [TestMethod]
    public void ChildScopeCancelsWhenParentIsDisposed()
    {
        using var parent = new CancellationScope();
        using var child = parent.CreateChild();

        parent.Dispose();

        Assert.IsTrue(child.IsCancellationRequested);
    }

    [TestMethod]
    public void RouteRegistryKeepsConsumerRoutesOutOfTheHost()
    {
        var registry = new NavigationRouteRegistry(
            [new NavigationRoute("home", typeof(UnitTestAppWindow))]);

        Assert.IsTrue(registry.TryGet("home", out var route));
        Assert.AreEqual(typeof(UnitTestAppWindow), route.PageType);
        Assert.IsFalse(registry.TryGet("missing", out _));
    }
}
