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
import module namespace pm-config="http://www.tei-c.org/tei-simple/pm-config" at "pm-config.xql";
import module namespace tpu="http://www.tei-c.org/tei-publisher/util" at "lib/util.xql";
import module namespace errors = "http://e-editiones.org/roaster/errors";
import module namespace zotero = "http://e-editiones.org/edep/api/zotero" at "lib/api/zotero.xql";

declare namespace json="http://www.json.org";
declare namespace tei="http://www.tei-c.org/ns/1.0";
declare namespace sm="http://exist-db.org/xquery/securitymanager";
declare namespace fore = "http://teipublisher.com/ns/fore";


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
            <div class="place">
                <a href="geodata.html?{$params}">{$label}</a>
                <!--
                <pb-geolocation latitude="{$coords[1]}" longitude="{$coords[2]}" label="{$label}" emit="map" event="click">
                    { if ($place/@type != 'approximate') then attribute zoom { 9 } else () }
                    <iron-icon icon="maps:map"></iron-icon>
                </pb-geolocation>
                -->
                <paper-icon-button id="{$place/@xml:id}" class="place-id" icon="icons:content-copy"
                    title="ID kopieren"></paper-icon-button>
            </div>
    }
};
declare function api:find-spot($request as map(*)) {
    let $doc := xmldb:decode($request?parameters?id)
    let $xml:= doc($config:data-root || '/' || $doc)
    let $placeIds := $xml//tei:origPlace/@corresp
    let $places := for $placeId in $placeIds return collection($config:data-root || "/places")/id($placeId)
    return
        array {
                for $place in $places
                let $tokenized := tokenize($place/tei:location/tei:geo, ',\s*')
                return
                map {
                    "latitude":$tokenized[1],
                    "longitude":$tokenized[2],
                    "label":$place/tei:placeName[@type eq 'findspot']/string()
                }
        }
};

declare function api:load-place ($request as map(*)) {
    let $loc := concat($config:places, $request?parameters?id, ".xml")
    return if (not(doc-available($loc))) then
        error($errors:NOT_FOUND)
    else
        let $return := doc($loc)
        return try { $return } catch * { () }
};

declare function api:geopicker-places($request as map(*)) {
    let $places := collection($config:data-root || "/places")//tei:place
    return
        <data xmlns="http://www.tei-c.org/ns/1.0">
        {
            for $place in $places
            order by $place/placeName[@type="findspot"]
            return
                <place xml:id="{$place/@xml:id}">
                    {$place/tei:placeName[@type="findspot"]}
                </place>
        }
        </data>

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
    let $loc := concat($config:people, $request?parameters?id, ".xml")
    return if (not(doc-available($loc))) then
        error($errors:NOT_FOUND)
    else
        let $return := doc($loc)
        return try { $return } catch * { () }
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
    let $check-collection :=
        if(not(xmldb:collection-available($config:inscription))) then
            xmldb:create-collection("/", $config:inscription)
        else
            ()
    let $collection := $config:data-root || "/" || $request?parameters?collection
    let $id :=
        if ($request?parameters?id and $request?parameters?id != '') then
            let $store := xmldb:store($collection, concat($request?parameters?id, ".xml"), api:clean($request?body, $request?parameters?id, true()))
            return $request?body//tei:idno[@type="EDEp"]/text()
        else if ($request?body//tei:idno[@type="EDEp"]/node()) then
            let $edepId := $request?body//tei:idno[@type="EDEp"]/text()
            let $store := xmldb:store($collection, concat($edepId, ".xml"), api:clean($request?body, $edepId, true()))
            return $request?body//tei:idno[@type="EDEp"]/text()
        else
            let $ids := sort(collection($collection)//tei:idno[@type="EDEp"][not(contains(.,'-'))]/text())
            let $id-new := if (empty($ids)) then "0000001" else format-number(xs:integer(replace($ids[last()], "E", "")) + 1, "0000000")
            let $store := xmldb:store($collection, concat("E", $id-new, ".xml"), api:clean($request?body, "E" || $id-new, true()))
            return concat("E", $id-new)
    return try {
        let $preprocessing := map {
            "parameters" : map {
                "id" : $id,
                "collection": $request?parameters?collection
            }
        }
        return api:inscription-template($preprocessing)
    } catch * {
        ()
    }
};

declare function api:fragment($request as map(*)) {
    let $check-collection :=
        if(not(xmldb:collection-available($config:inscription))) then
            xmldb:create-collection("/", $config:inscription)
        else
            ()
    let $collection := $config:data-root || "/" || $request?parameters?collection

    let $parentId := $request?body/*/@xml:id
    let $log := util:log('info','***** paren id ' || $parentId)

    let $fragments :=
        string-join(
            collection($config:data-root)//*[@corresp = $parentId]//tei:idno[@type='EDEp'],
            ' '
        )
    let $fragmentCnt := fn:count(tokenize($fragments,' ')) + 1

    let $newId := $parentId || "-" || $fragmentCnt
    let $log := util:log('info','***** new fragment id ' || $newId)
    let $rewritten := api:clean($request?body, $newId, true())
    (: store the parent doc first to keep potential changes   :)
    let $store := xmldb:store($collection, concat($parentId, ".xml"), api:clean($request?body, $parentId, true()))
    (: store the new fragment doc   :)
    let $store1 := xmldb:store($collection, concat($newId, ".xml"), api:clean($rewritten, $newId, true()))

    return $rewritten
};

declare function api:add-fragments-attr(
    $tei       as element(tei:TEI),
    $fragments as xs:string
) as element(tei:TEI) {
    element { node-name($tei) } {
        (: keep all existing attributes except any old @fragments :)
        $tei/@* except $tei/@fragments,
        if( not(exists($tei/@type)) or not($tei/@type='partial')) then attribute fragments { $fragments } else (),
        $tei/node()
    }
};

declare function api:inscription-template($request as map(*)) {
    let $id         := $request?parameters?id
    let $collection := $config:data-root || "/" || $request?parameters?collection

    let $doc :=
        if ($id and $id != '') then
            let $input :=
                (
                    collection($collection)//tei:idno[@type = "EDEp"][. = $id]/ancestor::tei:TEI,
                    collection($collection)//tei:idno[. = $id]/ancestor::tei:TEI,
                    doc($collection || "/" || $id || ".xml")/tei:TEI
                )[1]

            let $fragments :=
                if(not(exists($input/@corresp)) or $input/@corresp = '') then
                    string-join(
                        collection($config:data-root)//*[@corresp = $id]/@xml:id,
                        ' '
                    )
                else 'xxx'

            return
                if (string-length($fragments) != 0 and string-length($input/@corresp) = 0) then
                    (: build a new document whose root TEI has @fragments :)
                    document {
                        api:add-fragments-attr($input, $fragments)
                    }
                else
                    (: just return the original document node :)
                    root($input)
        else
            doc($config:inscription-templ)

    return
        try {
            $doc
        } catch * {
            ()
        }
};

declare function api:get-fragments($request as map(*)) {
    let $id      := $request?parameters?id
    let $matches := collection($config:data-root)//*[@corresp = $id]
    return
        map {
            "fragments":
                for $frag in $matches/@xml:id ! string()
                order by $frag
                return $frag
        }
};

declare %private function api:clean($nodes as node()*, $edepId as xs:string?, $removeRedundant as xs:boolean?) {
    let $output := api:postprocess($nodes, $edepId) => api:clean-namespace()
    let $cleaned := if ($removeRedundant) then $pm-config:tei-transform($output, map{} , 'edep-clean.odd') else $output
    return
        $cleaned
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
                if(contains($edepId,'-')) then (
                    let $seed := substring-before($edepId,'-')
                    return
                    element { node-name($node) } {
                        $node/@* except ($node/@xml:id, $node/@corresp, $node/@type),
                        attribute xml:id { $edepId },
                        attribute corresp { $seed },
                        attribute type {'partial'},
                        api:postprocess($node/tei:teiHeader, $edepId),
                        root($node)//tei:facsimile,
                        api:postprocess($node/tei:text, $edepId)
                    }
               )else
                    element { node-name($node) } {
                        $node/@* except ($node/@xml:id),
                        attribute xml:id { $edepId },
                        api:postprocess($node/tei:teiHeader, $edepId),
                        root($node)//tei:facsimile,
                        api:postprocess($node/tei:text, $edepId)
                    }
            case element(tei:body) return
                element { node-name($node) } {
                    $node/@*,
                    root($node)//tei:div[@type=('apparatus', 'translation')],
                    $node/tei:div[@type='edition'] ,
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

declare function api:render($request as map(*)) {
    let $type := $request?parameters?type
    let $xml :=
        switch ($type)
            case "transcription" return
                $request?body//tei:div[@type="edition"]
            default return
                $request?body
    return
        $pm-config:web-transform(api:clean-namespace($xml), map { "root": $xml, "webcomponents": 7 }, $config:default-odd)
};
