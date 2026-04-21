---
name: windows-service-migration
description: "Windows Service migration policy for .NET Framework ServiceBase to modern .NET BackgroundService. Use when: migrating System.ServiceProcess.ServiceBase, ServiceInstaller, ServiceProcessInstaller, or TopShelf-hosted services. The Generic Host + BackgroundService + Microsoft.Extensions.Hosting.WindowsServices pattern is the default approach. Both hosting packages target netstandard2.0 and .NET Framework 4.6.2+, enabling multitarget-first migration. Native rewrite from ServiceBase to BackgroundService can happen while still on net472."
---

# Windows Service Migration Guide

## Policy

**During migration from .NET Framework to modern .NET, replace `System.ServiceProcess.ServiceBase` with `BackgroundService` using the Generic Host and `Microsoft.Extensions.Hosting.WindowsServices`.** Both `Microsoft.Extensions.Hosting` and `Microsoft.Extensions.Hosting.WindowsServices` target `netstandard2.0` and `.NET Framework 4.6.2+`, so the code migration can be performed during the multitarget phase — before dropping the Framework TFM. TopShelf does not support modern .NET and must always be migrated away from.

## Rules

1. **Replace ServiceBase with BackgroundService during the multitarget phase** — Convert `System.ServiceProcess.ServiceBase` subclasses to `BackgroundService` subclasses. Map `OnStart` logic to `ExecuteAsync(CancellationToken)`, and `OnStop` to cancellation token cooperation. This is safe to do while the project still targets .NET Framework because the hosting packages support it.
2. **Use `Microsoft.Extensions.Hosting.WindowsServices` — do NOT use TopShelf or third-party wrappers** — TopShelf does not support .NET 5+. The official `AddWindowsService()` extension method from `Microsoft.Extensions.Hosting.WindowsServices` is the only supported path. Do not introduce third-party service hosting wrappers.
3. **Both hosting packages are .NET Framework 4.6.2+ compatible** — `Microsoft.Extensions.Hosting` and `Microsoft.Extensions.Hosting.WindowsServices` both target `netstandard2.0` and have explicit `.NET Framework 4.6.2` assets. The ServiceBase → BackgroundService rewrite can happen under multitargeting (`net472` + `net10.0-windows`), validated on both targets before dropping the Framework TFM.
4. **The `-windows` TFM suffix is required for the modern .NET target** — Use `net10.0-windows` (not just `net10.0`) because `Microsoft.Extensions.Hosting.WindowsServices` requires the Windows platform extension for the `WindowsServiceLifetime` implementation.
5. **ServiceInstaller/ProjectInstaller removal is a manual follow-up** — Flag `ServiceInstaller`, `ServiceProcessInstaller`, and `ProjectInstaller` classes for removal after migration. They are not needed with the new hosting model (service registration uses `sc.exe` or PowerShell `New-Service`). Do not block migration on their removal.
6. **Linux/cross-platform support is a separate post-migration concern** — The `net10.0-windows` TFM and `AddWindowsService()` are Windows-specific by design. Removing the `-windows` suffix and replacing `AddWindowsService()` with `AddSystemd()` (`Microsoft.Extensions.Hosting.Systemd`) for Linux is a separate effort after the service is fully running on modern .NET.

## Migration Mapping

| .NET Framework (ServiceBase) | .NET 10 (BackgroundService) | Notes |
|---|---|---|
| `ServiceBase.OnStart(string[] args)` | `BackgroundService.ExecuteAsync(CancellationToken)` | CancellationToken signals stop |
| `ServiceBase.OnStop()` | CancellationToken cancellation | Or override `StopAsync()` for cleanup |
| `ServiceBase.OnPause()` / `OnContinue()` | No direct equivalent | Use `IHostedLifecycleService` or manual pause flag if needed |
| `ServiceBase.Run(services)` | `host.Run()` via `HostApplicationBuilder` | |
| `ServiceInstaller` / `ServiceProcessInstaller` | `sc.exe create` / PowerShell `New-Service` | Manual follow-up |
| `App.config` / `ConfigurationManager.AppSettings` | `appsettings.json` + `IOptions<T>` / `IConfiguration` | Handled by Generic Host |
| `EventLog.WriteEntry()` | `ILogger<T>` + EventLog provider | Auto-configured by `AddWindowsService()` |
| `System.Timers.Timer` callback | `while + Task.Delay` in `ExecuteAsync` | Or `PeriodicTimer` (.NET 6+) |
| Manual thread management | `async/await` in `ExecuteAsync` | CancellationToken for cooperative cancellation |
| Static service locator / singletons | Constructor injection via DI | Register in `builder.Services` |
| Multiple `ServiceBase` subclasses in one exe | Multiple `AddHostedService<T>()` calls | Each gets its own `BackgroundService` subclass |

## Migration Procedure

1. **Replace `System.ServiceProcess` references with hosting packages** — Remove the `System.ServiceProcess` assembly or package reference. Add `Microsoft.Extensions.Hosting` and `Microsoft.Extensions.Hosting.WindowsServices` as `PackageReference` entries.

2. **Rewrite Program.cs entry point** — Replace `ServiceBase.Run()` with the Generic Host pattern:

   ```csharp
   HostApplicationBuilder builder = Host.CreateApplicationBuilder(args);
   builder.Services.AddWindowsService(options =>
   {
       options.ServiceName = "My Service Name";
   });

   builder.Services.AddHostedService<MyBackgroundService>();
   // Register additional services for DI

   IHost host = builder.Build();
   host.Run();
   ```

3. **Convert each ServiceBase subclass to BackgroundService** — Map `OnStart` logic into `ExecuteAsync(CancellationToken)`, replace `OnStop` with cancellation token cooperation, and extract dependencies to constructor injection:

   ```csharp
   public sealed class MyBackgroundService(
       IMyDependency dependency,
       ILogger<MyBackgroundService> logger) : BackgroundService
   {
       protected override async Task ExecuteAsync(CancellationToken stoppingToken)
       {
           try
           {
               while (!stoppingToken.IsCancellationRequested)
               {
                   // Work migrated from OnStart / timer callback
                   await Task.Delay(TimeSpan.FromSeconds(60), stoppingToken);
               }
           }
           catch (OperationCanceledException)
           {
               // Expected when stoppingToken is canceled (service stop)
           }
           catch (Exception ex)
           {
               logger.LogError(ex, "{Message}", ex.Message);
               Environment.Exit(1);
           }
       }
   }
   ```

4. **Replace timer patterns** — Convert `System.Timers.Timer` callbacks to `while (!stoppingToken.IsCancellationRequested) { await Task.Delay(interval, stoppingToken); }` inside `ExecuteAsync`, or use `PeriodicTimer` on .NET 6+.

5. **Migrate logging** — Replace `EventLog.WriteEntry()` or direct logging calls with `ILogger<T>` constructor injection. The `AddWindowsService()` call automatically configures the Windows Event Log provider.

6. **Stabilize with Build Fix agent** — Run the Build Fix agent to resolve remaining compilation errors. The agent will iterate `dotnet build` → diagnose → fix until the project builds.

## NuGet Packages

| Package | Target | Purpose |
|---------|--------|---------|
| `Microsoft.Extensions.Hosting` | netstandard2.0, net462+, net8.0+ | Generic Host, `BackgroundService`, DI, configuration, logging |
| `Microsoft.Extensions.Hosting.WindowsServices` | netstandard2.0, net462+, net8.0+ | Windows Service lifetime via `AddWindowsService()`, Event Log integration |

## When This Applies

- **Multitarget migration**: When build errors reference `System.ServiceProcess.ServiceBase`, `ServiceController`, `ServiceInstaller`, or the project is classified as `windows-service` — apply the migration procedure above.
- **Package compatibility analysis**: Replace `System.ServiceProcess` with the two hosting packages. If TopShelf packages (`Topshelf`, `Topshelf.NLog`, etc.) are present, remove them and migrate to the Generic Host model.
- **Assessment reports**: Classify projects with `ServiceBase` subclasses as `windows-service`. This is an in-scope migration item, not a post-migration task.
- **SDK-style conversion**: No special handling needed — SDK conversion works the same for Windows Service projects.

## What NOT to Do

- Do not use TopShelf for the migration target — it has no .NET 5+ support
- Do not introduce other third-party service hosting wrappers (e.g., `PeterKottas.DotNetCore.WindowsService`)
- Do not block migration on `ServiceInstaller` / `ProjectInstaller` removal — flag as manual follow-up
- Do not treat Windows Service projects as web hosts — they are `non-web-project` + `windows-service`
- Do not defer the ServiceBase → BackgroundService rewrite to post-migration — the hosting packages work on .NET Framework 4.6.2+, so it is safe during multitargeting
- Do not attempt to make the service cross-platform or Linux-compatible during this migration — use `net10.0-windows` and `AddWindowsService()`, not `net10.0` with platform-conditional hosting

## Post-Migration Considerations

- **Linux / cross-platform hosting**: After the service is fully running on modern .NET with `net10.0-windows`, teams can optionally remove the `-windows` TFM suffix and replace `AddWindowsService()` with platform-conditional hosting — `AddWindowsService()` on Windows, `AddSystemd()` (from `Microsoft.Extensions.Hosting.Systemd`) on Linux. This is a separate effort and should not be attempted during the framework migration.
- **MSI/WiX installer migration**: If the original service used an MSI installer (WiX, InstallShield), installer migration is out of scope for code migration. Flag as a manual follow-up task. The new service can be registered with `sc.exe create` or PowerShell `New-Service`.
- **Service identity and permissions**: Service accounts (LocalSystem, NetworkService, custom accounts) are operational concerns preserved at the `sc.exe` / `New-Service` level — not code changes.
- **OnPause/OnContinue**: Rare in practice. If the original service overrides `OnPause`/`OnContinue`, use `IHostedLifecycleService` (.NET 8+) or implement a manual pause mechanism with `ManualResetEventSlim` checked in the `ExecuteAsync` loop.
- **EF6 in services**: If the Windows Service uses Entity Framework 6, follow the `ef6-migration-policy` skill — retain EF6, do not replace with EF Core during migration.
- **Configuration migration**: `App.config` → `appsettings.json` is handled naturally by the Generic Host's `CreateApplicationBuilder`, which sets up `IConfiguration` with JSON providers. Strongly-typed `IOptions<T>` bindings replace `ConfigurationManager.AppSettings` lookups.

## References

- [Create Windows Service using BackgroundService](https://learn.microsoft.com/en-us/dotnet/core/extensions/windows-service)
- [Host ASP.NET Core in a Windows Service](https://learn.microsoft.com/en-us/aspnet/core/host-and-deploy/windows-service)
- [Worker Services in .NET](https://learn.microsoft.com/en-us/dotnet/core/extensions/workers)
- [Microsoft.Extensions.Hosting.WindowsServices NuGet](https://www.nuget.org/packages/Microsoft.Extensions.Hosting.WindowsServices)
