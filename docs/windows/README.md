# Windows foundation pilot

This is a bounded Microsoft WinUI 3 foundation library plus a packaged harness,
not a consumer UI rewrite. `CancellationScope` owns cancellable lifetimes,
`WindowFoundationHost` scopes navigation and modal ownership to a window, and
`INavigationRouteRegistry` keeps routes injected by the consumer. The harness
references `FentonWindowsFoundation.Foundation`; it does not duplicate those
classes.

The pilot is packaged by default and targets x64/ARM64 with .NET 9 and Windows
App SDK 2.6.5. The pure foundation test project runs focused cancellation and
route tests without package identity. The packaged WinUI test host also builds,
but its execution is gated by Developer Mode and Windows App Runtime package
registration on the host. This pilot does not claim accessibility, visual,
lifecycle, or performance qualification; those require a safely owned native UI
harness run.

Direct NuGet references are Microsoft.WindowsAppSDK 2.6.5 and
Microsoft.Windows.SDK.BuildTools 10.0.28000.2957, with WinApp/WinUIAnalyzer
0.7.1. The test host uses MSTest 3.8.3 with
Microsoft.NET.Test.Sdk/TestHost 17.13.0 for the packaged test host. The
resolved Windows App SDK graph includes WebView2 1.0.3719.77, Windows SDK
MSIX 1.7.251221100, Windows App SDK runtime/Foundation/WinUI 2.6.5, and the
other SDK-provided components. Exact restore output remains the licensing
source of truth in the Windows `obj/project.assets.json` files.

Resolved NuGet metadata observed on the Windows host: Windows App SDK
`license.txt`, project `https://github.com/microsoft/windowsappsdk`;
WinApp/WinUIAnalyzer `MIT`, `https://licenses.nuget.org/MIT`, projects
`https://github.com/microsoft/WinAppCli` and
`https://github.com/microsoft/winappCli`; Windows SDK BuildTools uses the
Microsoft URL `https://aka.ms/WinSDKLicenseURL`. A complete transitive SPDX
manifest is still an explicit parent licensing gate.
