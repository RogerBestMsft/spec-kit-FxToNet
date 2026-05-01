# Behavioral Differences When Using System.Web Adapters

Key behavioral differences between `System.Web.HttpContext` on ASP.NET Framework versus running through adapters on ASP.NET Core.

## HttpContext Lifetime

The adapters are backed by ASP.NET Core's `HttpContext`, which cannot be used past the lifetime of a request. An `ObjectDisposedException` is thrown if accessed after request end.

**Recommendation:** Store values into a POCO if you need them beyond the request.

## Thread Affinity

ASP.NET Core does not guarantee thread affinity. `HttpContext.Current` is available within the same async context but not tied to a specific thread.

If code requires single-threaded access, apply `[SingleThreadedRequest]`:
```csharp
[SingleThreadedRequest]
public class SomeController : Controller { }
```
This uses `ISingleThreadedRequestMetadata` and has performance implications — only use if you can't refactor to ensure non-concurrent access.

## Request Stream Buffering

The incoming request stream is not always seekable in ASP.NET Core. Opt in to prebuffering with `[PreBufferRequestStream]` on controllers/methods, or globally:
```csharp
app.MapDefaultControllerRoute()
    .PreBufferRequestStream();
```

This fully reads the incoming stream and buffers to memory or disk (depending on settings).

## Response Stream Buffering

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

## Unit Testing with Adapters

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
