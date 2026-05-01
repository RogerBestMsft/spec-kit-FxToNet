---
name: systemweb-adapters
description: "System.Web adapters migration policy for ASP.NET Framework to ASP.NET Core. Use when: migrating System.Web.HttpContext, HttpRequest, HttpResponse, IHttpModule, IHttpHandler, HttpApplication, Global.asax, or other System.Web types to ASP.NET Core. Adapters are the DEFAULT approach during migration to minimize code changes. Covers adapter packages, property translations, incremental IHttpModule/IHttpHandler support, and behavioral differences (lifetime, threading, buffering). Native ASP.NET Core rewrite is a post-migration optimization."
---

# System.Web Adapters Migration Guide

## Policy

**During migration from ASP.NET Framework to ASP.NET Core, use System.Web adapters as the default approach.** The goal is to minimize code changes to only what is necessary to get the application running on ASP.NET Core. Do not refactor code to use native ASP.NET Core types (e.g., `Microsoft.AspNetCore.Http.HttpContext`) during the migration itself — that is a separate post-migration optimization effort.

## Rules

1. **Use adapters by default** — When code references `System.Web.HttpContext`, `HttpRequest`, `HttpResponse`, `IHttpModule`, `IHttpHandler`, or `HttpApplication`, use System.Web adapter packages to keep existing code working with minimal changes.
2. **Do not rewrite to native ASP.NET Core types during migration** — Replacing `System.Web.HttpContext` with `Microsoft.AspNetCore.Http.HttpContext` throughout shared libraries is out of scope for the framework migration. It introduces unnecessary risk and churn.
3. **Adapters enable shared libraries to work on both frameworks** — Libraries referencing `Microsoft.AspNetCore.SystemWebAdapters` can target .NET Standard 2.0 and work from both ASP.NET Framework and ASP.NET Core callers during the migration period.
4. **Native rewrite is a post-migration activity** — After the application is fully running on ASP.NET Core, teams can choose to replace adapter usage with native ASP.NET Core APIs for performance or to remove the adapter dependency.
5. **Only rewrite to native types when adapters are insufficient** — If a specific API is not supported by adapters or adapter behavior causes a functional issue, rewrite that specific usage to native ASP.NET Core types. Do not rewrite broadly.

## When to Use Each Approach

| Scenario | Approach | Phase |
|----------|----------|-------|
| Any `System.Web` usage in shared libraries | **System.Web adapters** | During migration |
| `IHttpModule` that needs to run on ASP.NET Core | **System.Web adapters** (RegisterModule) | During migration |
| `Global.asax` / `HttpApplication` lifecycle events | **System.Web adapters** (AddHttpApplication) | During migration |
| `HttpContext.Current` usage throughout codebase | **System.Web adapters** | During migration |
| API not supported by adapters (causes functional issue) | **Native ASP.NET Core rewrite** (targeted) | During migration (exception) |
| Remove adapter dependency for performance | **Native ASP.NET Core rewrite** | Post-migration |
| Modernize to ASP.NET Core middleware patterns | **Native ASP.NET Core rewrite** | Post-migration |

## Migration Procedure

1. **Replace `System.Web` assembly references with adapter packages** — Remove the `System.Web.dll` reference and add `Microsoft.AspNetCore.SystemWebAdapters` to each project that uses `System.Web` types. For shared libraries, this package targets .NET Standard 2.0 so it works from both Framework and Core callers.
2. **Add service packages to host projects** — Add `Microsoft.AspNetCore.SystemWebAdapters.CoreServices` to the ASP.NET Core host. If the Framework app is still running during incremental migration, add `Microsoft.AspNetCore.SystemWebAdapters.FrameworkServices` to it.
3. **Register modules and HttpApplication** — Wire up `AddSystemWebAdapters()`, `AddHttpApplication<T>()`, and `RegisterModule<T>()` in the ASP.NET Core host for any `IHttpModule` or `Global.asax` logic. See [migrating modules reference](./references/migrating-modules.md).
4. **Rewrite IHttpHandler to middleware** — Convert `IHttpHandler` implementations to minimal middleware with `MapWhen` branching (adapters don't cover handlers). See [migrating handlers reference](./references/migrating-handlers.md).
5. **Stabilize with Build Fix agent** — Run the Build Fix agent to resolve compilation errors introduced by the package swap. The agent will iterate `dotnet build` → diagnose → fix until the project builds.
6. **Address behavioral differences as needed** — If runtime issues arise from lifetime, threading, or buffering differences, apply adapter attributes (`[SingleThreadedRequest]`, `[PreBufferRequestStream]`, `[BufferResponseStream]`). See [behavioral differences reference](./references/behavioral-differences.md).

## NuGet Packages

| Package | Target | Purpose |
|---------|--------|---------|
| `Microsoft.AspNetCore.SystemWebAdapters` | .NET Standard 2.0, .NET Framework 4.5+, .NET 5+ | Shared libraries — provides `System.Web` API surface (`HttpContext`, etc.) |
| `Microsoft.AspNetCore.SystemWebAdapters.CoreServices` | .NET 6+ | ASP.NET Core app — configures adapter behavior and incremental migration services |
| `Microsoft.AspNetCore.SystemWebAdapters.FrameworkServices` | .NET Framework | ASP.NET Framework app — provides incremental migration services |
| `Microsoft.AspNetCore.SystemWebAdapters.Abstractions` | Multi-target | Shared abstractions (e.g., session state serialization) |

## Converting Between HttpContext Types

```csharp
// ASP.NET Core HttpContext → System.Web.HttpContext
System.Web.HttpContext adapted = coreHttpContext; // implicit cast
System.Web.HttpContext adapted = coreHttpContext.AsSystemWeb();

// System.Web.HttpContext → ASP.NET Core HttpContext
Microsoft.AspNetCore.Http.HttpContext core = systemWebContext; // implicit cast
Microsoft.AspNetCore.Http.HttpContext core = systemWebContext.AsAspNetCore();
```

Both methods cache the representation for the duration of a request.

## Important Behavioral Differences

Adapters have key behavioral differences from ASP.NET Framework (lifetime, threading, buffering). Read the [behavioral differences reference](./references/behavioral-differences.md) when encountering `ObjectDisposedException`, threading issues, or when `Response.End()`/`Response.Output` APIs are used.

## Migrating IHttpModule

**During migration:** Keep existing `IHttpModule` classes running on ASP.NET Core via `AddHttpApplication` + `RegisterModule`. No changes to module code required.

**Post-migration:** Optionally rewrite to native ASP.NET Core middleware.

See [migrating modules reference](./references/migrating-modules.md) for registration patterns, `Global.asax` migration, auth event ordering, and the native middleware rewrite pattern.

## Migrating IHttpHandler

Adapters do not support `IHttpHandler` directly — this requires a targeted rewrite to middleware during migration. Keep the conversion minimal.

See [migrating handlers reference](./references/migrating-handlers.md) for before/after examples and `MapWhen` pipeline branching.

## HttpContext Property Translations (Post-Migration)

During migration, code using `System.Web.HttpContext` continues to work via adapters — **no translation needed**.

Post-migration, see [property translations reference](./references/property-translations.md) for the complete mapping from `System.Web` types to native `Microsoft.AspNetCore.Http` types.

## References

- [System.Web adapters documentation](https://learn.microsoft.com/en-us/aspnet/core/migration/fx-to-core/inc/systemweb-adapters?view=aspnetcore-10.0)
- [HttpContext migration](https://learn.microsoft.com/en-us/aspnet/core/migration/fx-to-core/areas/http-context?view=aspnetcore-10.0)
- [HTTP modules to middleware](https://learn.microsoft.com/en-us/aspnet/core/migration/fx-to-core/areas/http-modules?view=aspnetcore-10.0)
- [HTTP handlers to middleware](https://learn.microsoft.com/en-us/aspnet/core/migration/fx-to-core/areas/http-handlers?view=aspnetcore-10.0)
- [Technology-specific migration areas](https://learn.microsoft.com/en-us/aspnet/core/migration/fx-to-core/areas/?view=aspnetcore-10.0)
