
xquery version "3.1";

module namespace pm-config="http://www.tei-c.org/tei-simple/pm-config";

import module namespace pm-landing-web="http://www.tei-c.org/pm/models/landing/web/module" at "../transform/landing-web-module.xql";
import module namespace pm-edep-output-web="http://www.tei-c.org/pm/models/edep-output/web/module" at "../transform/edep-output-web-module.xql";
import module namespace pm-edep-output-print="http://www.tei-c.org/pm/models/edep-output/print/module" at "../transform/edep-output-print-module.xql";
import module namespace pm-edep-web="http://www.tei-c.org/pm/models/edep/web/module" at "../transform/edep-web-module.xql";
import module namespace pm-edep-print="http://www.tei-c.org/pm/models/edep/print/module" at "../transform/edep-print-module.xql";
import module namespace pm-teipublisher-web="http://www.tei-c.org/pm/models/teipublisher/web/module" at "../transform/teipublisher-web-module.xql";
import module namespace pm-teipublisher-print="http://www.tei-c.org/pm/models/teipublisher/print/module" at "../transform/teipublisher-print-module.xql";
import module namespace pm-teipublisher-epub="http://www.tei-c.org/pm/models/teipublisher/epub/module" at "../transform/teipublisher-epub-module.xql";

declare variable $pm-config:web-transform := function($xml as node()*, $parameters as map(*)?, $odd as xs:string?) {
    switch ($odd)
    case "landing.odd" return pm-landing-web:transform($xml, $parameters)
case "edep-output.odd" return pm-edep-output-web:transform($xml, $parameters)
case "edep.odd" return pm-edep-web:transform($xml, $parameters)
case "teipublisher.odd" return pm-teipublisher-web:transform($xml, $parameters)
    default return pm-edep-output-web:transform($xml, $parameters)
            

};
            


declare variable $pm-config:print-transform := function($xml as node()*, $parameters as map(*)?, $odd as xs:string?) {
    switch ($odd)
    case "edep-output.odd" return pm-edep-output-print:transform($xml, $parameters)
case "edep.odd" return pm-edep-print:transform($xml, $parameters)
case "teipublisher.odd" return pm-teipublisher-print:transform($xml, $parameters)
    default return pm-edep-output-print:transform($xml, $parameters)
            

};
            


declare variable $pm-config:epub-transform := function($xml as node()*, $parameters as map(*)?, $odd as xs:string?) {
    switch ($odd)
    case "teipublisher.odd" return pm-teipublisher-epub:transform($xml, $parameters)
    default return error(QName("http://www.tei-c.org/tei-simple/pm-config", "error"), "No default ODD found for output mode epub")
            

};
            


declare variable $pm-config:tei-transform := function($xml as node()*, $parameters as map(*)?, $odd as xs:string?) {
    error(QName("http://www.tei-c.org/tei-simple/pm-config", "error"), "No default ODD found for output mode tei")

};
            
    