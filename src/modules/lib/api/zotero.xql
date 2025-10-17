xquery version "3.1";

module namespace zotero = "http://e-editiones.org/edep/api/zotero";

declare namespace http     = "http://expath.org/ns/http-client";
declare namespace request  = "http://exist-db.org/xquery/request";
declare namespace response = "http://exist-db.org/xquery/response";
declare namespace xmldb    = "http://exist-db.org/xquery/xmldb";
declare namespace util     = "http://exist-db.org/xquery/util";
import module namespace config = "http://www.tei-c.org/tei-simple/config" at "../../config.xqm";

(: ---------------------------------------------------------------------------
   CONFIG (provided by your app's modules/config.xqm)
   We assume these exist:
     $config:zotero-api-base    (e.g. "https://api.zotero.org")
     $config:zotero-group-id    (e.g. "2519759")
     $config:zotero-style       (e.g. "digital-humanities-im-deutschsprachigen-raum")
     $config:zotero-meta-path   (abs resource path to meta.json)
     $config:zotero-items-dir   (collection for JSON items)
     $config:zotero-items-xml-dir (collection for XML mirror; you set '/items-xml')
     $config:zotero-api-key     (optional)
--------------------------------------------------------------------------- :)
(: ---- RESOLVED CONFIG (computed once) -------------------------------- :)

(: base collection holding JSON items, as configured :)
declare variable $zotero:ITEMS_DIR as xs:string := $config:zotero-items-dir;

(: derive the Zotero group base “…/zotero/groups/{id}” from ITEMS_DIR :)
declare variable $zotero:GROUP_BASE as xs:string :=
  substring-before($zotero:ITEMS_DIR, "/items");

(: canonical XML mirror collection:
   - if $config:zotero-items-xml-dir starts with /db/ use as-is
   - else treat it as relative to GROUP_BASE (strip leading / if present) :)
declare variable $zotero:XML_DIR as xs:string :=
  let $cfg := normalize-space($config:zotero-items-xml-dir)
  return
    if (starts-with($cfg, "/db/")) then $cfg
    else concat($zotero:GROUP_BASE, "/", replace($cfg, "^/", ""));

(: meta.json absolute resource path as configured :)
declare variable $zotero:META_PATH as xs:string := $config:zotero-meta-path;

(: API constants :)
declare variable $zotero:API_BASE  as xs:string := $config:zotero-api-base;
declare variable $zotero:GROUP_ID  as xs:string := $config:zotero-group-id;
declare variable $zotero:STYLE     as xs:string := $config:zotero-style;
declare variable $zotero:API_KEY   as xs:string := $config:zotero-api-key;

declare %private function zotero:_xml-matches($i as element(item), $q as xs:string) as xs:boolean {
  if ($q = "") then true()
  else
    let $lc := lower-case#1
    let $hay := string-join((
      $lc(string($i/title)),
      for $c in $i/creators/c return string-join(($lc(string($c/@last)), $lc(string($c/@first)), $lc(string($c/@name))), " "),
      $lc(string($i/doi))
    ), " ")
    return contains($hay, $q)
};

(: ====== HEADERS for Zotero HTTP requests ====== :)
declare %private function zotero:headers($extra as element(http:header)?) as element(http:header)* {
  let $base :=
    (<http:header name="Accept" value="application/json"/>,
     <http:header name="User-Agent" value="eXist/zotero-sync"/>,
     <http:header name="Accept-Encoding" value="identity"/>)
  let $auth := if (normalize-space($zotero:API_KEY) ne "")
               then <http:header name="Zotero-API-Key" value="{ $zotero:API_KEY }"/>
               else ()
  return ($base, $auth, $extra)
};

declare %private function zotero:read-meta() as map(*) {
  if (doc-available($zotero:META_PATH)) then
    let $bin := util:binary-doc($zotero:META_PATH)
    let $txt := if ($bin) then util:binary-to-string($bin) else ""
    return if ($txt ne "") then try { parse-json($txt) } catch * { map{ "libraryVersion": 0 } }
           else map{ "libraryVersion": 0 }
  else map{ "libraryVersion": 0 }
};

declare %private function zotero:write-meta($lv as xs:integer) as xs:boolean {
  let $coll := substring-before($zotero:META_PATH, concat("/", tokenize($zotero:META_PATH, "/")[last()]))
  let $name := tokenize($zotero:META_PATH, "/")[last()]
  return
    try {
      let $_ := xmldb:store(
        $coll,
        $name,
        serialize(
          map{ "libraryVersion": $lv, "syncedAt": current-dateTime() },
          map{ "method":"json", "indent": true() }
        ),
        "application/json"
      )
      return true()
    } catch * {
      false()
    }
};

declare %private function zotero:xml-from-json($data as map(*), $bib as xs:string?) as element(item) {
  let $key     := string(($data?key, $data?data?key)[1])
  let $title   := string(($data?title, $data?data?title)[1])
  let $dt      := string(($data?dateModified, $data?data?dateModified)[1])
  let $parent  := string(($data?parentItem, $data?data?parentItem)[1])
  let $type    := string(($data?itemType, $data?data?itemType)[1])
  let $cre     := $data?data?creators
  let $tagsArr := $data?data?tags
  let $doi     := string(($data?data?DOI, $data?data?doi)[1])
  return
    <item key="{ $key }" itemType="{ $type }" dateModified="{ $dt }" parentItem="{ $parent }">
      <title>{ $title }</title>
      <creators>{
        if ($cre instance of array(*)) then
          for $i in 1 to array:size($cre)
          let $c := array:get($cre, $i)
          return element c {
            if ($c?lastName)  then attribute last  { string($c?lastName) }  else (),
            if ($c?firstName) then attribute first { string($c?firstName) } else (),
            if ($c?name)      then attribute name  { string($c?name) }      else ()
          }
        else ()
      }</creators>
      { if (normalize-space($doi) ne "") then <doi>{ $doi }</doi> else () }
      <tags>{
        if ($tagsArr instance of array(*)) then
          for $i in 1 to array:size($tagsArr)
          let $t := lower-case(normalize-space(string(array:get($tagsArr, $i)?tag)))
          where $t ne "" return <tag>{ $t }</tag>
        else ()
      }</tags>
      { if (normalize-space($bib) ne "") then <bib html="true">{ $bib }</bib> else <bib html="false"/> }
    </item>
};

declare %private function zotero:xml-upsert(
  $data as map(*),
  $bib  as xs:string?
) as empty-sequence() {
  let $key  := string(($data?key, $data?data?key)[1])
  let $xml  := zotero:xml-from-json($data, $bib)
  let $name := concat($key, ".xml")
  let $_    := xmldb:store($zotero:XML_DIR, $name, $xml, "application/xml")
  return ()
};

(: ====== Ingest one page of items from Zotero (array) ====== :)
declare %private function zotero:ingest-page($arr as array(*)) as xs:integer {
  let $n :=
    sum(
      for $i in 1 to array:size($arr)
      let $entry := array:get($arr, $i)
      let $key   := string(($entry?key, $entry?data?key)[1])
      let $data  := if ($entry?data instance of map(*)) then $entry?data else map{}
      let $bib   := string(($entry?bib)[1])
      let $json  := serialize(map{ "data": $data, "bib": $bib }, map{"method":"json"})
      let $_js   := xmldb:store($config:zotero-items-dir, concat($key, ".json"), $json, "application/json")
      let $_xml  := zotero:xml-upsert(map{ "key": $key, "data": $data }, $bib)
      return 1
    )
  return $n
};

(: ====== Follow pagination via Link rel="next" and ingest ====== :)
declare %private function zotero:sync-follow($next as xs:string, $acc as xs:integer) as xs:integer {
  if (normalize-space($next) = "") then $acc
  else
    let $req :=
    <http:request method="GET">
    { attribute href { $next } }
    { zotero:headers(()) }
    </http:request>
    let $res := try { http:send-request($req) } catch * { () }
    return
      if (empty($res)) then $acc
      else
        let $r1    := $res[1]
        let $code  := xs:integer($r1/@status)
        return
          if ($code != 200) then $acc
          else
            let $raw  := try { util:binary-to-string($res[2]) } catch * { "" }
            let $arr  := if (normalize-space($raw) = "") then array{} else try { parse-json($raw) } catch * { array{} }
            let $cnt  := if ($arr instance of array(*)) then zotero:ingest-page($arr) else 0
            let $nextHref :=
              string((
                for $line in $r1/http:header[lower-case(@name)='link']/@value/string()
                let $parts := tokenize($line, ",")
                for $p in $parts
                where contains($p, 'rel="next"') or contains($p, "rel='next'")
                return normalize-space(substring-before(substring-after($p, "<"), ">"))
              )[1])
            return zotero:sync-follow($nextHref, $acc + $cnt)
};

(: ====== SYNC endpoint ====== :)
declare function zotero:sync($request as map(*)) {
  response:set-header("Content-Type","application/json"),

  let $meta  := try { zotero:read-meta() } catch * { map{ "libraryVersion": 0 } }
  let $since := xs:integer(($meta?libraryVersion, 0)[1])
  let $log := util:log('info','USER ' || sm:id()//sm:real/sm:username/string())
  let $user := $request?user
  let $log := util:log('info','REQUEST USER ' || sm:id()//sm:real/sm:username/string())

  let $base  := concat($zotero:API_BASE, "/groups/", $zotero:GROUP_ID, "/items")
  let $qs    := string-join((
                  concat("since=", encode-for-uri(string($since))),
                  "limit=100",
                  "include=data,bib",
                  "format=json",
                  if (normalize-space($zotero:STYLE) ne "")
                  then concat("style=", encode-for-uri($zotero:STYLE))
                  else ()
               ), "&amp;")
  let $href  := concat($base, "?", $qs)
  let $log := util:log('info','HREF ' || $href)

  let $req :=
    <http:request method="GET">
      { attribute href { $href } }
      {
        zotero:headers(
          if ($since gt 0)
          then <http:header name="If-Modified-Since-Version" value="{ string($since) }"/>
          else ()
        )
      }
    </http:request>

  let $respSeq := try { http:send-request($req) } catch * { () }

  return
    if (empty($respSeq)) then
      serialize(map{
        "status":"error",
        "reason":"http:send-request failed",
        "requestHref": $href
      }, map{"method":"json","indent":true()})
    else
      let $resp   := $respSeq[1]
      let $status := xs:integer($resp/@status)
      return

        if ($status = 304) then (
          zotero:write-meta($since),
          serialize(map{ "status":"ok", "updated": 0, "libraryVersion": $since },
                    map{"method":"json","indent":true()})
        )
        else if ($status != 200) then
          let $err := try { util:binary-to-string($respSeq[2]) } catch * { "" }
          return serialize(map{
            "status":"error",
            "httpStatus": $status,
            "errorBody": $err,
            "requestHref": $href
          }, map{"method":"json","indent":true()})
        else
          let $raw   := try { util:binary-to-string($respSeq[2]) } catch * { "" }
          let $clean := if (starts-with($raw, codepoints-to-string(65279))) then substring($raw, 2) else $raw
          let $arr   := if (normalize-space($clean) = "") then array{} else try { parse-json($clean) } catch * { array{} }
          let $c1    :=
            if ($arr instance of array(*)) then
              sum(
                for $i in 1 to array:size($arr)
                let $entry := array:get($arr, $i)
                let $key   := string(($entry?key, $entry?data?key)[1])
                let $data  := if ($entry?data instance of map(*)) then $entry?data else map{}
                let $bib   := string(($entry?bib)[1])
                let $json  := serialize(map{ "data": $data, "bib": $bib }, map{"method":"json"})
                let $_j    := xmldb:store($zotero:ITEMS_DIR, concat($key, ".json"), $json, "application/json")
                let $_x    := zotero:xml-upsert(map{ "key": $key, "data": $data }, $bib)
                return 1
              )
            else 0
          let $next  := string((
              for $line in $resp/http:header[lower-case(@name)='link']/@value/string()
              let $parts := tokenize($line, ",")
              for $p in $parts
              where contains($p, 'rel="next"') or contains($p, "rel='next'")
              return normalize-space(substring-before(substring-after($p, "<"), ">"))
            )[1])
          let $cN   := if ($next = '') then 0 else zotero:sync-follow($next, 0)
          let $lmvStr := ($resp/http:header[lower-case(@name)='last-modified-version']/@value)[1]
          let $lmv    := if ($lmvStr and normalize-space($lmvStr) ne "") then xs:integer($lmvStr) else $since
          let $_m := zotero:write-meta($lmv)
          return serialize(map{
            "status":"ok",
            "updated": $c1 + $cN,
            "libraryVersion": $lmv
          }, map{"method":"json","indent":true()})
};

(: ====== SUGGEST (lightweight for autocomplete) ====== :)
declare function zotero:items-suggest($request as map(*)) {
  response:set-header("Content-Type", "application/json"),
  let $q     := lower-case(normalize-space(request:get-parameter("q", "")))
  let $tag   := lower-case(normalize-space(request:get-parameter("tag", "")))
  let $limit := let $l := number(request:get-parameter("limit", "8")) return if ($l ge 1) then xs:integer($l) else 8

  let $pool :=
    collection($zotero:XML_DIR)/item[
      zotero:_xml-matches(., $q)
      and ( $tag = "" or tags/tag = $tag )
    ]
  let $sorted := for $i in $pool order by xs:dateTime($i/@dateModified) descending return $i
  let $picked := subsequence($sorted, 1, $limit)

  let $arr := array {
    for $i in $picked
    return map{
      "key":   string($i/@key),
      "title": string($i/title),
      "bib":   if ($i/bib/@html = "true") then string($i/bib) else "",
      "tag": data($i//tag[1])
    }
  }
  return serialize($arr, map{ "method":"json", "indent": true() })
};


declare function zotero:items-search($request as map(*)) {
  response:set-header("Content-Type", "application/json"),
  let $q     := lower-case(normalize-space(request:get-parameter("q", "")))
  let $tag   := lower-case(normalize-space(request:get-parameter("tag", "")))
  let $limit := let $l := number(request:get-parameter("limit", "15")) return if ($l ge 1) then xs:integer($l) else 15

  let $pool :=
    collection($zotero:XML_DIR)/item[
      ( $q = "" or ft:query(., $q) )
      and ( $tag = "" or tags/tag = $tag )
    ]

  let $sorted := for $i in $pool order by xs:dateTime($i/@dateModified) descending return $i
  let $total  := count($sorted)
  let $picked := subsequence($sorted, 1, $limit)

  let $items := array {
    for $i in $picked
    let $key := string($i/@key)
    let $bin := util:binary-doc(concat($zotero:ITEMS_DIR, "/", $key, ".json"))
    let $txt := if ($bin) then util:binary-to-string($bin) else ""
    let $obj := if ($txt ne "") then try { parse-json($txt) } catch * { () } else ()
    return
      if ($obj instance of map(*)) then map{ "key": $key, "data": ($obj?data, $obj)[1] }
      else                           map{ "key": $key, "data": map{} }
  }

  let $resp := map{
    "query":    map{ "q": $q, "tag": $tag, "limit": $limit },
    "total":    $total,
    "returned": array:size($items),
    "items":    $items
  }
  return serialize($resp, map{ "method":"json", "indent": true() })
};

(: ====== BIB HTML SNIPPET (streams raw HTML) ====== :)

declare %private function zotero:_fallback-html($title as xs:string) as xs:string {
  serialize(<span class="zotero-title">{ $title }</span>, map{"method":"html","omit-xml-declaration":true(),"indent":false()})
};

declare %private function zotero:_load-json($key as xs:string) as map(*)? {
  let $bin := util:binary-doc(concat($config:zotero-items-dir, "/", $key, ".json"))
  let $txt := if ($bin) then util:binary-to-string($bin) else ""
  return if ($txt ne "") then try { parse-json($txt) } catch * { () } else ()
};

