xquery version "3.1";

(:~
 : This is the place to import your own XQuery modules for either:
 :
 : 1. custom API request handling functions
 : 2. custom templating functions to be called from one of the HTML templates
 :)
module namespace api="http://teipublisher.com/api/custom";

(: Add your own module imports here :)
import module namespace config="http://www.tei-c.org/tei-simple/config" at "config.xqm";

declare namespace json="http://www.json.org";
declare namespace tei="http://www.tei-c.org/ns/1.0";
declare namespace sm="http://exist-db.org/xquery/securitymanager";

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
        <root>{doc($config:data-root || "/writing.xml")/items/item}</root>
    } catch * {
        ()
    }
};

declare function api:typeins($request as map(*)) {         
    try {
        <root>{doc($config:data-root || "/typeins.xml")}</root>
    } catch * {
        ()
    }
};

declare function api:statepreserv($request as map(*)) {
   try {
        <root>{doc($config:data-root || "/statepreserv.xml")/items/item}</root>
    } catch * {
        ()
    }
};

declare function api:objtyp($request as map(*)) {
    try {
        <root>{doc($config:data-root || "/objtyp.xml")/items/item}</root>
    } catch * {
        ()
    }
};

declare function api:decor($request as map(*)) {
   try {
        <root>{doc($config:data-root || "/decor.xml")/items/item}</root> 
    } catch * {
        ()
    }
};

declare function api:material($request as map(*)) {
    try {
        <root>{doc($config:data-root || "/material.xml")//material}</root>
    } catch * {
        ()
    }
};

declare function api:places-browse($request as map(*)) {
    let $search := normalize-space($request?parameters?search)
    let $letterParam := $request?parameters?category
    let $limit := $request?parameters?limit
    let $places :=
        if ($search and $search != '') then
            collection($config:data-root || "/places")//tei:place[ft:query(tei:placeName, $search || '*')] |
            collection($config:data-root || "/places")//tei:place[contains(@xml:id, $search)]
        else
            collection($config:data-root || "/places")//tei:place
    let $sorted := 
        for $place in $places
        order by $place/tei:placeName[@type="modern"]
        return
            $place
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
                starts-with(lower-case($entry/tei:placeName[@type="modern"]), lower-case($letter))
            })
    return
        map {
            "items": api:output-place($byLetter, $letter, $search),
            "categories":
                if (count($places) < $limit) then
                    []
                else array {
                    for $index in 1 to string-length('ABCDEFGHIJKLMNOPQRSTUVWXYZ')
                    let $alpha := substring('ABCDEFGHIJKLMNOPQRSTUVWXYZ', $index, 1)
                    let $hits := count(filter($sorted, function($entry) { starts-with(lower-case($entry/tei:placeName[@type="modern"]), lower-case($alpha))}))
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
};

declare function api:output-place($list, $category as xs:string, $search as xs:string?) {
    array {
        for $place in $list
        let $categoryParam := if ($category = "all") then substring($place/@n, 1, 1) else $category
        let $params := "id=" || $place/@xml:id || "&amp;category=" || $categoryParam || "&amp;search=" || $search
        let $label := string-join((
            $place/tei:placeName[@type='modern'][node()],
            $place/tei:placeName[@type='ancient'][node()],
            $place/tei:region[@type='ancient'][node()],
            $place/tei:region[@type='province'][node()],
            $place/tei:placeName[@type='findspot'][node()]
        ), '; ')
        let $coords := tokenize($place/tei:location/tei:geo)
        return
            <span class="place">
                <a href="geodata.html?{$params}">{$label}</a>
                <!--
                <pb-geolocation latitude="{$coords[1]}" longitude="{$coords[2]}" label="{$label}" emit="map" event="click">
                    { if ($place/@type != 'approximate') then attribute zoom { 9 } else () }
                    <iron-icon icon="maps:map"></iron-icon>
                </pb-geolocation>
                -->
                <paper-icon-button id="{$place/@xml:id}" class="place-id" icon="icons:content-copy"
                    title="ID kopieren"></paper-icon-button>
            </span>
    }
};

declare function api:load-place($request as map(*)) {
    let $return := doc(concat($config:places, $request?parameters?id, ".xml"))
    return try {
        $return
    } catch * {
        ()
    }
};

declare function api:places-add($request as map(*)) {
    let $id := if ($request?parameters?id and not(empty($request?body//@xml:id))) then
            let $store := xmldb:store($config:places, concat($request?parameters?id, ".xml"), $request?body)
            return $request?body//@xml:id

        else if ($request?body//@xml:id) then
            let $id := $request?body//@xml:id
            let $store  := xmldb:store($config:places, concat($id, ".xml"), $request?body)
            return $id
        else
            let $ids := sort(collection($config:places)//@xml:id/string())
            let $id-new := if (empty($ids)) then "000000" else format-number(xs:integer(replace($ids[last()], "G", "")) + 1, "000000")
            let $store := xmldb:store($config:places, concat("G", $id-new, ".xml"), $request?body)
            let $update := update insert attribute xml:id {concat("G", $id-new)} into doc(concat($config:places, "G", $id-new, ".xml"))/tei:place
            return concat("G",$id-new)
             

    return try {
        doc(concat($config:places, $id, ".xml"))
    } catch * {
        ()
    }
};

declare function api:people-browse($request as map(*)) {
    let $search := normalize-space($request?parameters?search)
    let $letterParam := $request?parameters?category
    let $limit := $request?parameters?limit
    let $people :=
        if ($search and $search != '') then
            collection($config:data-root || "/people")//tei:person[ft:query(tei:persName, $search || '*')]
        else
            collection($config:data-root || "/people")//tei:person
    let $sorted := 
        for $person in $people
        order by $person/tei:persName[@type='nomen']
        return
            $person
    let $letter := 
        if (count($people) < $limit) then 
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
                starts-with(lower-case($entry/tei:persName/tei:name[@type='nomen']), lower-case($letter))
            })
    return
        map {
            "items": api:output-person($byLetter, $letter, $search),
            "categories":
                if (count($people) < $limit) then
                    []
                else array {
                    for $index in 1 to string-length('ABCDEFGHIJKLMNOPQRSTUVWXYZ')
                    let $alpha := substring('ABCDEFGHIJKLMNOPQRSTUVWXYZ', $index, 1)
                    let $hits := count(filter($sorted, function($entry) { starts-with(lower-case($entry/tei:persName/tei:name[@type='nomen']), lower-case($alpha))}))
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
};

declare function api:output-person($list, $category as xs:string, $search as xs:string?) {
    array {
        for $person in $list
        let $categoryParam := if ($category = "all") then substring($person/tei:persName/tei:name[@type='nomen'], 1, 1) else $category
        let $params := "id=" || $person/@xml:id || "&amp;category=" || $categoryParam || "&amp;search=" || $search
        let $label := string-join((
            $person/tei:persName/tei:name[@type='praenomen'][node()],
            $person/tei:persName/tei:name[@type='cognomen'][node()],
            $person/tei:persName/tei:name[@type='nomen'][node()]
        ), ' ')
        return
            <span class="person">
                <a href="person.html?{$params}">{$label}</a>
                <paper-icon-button id="{$person/@xml:id}" class="place-id" icon="icons:content-copy"
                    title="ID kopieren"></paper-icon-button>
            </span>
    }
};

declare function api:load-person($request as map(*)) {
    let $return := doc(concat($config:people, $request?parameters?id, ".xml"))
    return try {
        $return
    } catch * {
        ()
    }
};

declare function api:person-add($request as map(*)) {
    let $id := if ($request?parameters?id and not(empty($request?body//@xml:id))) then
            let $store := xmldb:store($config:people, concat($request?parameters?id, ".xml"), $request?body)
            return $request?body//@xml:id

        else if ($request?body//@xml:id) then
            let $id := $request?body//@xml:id
            let $store  := xmldb:store($config:people, concat($id, ".xml"), $request?body)
            return $id
        else
            let $ids := sort(collection($config:people)//@xml:id/string())
            let $id-new := if (empty($ids)) then "000000" else format-number(xs:integer(replace($ids[last()], "P", "")) + 1, "000000")
            let $withId :=
                <person xmlns="http://www.tei-c.org/ns/1.0" xml:id="P{$id-new}">
                { 
                    $request?body//tei:person/@sex,
                    $request?body/tei:person/* 
                }
                </person>
            let $store := xmldb:store($config:people, concat("P", $id-new, ".xml"), $withId)
            return concat("P",$id-new)
             

    return try {
        doc(concat($config:people, $id, ".xml"))
    } catch * {
        ()
    }
};

declare function api:inscription($request as map(*)) {
    let $check-collection := if(not(xmldb:collection-available($config:inscription))) then xmldb:create-collection("/", $config:inscription) else ()
    let $id := 
        if ($request?parameters?id) then
            let $store := xmldb:store($config:inscription, concat($request?parameters?id, ".xml"), api:postprocess($request?body, ()) => api:clean-namespace())
            return $request?body//tei:idno[@type="EDEp"]/text()
        else if ($request?body//tei:idno[@type="EDEp"]/node()) then
            let $id := $request?body//tei:idno[@type="EDEp"]/text()
            let $store := xmldb:store($config:inscription, concat($id, ".xml"), api:postprocess($request?body, ()) => api:clean-namespace())
            return $request?body//tei:idno[@type="EDEp"]/text()
        else
            let $ids := sort(collection($config:inscription)//tei:idno[@type="EDEp"]/text())
            let $id-new := if (empty($ids)) then "0000001" else format-number(xs:integer(replace($ids[last()], "E", "")) + 1, "0000000")
            let $store := xmldb:store($config:inscription, concat("E", $id-new, ".xml"), api:postprocess($request?body, "E" || $id-new) => api:clean-namespace())
            return concat("E", $id-new)

    return try {
        let $preprocessing := map {
            "parameters" : map {
                    "id" : $id
                }
            }
        return api:inscription-template($preprocessing)
    } catch * {
        ()
    }
};

declare function api:inscription-template($request as map(*)) {
    let $id := $request?parameters?id
    let $doc :=
        if ($id) then
            collection($config:data-root)//tei:idno[@type="EDEp"][. = $id]/ancestor::tei:TEI
        else
            doc($config:inscription-templ)
    let $input :=
        if (util:document-name($doc) = "epidoc-template.xml") then
            api:preprocessing-uuid($doc, util:uuid())
        else
            $doc
    let $return := api:preprocessing-copy($input)

    return try {
        $return
    } catch * {
        ()
    }
};

declare %private function api:postprocess($nodes as node()*, $edepId as xs:string?) {
    for $node in $nodes
    return
        typeswitch($node)
            case document-node() return
                document { api:postprocess($node/node(), $edepId) }
            case element(tei:msPart) return
                element { node-name($node) } {
                    $node/@*,
                    api:postprocess($node/* except ($node/tei:div, $node/tei:facsimile), $edepId)
                }
            case element(tei:idno) return
                if ($node/@type = "EDEp" and exists($edepId)) then
                    element { node-name($node) } {
                        $node/@*,
                        $edepId
                    }
                else
                    $node
            case element(tei:TEI) return
                element { node-name($node) } {
                    $node/@*,
                    api:postprocess($node/tei:teiHeader, $edepId),
                    root($node)//tei:msPart/tei:facsimile,
                    api:postprocess($node/tei:text, $edepId)
                }
            case element(tei:body) return
                element { node-name($node) } {
                    $node/@*,
                    root($node)//tei:msPart/tei:div[@type=('apparatus', 'translation')],
                    <div type="edition" xmlns="http://www.tei-c.org/ns/1.0">
                    { root($node)//tei:msPart/tei:div[@type='textpart'] }
                    </div>,
                    $node/tei:div[@type = "commentary"]
                }
            case element(tei:revisionDesc) return
                element { node-name($node) } {
                    $node/@*,
                    $node/tei:change[@type='created'],
                    <change xmlns="http://www.tei-c.org/ns/1.0" 
                        type="{if (empty($node/tei:change)) then 'created' else 'changed'}" 
                        when="{current-dateTime()}" 
                        who="{sm:id()//sm:real/sm:username/string()}"/>
                }
            case element() return
                element { node-name($node) } {
                    $node/@*,
                    api:postprocess($node/node(), $edepId)
                }
            default return
                $node
};

declare function api:clean-namespace($nodes as node()*) {
    for $node in $nodes
    return
        typeswitch($node)
            case document-node() return
                document { api:clean-namespace($node/node()) }
            case element() return
                element { QName("http://www.tei-c.org/ns/1.0", local-name($node)) } {
                    $node/@*,
                    api:clean-namespace($node/node())
                }
            default return
                $node
};

declare %private function  api:preprocessing-uuid($nodes as node()*, $uuid as xs:string){
    for $node in $nodes
    return
        typeswitch($node)
            case document-node() return
                document { api:preprocessing-uuid($node/node(), $uuid) }
            case element (tei:msPart) return 
                element {node-name($node)} {
                    attribute xml:id {$uuid},
                    $node/node()
                }
            case element (tei:facsimile) return 
                element { node-name($node) } {
                    attribute corresp {concat("#",$uuid)},
                    $node/node()
                }
            case element (tei:div) return
                if ($node/@type = "commentary") then
                    $node
                else if ($node/@type = "edition") then
                    api:preprocessing-uuid($node/node(), $uuid)
                else
                    element { node-name($node) } {
                        $node/@* except $node/@corresp,
                        attribute corresp {concat("#",$uuid)},
                        $node/node()
                    }
            case element () return 
                element { node-name($node) } { 
                    $node/@*, 
                    api:preprocessing-uuid($node/node(), $uuid)
                }
            default return
                $node
};

declare %private function  api:preprocessing-copy($nodes as node()*){
    for $node in $nodes
    return
        typeswitch($node)
            case comment () return $node
            case text() return $node
            case element (tei:msPart) return
                let $corresp := '#' || $node/@xml:id
                return
                    element { node-name($node) } {
                        $node/@*, 
                        $node/node(),
                        root($node)//tei:body//tei:div[@type="textpart"][@corresp=$corresp],
                        root($node)//tei:body//tei:div[@type="apparatus"][@corresp=$corresp],
                        root($node)//tei:body//tei:div[@type="translation"][@corresp=$corresp],
                        root($node)//tei:facsimile[@corresp=$corresp]
                    }
            case element(tei:body) return
                element { node-name($node) } {
                    $node/@*,
                    $node/tei:div[@type="commentary"]
                }
            case element(tei:facsimile) return
                ()
            case element () return  element {node-name($node)} { $node/@*, api:preprocessing-copy($node/node())}
        default return api:preprocessing-copy($node/node())
}; 