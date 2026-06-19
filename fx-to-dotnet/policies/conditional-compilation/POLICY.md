---
name: conditional-compilation
description: "Conditional compilation policy for multi-targeted .NET projects. Use when: a project targets both .NET Framework and modern .NET (e.g., net472;net10.0) and code must diverge by target. Covers SDK-defined preprocessor symbols, #if directive patterns, priority order (adapters first, then #if, then removal), and project-file conventions. Do NOT define custom DefineConstants for framework detection — SDK-style projects auto-define all required symbols."
---

# Conditional Compilation Policy for Multi-Targeted Projects

## Policy

**When a project targets both .NET Framework and modern .NET, use `#if` conditional compilation directives to maintain framework-specific code paths.** Adapter packages (e.g., `Microsoft.AspNetCore.SystemWebAdapters`) are preferred when they cover the API surface. Use `#if` directives only when adapters are unavailable or insufficient. Never remove the .NET Framework code path during migration — both targets must compile and function correctly.

## Rules

1. **Priority order for resolving framework-specific API differences**:
   - **(a) Adapter or polyfill package** — Use a cross-framework compatibility package when one exists (e.g., System.Web adapters, `Microsoft.Extensions.Hosting` for Windows Services). These packages target `netstandard2.0` or multi-target explicitly, so no `#if` guards are needed.
   - **(b) `#if` conditional compilation** — When no adapter covers the API, wrap the divergent code in `#if NETFRAMEWORK` / `#else` / `#endif` (or `#if NET10_0_OR_GREATER` / `#endif`) blocks. Keep both implementations so the project builds under both targets.
   - **(c) Code removal** — Only remove code when the functionality is deprecated, unused on both targets, and confirmed safe to drop. Removal is a last resort during migration.

2. **Use SDK-defined preprocessor symbols only** — SDK-style projects automatically define framework symbols during build. Do NOT add custom `<DefineConstants>` entries for framework detection. The SDK-provided symbols are:

   | Symbol | Defined When |
   |--------|-------------|
   | `NETFRAMEWORK` | Any .NET Framework target (`net45`, `net472`, etc.) |
   | `NET472` | Targeting `net472` specifically |
   | `NET48` | Targeting `net48` specifically |
   | `NET10_0` | Targeting `net10.0` specifically |
   | `NET10_0_OR_GREATER` | Targeting `net10.0` or any later version |
   | `NET10_0_WINDOWS` | Targeting `net10.0-windows` |
   | `NETCOREAPP` | Any .NET Core / .NET 5+ target |

   Full reference: [MSBuild preprocessor symbols](https://learn.microsoft.com/dotnet/core/project-sdk/msbuild-props#preprocessor-symbols).

3. **Prefer `_OR_GREATER` symbols for forward compatibility** — Use `#if NET10_0_OR_GREATER` instead of `#if NET10_0` so the code remains valid when the project upgrades to future .NET versions without editing every `#if` guard.

4. **Keep `#if` blocks small and local** — Wrap only the divergent lines, not entire methods or classes. If more than ~20 lines diverge within a single method, extract the platform-specific logic into a partial class or separate file per target.

5. **Guard `using` directives at file top when namespaces differ** — When framework-specific code requires different namespaces, place the `using` directives inside `#if` blocks at the top of the file rather than scattering them throughout the code.

6. **Do NOT use `#if` to swap entire NuGet package dependencies** — Package references apply to all targets unless conditioned in the project file with MSBuild `Condition` attributes. If a package is needed only for one target, use `<PackageReference Condition="'$(TargetFramework)' == 'net472'" ... />` in the project file instead of `#if` in source code.

7. **Do NOT suppress warnings with `NoWarn` as a substitute for conditional compilation** — If a type or API produces a warning on one target, fix it with a `#if` guard or an adapter — not by suppressing the warning.

## Patterns

### Pattern 1: Using Directive Guards

When different targets require different namespaces for the same concept:

```csharp
#if NETFRAMEWORK
using System.Web;
#else
using Microsoft.AspNetCore.Http;
#endif
```

### Pattern 2: Type or API Swap

When a type or method exists on one target but has a different equivalent on the other:

```csharp
public void Configure()
{
#if NETFRAMEWORK
    var context = HttpContext.Current;
#else
    // Injected via DI in modern .NET
    var context = _httpContextAccessor.HttpContext;
#endif
}
```

### Pattern 3: Feature Gating (New-Only Code)

When new functionality should only compile on the modern target:

```csharp
#if NET10_0_OR_GREATER
public async Task<HealthCheckResult> CheckHealthAsync(CancellationToken ct)
{
    // Health check endpoint only available on modern .NET
    return HealthCheckResult.Healthy();
}
#endif
```

### Pattern 4: Framework-Only Code (Legacy Retention)

When legacy code must remain for the Framework target but is not needed on modern .NET:

```csharp
#if NETFRAMEWORK
[Serializable]
public class LegacySessionState : MarshalByRefObject
{
    // Only needed for .NET Framework remoting
}
#endif
```

### Pattern 5: Conditional Package Reference in Project File

When a NuGet package is needed only for one target framework:

```xml
<ItemGroup Condition="'$(TargetFramework)' == 'net472'">
  <PackageReference Include="System.Net.Http" Version="4.3.4" />
</ItemGroup>

<ItemGroup Condition="$(TargetFramework.StartsWith('net10'))">
  <PackageReference Include="Microsoft.Extensions.Http" Version="10.0.0" />
</ItemGroup>
```

### Pattern 6: Partial Class Split (Large Divergence)

When a class has substantial framework-specific logic (>20 divergent lines), split into partial classes per target instead of inline `#if` blocks:

```
MyService.cs                   — shared members (no #if)
MyService.Framework.cs         — #if NETFRAMEWORK guarded, Framework-only members
MyService.Modern.cs            — #if NET10_0_OR_GREATER guarded, modern-only members
```

Each file wraps its entire content in the appropriate `#if` guard. The project file includes all files; the compiler selects the correct partial based on the active target.

## Project File Conventions

### TargetFrameworks Element

Multi-targeted projects use `<TargetFrameworks>` (plural) with a semicolon-delimited list. The original .NET Framework target is listed first to preserve it as the default:

```xml
<PropertyGroup>
  <TargetFrameworks>net472;net10.0</TargetFrameworks>
</PropertyGroup>
```

For Windows Service projects that require platform-specific APIs:

```xml
<PropertyGroup>
  <TargetFrameworks>net472;net10.0-windows</TargetFrameworks>
</PropertyGroup>
```

### No Manual DefineConstants

Do NOT add framework detection symbols manually. The following is **wrong**:

```xml
<!-- WRONG — do not do this -->
<PropertyGroup Condition="'$(TargetFramework)' == 'net472'">
  <DefineConstants>$(DefineConstants);NETFRAMEWORK</DefineConstants>
</PropertyGroup>
```

SDK-style projects define `NETFRAMEWORK`, `NET472`, `NET10_0_OR_GREATER`, and all other framework symbols automatically.

## Interaction with Other Policies

| Policy | Interaction |
|--------|-------------|
| `systemweb-adapters` | Adapters are priority (a) — use them for `System.Web` types. Fall back to `#if` only for APIs adapters do not cover. |
| `ef6-migration-policy` | EF6 6.5+ supports modern .NET via netstandard2.1 — no `#if` guards needed for EF6 types. Do not introduce `#if` to swap EF6 for EF Core. |
| `windows-service-migration` | Hosting packages support both targets via netstandard2.0 — BackgroundService migration does not require `#if` guards. |
| `nuget-package-compat` | Use conditional `<PackageReference>` with MSBuild `Condition` attributes (Pattern 5) for packages that differ by target. |
