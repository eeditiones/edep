xquery version "3.1";

(:~
 : This is the place to import your own XQuery modules for either:
 :
 : 1. custom API request handling functions
 : 2. custom templating functions to be called from one of the HTML templates
 :)
module namespace api="http://teipublisher.com/api/custom";

(: Add your own module imports here :)
import module namespace rutil="http://exist-db.org/xquery/router/util";
import module namespace app="teipublisher.com/app" at "app.xql";
import module namespace config="http://www.tei-c.org/tei-simple/config" at "config.xqm";

declare namespace json="http://www.json.org";
declare namespace tei="http://www.tei-c.org/ns/1.0";


(:~
 : Keep this. This function does the actual lookup in the imported modules.
 :)
declare function api:lookup($name as xs:string, $arity as xs:integer) {
    try {
        function-lookup(xs:QName($name), $arity)
    } catch * {
        ()
    }
};

declare function api:writing($request as map(*)) {
    try {
        <root>{doc("/db/apps/edep/data/writing.xml")/items/item}</root>
    } catch * {
        ()
    }
};

declare function api:typeins($request as map(*)) {         
    try {
        <root>{doc("/db/apps/edep/data/typeins.xml")}</root>
    } catch * {
        ()
    }
};

declare function api:statepreserv($request as map(*)) {
   try {
        <root>{doc("/db/apps/edep/data/statepreserv.xml")/items/item}</root>
    } catch * {
        ()
    }
};

declare function api:objtyp($request as map(*)) {
    try {
        <root>{doc("/db/apps/edep/data/objtyp.xml")/items/item}</root>
    } catch * {
        ()
    }
};

declare function api:decor($request as map(*)) {
   try {
        <root>{doc("/db/apps/edep/data/decor.xml")/items/item}</root> 
    } catch * {
        ()
    }
};

declare function api:material($request as map(*)) {
    try {
        <root>{doc("/db/apps/edep/data/material.xml")//material}</root>
    } catch * {
        ()
    }
};

declare function api:places-list($request as map(*)) {
    let $return := if (not($request?parameters?id)) then
        let $search := normalize-space($request?parameters?search)
        let $letterParam := $request?parameters?category
        let $limit := $request?parameters?limit
        let $places :=
            if ($search and $search != '') then
                collection($config:places)/tei:place/tei:placeName[@type="findspot"][matches(@n, "^" || $search, "i")]/text()
            else
                collection($config:places)/tei:place/tei:placeName[@type="findspot"]/text()
        let $sorted := sort($places, "?lang=de-DE", function($place) { lower-case($place/@n) })
        let $letter := 
            if (count($places) < $limit) then 
                "Alle"
            else if ($letterParam = '') then
                substring($sorted[1], 1, 1) => upper-case()
            else
                $letterParam
        let $byLetter :=
            if ($letter = 'Alle') then
                $sorted
            else
                filter($sorted, function($entry) {
                    starts-with(lower-case($entry/@n), lower-case($letter))
                })
        return
            map {
                "items": api:output-place($byLetter),
                "categories":
                    if (count($places) < $limit) then
                        []
                    else array {
                        for $index in 1 to string-length('ABCDEFGHIJKLMNOPQRSTUVWXYZ')
                            let $alpha := substring('ABCDEFGHIJKLMNOPQRSTUVWXYZ', $index, 1)
                            let $hits := count(filter($sorted, function($entry) { starts-with(lower-case($entry/@n), lower-case($alpha))}))
                            where $hits > 0
                            return
                                map {
                                    "category": $alpha,
                                    "count": $hits
                                },
                                map {
                                    "category": "Alle",
                                    "count": count($sorted)
                                }
                    }
            }
    else 
        doc(concat($config:places, $request?parameters?id, ".xml"))
    return try {
        $return
    } catch * {
        ()
    }
};

declare function api:output-place($list) {
    array {
        for $place in $list
            let $label := $place/@n/string()
            return
                <span class="place">
                    <a href="{$label}">{$place}</a>
                </span>
    }
};

declare function api:places-add($request as map(*)) {
    let $return := if ($request?parameters?id and not(empty($request?body//@xml:id))) then
            xmldb:store($config:places, concat($request?parameters?id, ".xml"), $request?body)
        else
            let $ids := sort(collection($config:places)//@xml:id/string())
            let $id-new := if (empty($ids)) then "000000" else format-number(xs:integer(replace($ids[last()], "G", "")) + 1, "000000")
            let $store := xmldb:store($config:places, concat("G", $id-new, ".xml"), $request?body)
            let $update := update insert attribute xml:id {concat("G", $id-new)} into doc(concat($config:places, "G", $id-new, ".xml"))/tei:place
            return $ids   

    return try {
        $return
    } catch * {
        ()
    }
};

declare function api:inscription($request as map(*)) {
    let $check-collection := if(not(xmldb:collection-available($config:inscription))) then xmldb:create-collection("/", $config:inscription) else ()
    let $return := if ($request?parameters?id) then
            xmldb:store($config:inscription, concat($request?parameters?id, ".xml"), $request?body)
        else
            let $ids := sort(collection($config:inscription)//tei:idno[@type="EDEp"]/text())
            let $id-new := if (empty($ids)) then "0000000" else format-number(xs:integer(replace($ids[last()], "E", "")) + 1, "0000000")
            let $store := xmldb:store($config:inscription, concat("E", $id-new, ".xml"), $request?body)
            return update value doc(concat($config:inscription, "E", $id-new, ".xml"))//tei:msIdentifier/tei:idno[@type="EDEp"] 
                with concat("E", $id-new)

    return try {
        $return
    } catch * {
        ()
    }
};

declare function api:inscription-template($request as map(*)) {
    let $uuid := util:uuid()
    let $template := doc($config:inscription-templ)
    let $pre-uuid := api:preprocessing-uuid($template, $uuid) 
    let $pre-select := api:preprocessing-select($pre-uuid)
    let $return := api:preprocessing-copy($pre-uuid, $pre-select)

    return try {
        $return
    } catch * {
        ()
    }
};

declare %private function  api:preprocessing-uuid($nodes as node()*, $uuid as xs:string){
    for $node in $nodes
    return
        typeswitch($node)
            case comment () return $node
            case text() return $node
            case element (tei:msPart) return <msPart > {attribute xml:id {$uuid}} {$node/node()}</msPart>
            case element (tei:surface) return <surface> {attribute corresp {concat("#",$uuid)}} {$node/node()}</surface>
            case element (tei:div) return 
                if  ($node/@corresp) then <div corresp="{concat("#",$uuid)}"> { $node/@type, $node/@subtype, $node/@n, $node/node()} </div> 
                else <div> { $node/@*, api:preprocessing-uuid($node/node(), $uuid) } </div>
            case element () return  element {node-name($node)} { $node/@*, api:preprocessing-uuid($node/node(), $uuid)}
        default return  api:preprocessing-uuid($node/node(), $uuid)
};

declare %private function  api:preprocessing-select($nodes as node()*){
    for $node in $nodes
    return
        typeswitch($node)
            case element (tei:body) return $node/node()
            case element (tei:facsimile) return $node
        default return api:preprocessing-select($node/node())
};

declare %private function  api:preprocessing-copy($nodes as node()*, $insert as node()*){
    for $node in $nodes
    return
        typeswitch($node)
            case comment () return $node
            case text() return $node
            case element (tei:msPart) return <msPart> {$node/@* , $node/node(), $insert } </msPart>
            case element () return  element {node-name($node)} { $node/@*, api:preprocessing-copy($node/node(), $insert)}
        default return api:preprocessing-copy($node/node(), $insert)
}; 