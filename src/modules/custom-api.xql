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

declare function api:load-place($request as map(*)) {
    let $return := doc(concat($config:places, $request?parameters?id, ".xml"))
    return try {
        $return
    } catch * {
        ()
    }
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
    let $check-collection := 
        if(not(xmldb:collection-available($config:inscription))) then 
            xmldb:create-collection("/", $config:inscription) 
        else 
            ()
    let $collection := $config:data-root || "/" || $request?parameters?collection
    let $id := 
        if ($request?parameters?id and $request?parameters?id != '') then
            let $store := xmldb:store($collection, concat($request?parameters?id, ".xml"), api:clean($request?body, (), true()))
            return $request?body//tei:idno[@type="EDEp"]/text()
        else if ($request?body//tei:idno[@type="EDEp"]/node()) then
            let $id := $request?body//tei:idno[@type="EDEp"]/text()
            let $store := xmldb:store($collection, concat($id, ".xml"), api:clean($request?body, (), true()))
            return $request?body//tei:idno[@type="EDEp"]/text()
        else
            let $ids := sort(collection($collection)//tei:idno[@type="EDEp"]/text())
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

declare function api:inscription-template($request as map(*)) {
    let $id := $request?parameters?id
    let $collection := $config:data-root || "/" || $request?parameters?collection
    let $doc :=
        if ($id and $id != '') then
            let $input := collection($collection)//tei:idno[@type="EDEp"][. = $id]/ancestor::tei:TEI
            let $merged := api:file-upload(doc($config:inscription-templ), root($input))
            return
                $merged
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
                    $node/@* except $node/@xml:id,
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
                        api:preprocessing-copy($node/node()),
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



declare %private function api:merge($input as element()?, $template as element()) {
    if ($input) then
        element { node-name($input) } {
            $input/@*,
            for $child in $template/*
            let $inputChild := $input/*[node-name(.)=node-name($child)]
            return
                if ($inputChild) then
                    api:merge($inputChild, $child)
                else
                    $child
        }
    else
        $template
};

declare function api:render($request as map(*)) {
    let $type := $request?parameters?type
    let $xml := 
        switch ($type)
            case "transcription" return
                $request?body//tei:msPart/tei:div[@type="textpart"]
            default return
                $request?body
    return
        $pm-config:web-transform(api:clean-namespace($xml), map { "root": $xml, "webcomponents": 7 }, $config:default-odd)
};

declare function api:upload($request as map(*)) {
            api:file-upload(doc($config:inscription-templ), root($request?body))
};

(: Main function to handle the upload of an epidoc file to the app: the first argument is the
template “epidoc-template.xml” and the second argument is the epidoc file to upload :)
declare function api:file-upload($mainTmpl as document-node(), $input as document-node()) as node() {
    for $node in $mainTmpl/*
    return
        api:reconstruct-tree($node, $input)
};

(: Function to look in the input file for the equivalent element to the element being processed
in the template  :)
declare %private function api:find-counterpart($nodeTemplate as element(), $input as node()) as item()* {
    (: List of candidates is created based on the name of the element and its ancestors. In addition
    we look for the values of the attribute @type to disambiguate <msPart type="main"> from <msPart type="fragment">
    and for the values of @scheme to disambiguate the <keywords> elements :)
    let $candidates := $input/descendant::*[local-name() eq $nodeTemplate/local-name()]
        [every $elName in ancestor::*/local-name()
            satisfies $elName = ($nodeTemplate/ancestor::*/local-name())][count(ancestor::*) eq count($nodeTemplate/ancestor::*)]
        [every $typeValue in $nodeTemplate/ancestor-or-self::*[@type ne '']/@type
            satisfies $typeValue = ./ancestor-or-self::*/@type]
        [every $scheme in $nodeTemplate/ancestor-or-self::*[@scheme ne '']/@scheme
            satisfies $scheme = ./ancestor-or-self::*/@scheme]
    (: To make the final selection for the equivalent element we take into consideration
    the presence of @fore:type (so far only present in <div type="fragment")> and we just
    select the first one. The other fragments will be processed through api:reconstruct-tree() 
    If the candidates are siblings, we also selected the first one.
    If at this point we have more than one candidate, throw an error with the element name :)
    let $counterpart :=    
        if ($nodeTemplate/@fore:type) then
            $candidates[1]
        else
            if (count($candidates/parent::*) eq 1) then $candidates[1]
            else
                if (count($candidates) <= 1) then
                    $candidates
                else
                    error(xs:QName("ERROR"), "ambiguous elements with element name " || $candidates[1]/name())
    return
        $counterpart
};
(: Function to merge the contents of each element after the comparison :)
declare %private function api:process-children($nodeTemplate as element(), $nodeInput as element()) as item()* {
    (: if the node from the input file only contais a text node, or mixed content, then get its children :)
    if ($nodeInput[((count(child::node()) eq 1) and (text()[string-length(replace(., '\s+', '')) ne 0])) or
    ((text()[string-length(replace(., '\s+', '')) ne 0]) and child::element())]) then
        $nodeInput/node()
    else
        (:if the node from the template is empty, get whatever its counterpart has :)
        if ($nodeTemplate/not(child::*)) then
            $nodeInput/node()
        else
            (: else process each child from the template :)
            for $node in $nodeTemplate/*
            return
                api:reconstruct-tree($node, $nodeInput/root())
};
(: Function that compares element nodes from the template with the input file :)
declare %private function api:reconstruct-tree($tmplNodes as element()*, $input as node()*) as node()* {
    for $tmpl in $tmplNodes
    let $name := $tmpl/local-name()
    let $counterpart := api:find-counterpart($tmpl, $input)
    return
    (: if we find an equivalent element, we return more than one item: on one hand, 
    the result of processing the this “counterpart” element, on the other, additional
    operations are done to handle repeateable elements :)
        if ($counterpart) then
            (: if the node it’s exactly the same in both form and input, copy the node :)
            (if (deep-equal($tmpl, $counterpart)) then
                $tmpl
            else
                (: if the number of attributes is not the same, get the missing attributes from the template:)
                if (count($counterpart/@*) ne count($tmpl/@*))
                then
                    (:let $atts := for $att in $tmpl/@*
                            return
                                if ($counterpart/@*[name() eq $att/name()]) then
                                    $counterpart/@*[name() eq $att]
                                else
                                    $att:)                    
                    let $emptyAttsNames := for $att in $tmpl/@*
                    return
                        $att[not(name() = $counterpart/@*/name())]/name()
                    let $emptyAtts := for $attName in $emptyAttsNames
                    return
                        attribute {$attName} {""}                        
                    return
                    (: we return an element with the all the attributes and then we process its contents :)
                        element {QName("http://www.tei-c.org/ns/1.0", $name)}
                        {
                            $counterpart/@* | $emptyAtts,
                            api:process-children($tmpl, $counterpart)
                        }
                else
                (: if the number of attributes is the same, copy the attributes from the input element
                and then process its children :)
                    element {QName("http://www.tei-c.org/ns/1.0", $name)} {
                        $counterpart/@*,
                        api:process-children($tmpl, $counterpart)
                    }, 
                    (: Processing of repeteable elements. There are two possible scenarios
                    Scenario 1: we have an attribute @fore:type which mean that we were only
                    processing the first “candidate”. We thus need to get its following siblings :)
                      if ($tmpl[@fore:type]) 
                        then $counterpart/following-sibling::* 
                      else 
                      (: Second scenario: there are elements in the input file, not present in the template
                      this would be the case of <msPart type='fragment'>, for example, since
                      in the template we only have <msPart type='main'>. For those cases
                      we look in the element in the input file being processed has a following-sibling
                      that it’s not present in the template :)
                      if (not($counterpart/following-sibling::*[local-name() = $tmpl/following-sibling::*/local-name()])) then
                      $counterpart/following-sibling::*[not(local-name() = $tmpl/following-sibling::*/local-name())]
                      else ()
                      )
                     else
            $tmpl
};