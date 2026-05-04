# HttpContext Property Translations (Post-Migration Reference)

This reference is for **post-migration optimization** when removing System.Web adapter dependencies. During migration, code using `System.Web.HttpContext` should continue to use those types via adapters — no translation is needed.

Complete property-by-property translation from `System.Web.HttpContext` to native `Microsoft.AspNetCore.Http.HttpContext`.

## HttpContext Properties

| System.Web | ASP.NET Core | Notes |
|------------|-------------|-------|
| `HttpContext.Items` | `HttpContext.Items` | Type changes to `IDictionary<object, object>` |
| `HttpContext.Current` | Inject `IHttpContextAccessor` | No static accessor in ASP.NET Core |
| _(no equivalent)_ | `HttpContext.TraceIdentifier` | Unique request ID for logging |

## HttpRequest Properties

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

## HttpResponse Properties

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

## Response Header/Cookie Pattern

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
