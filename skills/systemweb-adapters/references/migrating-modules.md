# Migrating IHttpModule

## During Migration: Keep Existing Modules via System.Web Adapters

Keep existing `IHttpModule` classes running on ASP.NET Core via adapters. **No changes to module code are required.**

### Registration

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

### Global.asax Migration

Register the custom `HttpApplication`:
```csharp
builder.Services.AddSystemWebAdapters()
    .AddHttpApplication<Global>();
```

### Authentication/Authorization Event Ordering

Events must be ordered correctly:
```csharp
app.UseAuthentication();
app.UseAuthenticationEvents();   // Must follow UseAuthentication
app.UseAuthorization();
app.UseAuthorizationEvents();    // Must follow UseAuthorization
```

If not ordered this way, events still run but during `.UseSystemWebAdapters()` instead.

### HTTP Module Pooling

Modules and applications are pooled via `ObjectPool<HttpApplication>`. Customize with a custom pool provider if needed:
```csharp
builder.Services.TryAddSingleton<ObjectPool<HttpApplication>>(sp =>
{
    var policy = sp.GetRequiredService<IPooledObjectPolicy<HttpApplication>>();
    var provider = new DefaultObjectPoolProvider();
    return provider.Create(policy);
});
```

---

## Post-Migration: Rewrite to Native Middleware

After the application is fully running on ASP.NET Core, modules can optionally be rewritten to native middleware to remove the adapter dependency.

### Before (ASP.NET Framework IHttpModule)

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

### After (ASP.NET Core Middleware)

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

### Middleware Configuration Options

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
