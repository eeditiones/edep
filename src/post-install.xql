xquery version "3.0";

import module namespace pmu="http://www.tei-c.org/tei-simple/xquery/util";
import module namespace pmc="http://www.tei-c.org/tei-simple/xquery/config";
import module namespace odd="http://www.tei-c.org/tei-simple/odd2odd";
import module namespace config="http://www.tei-c.org/tei-simple/config" at "modules/config.xqm";
import module namespace tpu="http://www.tei-c.org/tei-publisher/util" at "util.xql";

declare namespace repo="http://exist-db.org/xquery/repo";

(: The following external variables are set by the repo:deploy function :)

(: file path pointing to the exist installation directory :)
declare variable $home external;
(: path to the directory containing the unpacked .xar package :)
declare variable $dir external;
(: the target collection into which the app is deployed :)
declare variable $target external;


declare variable $repoxml :=
    let $uri := doc($target || "/expath-pkg.xml")/*/@name
    let $repo := util:binary-to-string(repo:get-resource($uri, "repo.xml"))
    return
        parse-xml($repo)
;

declare function local:mkcol-recursive($collection, $components) {
    if (exists($components)) then
        let $newColl := concat($collection, "/", $components[1])
        return (
            if (not(xmldb:collection-available($collection || "/" || $components[1]))) then
                let $created := xmldb:create-collection($collection, $components[1])
                return (
                    sm:chown(xs:anyURI($created), $repoxml//repo:permissions/@user),
                    sm:chgrp(xs:anyURI($created), $repoxml//repo:permissions/@group),
                    sm:chmod(xs:anyURI($created), replace($repoxml//repo:permissions/@mode, "(..).(..).(..).", "$1x$2x$3x"))
                )
            else
                (),
            local:mkcol-recursive($newColl, subsequence($components, 2))
        )
    else
        ()
};

(: Helper function to recursively create a collection hierarchy. :)
declare function local:mkcol($collection, $path) {
    local:mkcol-recursive($collection, tokenize($path, "/"))
};

declare function local:create-data-collection() {
    if (xmldb:collection-available($config:data-root)) then
        ()
    else if (starts-with($config:data-root, $target)) then
        local:mkcol($target, substring-after($config:data-root, $target || "/"))
    else
        ()
};


declare function local:generate-code($collection as xs:string) {
    for $source in ($config:odd-available, $config:odd-internal)
    let $odd := doc($collection || "/resources/odd/" || $source)
    let $pi := tpu:parse-pi($odd, (), $source)
    for $module in
        if ($pi?output) then
            tokenize($pi?output)
        else
            $config:odd-media
    for $file in pmu:process-odd (
        (:    $odd as document-node():)
        odd:get-compiled($collection || "/resources/odd" , $source),
        (:    $output-root as xs:string    :)
        $collection || "/transform",
        (:    $mode as xs:string    :)
        $module,
        (:    $relPath as xs:string    :)
        "transform",
        (:    $config as element(modules)?    :)
        doc($collection || "/resources/odd/configuration.xml")/*,
        $module = "web")
    return
        (),
    let $permissions := $repoxml//repo:permissions[1]
    return (
        for $file in xmldb:get-child-resources($collection || "/transform")
        let $path := xs:anyURI($collection || "/transform/" || $file)
        return (
            sm:chown($path, $permissions/@user),
            sm:chgrp($path, $permissions/@group)
        )
    )
};

(:─────────────────────────────────────────────────────────────
 : ZOTERO LAYOUT (uses local:mkcol-recursive($collection,$components))
 : append to post-install.xql — no existing code removed
 :─────────────────────────────────────────────────────────────:)

(: split absolute /db path into components after '/db/' :)
declare function local:path-components-after-db($abs as xs:string) as xs:string* {
  let $norm := replace($abs, '/+$', '')
  let $rel  := substring-after($norm, '/db/')
  return if ($rel = '' or $rel = $norm) then () else tokenize($rel, '/')
};

(: convenience wrapper: create an absolute /db path with mkcol-recursive :)
declare function local:mkcol-abs($abs as xs:string) as empty-sequence() {
  let $comps := local:path-components-after-db($abs)
  return if (empty($comps)) then () else local:mkcol-recursive('/db', $comps)
};

(: 6.4-safe resource existence :)
declare function local:zotero-resource-exists($coll as xs:string, $name as xs:string) as xs:boolean {
  if (not(xmldb:collection-available($coll))) then false()
  else some $r in xmldb:get-child-resources($coll) satisfies ($r = $name)
};

(: split absolute db path → {coll, name} :)
declare function local:zotero-path-split($abs as xs:string) as map(*) {
  let $name := tokenize($abs, '/')[last()]
  let $coll := substring($abs, 1, string-length($abs) - string-length($name) - 1)
  return map{ "coll": $coll, "name": $name }
};

(: seed meta.json if missing; returns true() if written :)
(: seed meta.json if missing, then align its permissions to the parent collection :)
declare function local:zotero-seed-meta-if-missing($abs as xs:string) as xs:boolean {
  let $ps := local:zotero-path-split($abs)
  return
    if (not(xmldb:collection-available($ps?coll))) then false()
    else
      let $exists  := local:zotero-resource-exists($ps?coll, $ps?name)
      let $created :=
        if ($exists) then false()
        else
          try {
            let $_ := xmldb:store(
              $ps?coll, $ps?name,
              serialize(
                map { "libraryVersion": 0, "syncedAt": current-dateTime() },
                map { "method":"json", "indent": true() }
              ),
              "application/json"
            )
            return true()
          } catch * { false() }
      (: ALWAYS try to align perms (whether created just now or already existed) :)
      let $_fixPerms :=
        try {
          let $resPath := concat($ps?coll, "/", $ps?name)
          let $p       := sm:get-permissions($ps?coll)
          let $owner   := string(($p/@owner, "guest")[1])
          let $group   := string(($p/@group, "guest")[1])
          let $mode    := string(($p/@mode,  "rw-rw-r--")[1])
          let $_1 := sm:chown($resPath, "edep")
          let $_2 := sm:chgrp($resPath, "tei")
          let $_3 := sm:chmod($resPath, $mode)
          return ()
        } catch * { () }
      return $created
};

(: PUBLIC: ensure base, group, items; then seed meta :)
declare function local:zotero-ensure-layout() as map(*) {
  let $_b := local:mkcol-abs($config:zotero-base-dir)
  let $_g := local:mkcol-abs($config:zotero-group-dir)
  let $_i := local:mkcol-abs($config:zotero-items-dir)
  let $_h := local:mkcol-abs($config:zotero-items-xml-dir)

  let $metaSeeded := local:zotero-seed-meta-if-missing($config:zotero-meta-path)

  return map{
    "status": "ok",
    "ensured": map{
      "base":  xmldb:collection-available($config:zotero-base-dir),
      "group": xmldb:collection-available($config:zotero-group-dir),
      "items": xmldb:collection-available($config:zotero-items-dir),
      "items-xml": xmldb:collection-available($config:zotero-items-xml-dir),
      "metaSeeded": $metaSeeded
    },
    "paths": map{
      "base":  $config:zotero-base-dir,
      "group": $config:zotero-group-dir,
      "items": $config:zotero-items-dir,
      "items-xml": $config:zotero-items-xml-dir,
      "meta":  $config:zotero-meta-path
    }
  }
};

(: OPTIONAL JSON summary for logs :)
declare function local:zotero-ensure-layout-json() as xs:string {
  serialize(local:zotero-ensure-layout(), map{ "method":"json", "indent": true() })
};


(: API needs dba rights for LaTeX :)
sm:chgrp(xs:anyURI($target || "/modules/lib/api-dba.xql"), "dba"),
sm:chmod(xs:anyURI($target || "/modules/lib/api-dba.xql"), "rwxr-Sr-x"),

local:mkcol($target, "transform"),
local:generate-code($target),
local:create-data-collection(),
local:zotero-ensure-layout(),
xmldb:reindex('/db/apps/edep-data'),
let $pmuConfig := pmc:generate-pm-config(($config:odd-available, $config:odd-internal), $config:default-odd, $config:odd-root, $config:odd-media)
return
    xmldb:store($config:app-root || "/modules", "pm-config.xql", $pmuConfig, "application/xquery")