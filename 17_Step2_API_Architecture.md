# Step 2 API architecture

The API is implemented as an Express router mounted at `/api` by the existing
`server.mjs`. It reuses `app.locals.getDatabasePool` and
`app.locals.sql`; no second connection architecture or duplicated database
business rules was introduced.

`organisation-routes.mjs` is the HTTP/controller boundary. SQL Server stored
procedures remain authoritative for assignment writes and lookups. Direct
parameterised queries are used only for reference CRUD, history and reporting.
Responses use `{ success, data }`; errors use `{ success: false, error }`.

When `API_AUTH_REQUIRED=true`, reads require one of the configured read roles and
writes require `organisation-administrator` or `wellbeing-administrator`.
The existing application does not currently provide an Entra token validator;
an upstream Entra middleware should populate `req.auth`/roles before enabling
this setting. No student data is logged.

The existing Compass and wellbeing incident routes remain mounted unchanged.

Run the integration checks with the API running:

```powershell
$env:API_BASE_URL = "http://127.0.0.1:4201/api"
npm run test:organisation
```

Organisation endpoints use the separate `/api/org` path, for example
`http://127.0.0.1:4201/api/org/houses`.

Set `API_AUTH_REQUIRED=true` and provide an Entra-integrated middleware before
using this module outside local development. The current repository had no
token validation middleware to reuse, so the router deliberately fails closed
for protected deployments rather than accepting unvalidated bearer tokens.
