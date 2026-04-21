# Migrating IHttpHandler

## During Migration: Minimal Rewrite to Middleware

Adapters do not support `IHttpHandler` directly, so handlers must be converted to middleware. Keep the conversion minimal — this is one of the cases where targeted rewrite is necessary during migration.

### Before (ASP.NET Framework IHttpHandler)

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

### After (ASP.NET Core Middleware)

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
