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
3. **Register modules and HttpApplication** — Wire up `AddSystemWebAdapters()`, `AddHttpApplication<T>()`, and `RegisterModule<T>()` in the ASP.NET Core host for any `IHttpModule` or `Global.asax` logic. See the Migrating IHttpModule section below.
4. **Rewrite IHttpHandler to middleware** — Convert `IHttpHandler` implementations to minimal middleware with `MapWhen` branching (adapters don't cover handlers). See the Migrating IHttpHandler section below.
5. **Stabilize with Build Fix** — Invoke `speckit.fx-to-dotnet-build-fix.fix` to resolve compilation errors introduced by the package swap. The command will iterate `dotnet build` → diagnose → fix until the project builds.
6. **Address behavioral differences as needed** — If runtime issues arise from lifetime, threading, or buffering differences, apply adapter attributes (`[SingleThreadedRequest]`, `[PreBufferRequestStream]`, `[BufferResponseStream]`). See the Behavioral Differences section below.

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

Adapters have key behavioral differences from ASP.NET Framework (lifetime, threading, buffering). Read the Behavioral Differences section below when encountering `ObjectDisposedException`, threading issues, or when `Response.End()`/`Response.Output` APIs are used.

---

## Behavioral Differences When Using System.Web Adapters

Key behavioral differences between `System.Web.HttpContext` on ASP.NET Framework versus running through adapters on ASP.NET Core.

### HttpContext Lifetime

The adapters are backed by ASP.NET Core's `HttpContext`, which cannot be used past the lifetime of a request. An `ObjectDisposedException` is thrown if accessed after request end.

**Recommendation:** Store values into a POCO if you need them beyond the request.

### Thread Affinity

ASP.NET Core does not guarantee thread affinity. `HttpContext.Current` is available within the same async context but not tied to a specific thread.

If code requires single-threaded access, apply `[SingleThreadedRequest]`:
```csharp
[SingleThreadedRequest]
public class SomeController : Controller { }
```
This uses `ISingleThreadedRequestMetadata` and has performance implications — only use if you can't refactor to ensure non-concurrent access.

### Request Stream Buffering

The incoming request stream is not always seekable in ASP.NET Core. Opt in to prebuffering with `[PreBufferRequestStream]` on controllers/methods, or globally:
```csharp
app.MapDefaultControllerRoute()
    .PreBufferRequestStream();
```

This fully reads the incoming stream and buffers to memory or disk (depending on settings).

### Response Stream Buffering

Some `System.Web.HttpResponse` APIs require that the output stream is buffered:
- `Response.Output`
- `Response.End()`
- `Response.Clear()`
- `Response.SuppressContent`

Opt in with `[BufferResponseStream]` on controllers/methods, or globally:
```csharp
app.MapDefaultControllerRoute()
    .BufferResponseStream();
```

### Unit Testing with Adapters

When testing code that uses `HttpRuntime` or `HostingEnvironment`, start up the SystemWebAdapters service:

```csharp
public static async Task<IDisposable> EnableRuntimeAsync(
    Action<SystemWebAdaptersOptions>? configure = null,
    CancellationToken token = default)
    => await new HostBuilder()
       .ConfigureWebHost(webBuilder =>
       {
           webBuilder.UseTestServer()
               .ConfigureServices(services =>
               {
                   services.AddSystemWebAdapters();
                   if (configure is not null)
                       services.AddOptions<SystemWebAdaptersOptions>().Configure(configure);
               })
               .Configure(app => { });
       })
       .StartAsync(token);
```

Tests using this must run sequentially (disable parallel execution).

---

## Migrating IHttpModule

### During Migration: Keep Existing Modules via System.Web Adapters

Keep existing `IHttpModule` classes running on ASP.NET Core via adapters. **No changes to module code are required.**

#### Registration

```csharp
var builder = WebApplication.CreateBuilder(args);

builder.Services.AddSystemWebAdapters()
    .AddHttpApplication<MyApp>(options =>
    {
        options.PoolSize = 10;
        options.RegisterModule<MyModule>("MyModule");
    });

var app = builder.Build();

app.UseAuthentication();
app.UseAuthenticationEvents();
app.UseAuthorization();
app.UseAuthorizationEvents();
app.UseSystemWebAdapters();

app.Run();
```

#### Global.asax Migration

Register the custom `HttpApplication`:
```csharp
builder.Services.AddSystemWebAdapters()
    .AddHttpApplication<Global>();
```

#### Authentication/Authorization Event Ordering

Events must be ordered correctly:
```csharp
app.UseAuthentication();
app.UseAuthenticationEvents();   // Must follow UseAuthentication
app.UseAuthorization();
app.UseAuthorizationEvents();    // Must follow UseAuthorization
```

If not ordered this way, events still run but during `.UseSystemWebAdapters()` instead.

#### HTTP Module Pooling

Modules and applications are pooled via `ObjectPool<HttpApplication>`. Customize with a custom pool provider if needed:
```csharp
builder.Services.TryAddSingleton<ObjectPool<HttpApplication>>(sp =>
{
    var policy = sp.GetRequiredService<IPooledObjectPolicy<HttpApplication>>();
    var provider = new DefaultObjectPoolProvider();
    return provider.Create(policy);
});
```

### Post-Migration: Rewrite to Native Middleware

After the application is fully running on ASP.NET Core, modules can optionally be rewritten to native middleware to remove the adapter dependency.

#### Before (ASP.NET Framework IHttpModule)

```csharp
public class MyModule : IHttpModule
{
    public void Init(HttpApplication application)
    {
        application.BeginRequest += (s, e) =>
        {
            HttpContext context = ((HttpApplication)s).Context;
            // Begin-request logic
        };
        application.EndRequest += (s, e) =>
        {
            HttpContext context = ((HttpApplication)s).Context;
            // End-request logic
        };
    }
    public void Dispose() { }
}
```

#### After (ASP.NET Core Middleware)

```csharp
public class MyMiddleware
{
    private readonly RequestDelegate _next;
    public MyMiddleware(RequestDelegate next) => _next = next;

    public async Task Invoke(HttpContext context)
    {
        // Begin-request logic
        await _next.Invoke(context);
        // End-request logic (runs on response path)
    }
}

public static class MyMiddlewareExtensions
{
    public static IApplicationBuilder UseMyMiddleware(this IApplicationBuilder builder)
        => builder.UseMiddleware<MyMiddleware>();
}
```

Register in `Program.cs`:
```csharp
app.UseMyMiddleware();
```

#### Middleware Configuration Options

When modules are rewritten to native middleware, options stored in `Web.config` should migrate to `appsettings.json` + Options pattern:

```csharp
// appsettings.json
{ "MyMiddlewareOptions": { "Param1": "Value1" } }

// Startup.ConfigureServices
services.Configure<MyMiddlewareOptions>(
    Configuration.GetSection("MyMiddlewareOptions"));

// Middleware constructor injection
public MyMiddleware(RequestDelegate next, IOptions<MyMiddlewareOptions> options)
```

For multiple instances of the same middleware with different options, pass options directly via `UseMiddleware<T>(optionsInstance)` wrapped in `OptionsWrapper<T>`.

---

## Migrating IHttpHandler

### During Migration: Minimal Rewrite to Middleware

Adapters do not support `IHttpHandler` directly, so handlers must be converted to middleware. Keep the conversion minimal — this is one of the cases where targeted rewrite is necessary during migration.

#### Before (ASP.NET Framework IHttpHandler)

```csharp
public class MyHandler : IHttpHandler
{
    public bool IsReusable => true;
    public void ProcessRequest(HttpContext context)
    {
        string title = context.Request.QueryString["title"];
        context.Response.ContentType = "text/plain";
        context.Response.Output.Write($"Title: {title}");
    }
}
```

Configured in Web.config:
```xml
<configuration>
  <system.webServer>
    <handlers>
      <add name="MyHandler" verb="*" path="*.report"
           type="MyApp.HttpHandlers.MyHandler"
           resourceType="Unspecified" preCondition="integratedMode"/>
    </handlers>
  </system.webServer>
</configuration>
```

#### After (ASP.NET Core Middleware)

```csharp
public class MyHandlerMiddleware
{
    public MyHandlerMiddleware(RequestDelegate next) { /* handler — no next needed */ }

    public async Task Invoke(HttpContext context)
    {
        string title = context.Request.Query["title"];
        context.Response.ContentType = "text/plain";
        await context.Response.WriteAsync($"Title: {title}");
    }
}
```

Replace Web.config `<handlers>` with `MapWhen` pipeline branching:
```csharp
app.MapWhen(
    context => context.Request.Path.ToString().EndsWith(".report"),
    branch => branch.UseMiddleware<MyHandlerMiddleware>());
```

Note: Handler middleware uses `Microsoft.AspNetCore.Http.HttpContext` directly because there is no adapter equivalent for `IHttpHandler`.

---

## HttpContext Property Translations (Post-Migration Reference)

This reference is for **post-migration optimization** when removing System.Web adapter dependencies. During migration, code using `System.Web.HttpContext` should continue to use those types via adapters — no translation is needed.

Complete property-by-property translation from `System.Web.HttpContext` to native `Microsoft.AspNetCore.Http.HttpContext`.

### HttpContext Properties

| System.Web | ASP.NET Core | Notes |
|------------|-------------|-------|
| `HttpContext.Items` | `HttpContext.Items` | Type changes to `IDictionary<object, object>` |
| `HttpContext.Current` | Inject `IHttpContextAccessor` | No static accessor in ASP.NET Core |
| _(no equivalent)_ | `HttpContext.TraceIdentifier` | Unique request ID for logging |

### HttpRequest Properties

| System.Web | ASP.NET Core | Code Example |
|------------|-------------|-------------|
| `HttpRequest.HttpMethod` | `HttpRequest.Method` | `string method = context.Request.Method;` |
| `HttpRequest.QueryString["key"]` | `HttpRequest.Query["key"]` | Returns `StringValues`; use `.ToString()` for single value |
| `HttpRequest.Url` / `HttpRequest.RawUrl` | Multiple properties | `context.Request.GetDisplayUrl()` (using `Microsoft.AspNetCore.Http.Extensions`) or compose from `Scheme`, `Host`, `PathBase`, `Path`, `QueryString` |
| `HttpRequest.IsSecureConnection` | `HttpRequest.IsHttps` | `bool secure = context.Request.IsHttps;` |
| `HttpRequest.UserHostAddress` | `HttpContext.Connection.RemoteIpAddress` | `string addr = context.Connection.RemoteIpAddress?.ToString();` |
| `HttpRequest.Cookies["name"]` | `HttpRequest.Cookies["name"]` | Returns `null` for unknown cookies (no exception) |
| `HttpRequest.RequestContext.RouteData` | `HttpContext.GetRouteValue("key")` | Via `Microsoft.AspNetCore.Routing` extensions |
| `HttpRequest.Headers["name"]` | `HttpRequest.Headers["name"]` | Strongly typed access via `context.Request.GetTypedHeaders()` |
| `HttpRequest.UserAgent` | `HttpRequest.Headers[HeaderNames.UserAgent]` | Requires `Microsoft.Net.Http.Headers` |
| `HttpRequest.UrlReferrer` | `HttpRequest.Headers[HeaderNames.Referer]` | Returns string, not `Uri` |
| `HttpRequest.ContentType` | `HttpRequest.ContentType` | For parsed access: `context.Request.GetTypedHeaders().ContentType` |
| `HttpRequest.Form["key"]` | `HttpRequest.Form["key"]` | Check `context.Request.HasFormContentType` first; async: `await context.Request.ReadFormAsync()` |
| `HttpRequest.InputStream` | `HttpRequest.Body` | Body can only be read once per request. Use `StreamReader` with `Encoding.UTF8` |

### HttpResponse Properties

| System.Web | ASP.NET Core | Code Example |
|------------|-------------|-------------|
| `HttpResponse.StatusCode` | `HttpResponse.StatusCode` | `context.Response.StatusCode = StatusCodes.Status200OK;` |
| `HttpResponse.Status` / `StatusDescription` | `HttpResponse.StatusCode` | Status descriptions not directly supported |
| `HttpResponse.ContentEncoding` / `ContentType` | `HttpResponse.ContentType` | Set encoding via `MediaTypeHeaderValue`: `new MediaTypeHeaderValue("application/json") { Encoding = Encoding.UTF8 }` |
| `HttpResponse.Output.Write()` | `await HttpResponse.WriteAsync()` | `await context.Response.WriteAsync(content);` |
| `HttpResponse.TransmitFile` | Request features | See `IHttpResponseBodyFeature` / `SendFileAsync` |
| `HttpResponse.Headers` | `HttpResponse.Headers` | Must set before response starts; use `OnStarting` callback pattern |
| `HttpResponse.Cookies.Add()` | `HttpResponse.Cookies.Append()` | Must set before response starts; use `OnStarting` callback |
| `HttpResponse.Redirect()` | `HttpResponse.Redirect()` | Or set `Headers[HeaderNames.Location]` directly |
| `HttpResponse.CacheControl` | `GetTypedHeaders().CacheControl` | Use `CacheControlHeaderValue` via `OnStarting` callback |
| `HttpResponse.End()` | _(no equivalent)_ | Requires response buffering (`BufferResponseStream`) with adapters |
| `HttpResponse.Clear()` | _(no equivalent)_ | Requires response buffering with adapters |
| `HttpResponse.SuppressContent` | _(no equivalent)_ | Requires response buffering with adapters |

### Response Header/Cookie Pattern

Headers and cookies must be set via `OnStarting` callbacks before the response starts streaming:

```csharp
public async Task Invoke(HttpContext context)
{
    context.Response.OnStarting(state =>
    {
        var ctx = (HttpContext)state;
        ctx.Response.Headers["X-Custom"] = "value";
        ctx.Response.Cookies.Append("cookie1", "value1");
        ctx.Response.Cookies.Append("cookie2", "value2",
            new CookieOptions { Expires = DateTime.Now.AddDays(5), HttpOnly = true });
        return Task.CompletedTask;
    }, context);

    await _next.Invoke(context);
}
```

## References

- [System.Web adapters documentation](https://learn.microsoft.com/en-us/aspnet/core/migration/fx-to-core/inc/systemweb-adapters?view=aspnetcore-10.0)
- [HttpContext migration](https://learn.microsoft.com/en-us/aspnet/core/migration/fx-to-core/areas/http-context?view=aspnetcore-10.0)
- [HTTP modules to middleware](https://learn.microsoft.com/en-us/aspnet/core/migration/fx-to-core/areas/http-modules?view=aspnetcore-10.0)
- [HTTP handlers to middleware](https://learn.microsoft.com/en-us/aspnet/core/migration/fx-to-core/areas/http-handlers?view=aspnetcore-10.0)
- [Technology-specific migration areas](https://learn.microsoft.com/en-us/aspnet/core/migration/fx-to-core/areas/?view=aspnetcore-10.0)
