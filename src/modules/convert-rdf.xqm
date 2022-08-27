xquery version "3.1";

declare namespace skos="http://www.w3.org/2004/02/skos/core#";
declare namespace rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#";

declare variable $default-lang := "en";
declare variable $rdf-path := "/db/apps/edep/data";
declare variable $xml-path := "/db/apps/edep/data";

declare variable $rdfs := ("decor", "material", "objtyp", "statepreserv", "typeins", "writing");
declare variable $material := ("material");

declare function local:convert-material() {
    let $concepts :=
        array {
            for $concept in doc('/db/apps/edep/data/material.rdf')/rdf:RDF/skos:Concept
            let $label := string-join(local:material-label($concept), ' / ')
                => replace("[\n\t\s]{2,}", " ")
            order by $label
            return
                map {
                    "name": $label,
                    "value": $concept/@rdf:about/string()
                }
        }
    let $serialized := serialize($concepts, map { "method": "json", "indent": true() })
    return
        xmldb:store("/db/apps/edep/data", 'material.json', $serialized, 'application/json')
};

declare function local:material-label($concept as element()?) {
    if (exists($concept)) then (
        if ($concept/skos:broader) then
            local:material-label(root($concept)//skos:Concept[@rdf:about = $concept/skos:broader/@rdf:resource])
        else
            (),
        (
            $concept/skos:altLabel[@xml:lang='de']/string(),
            $concept/skos:prefLabel/string()
        )[1]
    ) else
        ()
};

declare function local:convert-rdf($rdf as xs:string) {

    let $rdf := doc(concat($rdf-path, "/", $rdf,".rdf"))/rdf:RDF/skos:Concept
    let $list := for $item in $rdf
        let $label := if (exists($item/skos:prefLabel)) then
                $item/skos:prefLabel/text()
            else 
                $item/skos:altLabel[@xml:lang=$default-lang]/text()
        return <item value="{$item/@rdf:about/string()}" name="{$label}"/> 
        
    return $list
};  

declare function local:save-xml($rdf as xs:string) {
    let $save := <items>{local:convert-rdf($rdf)}</items>
    return xmldb:store($xml-path, concat ($rdf,"-gen.xml"), $save)
};

declare function local:convert-all() {
    for $rdf in $rdfs
        return local:save-xml($rdf)
};

(: local:convert-all() :)
local:convert-material()