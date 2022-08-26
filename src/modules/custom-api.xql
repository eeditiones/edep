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
    let $return :=if (not($request?parameters?id)) then
        let $thead := 
            <tr>
                <td>Id</td>
                <td>Findspot</td>
                <td>Modern</td>
                <td>Ancient</td>
                <td>Region / Province</td>
                <td>Region / Modern</td>
                <td>Country</td>
            </tr>

        let $places := 
            for $place in collection($config:places)//tei:place
            let $id := $place/@xml:id/string()
            return 
            <tr>
                <td>{$id}</td>
                <td><a href="geodata.html?id={$id}">{$place/tei:placeName[@type="findspot"]/string()}</a></td>
                <td>{$place/tei:placeName[@type="modern"]/string()}</td>
                <td>{$place/tei:placeName[@type="ancient"]/string()}</td>
                <td>{$place/tei:region[@type="province"]/string()}</td> 
                <td>{$place/tei:region[@type="modern"]/string()}</td>
                <td>{$place/tei:country/string()}</td>
            </tr>
        return <table id="places-list"> <thead> {$thead} </thead> <tbody> {$places} </tbody> </table>
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
                    api:postprocess($node/* except $node/tei:div, $edepId)
                }
            case element(tei:idno) return
                if ($node/@type = "EDEp" and exists($edepId)) then
                    element { node-name($node) } {
                        $node/@*,
                        $edepId
                    }
                else
                    $node
            case element(tei:body) return
                element { node-name($node) } {
                    $node/@*,
                    root($node)//tei:msPart/tei:div[@type=('apparatus', 'translation')],
                    <div type="edition" xmlns="http://www.tei-c.org/ns/1.0">
                    { root($node)//tei:msPart/tei:div[@type='textpart'] }
                    </div>,
                    $node/tei:div[@type = "commentary"]
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
            case element (tei:surface) return 
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
                element { node-name($node) } {
                    $node/@*, 
                    $node/node(),
                    root($node)//tei:body//tei:div[@type="textpart"],
                    root($node)//tei:body//tei:div[@type="apparatus"],
                    root($node)//tei:body//tei:div[@type="translation"]
                }
            case element(tei:body) return
                element { node-name($node) } {
                    $node/@*,
                    $node/tei:div[@type="commentary"]
                }
            case element () return  element {node-name($node)} { $node/@*, api:preprocessing-copy($node/node())}
        default return api:preprocessing-copy($node/node())
}; 