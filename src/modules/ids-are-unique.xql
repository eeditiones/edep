xquery version "3.1";
(:
returns true when xml:ids are unique in the taxonomy
:)
let $ids := collection('/db/apps/edep-data')/data/taxonomy//@xml:id/string()
return count($ids) eq count(distinct-values($ids))