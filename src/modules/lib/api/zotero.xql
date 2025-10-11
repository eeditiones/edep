xquery version "3.1";

module namespace zotero = "http://teipublisher.com/api/zotero";

declare namespace map   = "http://www.w3.org/2005/xpath-functions/map";
declare namespace http  = "http://expath.org/ns/http-client";
declare namespace xmldb = "http://exist-db.org/xquery/xmldb";
declare namespace util  = "http://exist-db.org/xquery/util";
import module namespace response = "http://exist-db.org/xquery/response";
import module namespace config = "http://www.tei-c.org/tei-simple/config" at "../../config.xqm";

(:~
  ==============================================================================
  Zotero cache + lookup module
  ==============================================================================

  Purpose
  -------
  Provide a thin caching layer for a single Zotero group and a set of read APIs
  that the Fore UI can call with low latency. The module:
    • syncs items from the Zotero Web API (data + bib),
    • stores each record as <key>.json in the local DB,
    • exposes lightweight endpoints for search and for rendering a single
      bibliography (or a safe title fallback) as HTML.

  Public endpoints (Roaster)
  --------------------------
  Each endpoint exposes 3 arities so Roaster can bind it:
    f(), f($request as map(*)), f($request as map(*), $root as element()).

  1) zotero:sync($request, $root) as xs:string
     - Fetches from Zotero /groups/{groupId}/items with include=data,bib and
       the configured CSL style; follows Link rel="next".
     - Writes items to $config:zotero-items-dir as <key>.json.
     - Updates meta.json with libraryVersion and syncedAt.
     - Returns a serialized JSON string (xs:string). Sets Content-Type: application/json.
     - NOTE: We serialize on purpose to avoid Roaster atomizing map/array
       values (FOTY0013). If Roaster is patched later, this can return map(*).

  2) zotero:items-search($request, $root) as xs:string
     - Query params: q (full-text over title + creators + DOI), tag (exact,
       case-insensitive), limit (default 15).
     - Returns serialized JSON with { query, total, returned, items[] }.
     - Sets headers: Content-Type: application/json, X-Total-Count: <total>.

  3) zotero:item-bib-top($request, $root) as xs:string
     - Query params:
         key = item key; OR
         tag = tag name (top-level only, first match).
     - Returns a single HTML snippet:
         • bib string if present, else
         • <span class="zotero-title">Title or note</span> (safely serialized).
     - Sets Content-Type: text/html; charset=UTF-8.

  Configuration (from modules/config.xqm)
  ---------------------------------------
  The module expects these variables to be provided by your app config:

    $config:zotero-api-base   xs:string
      Base URL for Zotero Web API, e.g. "https://api.zotero.org".

    $config:zotero-group-id   xs:string or xs:integer
      The single group to sync, e.g. "2519759".

    $config:zotero-style      xs:string
      CSL style id for server-side bibliography rendering, e.g.
      "chicago-note-bibliography" or "digital-humanities-im-deutschsprachigen-raum".

    $config:zotero-items-dir  xs:string
      Collection where item JSON files are stored, e.g.
      "/db/apps/edep-data/zotero/groups/2519759/items".

    $config:zotero-meta-path  xs:string
      Full resource path to meta.json, e.g.
      "/db/apps/edep-data/zotero/groups/2519759/meta.json".

    $config:zotero-api-key    xs:string (optional)
      API key if the group requires auth. Public groups can omit this.

  Storage layout (created by post-install)
  ----------------------------------------
    /db/apps/edep-data/zotero/
      groups/
        {groupId}/
          items/
            <key>.json     (serialized map { data: {...}, bib: "<html or empty>" })
          meta.json        (serialized map { libraryVersion: int, syncedAt: dateTime })

  Error handling and status
  -------------------------
    • Upstream HTTP errors return a JSON body { status: "error", httpStatus, ... }.
    • Sync handles 304 Not Modified and updates meta.json accordingly.
    • Search always returns 200 with an empty result set when nothing matches.
    • item-bib-top returns:
        200 on success,
        400 when both key and tag are missing,
        404 when the cache is missing or no item was found.

  Notes on Roaster JSON handling
  ------------------------------
    Roaster 1.10.0 atomizes function results; XDM maps/arrays are function
    items and cannot be atomized (FOTY0013). Until Roaster gains native JSON
    output for map/array values, endpoints in this module serialize their
    responses to xs:string and set the Content-Type header themselves.
    In OpenAPI, you can declare "text/plain" for such responses to avoid
    double-encoding; clients still see valid JSON because the handler sets
    application/json.

  ==============================================================================
:)


declare %private function zotero:json($v as item()*) as xs:string {
  serialize($v, map{"method":"json","indent":true()})
};

(: grab header values case-insensitively :)
declare %private function zotero:header($resp as element(http:response), $name as xs:string) as xs:string* {
  $resp/http:header[lower-case(@name) = lower-case($name)]/@value/string()
};

(:~
  Build standard HTTP headers for Zotero API calls.

  Always includes:
    - Accept: application/json
    - User-Agent: eXist/zotero-sync

  Optionally includes:
    - Authorization / Zotero-API-Key header if configured in your config.xqm.
    - Any extra header passed in (e.g., If-Modified-Since-Version).

  Parameters:
    @param $extra element(http:header)?  Optional extra header to include.

  Return:
    @return element(http:header)*  A sequence of http:header elements ready to
                                   be inserted into <http:request>.

  Example:
    <http:request method="GET">
      { attribute href { $href } }
      { zotero:headers(
          if ($since gt 0)
          then <http:header name="If-Modified-Since-Version" value="{ $since }"/>
          else ()
        )
      }
    </http:request>
:)
(: Build headers for Zotero requests :)
declare function zotero:headers($extra as element(http:header)?) as element(http:header)* {
  let $base :=
    (<http:header name="Accept" value="application/json"/>,
     <http:header name="User-Agent" value="eXist/zotero-sync"/>,
     (: avoid gzip auto-encoding issues :)
     <http:header name="Accept-Encoding" value="identity"/>)
  let $key := normalize-space(string(($config:zotero-api-key, "")[1]))
  let $auth :=
    if ($key ne "")
    then <http:header name="Zotero-API-Key" value="{ $key }"/>
    else ()
  return ($base, $auth, $extra)
};


(: ───────────────── path helper (normalized) ───────────────── :)
declare %private function zotero:path-split($abs as xs:string) as map(*) {
  let $norm := replace($abs, '/+$', '')                     (: drop trailing '/' :)
  let $name := tokenize($norm, '/')[last()]
  let $coll := substring($norm, 1, string-length($norm) - string-length($name) - 1)
  return map{ "coll": $coll, "name": $name }
};

declare %private function zotero:resource-exists($coll as xs:string, $name as xs:string) as xs:boolean {
  if (not(xmldb:collection-available($coll))) then false()
  else some $r in xmldb:get-child-resources($coll) satisfies ($r = $name)
};

(:~
  Read the sync meta information from `$config:zotero-meta-path`.

  If the meta file does not exist or cannot be parsed, returns a default map:
    { "libraryVersion": 0 }

  Return:
    @return map(*)  e.g. { "libraryVersion": 8306, "syncedAt": "2025-10-09T12:34:56Z" }

  Errors:
    - Exceptions are caught internally; a default map is returned.
:)
declare %private function zotero:read-meta() as map(*) {
  let $ps := zotero:path-split($config:zotero-meta-path)
  let $exists := zotero:resource-exists($ps?coll, $ps?name)
  return
    if (not($exists)) then
      map{ "libraryVersion": 0, "syncedAt": "" }
    else
      let $uri := concat($ps?coll, "/", $ps?name)
      let $bin := try { util:binary-doc($uri) } catch * { () }
      let $txt := if (exists($bin)) then util:binary-to-string($bin) else ""
      return
        if (normalize-space($txt) = "") then
          map{ "libraryVersion": 0, "syncedAt": "" }
        else
          try { parse-json($txt) } catch * { map{ "libraryVersion": 0, "syncedAt": "" } }
};

(:~
  Write sync meta information to `$config:zotero-meta-path`.

  Overwrites or creates `meta.json` with:
    {
      "libraryVersion": <lmv>,
      "syncedAt": current-dateTime()
    }

  Parameters:
    @param $libraryVersion xs:integer  Zotero Last-Modified-Version to persist.

  Return:
    @return xs:boolean  true() on success, false() on any error.

  Side-effects:
    - Stores JSON with media type `application/json`.
:)
declare %private function zotero:write-meta($lmv as xs:integer) as xs:boolean {
  let $ps   := zotero:path-split($config:zotero-meta-path)
  let $json := serialize(
                 map{ "libraryVersion": $lmv, "syncedAt": current-dateTime() },
                 map{ "method":"json", "indent": true() }
               )
  let $_rm  := try { xmldb:remove($ps?coll, $ps?name) } catch * { () }
  return
    try {
      let $_ := xmldb:store($ps?coll, $ps?name, $json, "application/json")
      return true()
    } catch * {
      false()
    }
};

(: store one item <key>.json into items dir — 4-arg store :)
declare %private function zotero:store-item($key as xs:string, $data as map(*)) as xs:string {
  xmldb:store(
    $config:zotero-items-dir,
    concat($key, ".json"),
    serialize($data, map{"method":"json","indent": true()}),
    "application/json"
  )
};

(:~
  Ingest a single Zotero page (array of items) into the local cache.

  For each array entry, extracts:
    - key = item key (from top-level `key` or `data?key`)
    - data = the `data` object
    - bib  = the `bib` string (when `include=bib` was requested)

  Stores `{ data + "bib": <string?> }` as `<key>.json` under `$config:zotero-items-dir`.

  Parameters:
    @param $arr array(*)  The parsed JSON array from Zotero.

  Return:
    @return xs:integer  Number of items successfully stored.
:)
declare %private function zotero:ingest-page($arr as array(*)) as xs:integer {
  let $n := array:size($arr)
  return
    if ($n = 0) then 0
    else
      sum(
        for $i in 1 to $n
        let $item   := array:get($arr, $i)
        let $key    := string(($item?key, $item?data?key)[1])
        let $data   := $item?data
        let $bib    := $item?bib
        let $toSave :=
          if (exists($data)) then
            if (exists($bib)) then map:merge(($data, map{"bib": string($bib)}))
            else $data
          else
            (: extremely rare, but if Zotero returned only a bib :)
            map{"bib": string($bib)}
        let $_ :=
          if ($key != "") then zotero:store-item($key, $toSave) else ()
        return if ($key != "") then 1 else 0
      )
};
declare %private function zotero:next-link($resp as element(http:response)) as xs:string {
  let $links := $resp/http:header[lower-case(@name) = 'link']/@value/string()
  let $cands :=
    for $line in $links
    let $parts := tokenize($line, ',')
    for $p in $parts
    where contains($p, 'rel="next"') or contains($p, "rel='next'")
    let $u := normalize-space(substring-before(substring-after($p, '<'), '>'))
    return $u
  return string-join((($cands)[1]), '')  (: () -> '' :)
};

(:~
  Follow pagination and ingest subsequent pages.

  Issues an HTTP GET to `$next`, parses JSON, ingests items, and recursively
  follows the next `Link: rel="next"` until exhausted.

  Parameters:
    @param $next xs:string     Absolute Zotero API URL taken from the Link header.
    @param $acc  xs:integer    Accumulator of items ingested so far.

  Return:
    @return xs:integer         Total count of items ingested (including prior pages).

  Notes:
    - Pass an empty string to stop: the function will return $acc unchanged.
    - Uses the same headers as the first page (zotero:headers()).
:)
declare %private function zotero:sync-follow($next as xs:string?, $acc as xs:integer) as xs:integer {
  if (empty($next) or $next = '') then $acc
  else
    let $req :=
      <http:request method="GET" href="{$next}">
        { zotero:headers(()) }
      </http:request>
    let $seq := try { http:send-request($req) } catch * { () }
    return
      if (empty($seq)) then $acc
      else
        let $resp   := $seq[1]
        let $status := xs:integer($resp/@status)
        return
          if ($status != 200) then $acc
          else
            let $raw := try { util:binary-to-string($seq[2]) } catch * { "" }
            let $arr := if (normalize-space($raw) = "") then array{} else
                        try { parse-json($raw) } catch * { array{} }
            let $c   := zotero:ingest-page($arr)
            let $more := zotero:next-link($resp)
            return zotero:sync-follow($more, $acc + $c)
};

(: ─────────────────────────────────────────────────────────
   Public endpoint: POST /api/zotero/sync
   ───────────────────────────────────────────────────────── :)
declare function zotero:sync() as xs:string {
  response:set-header("Content-Type","application/json"),
  zotero:sync(map{}, <root/>)
};
declare function zotero:sync($request as map(*)) as xs:string {
  response:set-header("Content-Type","application/json"),
  zotero:sync($request, <root/>)
};

(:~
  Sync cached Zotero items for the configured group.

  Hits the Zotero Web API `/groups/{groupId}/items` with `include=data,bib`
  (plus your CSL `style`) and `limit=100`, follows pagination via the HTTP
  `Link: rel="next"` header, and writes each item as `<key>.json` into
  `$config:zotero-items-dir`. Also updates `$config:zotero-meta-path`
  with the latest `libraryVersion` and `syncedAt`.

  NOTE: Returns a serialized JSON string (xs:string) intentionally to avoid
  Roaster’s atomization issue with map/array results. `Content-Type` is set
  to `application/json`.

  Parameters:
    @param $request map(*)   Roaster request context (not used here; kept for arity).
    @param $root    element() Roaster root element (unused).

  Return:
    @return xs:string  JSON string like:
      {
        "status":"ok|error",
        "updated": <int>,                 (: number of items written this call :)
        "libraryVersion": <int>,          (: Zotero Last-Modified-Version :)
        "metaWriteOk": true|false,        (: meta.json write result :)
        "metaPath": "<abs-collection>/meta.json",
        "httpStatus": <int>,              (: only on error :)
        "errorBody": "<payload>",         (: only on error :)
        "requestHref": "<debug-url>"      (: on error, sometimes on ok :)
      }

  Headers:
    - Sets `Content-Type: application/json`.
    - Sends `If-Modified-Since-Version` when a previous `libraryVersion` exists.
    - Adds `Zotero-API-Key` if configured in your module.

  Side-effects:
    - Writes/overwrites `<items-dir>/<key>.json` (merged { data + bib }).
    - Writes/overwrites `meta.json` with { libraryVersion, syncedAt }.

  Status codes:
    - 200 (body "status":"ok") on success or 304-from-Zotero.
    - 200 (body "status":"error") with details on upstream HTTP errors.

  Example (curl):
    curl -sS '…/api/zotero/sync'

  See also:
    - zotero:headers()
    - zotero:ingest-page()
    - zotero:write-meta()
    - zotero:sync-follow()
:)
declare function zotero:sync($request as map(*), $root as element()) {
  response:set-header("Content-Type","application/json"),

  let $meta   := try { zotero:read-meta() } catch * { map{ "libraryVersion": 0 } }
  let $since  := xs:integer(($meta?libraryVersion, 0)[1])

  let $base   := concat($config:zotero-api-base, "/groups/", string($config:zotero-group-id), "/items")

  (: IMPORTANT: & must be &amp; inside attributes; style value must be encoded :)
  let $href   := concat(
                    $base,
                    "?since=", encode-for-uri(string($since)),
                    "&amp;limit=100",
                    "&amp;include=data,bib",
                    "&amp;format=json",
                    "&amp;style=",$config:zotero-style
                 )

  let $req :=
    <http:request method="GET" href="{$href}">
      {
        zotero:headers(
          if ($since gt 0)
          then <http:header name="If-Modified-Since-Version" value="{ string($since) }"/>
          else ()
        )
      }
    </http:request>

  let $respSeq := try { http:send-request($req) } catch * { () }

  let $payload :=
    if (empty($respSeq)) then
      map{
        "status"      : "error",
        "reason"      : "http:send-request failed",
        "requestHref" : $href,
        "metaPath"    : $config:zotero-meta-path
      }
    else
      let $resp   := $respSeq[1]
      let $status := xs:integer($resp/@status)
      return
        if ($status = 304) then
          let $ok := zotero:write-meta($since)
          return map{
            "status"         : "ok",
            "updated"        : 0,
            "libraryVersion" : $since,
            "metaWriteOk"    : $ok,
            "metaPath"       : $config:zotero-meta-path
          }
        else if ($status != 200) then
          let $errBody := try { util:binary-to-string($respSeq[2]) } catch * { "" }
          return map{
            "status"      : "error",
            "httpStatus"  : $status,
            "errorBody"   : $errBody,
            "requestHref" : $href,
            "metaPath"    : $config:zotero-meta-path
          }
        else
          let $raw   := try { util:binary-to-string($respSeq[2]) } catch * { "" }
          let $clean := if (starts-with($raw, codepoints-to-string(65279))) then substring($raw, 2) else $raw
          let $arr   := if (normalize-space($clean) = "") then array{} else
                        try { parse-json($clean) } catch * { array{} }
          let $items := if ($arr instance of array(*)) then $arr else array{}
          let $c1    := zotero:ingest-page($items)

          (: make $next a STRING so we never pass () into sync-follow :)
          let $next  := string((
            for $line in $resp/http:header[lower-case(@name)='link']/@value/string()
            let $parts := tokenize($line, ",")
            for $p in $parts
            where contains($p, 'rel="next"') or contains($p, "rel='next'")
            return normalize-space(substring-before(substring-after($p, "<"), ">"))
          )[1])

          let $cN    := if ($next = '') then 0 else zotero:sync-follow($next, 0)

          let $lmvStr := ($resp/http:header[lower-case(@name)='last-modified-version']/@value)[1]
          let $lmv    := if (exists($lmvStr) and normalize-space($lmvStr) ne "") then xs:integer($lmvStr) else $since

          let $ok := zotero:write-meta($lmv)

          return map{
            "status"         : "ok",
            "updated"        : $c1 + $cN,
            "libraryVersion" : $lmv,
            "metaWriteOk"    : $ok,
            "metaPath"       : $config:zotero-meta-path
          }

  return serialize($payload, map{ "method":"json", "indent": true() })
};

(: ─────────────────────────────────────────────────────────
   Public endpoint: POST /api/zotero/items/search
   ───────────────────────────────────────────────────────── :)

declare function zotero:items-search() as xs:string {
  zotero:items-search(map{}, <root/>)
};

declare function zotero:items-search($request as map(*)) as xs:string {
  zotero:items-search($request, <root/>)
};

(:~
  Search cached items (JSON only, from local cache).

  Scans `$config:zotero-items-dir` for `*.json`, applies optional
  full-text query `q` over title/creators/DOI, optional `tag` filter,
  applies `limit`, and returns a result object with counts and items.

  NOTE: Returns a serialized JSON string (xs:string). Sets
  `Content-Type: application/json` and `X-Total-Count`.

  Query parameters:
    - q     (string)   Full-text across title + creators + DOI (case-insensitive).
    - tag   (string)   Match items that have this Zotero tag (case-insensitive).
    - limit (integer)  Maximum items to return (default 15; minimum 1).

  Parameters:
    @param $request map(*)    Roaster request context (unused beyond reading query params).
    @param $root    element() Roaster root element (unused).

  Return:
    @return xs:string JSON like:
      {
        "query":    { "q":"…", "tag":"…", "limit": 15 },
        "total":    <int>,           (: matches before limit :)
        "returned": <int>,           (: items included :)
        "items":    [ { "key":"…", "data": {…} }, … ]
      }

  Matching rules:
    - `q` is matched with `contains()` against a normalized string built from:
        - title (data?title)
        - creators (joined first/last/name)
        - DOI (data?DOI or data?doi)
    - `tag` matches if the item has ANY tag equal to the parameter (lowercased).

  Headers:
    - `Content-Type: application/json`
    - `X-Total-Count: <total>`

  Status codes:
    - 200 (always) — empty result set when nothing matches.

:)
declare function zotero:items-search($request as map(*), $root as element()) as xs:string {
  response:set-header("Content-Type", "application/json"),

  let $coll  := $config:zotero-items-dir
  let $qIn   := lower-case(normalize-space(request:get-parameter("q", "")))
  let $tagIn := lower-case(normalize-space(request:get-parameter("tag", "")))
  let $limIn := $request?parameters?limit
  let $limit := let $n := try { xs:integer($limIn) } catch * { 15 }
                return if ($n lt 1) then 15 else $n

  let $names :=
    if (xmldb:collection-available($coll))
    then for $n in xmldb:get-child-resources($coll)
         where ends-with($n, ".json")
         return $n
    else ()

  let $matches :=
    for $name in $names
    let $uri := concat($coll, "/", $name)
    let $bin := try { util:binary-doc($uri) } catch * { () }
    let $txt := if (exists($bin)) then util:binary-to-string($bin) else ""
    where string-length($txt) gt 0
    let $data := try { parse-json($txt) } catch * { map{} }

    let $key  := string(( $data?key, replace($name, "\.json$", "") )[1])

    (: tag filter :)
    let $hasTag :=
      if ($tagIn = "") then true()
      else if ($data?tags instance of array(*)) then
        some $i in 1 to array:size($data?tags)
        satisfies lower-case(string((array:get($data?tags, $i)?tag)[1])) = $tagIn
      else false()

    (: q filter over title + creators + DOI — SAFE coalescing :)
    let $title    := lower-case(string(($data?title)[1]))
    let $creators :=
      if ($data?creators instance of array(*)) then
        string-join(
          for $i in 1 to array:size($data?creators)
          let $c  := array:get($data?creators, $i)
          let $ln := string(($c?lastName)[1])
          let $fn := string(($c?firstName)[1])
          let $nm := string(($c?name)[1])
          let $parts := ($ln, $fn, $nm)
          let $nonEmpty := for $p in $parts where normalize-space($p) ne "" return $p
          let $one := normalize-space(string-join($nonEmpty, " "))
          where $one ne ""
          return $one
        , " ")
      else ""
    let $doi      := lower-case(string((($data?DOI, $data?doi)[1])))

    let $hay := normalize-space(string-join(($title, $creators, $doi), " "))
    let $okQ := ($qIn = "") or contains($hay, $qIn)

    where $hasTag and $okQ
    return map{ "key": $key, "data": $data }

  let $total    := count($matches)
  let $limited  := subsequence($matches, 1, $limit)
  let $_hdr     := response:set-header("X-Total-Count", string($total))

  let $payload := map{
    "query":    map{ "q": $qIn, "tag": $tagIn, "limit": $limit },
    "total":    $total,                       (: matches before limit :)
    "returned": count($limited),              (: items in this page :)
    "items":    array { $limited }            (: [{key,data}, …] :)
  }

  return serialize($payload, map{ "method": "json", "indent": true() })
};

(: ─────────────────────────────────────────────────────────
   Public endpoint: POST /api/zotero/items/bib
   ───────────────────────────────────────────────────────── :)

(: ── wrappers (streaming: return empty-sequence()) ── :)
declare function zotero:item-bib() as empty-sequence() {
  zotero:item-bib(map{}, <root/>)
};

declare function zotero:item-bib($request as map(*)) as empty-sequence() {
  zotero:item-bib($request, <root/>)
};

(: helper: serialize a small HTML fallback safely :)
declare %private function zotero:_fallback-html($title as xs:string) as xs:string {
  serialize(
    <span class="zotero-title">{ $title }</span>,
    map{ "method":"html", "omit-xml-declaration": true(), "indent": false() }
  )
};

(: helper: load one cached item by key (returns parsed map or empty) :)
declare %private function zotero:_load-item-by-key($key as xs:string) as item()? {
  let $coll := $config:zotero-items-dir
  let $uri  := concat($coll, "/", $key, ".json")
  let $bin  := try { util:binary-doc($uri) } catch * { () }
  let $txt  := if (exists($bin)) then util:binary-to-string($bin) else ""
  return if ($txt ne "") then try { parse-json($txt) } catch * { () } else ()
};

(: ── MAIN: GET /api/zotero/items/top/bib?key=... | ?tag=... ── :)
declare function zotero:item-bib($request as map(*), $root as element()) as empty-sequence() {
  response:set-header("Content-Type", "text/html; charset=UTF-8"),

  let $coll := $config:zotero-items-dir
  let $key  := normalize-space(request:get-parameter("key", ""))
  let $tag  := lower-case(normalize-space(request:get-parameter("tag", "")))

  let $emit :=
    function($html as xs:string) as empty-sequence() {
      response:stream-binary(util:string-to-binary($html), "text/html", ()),
      ()
    }

  return
    if (not(xmldb:collection-available($coll))) then (
      response:set-status-code(404),
      $emit("<!-- cache not available -->")
    )

    else if ($key ne "") then
      let $item := zotero:_load-item-by-key($key)
      return
        if (empty($item)) then (
          response:set-status-code(404),
          $emit("<!-- no cached item for key -->")
        ) else
          let $bib := string(($item?bib)[1])
          return
            if (normalize-space($bib) ne "") then
              $emit($bib)
            else
              let $parentKey := string(($item?parentItem)[1])
              return
                if (normalize-space($parentKey) ne "") then
                  let $parent := zotero:_load-item-by-key($parentKey)
                  return
                    if (empty($parent)) then
                      $emit(zotero:_fallback-html(string((($item?title, $item?note)[1]))))
                    else
                      let $pb := string(($parent?bib)[1])
                      return
                        if (normalize-space($pb) ne "") then
                          $emit($pb)
                        else
                          $emit(zotero:_fallback-html(string((($parent?title, $item?title, $item?note)[1]))))
                else
                  $emit(zotero:_fallback-html(string((($item?title, $item?note)[1]))))

    else if ($tag ne "") then
      let $names := xmldb:get-child-resources($coll)[ends-with(., ".json")]
      let $found :=
        (
          for $name in $names
          let $uri := concat($coll, "/", $name)
          let $bin := try { util:binary-doc($uri) } catch * { () }
          let $txt := if (exists($bin)) then util:binary-to-string($bin) else ""
          where $txt ne ""
          let $data := try { parse-json($txt) } catch * { () }

          (: top-level only :)
          let $parent := string(($data?parentItem)[1])
          where normalize-space($parent) = ""

          (: tag match, case-insensitive :)
          let $tags :=
            if ($data?tags instance of array(*)) then
              for $i in 1 to array:size($data?tags)
              return lower-case(normalize-space(string((array:get($data?tags, $i)?tag)[1])))
            else ()
          where some $t in $tags satisfies $t = $tag

          return $data
        )[1]
      return
        if (empty($found)) then (
          response:set-status-code(404),
          $emit("<!-- no top-level item with that tag -->")
        )
        else
          let $bib := string(($found?bib)[1])
          return
            if (normalize-space($bib) ne "") then
              $emit($bib)
            else
              $emit(zotero:_fallback-html(string(($found?title)[1])))

    else (
      response:set-status-code(400),
      $emit("<!-- missing key or tag parameter -->")
    )
};

(: ── wrappers ── :)
declare function zotero:items-suggest() as xs:string {
  zotero:items-suggest(map{}, <root/>)
};

declare function zotero:items-suggest($request as map(*)) as xs:string {
  zotero:items-suggest($request, <root/>)
};

(: serialize a tiny HTML safely :)
declare %private function zotero:_as-html($n as node()) as xs:string {
  serialize($n, map { "method":"html", "omit-xml-declaration": true(), "indent": false() })
};

(: MAIN: GET /api/zotero/items/suggest?q=&tag=&limit=&top=1 :)
declare function zotero:items-suggest($request as map(*), $root as element()) as xs:string {
  response:set-header("Content-Type", "application/json"),

  let $coll   := $config:zotero-items-dir
  let $qIn    := lower-case(normalize-space(request:get-parameter("q", "")))
  let $tagIn  := lower-case(normalize-space(request:get-parameter("tag", "")))
  let $limIn  := request:get-parameter("limit", "8")
  let $limit  := let $n := try { xs:integer($limIn) } catch * { 8 }
                 return if ($n lt 1) then 8 else $n
  let $topIn  := request:get-parameter("top", "1")
  let $topOnly:= not($topIn = ("0","false","no"))

  let $names :=
    if (xmldb:collection-available($coll))
    then xmldb:get-child-resources($coll)[ends-with(., ".json")]
    else ()

  let $matches :=
    for $name in $names
    let $uri := concat($coll, "/", $name)
    let $bin := try { util:binary-doc($uri) } catch * { () }
    let $txt := if (exists($bin)) then util:binary-to-string($bin) else ""
    where $txt ne ""
    let $data := try { parse-json($txt) } catch * { map{} }

    (: skip non-top-level if requested :)
    let $parent := string(($data?parentItem)[1])
    where (not($topOnly)) or (normalize-space($parent) = "")

    (: quick tag set :)
    let $tags :=
      if ($data?tags instance of array(*)) then
        for $i in 1 to array:size($data?tags)
        return lower-case(normalize-space(string((array:get($data?tags, $i)?tag)[1])))
      else ()
    let $primaryTag := string(($tags[1], "")[1])

    (: tag filter :)
    where ($tagIn = "") or (some $t in $tags satisfies $t = $tagIn)

    (: build haystack for q over title/creators/DOI :)
    let $title := lower-case(string(($data?title)[1]))
    let $creators :=
      if ($data?creators instance of array(*)) then
        string-join(
          for $i in 1 to array:size($data?creators)
          let $c  := array:get($data?creators, $i)
          let $ln := string(($c?lastName)[1])
          let $fn := string(($c?firstName)[1])
          let $nm := string(($c?name)[1])
          let $parts := ($ln, $fn, $nm)
          let $nonEmpty := for $p in $parts where normalize-space($p) ne "" return $p
          let $one := normalize-space(string-join($nonEmpty, " "))
          where $one ne ""
          return $one
        , " ")
      else ""
    let $doi := lower-case(string((($data?DOI, $data?doi)[1])))
    let $hay := normalize-space(string-join(($title, $creators, $doi), " "))

    where ($qIn = "") or contains($hay, $qIn)

    (: display label: cached bib or title fallback :)
    let $bib := string(($data?bib)[1])
    let $label :=
      if (normalize-space($bib) ne "") then $bib
      else zotero:_as-html(<span class="zotero-title">{ $title }</span>)

    let $key := string(($data?key, replace($name, "\.json$", ""))[1])

    return map{
      "key":   $key,
      "tag":   $primaryTag,
      "label": $label
    }

  let $total   := count($matches)
  let $limited := subsequence($matches, 1, $limit)

  let $payload := map{
    "query":    map{ "q": $qIn, "tag": $tagIn, "limit": $limit, "top": $topOnly },
    "total":    $total,
    "returned": count($limited),
    "items":    array { $limited }
  }

  return serialize($payload, map{ "method":"json", "indent": true() })
};
