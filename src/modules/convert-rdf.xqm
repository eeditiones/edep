xquery version "3.1";

declare namespace skos="http://www.w3.org/2004/02/skos/core#";
declare namespace rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#";

declare variable $default-lang := "en";
declare variable $rdf-path := "/db/apps/edep/data";
declare variable $xml-path := "/db/apps/edep/data";

declare variable $rdfs := ("decor", "material", "objtyp", "statepreserv", "typeins", "writing");

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
    return xmldb:store($xml-path, concat ($rdf,".xml"), $save)
};

declare function local:convert-all() {
    for $rdf in $rdfs
        return local:save-xml($rdf)
};

local:convert-all()