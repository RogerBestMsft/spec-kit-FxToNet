# spec-kit-FxToNet Extension: Web Migration Runtime Fix Plan

## Summary

The `web-migrate` command produces ASP.NET Core hosts that fail at runtime due to three systematic gaps discovered during the IAP.Server migration (Petronas.Iap.WebApi). This document describes the root causes, the planned extension changes, and verification steps.

## Runtime Issues Observed

### Issue 1: Ambiguous Route Matching (`AmbiguousMatchException`)

**Symptom**: ASP.NET Core throws `AmbiguousMatchException: The request matched multiple endpoints` at runtime. Multiple controllers (e.g., `PemsSubElementController`, `PemsSectionController`, `PemsScopeController`) all resolve to the same route.

**Root cause**: Legacy controllers use `[RoutePrefix("v1/foo")]` + per-action `[Route("")]` / `[Route("{id}")]`. The extension does not convert `[RoutePrefix]` to `[Route]` on the controller class during migration. ASP.NET Core's endpoint routing is stricter than Web API 2 — identical relative route templates across controllers (e.g., `GET {id}`) become ambiguous when `RoutePrefix` isn't translated.

**Scale**: ~200 controllers, most using `[RoutePrefix]` + per-action `[Route]`. Some use full per-action routes (no prefix).

### Issue 2: Missing DI Registrations (`InvalidOperationException`)

**Symptom**: `Unable to resolve service for type 'Petronas.Iap.Domain.Services.IAccountService' while attempting to activate 'Petronas.Iap.WebApi.Controllers.AccountsController'`.

**Root cause**: Legacy `Startup.ConfigureIoc.cs` has ~400+ Autofac registrations (`RegisterType<T>().As<I>()`, `InstancePerRequest`, `InstancePerLifetimeScope`). The `web-migrate` command left a TODO comment in `Program.cs` `ConfigureContainer<ContainerBuilder>` with no actual registrations ported. The extension has no Autofac migration guidance.

### Issue 3: Swagger Generation Failure (`SwaggerGeneratorException`)

**Symptom**: `Conflicting method/path combination "GET {id}"` across dozens of controllers when hitting `/swagger/v1/swagger.json`.

**Root cause**: Direct consequence of Issue 1. Swashbuckle sees conflicting route templates when `[RoutePrefix]` isn't properly translated. Resolves automatically when routing is fixed.

## Current Extension Gaps

| Area | Current State | Gap |
|------|--------------|-----|
| `[RoutePrefix]` → `[Route]` conversion | Not handled | No policy or guidance exists |
| Autofac DI migration | Vague one-liner in web-migrate | No policy; no concrete steps for porting registrations |
| Swagger/OpenAPI route conflicts | Not addressed | No guidance on ambiguity or workarounds |
| Route inventory ambiguity detection | Inventory lists routes but doesn't flag collisions | No collision analysis in output |

## Planned Changes

### Phase 1: New Policy — `webapi-routing`

**File**: `fx-to-dotnet/policies/webapi-routing/POLICY.md` (new)

Covers:

- **RoutePrefix translation**: `[RoutePrefix("v1/foo")]` → `[Route("v1/foo")]` on the controller class. `RoutePrefix` is a `System.Web.Http` attribute with no ASP.NET Core equivalent — the ASP.NET Core `[Route]` attribute on a controller class serves the same purpose.
- **Route combination rules**: How Web API 2 combines `RoutePrefix` + `Route` vs how ASP.NET Core combines controller `[Route]` + action `[Route]`. Key difference: Web API 2 uses `~` prefix to override `RoutePrefix`; ASP.NET Core uses `/` prefix.
- **Ambiguity detection**: Diagnostic checklist for identifying controllers that produce identical effective route templates.
- **Common patterns**:
  - Controllers with no `RoutePrefix` (full per-action routes) — leave as-is.
  - Controllers with `RoutePrefix` + relative routes — convert prefix to `[Route]`.
  - Controllers mixing both — normalize.
- **IHttpActionResult → IActionResult**: When using compat shims, `IHttpActionResult` is preserved. When porting natively, replace with `IActionResult` / `ActionResult<T>`.
- **Swagger/OpenAPI**: Route ambiguity causes Swashbuckle `SwaggerGeneratorException`; fixing routes fixes Swagger. Recommend `ResolveConflictingActions` as interim workaround during incremental migration.

Example transformation:

```csharp
// BEFORE: ASP.NET Framework (Web API 2)
[RoutePrefix("v1/pemsSubElement")]
public class PemsSubElementController : ApiController
{
    [HttpGet]
    [Route("{id}")]
    public IHttpActionResult GetById(Guid id) { ... }
}

// AFTER: ASP.NET Core
[Route("v1/pemsSubElement")]
public class PemsSubElementController : ControllerBase
{
    [HttpGet("{id}")]
    public IActionResult GetById(Guid id) { ... }
}
```

### Phase 2: New Policy — `autofac-di-migration`

**File**: `fx-to-dotnet/policies/autofac-di-migration/POLICY.md` (new)

Covers:

- **Strategy**: Keep Autofac via `Autofac.Extensions.DependencyInjection` rather than rewriting hundreds of registrations to `Microsoft.Extensions.DependencyInjection`. This preserves all existing registrations with minimal changes.
- **ASP.NET Core integration pattern**:
  ```csharp
  builder.Host.UseServiceProviderFactory(new AutofacServiceProviderFactory());
  builder.Host.ConfigureContainer<ContainerBuilder>(containerBuilder =>
  {
      // Port registrations from legacy Startup.ConfigureIoc here
  });
  ```
- **Lifetime mapping**:
  | Autofac (Framework) | Autofac (ASP.NET Core) | Notes |
  |---------------------|----------------------|-------|
  | `InstancePerRequest` | `InstancePerLifetimeScope` | Autofac scopes per-request automatically in ASP.NET Core |
  | `InstancePerLifetimeScope` | `InstancePerLifetimeScope` | Unchanged |
  | `SingleInstance` | `SingleInstance` | Unchanged |
  | `InstancePerDependency` | `InstancePerDependency` | Unchanged |

- **Registrations to remove**:
  - `RegisterApiControllers()` — ASP.NET Core discovers controllers via `AddControllers()`.
  - `RegisterWebApiFilterProvider()` — Replaced by ASP.NET Core filter pipeline.
  - OWIN-specific registrations (`RegisterWebApiModelBinderProvider`, etc.).
- **Porting approach**: Copy registration code from legacy `Startup.ConfigureIoc.cs` into `ConfigureContainer<ContainerBuilder>` callback. Replace `InstancePerRequest` with `InstancePerLifetimeScope`. Remove Web API / OWIN-specific registrations listed above.
- **Validation**: After porting, check for `Unable to resolve service` exceptions at runtime — each one indicates a missed registration.

### Phase 3: Update `web-migrate` Orchestrator

**File**: `fx-to-dotnet/commands/web-migrate/migrate.md` (update)

Changes:

- **Phase 1 (Discovery)**: Add to discovery checklist:
  - Routing pattern classification — identify which `RoutePrefix` style the project uses.
  - DI container type identification (Autofac, Unity, Ninject, raw MS DI, etc.).
- **Phase 2 (New Host)**: Add instructions to consult `webapi-routing` policy when establishing route configuration and `autofac-di-migration` policy when setting up DI.
- **Phase 3, Slice 1 (Bootstrap & DI)**: Replace vague "dependency injection" guidance with concrete steps: identify DI container type → consult appropriate policy → port registrations → validate with build + runtime test. Reference `autofac-di-migration` policy for Autofac projects.
- **Phase 3, Slice 5 (Controllers)**: Add explicit `[RoutePrefix]` → `[Route]` conversion step before porting controllers. Reference `webapi-routing` policy. Add Swagger validation step (hit `/swagger/v1/swagger.json` after porting a batch of controllers to catch ambiguity early).
- **Framework-Specific Guidance**: Add bullet for `[RoutePrefix]` → `[Route]` conversion referencing `webapi-routing` policy. Expand Autofac bullet to reference `autofac-di-migration` policy.

### Phase 4: Update Route Inventory Output

**File**: `fx-to-dotnet/commands/route-inventory/inventory.md` (update)

Changes:

- Add **Routing Ambiguity Warnings** section to the output format. After building the endpoint inventory, detect and report potential route collisions — cases where multiple controllers produce the same effective route template after combining `RoutePrefix` + `Route`.
- Add the resolved full route (prefix + action route combined) to each endpoint entry, making it explicit what the effective path is.

## File Summary

| File | Action | Description |
|------|--------|-------------|
| `fx-to-dotnet/policies/webapi-routing/POLICY.md` | **Create** | Routing migration policy: RoutePrefix conversion, ambiguity detection, Swagger fix |
| `fx-to-dotnet/policies/autofac-di-migration/POLICY.md` | **Create** | Autofac DI migration policy: keep Autofac, lifetime mapping, porting steps |
| `fx-to-dotnet/commands/web-migrate/migrate.md` | **Update** | Add policy references to discovery, slice guidance, framework-specific sections |
| `fx-to-dotnet/commands/route-inventory/inventory.md` | **Update** | Add ambiguity detection and resolved full routes to output format |

## Design Decisions

1. **Keep Autofac rather than rewrite to MS DI**: `Autofac.Extensions.DependencyInjection` is the lowest-friction path for projects with hundreds of existing registrations. Rewriting to MS DI is a future optimization, not a migration requirement.

2. **Issue 3 (Swagger) resolves via Issue 1**: No separate Swagger migration step needed. The `webapi-routing` policy includes a note about `ResolveConflictingActions` as a temporary workaround during incremental controller porting.

3. **Policies over code generation**: The extension is prompt-driven (agent instructions), not a code generator. New policies provide the migration knowledge; the `web-migrate` orchestrator applies it during its slice workflow.

4. **RoutePrefix conversion is controller-level**: The transformation moves `[RoutePrefix("...")]` to `[Route("...")]` on the controller class. Action-level `[Route]` attributes stay as-is.

## Verification

1. Run `speckit.fx-to-dotnet.show-policy` with name `webapi-routing` — verify it displays correctly.
2. Run `speckit.fx-to-dotnet.show-policy` with name `autofac-di-migration` — verify it displays correctly.
3. Run `speckit.fx-to-dotnet.inventory` against IAP.Server WebApi — verify output includes resolved full routes and ambiguity warnings.
4. Run `speckit.fx-to-dotnet.web-migrate` against IAP.Server WebApi — verify discovery identifies RoutePrefix patterns and DI container type, slice 1 ports Autofac registrations, slice 5 converts `[RoutePrefix]` → `[Route]`.
