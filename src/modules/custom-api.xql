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
declare namespace json="http://www.json.org";


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
    let $parameters :=
         <output:serialization-parameters
    xmlns:output="http://www.w3.org/2010/xslt-xquery-serialization">
             <output:method value="json"/>
             <output:media-type value="text/javascript"/>
         </output:serialization-parameters>
         
    return try {
         serialize(<root>{doc("/db/apps/edep/data/writing.xml")/items/item}</root>, $parameters) 
    } catch * {
        ()
    }
};

declare function api:typeins($request as map(*)) {
    let $parameters :=
         <output:serialization-parameters
    xmlns:output="http://www.w3.org/2010/xslt-xquery-serialization">
             <output:method value="json"/>
             <output:media-type value="text/javascript"/>
         </output:serialization-parameters>
         
    return try {
         doc("/db/apps/edep/data/typeins.json")
    } catch * {
        ()
    }
};

declare function api:statepreserv($request as map(*)) {
    let $parameters :=
         <output:serialization-parameters
    xmlns:output="http://www.w3.org/2010/xslt-xquery-serialization">
             <output:method value="json"/>
             <output:media-type value="text/javascript"/>
         </output:serialization-parameters>
         
    return try {
         serialize(<root>{doc("/db/apps/edep/data/statepreserv.xml")/items/item}</root>, $parameters) 
    } catch * {
        ()
    }
};

declare function api:objtyp($request as map(*)) {
    let $parameters :=
         <output:serialization-parameters
    xmlns:output="http://www.w3.org/2010/xslt-xquery-serialization">
             <output:method value="json"/>
             <output:media-type value="text/javascript"/>
         </output:serialization-parameters>
         
    return try {
         serialize(<root>{doc("/db/apps/edep/data/objtyp.xml")/items/item}</root>, $parameters) 
    } catch * {
        ()
    }
};

declare function api:decor($request as map(*)) {
    let $parameters :=
         <output:serialization-parameters
    xmlns:output="http://www.w3.org/2010/xslt-xquery-serialization">
             <output:method value="json"/>
             <output:media-type value="text/javascript"/>
         </output:serialization-parameters>
         
    return try {
         serialize(<root>{doc("/db/apps/edep/data/decor.xml")/items/item}</root>, $parameters) 
    } catch * {
        ()
    }
};

declare function api:material($request as map(*)) {
    let $parameters :=
         <output:serialization-parameters
    xmlns:output="http://www.w3.org/2010/xslt-xquery-serialization">
             <output:method value="json"/>
             <output:media-type value="text/javascript"/>
         </output:serialization-parameters>
         
    return try {
         serialize(<root>{doc("/db/apps/edep/data/material.xml")/items/item}</root>, $parameters) 
    } catch * {
        ()
    }
};