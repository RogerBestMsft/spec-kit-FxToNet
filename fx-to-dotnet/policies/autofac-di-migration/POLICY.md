---
name: autofac-di-migration
description: Migrating Autofac dependency injection from ASP.NET Framework (OWIN/Web API 2) to ASP.NET Core while preserving existing registrations.
scope: conditional
applies-to: [plan, web-migrate, build-fix]
detection:
  packages: ["Autofac", "Autofac.*"]
---

# Autofac DI Migration

## Overview

When migrating ASP.NET Framework applications that use Autofac for dependency injection, prefer keeping Autofac via the `Autofac.Extensions.DependencyInjection` integration package rather than rewriting all registrations to `Microsoft.Extensions.DependencyInjection`. This preserves existing container configuration with minimal changes and avoids introducing bugs in a large-scale rewrite.

## Strategy

1. Install `Autofac` and `Autofac.Extensions.DependencyInjection` NuGet packages in the new ASP.NET Core host project.
2. Wire Autofac as the service provider factory in `Program.cs`.
3. Port existing registrations from the legacy composition root into the `ConfigureContainer<ContainerBuilder>` callback.
4. Adjust lifetimes and remove Web API / OWIN-specific registrations.
5. Validate at runtime by checking for `Unable to resolve service` exceptions.

## ASP.NET Core Integration

### Program.cs Setup

```csharp
var builder = WebApplication.CreateBuilder(args);

// Use Autofac as the DI container
builder.Host.UseServiceProviderFactory(new AutofacServiceProviderFactory());

builder.Host.ConfigureContainer<ContainerBuilder>(containerBuilder =>
{
    // Port registrations from legacy Startup.ConfigureIoc / IocConfig here
    containerBuilder.RegisterType<MyService>().As<IMyService>().InstancePerLifetimeScope();
    // ...
});

builder.Services.AddControllers();
// ... other MS DI registrations (AddSwaggerGen, AddCors, etc.) ...

var app = builder.Build();
```

### Coexistence With MS DI

Autofac and `Microsoft.Extensions.DependencyInjection` coexist in ASP.NET Core. Services registered via `builder.Services.AddXxx()` (e.g., `AddControllers`, `AddSwaggerGen`, `AddCors`) are automatically available through Autofac's container. No special handling is needed.

Register ASP.NET Core framework services via `builder.Services` (MS DI) and application services via `ConfigureContainer<ContainerBuilder>` (Autofac).

## Lifetime Mapping

Autofac lifetimes translate directly to ASP.NET Core with one exception: `InstancePerRequest`.

| Autofac (Framework) | Autofac (ASP.NET Core) | Reason |
|---------------------|----------------------|--------|
| `InstancePerRequest()` | `InstancePerLifetimeScope()` | ASP.NET Core creates a new Autofac lifetime scope per HTTP request automatically. `InstancePerRequest` is an OWIN/Web API concept that does not exist in ASP.NET Core. `InstancePerLifetimeScope` achieves identical behavior. |
| `InstancePerLifetimeScope()` | `InstancePerLifetimeScope()` | Unchanged |
| `SingleInstance()` | `SingleInstance()` | Unchanged |
| `InstancePerDependency()` | `InstancePerDependency()` | Unchanged |
| `InstancePerMatchingLifetimeScope(tag)` | `InstancePerMatchingLifetimeScope(tag)` | Unchanged — only relevant if custom scopes are created manually |

### Bulk Replacement

In the ported registration code, perform a find-and-replace:
- `.InstancePerRequest()` → `.InstancePerLifetimeScope()`
- `.InstancePerApiRequest()` → `.InstancePerLifetimeScope()`

## Registrations To Remove

The following registration patterns are specific to ASP.NET Web API 2 or OWIN and must be removed when porting to ASP.NET Core:

| Registration | Reason to Remove |
|-------------|-----------------|
| `builder.RegisterApiControllers(assembly)` | ASP.NET Core discovers controllers via `AddControllers()`. Controller activation uses the built-in `IControllerActivator` backed by the DI container. |
| `builder.RegisterWebApiFilterProvider(config)` | Replaced by ASP.NET Core's filter pipeline. Register filters via `builder.Services.AddControllers(o => o.Filters.Add(...))` or `[ServiceFilter]` / `[TypeFilter]` attributes. |
| `builder.RegisterWebApiModelBinderProvider()` | ASP.NET Core has its own model binding infrastructure. |
| `builder.RegisterHttpRequestMessage(config)` | `HttpRequestMessage` is not the primary request abstraction in ASP.NET Core. Use `HttpContext` / `HttpRequest` instead. |
| `config.DependencyResolver = new AutofacWebApiDependencyResolver(container)` | ASP.NET Core uses `UseServiceProviderFactory` — no `DependencyResolver` concept. |
| `app.UseAutofacMiddleware(container)` | OWIN-specific. ASP.NET Core middleware is registered via `app.UseXxx()` in Program.cs. |
| `app.UseAutofacWebApi(config)` | OWIN-specific. Remove entirely. |

## Porting Approach

### Step 1: Locate the Legacy Composition Root

Common locations for Autofac registrations in Web API 2 projects:
- `App_Start/Startup.ConfigureIoc.cs`
- `App_Start/IocConfig.cs`
- `App_Start/AutofacConfig.cs`
- `Global.asax.cs` (in `Application_Start`)
- `Startup.cs` (OWIN startup class)
- Dedicated `Autofac.Module` subclasses

### Step 2: Copy Registrations

Copy the body of the registration method into the `ConfigureContainer<ContainerBuilder>` callback in `Program.cs`. For example:

```csharp
// LEGACY: App_Start/Startup.ConfigureIoc.cs
public void ConfigureIoc(IAppBuilder app)
{
    var builder = new ContainerBuilder();
    builder.RegisterApiControllers(Assembly.GetExecutingAssembly());
    builder.RegisterType<AccountService>().As<IAccountService>().InstancePerRequest();
    builder.RegisterType<OrderService>().As<IOrderService>().InstancePerLifetimeScope();
    builder.RegisterType<AppDbContext>().AsSelf().InstancePerRequest();
    // ... hundreds more ...
    var container = builder.Build();
    config.DependencyResolver = new AutofacWebApiDependencyResolver(container);
}

// NEW: Program.cs
builder.Host.ConfigureContainer<ContainerBuilder>(containerBuilder =>
{
    // Removed: RegisterApiControllers (handled by AddControllers)
    containerBuilder.RegisterType<AccountService>().As<IAccountService>().InstancePerLifetimeScope();
    containerBuilder.RegisterType<OrderService>().As<IOrderService>().InstancePerLifetimeScope();
    containerBuilder.RegisterType<AppDbContext>().AsSelf().InstancePerLifetimeScope();
    // ... hundreds more ...
    // Removed: container.Build() and DependencyResolver assignment
});
```

### Step 3: Apply Lifetime Fixes

Replace all `.InstancePerRequest()` calls with `.InstancePerLifetimeScope()`.

### Step 4: Remove Inapplicable Registrations

Remove the registrations listed in the "Registrations To Remove" section above.

### Step 5: Handle Autofac Modules

If the legacy project uses `Autofac.Module` subclasses, register them in the callback:

```csharp
builder.Host.ConfigureContainer<ContainerBuilder>(containerBuilder =>
{
    containerBuilder.RegisterModule<MyServiceModule>();
    containerBuilder.RegisterModule<MyDataModule>();
});
```

Module internals (registration code inside `Load()`) follow the same lifetime mapping rules.

## DbContext Registration

`InstancePerLifetimeScope` for `DbContext` in Autofac is functionally equivalent to `AddDbContext<T>(ServiceLifetime.Scoped)` in MS DI. Either approach works:

```csharp
// Option A: Autofac (preserves existing registration)
containerBuilder.RegisterType<AppDbContext>().AsSelf().InstancePerLifetimeScope();

// Option B: MS DI (if migrating to EF Core later)
builder.Services.AddDbContext<AppDbContext>(options =>
    options.UseSqlServer(connectionString));
```

When using Entity Framework 6 (not EF Core), keep the Autofac registration since `AddDbContext` is an EF Core extension method.

## Validation

After porting registrations, run the application and test endpoints. Check for:

1. **`InvalidOperationException: Unable to resolve service for type 'X' while attempting to activate 'Y'`** — indicates a missing registration. Find and add the registration for the missing type.
2. **`DependencyResolutionException`** — Autofac-specific resolution failure. Check for circular dependencies or missing registrations in the Autofac container.
3. **Captive dependency warnings** — a scoped service injected into a singleton. Review lifetime assignments if this occurs.

### Quick Smoke Test

After wiring DI, verify a representative endpoint works:
1. Start the application.
2. Hit an endpoint that exercises DI (e.g., a controller that depends on a service that depends on a DbContext).
3. If it returns a response (even an auth error), DI is wired correctly for that chain.
4. If it throws `Unable to resolve service`, trace the dependency chain and add missing registrations.
