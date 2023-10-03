
xquery version "3.1";

module namespace pm-config="http://www.tei-c.org/tei-simple/pm-config";

import module namespace pm-edep-web="http://www.tei-c.org/pm/models/edep/web/module" at "../transform/edep-web-module.xql";
import module namespace pm-edep-print="http://www.tei-c.org/pm/models/edep/print/module" at "../transform/edep-print-module.xql";
import module namespace pm-tei_simplePrint-web="http://www.tei-c.org/pm/models/tei_simplePrint/web/module" at "../transform/tei_simplePrint-web-module.xql";
import module namespace pm-tei_simplePrint-print="http://www.tei-c.org/pm/models/tei_simplePrint/print/module" at "../transform/tei_simplePrint-print-module.xql";
import module namespace pm-tei_simplePrint-latex="http://www.tei-c.org/pm/models/tei_simplePrint/latex/module" at "../transform/tei_simplePrint-latex-module.xql";
import module namespace pm-tei_simplePrint-epub="http://www.tei-c.org/pm/models/tei_simplePrint/epub/module" at "../transform/tei_simplePrint-epub-module.xql";
import module namespace pm-tei_simplePrint-fo="http://www.tei-c.org/pm/models/tei_simplePrint/fo/module" at "../transform/tei_simplePrint-fo-module.xql";
import module namespace pm-docx-tei="http://www.tei-c.org/pm/models/docx/tei/module" at "../transform/docx-tei-module.xql";
import module namespace pm-edep-clean-tei="http://www.tei-c.org/pm/models/edep-clean/tei/module" at "../transform/edep-clean-tei-module.xql";
import module namespace pm-teipublisher-web="http://www.tei-c.org/pm/models/teipublisher/web/module" at "../transform/teipublisher-web-module.xql";
import module namespace pm-teipublisher-print="http://www.tei-c.org/pm/models/teipublisher/print/module" at "../transform/teipublisher-print-module.xql";
import module namespace pm-teipublisher-latex="http://www.tei-c.org/pm/models/teipublisher/latex/module" at "../transform/teipublisher-latex-module.xql";
import module namespace pm-teipublisher-epub="http://www.tei-c.org/pm/models/teipublisher/epub/module" at "../transform/teipublisher-epub-module.xql";
import module namespace pm-teipublisher-fo="http://www.tei-c.org/pm/models/teipublisher/fo/module" at "../transform/teipublisher-fo-module.xql";
import module namespace pm-teipublisher_odds-web="http://www.tei-c.org/pm/models/teipublisher_odds/web/module" at "../transform/teipublisher_odds-web-module.xql";
import module namespace pm-teipublisher_odds-print="http://www.tei-c.org/pm/models/teipublisher_odds/print/module" at "../transform/teipublisher_odds-print-module.xql";
import module namespace pm-teipublisher_odds-latex="http://www.tei-c.org/pm/models/teipublisher_odds/latex/module" at "../transform/teipublisher_odds-latex-module.xql";
import module namespace pm-teipublisher_odds-epub="http://www.tei-c.org/pm/models/teipublisher_odds/epub/module" at "../transform/teipublisher_odds-epub-module.xql";
import module namespace pm-teipublisher_odds-fo="http://www.tei-c.org/pm/models/teipublisher_odds/fo/module" at "../transform/teipublisher_odds-fo-module.xql";

declare variable $pm-config:web-transform := function($xml as node()*, $parameters as map(*)?, $odd as xs:string?) {
    switch ($odd)
    case "edep.odd" return pm-edep-web:transform($xml, $parameters)
case "tei_simplePrint.odd" return pm-tei_simplePrint-web:transform($xml, $parameters)
case "teipublisher.odd" return pm-teipublisher-web:transform($xml, $parameters)
case "teipublisher_odds.odd" return pm-teipublisher_odds-web:transform($xml, $parameters)
    default return pm-edep-web:transform($xml, $parameters)
            
    
};
            


declare variable $pm-config:print-transform := function($xml as node()*, $parameters as map(*)?, $odd as xs:string?) {
    switch ($odd)
    case "edep.odd" return pm-edep-print:transform($xml, $parameters)
case "tei_simplePrint.odd" return pm-tei_simplePrint-print:transform($xml, $parameters)
case "teipublisher.odd" return pm-teipublisher-print:transform($xml, $parameters)
case "teipublisher_odds.odd" return pm-teipublisher_odds-print:transform($xml, $parameters)
    default return pm-edep-print:transform($xml, $parameters)
            
    
};
            


declare variable $pm-config:latex-transform := function($xml as node()*, $parameters as map(*)?, $odd as xs:string?) {
    switch ($odd)
    case "tei_simplePrint.odd" return pm-tei_simplePrint-latex:transform($xml, $parameters)
case "teipublisher.odd" return pm-teipublisher-latex:transform($xml, $parameters)
case "teipublisher_odds.odd" return pm-teipublisher_odds-latex:transform($xml, $parameters)
    default return error(QName("http://www.tei-c.org/tei-simple/pm-config", "error"), "No default ODD found for output mode latex")
            
    
};
            


declare variable $pm-config:epub-transform := function($xml as node()*, $parameters as map(*)?, $odd as xs:string?) {
    switch ($odd)
    case "tei_simplePrint.odd" return pm-tei_simplePrint-epub:transform($xml, $parameters)
case "teipublisher.odd" return pm-teipublisher-epub:transform($xml, $parameters)
case "teipublisher_odds.odd" return pm-teipublisher_odds-epub:transform($xml, $parameters)
    default return error(QName("http://www.tei-c.org/tei-simple/pm-config", "error"), "No default ODD found for output mode epub")
            
    
};
            


declare variable $pm-config:fo-transform := function($xml as node()*, $parameters as map(*)?, $odd as xs:string?) {
    switch ($odd)
    case "tei_simplePrint.odd" return pm-tei_simplePrint-fo:transform($xml, $parameters)
case "teipublisher.odd" return pm-teipublisher-fo:transform($xml, $parameters)
case "teipublisher_odds.odd" return pm-teipublisher_odds-fo:transform($xml, $parameters)
    default return error(QName("http://www.tei-c.org/tei-simple/pm-config", "error"), "No default ODD found for output mode fo")
            
    
};
            


declare variable $pm-config:tei-transform := function($xml as node()*, $parameters as map(*)?, $odd as xs:string?) {
    switch ($odd)
    case "docx.odd" return pm-docx-tei:transform($xml, $parameters)
    case "edep-clean.odd" return pm-edep-clean-tei:transform($xml, $parameters)
    default return error(QName("http://www.tei-c.org/tei-simple/pm-config", "error"), "No default ODD found for output mode tei")
            
    
};
            
    