xquery version "3.1";

module namespace zotero = "http://teipublisher.com/api/zotero";

declare namespace map   = "http://www.w3.org/2005/xpath-functions/map";
declare namespace http  = "http://expath.org/ns/http-client";
declare namespace xmldb = "http://exist-db.org/xquery/xmldb";
declare namespace util  = "http://exist-db.org/xquery/util";
import module namespace response = "http://exist-db.org/xquery/response";
(: Import your config module — update the path :)
import module namespace config = "http://www.tei-c.org/tei-simple/config"
  at "../../config.xqm";

(: ─────────────────────────────────────────────────────────
   Helpers
   ───────────────────────────────────────────────────────── :)

declare %private function zotero:json($v as item()*) as xs:string {
  serialize($v, map{"method":"json","indent":true()})
};

(: Build headers; Authorization omitted if key is empty :)
(:
declare %private function zotero:headers($extra as element(http:header)*) as element(http:header)* {
  let $apiVer := <http:header name="Zotero-API-Version" value="3"/>
  let $accept := <http:header name="Accept" value="application/json"/>
  let $ua     := <http:header name="User-Agent" value="edep/1.9 (exist-6.4; fore; contact: you@example.org)"/>
  let $auth   :=
    if (normalize-space($config:zotero-api-key) ne "") then (
      <http:header name="Zotero-API-Key" value="{ $config:zotero-api-key }"/>,
      <http:header name="Authorization" value="{ concat('Bearer ', $config:zotero-api-key) }"/>
    ) else ()
  return ($apiVer, $accept, $ua, $auth, $extra)
};
:)

(: grab header values case-insensitively :)
declare %private function zotero:header($resp as element(http:response), $name as xs:string) as xs:string* {
  $resp/http:header[lower-case(@name) = lower-case($name)]/@value/string()
};

(: replace your zotero:headers :)
declare %private function zotero:headers($extra as element(http:header)*) as element(http:header)* {
  let $apiVer := <http:header name="Zotero-API-Version" value="3"/>
  let $accept := <http:header name="Accept" value="application/json"/>
  let $ua     := <http:header name="User-Agent" value="edep/2.0 (exist-6.4; fore)"/>
  let $auth   :=
    if (normalize-space($config:zotero-api-key) ne "") then (
      <http:header name="Zotero-API-Key" value="{ $config:zotero-api-key }"/>,
      <http:header name="Authorization" value="{ concat('Bearer ', $config:zotero-api-key) }"/>
    ) else ()
  return ($apiVer, $accept, $ua, $auth, $extra)
};

(: split an absolute DB path into (collection, resource name) :)
(:declare %private function zotero:path-split($abs as xs:string) as map(*) {
  let $name := tokenize($abs, "/")[last()]
  let $coll := substring($abs, 1, string-length($abs) - string-length($name) - 1)
  return map{"coll": $coll, "name": $name}
};:)
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
(: read meta.json as JSON; create a template if missing — uses util:binary-doc :)
(:declare %private function zotero:read-meta() as map(*) {
  let $ps := zotero:path-split($config:zotero-meta-path)
  return
    if (not(xmldb:collection-available($ps?coll))) then
      map{"libraryVersion": 0, "syncedAt": ""}
    else if (zotero:resource-exists($ps?coll, $ps?name)) then
      let $bin := util:binary-doc($config:zotero-meta-path)
      return try { parse-json(util:binary-to-string($bin)) }
             catch * { map{"libraryVersion": 0, "syncedAt": ""} }
    else (
      map{"libraryVersion": 0, "syncedAt": ""}
    )
};:)

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

(: write meta.json — 4-arg store to set media type :)
(:declare %private function zotero:write-meta($lmv as xs:integer) as xs:string {
  let $ps := zotero:path-split($config:zotero-meta-path)
  return
    if (not(xmldb:collection-available($ps?coll))) then ""
    else xmldb:store(
      $ps?coll, $ps?name,
      serialize(map{"libraryVersion": $lmv, "syncedAt": current-dateTime()}, map{"method":"json","indent": true()}),
      "application/json"
    )
};:)
(: overwrite meta.json with new libraryVersion + syncedAt :)
(:
declare %private function zotero:write-meta($lmv as xs:integer) as xs:string {
  let $ps   := zotero:path-split($config:zotero-meta-path)
  let $_rm  := try { xmldb:remove($ps?coll, $ps?name) } catch * { () }
  let $json := serialize(
                 map{ "libraryVersion": $lmv, "syncedAt": current-dateTime() },
                 map{ "method":"json", "indent": true() }
               )
  return xmldb:store($ps?coll, $ps?name, $json, "application/json")
};
:)

(: ─────────── overwrite meta.json; return true() on success ─────────── :)
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


(: Ingest one page of items :)
declare %private function zotero:ingest-page($arr as array(*)) as xs:integer {
  let $n :=
    for $it in $arr?*
        let $k := $it?key
        let $d := $it?data
        where exists($k) and exists($d)
        return zotero:store-item($k, $d)
  return count($arr?*)
};

(: returns exactly one xs:string: the rel="next" URL or '' :)
(:declare %private function zotero:next-link($resp as element(http:response)) as xs:string {
  let $links := $resp/http:header[lower-case(@name) = 'link']/@value/string()
  let $cands :=
    for $line in $links
    let $parts := tokenize($line, ',')
    for $p in $parts
    where contains($p, 'rel="next"') or contains($p, "rel='next'")
    let $u := normalize-space(substring-before(substring-after($p, '<'), '>'))
    return $u
  return string-join((($cands)[1]), '')  :)(: coerce () → '' :)(:
};:)
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

(: Follow pagination :)
(: follow pagination; $next may be empty :)
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
   Incremental sync
   ───────────────────────────────────────────────────────── :)

(: primary worker: keep your existing sync($config,$root) unchanged :)
(: declare function zotero:sync($config as map(*), $root as element()) as xs:string { ... }; :)

declare function zotero:debug-exports() as xs:string {
  let $ns  := "http://example.org/zotero"
  let $ok2 := exists(function-lookup(QName($ns, "sync"), 2))
  let $ok1 := exists(function-lookup(QName($ns, "sync"), 1))
  let $ok0 := exists(function-lookup(QName($ns, "sync"), 0))
  return serialize(map{
    "sync#2": $ok2, "sync#1": $ok1, "sync#0": $ok0
  }, map{"method":"json","indent":true()})
};


(: ─────────────────────────────────────────────────────────
   Public endpoint: POST /api/z/sync
   ───────────────────────────────────────────────────────── :)
(: optional arity shims so Roaster can call #0/#1 too :)

(: MAIN :)

(: Roaster-safe wrappers; keep if your router may call #0/#1 :)
declare function zotero:sync() as xs:string {
  response:set-header("Content-Type","application/json"),
  zotero:sync(map{}, <root/>)
};
declare function zotero:sync($config as map(*)) as xs:string {
  response:set-header("Content-Type","application/json"),
  zotero:sync($config, <root/>)
};

(: MAIN :)
(: INLINE sync — writes meta.json on BOTH 304 and 200 :)
(: ─────────── sync: ALWAYS writes meta.json (200 and 304) ─────────── :)
declare function zotero:sync($config as map(*), $root as element()) as xs:string {
  response:set-header("Content-Type","application/json"),

  let $meta   := try { zotero:read-meta() } catch * { map{ "libraryVersion": 0 } }
  let $since  := xs:integer(($meta?libraryVersion, 0)[1])

  let $base   := concat($config:zotero-api-base, "/groups/", string($config:zotero-group-id), "/items")
  let $href   := concat($base,
                        "?since=", encode-for-uri(string($since)),
                        "&amp;limit=100",
                        "&amp;include=data")

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

  return serialize(
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

          let $next  := (
            for $line in $resp/http:header[lower-case(@name)='link']/@value/string()
            let $parts := tokenize($line, ",")
            for $p in $parts
            where contains($p, 'rel="next"') or contains($p, "rel='next'")
            return normalize-space(substring-before(substring-after($p, "<"), ">"))
          )[1]
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
  , map{ "method":"json", "indent": true() })
};
