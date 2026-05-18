xquery version "3.1";

declare namespace tei = "http://www.tei-c.org/ns/1.0";

let $values :=
    collection('/db/apps/edep-data/data/taxonomy')//@corresp
    ! normalize-space(string(.))
return
    count($values[. ne '']) eq count(distinct-values($values[. ne '']))