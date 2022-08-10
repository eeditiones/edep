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
        let $place := for $place in collection($config:places)//@xml:id/string()
            return <a href="geodata.html?id={$place}">{doc(concat($config:places, $place , ".xml"))/tei:place/tei:placeName[@type="findspot"]/string()}</a>

        let $places := for $spot in collection($config:places)/tei:place/tei:placeName[@type="findspot"]/string()
            return upper-case(substring(replace($spot, '\{', ''), 1,1))

        let $catagory :=  for $value in distinct-values($places)
            let $count := count($places[. eq $value])
            order by $count descending
            return map { "category" : $value, "count" : $count }

        return map {"items" : $place,
                    "categories" : $catagory}
        else 
            doc(concat($config:places, $request?parameters?id, ".xml"))

    return try {
        $return
    } catch * {
        ()
    }
};

declare function api:places-add($request as map(*)) {
    let $return := if ($request?parameters?id) then
            xmldb:store($config:places, concat($request?parameters?id, ".xml"), $request?body)
        else
            let $ids := collection($config:places)//@xml:id/string()
            let $id-new := format-number(xs:integer(replace($ids[last()], "G", "")) + 1, "000000")
            let $store := xmldb:store($config:places, concat("G", $id-new, ".xml"), $request?body)
            return update insert attribute xml:id {concat("G", $id-new)} into doc(concat($config:places, "G", $id-new, ".xml"))/tei:place

    return try {
        $return
    } catch * {
        ()
    }
};
