# Zotero Group Cache — Architecture & API (eXist-db 6.4)

This document describes the local Zotero cache used by the app, the expected collection layout in eXist‑db, the config variables, the sync endpoint, and the installation steps.

> Target stack: **eXist‑db 6.4.x**, **Roaster** (OpenAPI router), **Fore** frontend.  
> Zotero library: **Group** (public or private). API key is **optional** for public groups.

---

## Preconditions

* you must install edep-data.xar BEFORE edep.xar so the latter can create the necessary structure (see below)


## 1) Collection layout

Only the **group** collection is created dynamically by the post‑install script. The **base** and **items** collections are expected to exist after installation.

```
/edep-data
└── zotero/                        (collection)   [pre-created]
    └── groups/                          (collection)   [pre-created]
        └── <GROUP_ID>/                  (collection)   [created by post-install]
            ├── items/                   (collection)   [created by post-install]
            │   ├── ABC12345.json        (application/json)  ← Zotero item “data” for key ABC12345
            │   ├── 9KLMNO67.json        (application/json)
            │   └── ...                  (application/json)
            └── meta.json                (application/json)  ← created/seeded by post-install
```

### `meta.json` (seeded by post-install)
```json
{
  "libraryVersion": 0,
  "syncedAt": "YYYY-MM-DDThh:mm:ssZ"
}
```
- **libraryVersion**: last known Zotero `Last-Modified-Version` for the group (int).
- **syncedAt**: timestamp of last local sync.

### `items/<key>.json`
One file per Zotero item **key**. Stored content is the **pristine Zotero `data` object** (no wrapping). Example:
```json
{
  "itemType": "journalArticle",
  "title": "Example Title",
  "creators": [{ "creatorType": "author", "firstName": "Jane", "lastName": "Doe" }],
  "date": "2020",
  "DOI": "10.1234/example.doi",
  "url": "https://example.org",
  "tags": [{ "tag": "project:demo" }, { "tag": "public" }]
}
```

---

## 2) Config module (`config.xqm`)

The application reads **config variables** directly (hyphenated names), and also provides **function wrappers** for legacy callers. Keep both to avoid router/package regressions.

```xquery
xquery version "3.1";
module namespace config = "http://example.org/config";

(: ── variables (used directly) ── :)
declare variable $config:zotero-api-base  as xs:string  := "https://api.zotero.org";
declare variable $config:zotero-api-key   as xs:string  := "";          (: optional for public :)
declare variable $config:zotero-group-id  as xs:integer := 2529759;

declare variable $config:zotero-base-dir  as xs:string  := "/db/zotero-cache/groups";
declare variable $config:zotero-group-dir as xs:string  := concat($config:zotero-base-dir, "/", $config:zotero-group-id);
declare variable $config:zotero-items-dir as xs:string  := concat($config:zotero-group-dir, "/items");
declare variable $config:zotero-meta-path as xs:string  := concat($config:zotero-group-dir, "/meta.json");
```

**Notes**
- For **public** Zotero groups, `$config:zotero-api-key` may be the empty string; the sync omits the `Authorization` header in that case.
- If you change the **group id**, post‑install must be run again to create the new group layout.

---

## 3) Installation bootstrap (`post-install.xql`)

The post‑install script should:
1. Create collections: `$config:zotero-base-dir`, `$config:zotero-group-dir`, `$config:zotero-items-dir` (stepwise under `/db`).
2. Seed `$config:zotero-meta-path` with the template JSON (media type `application/json`) if missing.

A minimal post‑install does:
- `local:mkcol()` to ensure collections (stepwise, eXist‑6.4 safe)
- seeds `meta.json` via 4‑arg `xmldb:store(..., \"application/json\")`
- returns a JSON summary

> After installation, the **sync** endpoint will not create collections or seed meta; it assumes post‑install of edep app! prepared the layout.

---

## 4) Sync endpoint

**Route**: `POST /api/z/sync` → `zotero:sync`  
**Behavior**: Incremental, paginated sync from Zotero group into local cache.

### Request → Zotero
- `GET {zotero-api-base}/groups/{zotero-group-id}/items?since={libraryVersion}&limit=100`
- Headers:
    - `Zotero-API-Version: 3`
    - `Authorization: Bearer {apiKey}` (only if `$config:zotero-api-key` is non-empty)
    - `If-Modified-Since-Version: {libraryVersion}` (only when `libraryVersion > 0`)

### Response (local API)
```json
{ "status": "ok", "updated": <int>, "libraryVersion": <int> }
```
- `status`: `"ok"` or `"error"`
- `updated`: number of items locally stored across all pages
- `libraryVersion`: Zotero’s `Last-Modified-Version` captured and saved to `meta.json`

### Pagination
- Follows the `Link` response header (`rel="next"`) until exhausted.

### Error handling
When Zotero replies with a non‑200 status:
```json
{ "status":"error", "httpStatus": <int>, "backoff":"...", "retryAfter":"..." }
```
If Zotero returns `304 Not Modified`, the local API responds with:
```json
{ "status":"ok", "updated": 0, "libraryVersion": <unchanged> }
```

---

## 5) Router wiring (Roaster)

Example OpenAPI snippet (YAML):
```yaml
paths:
  /api/z/sync:
    post:
      summary: Sync local cache with Zotero group
      x-roaster-xquery:
        module: /db/apps/edep/modules/lib/zotero.xql
        function: zotero:sync    # supports sync#2 and sync#1 (wrapper)
      responses:
        '200':
          description: Sync result
```

Handler arities to be export-safe:
```xquery
(: wrapper for routers expecting sync#1 :)
declare function zotero:sync($config as map(*)) as xs:string {
  zotero:sync($config, <root/>)
};

(: main handler :)
declare function zotero:sync($config as map(*), $root as element()) as xs:string {
  (: run sync and return JSON string :)
};
```

---

## 6) Troubleshooting

- **make sure edep-data.xar has been installed before edep.xar**
  post-install of edep.xar creates the needed collections in edep-data

- **First run fails reading meta**  
  Ensure post‑install created `meta.json`. If absent, running post‑install again will seed it.

- **No items written**  
  Confirm that `$config:zotero-items-dir` exists and is writable. The sync does not create it.

- **Public group sync**  
  Leave `$config:zotero-api-key` empty. The Authorization header will be omitted.

---

## 7) Trigger sync (curl)
```bash
curl -X POST 'http://localhost:8080/api/z/sync'
```

You should see JSON like:
```json
{ "status":"ok", "updated": 123, "libraryVersion": 4567 }
```

---

*Document version:* 1.0  
*Last updated:* generated for the current build.
