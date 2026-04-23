# Upgrading ASP.NET Identity

## Overview

When upgrading ASP.NET applications that use classic ASP.NET Identity (the `Microsoft.AspNet.Identity.*` / OWIN-based stack) to ASP.NET Core, prefer continuing to use ASP.NET Identity and Entity Framework 6 via compatibility shims. This approach minimizes the amount of code that needs to be rewritten and allows for a smoother transition.

## Key Concepts

- ASP.NET Identity can be used in modern .NET by hosting an OWIN authentication pipeline within the new ASP.NET Core application using the [Microsoft.AspNetCore.SystemWebAdapters.Owin](https://www.nuget.org/packages/Microsoft.AspNetCore.SystemWebAdapters.Owin) package.
- If the project already uses ASP.NET Core Identity (`Microsoft.AspNetCore.Identity`) then this scenario does not apply.

## Steps to Upgrade

To upgrade an ASP.NET application using ASP.NET Identity to ASP.NET Core, the preferred approach is to update the ASP.NET Core app to use OWIN middleware for authentication to configure the existing ASP.NET Identity setup (*not* ASP.NET Core Identity) to work within the ASP.NET Core application.

Hosting this OWIN pipeline in ASP.NET Core (in place of `builder.Services.AddDefaultIdentity` / `AddIdentity` / similar) might look like the following in program.cs:

```csharp
builder.Services.AddAuthentication()
    .AddOwinAuthentication("SharedCookie", (app, services) =>
    {
        // Configure the db context, user manager and signin manager to use a single instance per request
        app.CreatePerOwinContext(ApplicationDbContext.Create);
        app.CreatePerOwinContext<ApplicationUserManager>(ApplicationUserManager.Create);
        app.CreatePerOwinContext<ApplicationSignInManager>(ApplicationSignInManager.Create);
        app.UseStageMarker(PipelineStage.Authenticate);

        var dataProtector = services.GetDataProtectionProvider()
            .GetCookieAuthenticationDataProtector("SharedCookie");

        app.UseCookieAuthentication(new CookieAuthenticationOptions
        {
            AuthenticationType = DefaultAuthenticationTypes.ApplicationCookie,
            LoginPath = new("/Account/Login"),
            Provider = new CookieAuthenticationProvider
            {
                // Enables the application to validate the security stamp when the user logs in.
                // This is a security feature which is used when you change a password or add an external login to your account.  
                OnValidateIdentity = Microsoft.AspNet.Identity.Owin.SecurityStampValidator.OnValidateIdentity<ApplicationUserManager, ApplicationUser>(
                        validateInterval: TimeSpan.FromMinutes(30),
                        regenerateIdentity: (manager, user) => user.GenerateUserIdentityAsync(manager))
            },

            // Settings to configure shared cookie with MvcCoreApp
            CookieName = ".AspNet.ApplicationCookie",
            TicketDataFormat = new AspNetTicketDataFormat(new DataProtectorShim(dataProtector))
        });
    });
```

## Tips and Considerations

**Do**
- Retain existing ASP.NET Identity and Entity Framework 6 code as much as possible.
- Use the `Microsoft.AspNetCore.SystemWebAdapters.Owin` package to host the OWIN authentication pipeline within ASP.NET Core applications, as explained in [this documentation](https://github.com/dotnet/systemweb-adapters/tree/identity-core/src/Microsoft.AspNetCore.SystemWebAdapters.Owin) and [this sample](https://github.com/dotnet/systemweb-adapters/blob/identity-core/samples/AuthRemoteIdentity/AuthRemoteIdentityCore/Program.cs).
- Ensure the ASP.NET Core authentication defaults/schemes line up with what the app expects (e.g., the cookie scheme name), so `[Authorize]` continues to work as before.

**Do Not**
- Migrate to ASP.NET Core Identity unless absolutely necessary. Continuing to use ASP.NET Identity with Entity Framework 6 is often the simplest path.
- This is deferred to after .NET Core migration is complete
- Remove or rewrite existing authentication code without first attempting to use the OWIN hosting approach.
- Mix ASP.NET Core Identity configuration into the same app unless you are intentionally doing a full migration.

## Additional Resources

- [Microsoft.AspNetCore.SystemWebAdapters.Owin Docs](https://github.com/dotnet/systemweb-adapters/tree/main/src/Microsoft.AspNetCore.SystemWebAdapters.Owin)
- [Microsoft.AspNetCore.SystemWebAdapters.Owin NuGet Package](https://www.nuget.org/packages/Microsoft.AspNetCore.SystemWebAdapters.Owin)
