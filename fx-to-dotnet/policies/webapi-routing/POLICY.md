---
name: webapi-routing
description: Migrating ASP.NET Web API 2 routing attributes and conventions to ASP.NET Core endpoint routing.
---

# Web API Routing Migration

## Overview

When migrating ASP.NET Web API 2 controllers to ASP.NET Core, routing attributes must be translated to their ASP.NET Core equivalents. The most critical translation is `[RoutePrefix]` → `[Route]` on the controller class. Failure to perform this conversion causes `AmbiguousMatchException` at runtime and `SwaggerGeneratorException` from Swashbuckle.

## RoutePrefix Translation

`System.Web.Http.RoutePrefixAttribute` has no ASP.NET Core equivalent. The ASP.NET Core `[Route]` attribute on a controller class serves the same purpose.

### Conversion Rule

Replace `[RoutePrefix("...")]` with `[Route("...")]` on the controller class.

```csharp
// BEFORE: ASP.NET Web API 2
[RoutePrefix("v1/products")]
public class ProductsController : ApiController
{
    [HttpGet]
    [Route("")]
    public IHttpActionResult GetAll() { ... }

    [HttpGet]
    [Route("{id}")]
    public IHttpActionResult GetById(int id) { ... }

    [HttpPost]
    [Route("")]
    public IHttpActionResult Create([FromBody] ProductDto dto) { ... }
}

// AFTER: ASP.NET Core
[Route("v1/products")]
public class ProductsController : ControllerBase
{
    [HttpGet("")]
    public IActionResult GetAll() { ... }

    [HttpGet("{id}")]
    public IActionResult GetById(int id) { ... }

    [HttpPost("")]
    public IActionResult Create([FromBody] ProductDto dto) { ... }
}
```

When using compatibility shims that preserve `ApiController` and `IHttpActionResult`, the change is limited to the attribute itself:

```csharp
// Minimal change with compat shims — only the attribute changes
[Route("v1/products")]          // was: [RoutePrefix("v1/products")]
public class ProductsController : ApiController
{
    [HttpGet]
    [Route("")]                 // unchanged
    public IHttpActionResult GetAll() { ... }
}
```

## Route Combination Rules

### Web API 2 Behavior
- `RoutePrefix` + `Route` are concatenated: `[RoutePrefix("api/v1")]` + `[Route("items")]` → `api/v1/items`
- `Route` starting with `~` overrides the prefix: `[Route("~/health")]` → `health`
- Empty `[Route("")]` resolves to just the prefix: `api/v1`

### ASP.NET Core Behavior
- Controller `[Route]` + action `[Route]` are concatenated: `[Route("api/v1")]` + `[Route("items")]` → `api/v1/items`
- `Route` starting with `/` overrides the controller route: `[Route("/health")]` → `health`
- Empty `[Route("")]` resolves to just the controller route: `api/v1`
- HTTP verb attributes with route templates also combine: `[HttpGet("{id}")]` → appended to controller route

### Migration Mapping

| Web API 2 | ASP.NET Core | Notes |
|-----------|-------------|-------|
| `[RoutePrefix("x")]` | `[Route("x")]` on controller | Direct replacement |
| `[Route("y")]` on action | `[Route("y")]` on action | Unchanged |
| `[Route("~/abs")]` | `[Route("/abs")]` | Override prefix: `~` → `/` |
| `[Route("")]` on action | `[Route("")]` on action | Unchanged |
| `[HttpGet]` + `[Route("y")]` | `[HttpGet("y")]` | Can inline route into verb attribute |

## Common Controller Patterns

### Pattern 1: RoutePrefix With Relative Routes (Most Common)

Controllers that use `[RoutePrefix]` at the class level and relative `[Route]` on each action.

**Action**: Replace `[RoutePrefix("...")]` with `[Route("...")]` on the controller class. Action-level `[Route]` attributes remain unchanged.

### Pattern 2: No RoutePrefix, Full Routes on Each Action

Controllers with no class-level prefix where each action has a full route path.

```csharp
public class AccountsController : ApiController
{
    [HttpGet]
    [Route("v1/accounts/test")]
    public IHttpActionResult Test() { ... }

    [HttpGet]
    [Route("v1/accounts/logout")]
    public IHttpActionResult Logout() { ... }
}
```

**Action**: No change needed for the routes themselves. Optionally extract a common prefix to `[Route]` on the controller for consistency, but this is not required for correctness.

### Pattern 3: Mixed — Some Actions Override the Prefix

Controllers where most actions use relative routes but some override with `~`.

```csharp
[RoutePrefix("v1/orders")]
public class OrdersController : ApiController
{
    [HttpGet]
    [Route("")]
    public IHttpActionResult GetAll() { ... }

    [HttpGet]
    [Route("~/health")]
    public IHttpActionResult Health() { ... }
}
```

**Action**: Replace `[RoutePrefix]` with `[Route]`. Replace `~` with `/` in override routes.

## Ambiguity Detection

ASP.NET Core endpoint routing is stricter than Web API 2. When `[RoutePrefix]` is not converted, all controllers that use relative routes like `[Route("{id}")]` or `[Route("")]` effectively register the same route template, causing `AmbiguousMatchException` at runtime.

### Diagnostic Checklist

1. **Search for `[RoutePrefix(` in the codebase** — every occurrence needs conversion to `[Route(`.
2. **Search for `[Route("")]` and `[Route("{id}")]`** — these are the most common sources of ambiguity when the prefix is missing.
3. **After migration, hit a root URL** (`/`) — if it returns `AmbiguousMatchException`, unconverted prefixes remain.
4. **After migration, hit `/swagger/v1/swagger.json`** — if Swashbuckle throws `SwaggerGeneratorException: Conflicting method/path combination`, unconverted prefixes remain.

### Identifying Collisions

Two controllers collide when they produce the same effective route after combining prefix and action route:

```
Controller A: [RoutePrefix("v1/foo")] + [Route("{id}")] → GET v1/foo/{id}  ✓ unique
Controller B: [RoutePrefix("v1/bar")] + [Route("{id}")] → GET v1/bar/{id}  ✓ unique

// After migration WITHOUT converting RoutePrefix:
Controller A: (no route on class) + [Route("{id}")] → GET {id}  ✗ collision!
Controller B: (no route on class) + [Route("{id}")] → GET {id}  ✗ collision!
```

## Swagger / OpenAPI

Route ambiguity causes Swashbuckle to throw `SwaggerGeneratorException: Conflicting method/path combination`. Fixing routes by converting `[RoutePrefix]` resolves the Swagger error.

### Interim Workaround During Incremental Migration

When porting controllers in batches, some controllers may temporarily have ambiguous routes. Use `ResolveConflictingActions` to unblock Swagger during migration:

```csharp
builder.Services.AddSwaggerGen(c =>
{
    c.ResolveConflictingActions(apiDescriptions => apiDescriptions.First());
});
```

Remove this workaround once all `[RoutePrefix]` attributes have been converted to `[Route]`.

## IHttpActionResult Migration

When using compatibility shims that define `IHttpActionResult` and `ApiController`, existing return types are preserved — no changes needed to action method signatures.

When porting natively (removing compat shims):

| Web API 2 | ASP.NET Core |
|-----------|-------------|
| `IHttpActionResult` | `IActionResult` |
| `Ok(value)` | `Ok(value)` |
| `BadRequest(msg)` | `BadRequest(msg)` |
| `NotFound()` | `NotFound()` |
| `Content(statusCode, value)` | `StatusCode(code, value)` |
| `ResponseMessage(msg)` | Construct response directly |
