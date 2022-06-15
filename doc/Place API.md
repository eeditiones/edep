# **Endpoints**

**GET: List of places** 

> /api/places

**GET: Places XML** 

> /api/places/G003588


**POST: Create new place**

> /api/places

**POST: Update place**

> /api/places/G003588


**Examples:**

Create a new Place:

```
curl -X 'POST' \
  'http://localhost:8080/exist/apps/edep/api/places' -u "tei-demo:tei"\
  -H 'accept: application/xml' -H "Content-Type: application/xml" \
  -d '<place xmlns="http://www.tei-c.org/ns/1.0" > <!-- ID automatisch vergeben --> 
   <placeName type="findspot">blub</placeName> <!-- Fundstelle -->
   <placeName type="modern">Trier</placeName> <!-- moderner Ortsname -->
   <placeName type="ancient">Augusta Treverorum</placeName> <!-- antiker Ortsname -->
   <region type="province">Belgica</region> <!-- antike Provinz -->
   <region type="modern">Rheinland-Pfalz</region> <!-- modernes Region -->
   <country>Germany</country> <!-- modernes Land -->
   <location>
      <!-- Latitude/longitude durch space getrennt -->
      <geo>49.745725844 6.6387891769</geo>
   </location>
   <ptr type="pleiades" target="https://pleiades.stoa.org/places/108894"/> <!-- Freitext -->
   <ptr type="geonames" target="https://geonames.org/2821164"/> <!-- Freitext -->
</place>'```

Update a Place:

```
curl -X 'POST' \
  'http://localhost:8080/exist/apps/edep/api/places/G003586' -u "tei-demo:tei"\
  -H 'accept: application/xml' -H "Content-Type: application/xml" \
  -d '<place xmlns="http://www.tei-c.org/ns/1.0" xml:id="G003586"> <!-- ID automatisch vergeben -->
   <placeName type="findspot">AslsoFFF23</placeName> <!-- Fundstelle -->
   <placeName type="modern">Trier</placeName> <!-- moderner Ortsname -->
   <placeName type="ancient">Augusta Treverorum</placeName> <!-- antiker Ortsname -->
   <region type="province">Belgica</region> <!-- antike Provinz -->
   <region type="modern">Rheinland-Pfalz</region> <!-- modernes Region -->
   <country>Germany</country> <!-- modernes Land -->
   <location>
      <!-- Latitude/longitude durch space getrennt -->
      <geo>49.745725844 6.6387891769</geo>
   </location>
   <ptr type="pleiades" target="https://pleiades.stoa.org/places/108894"/> <!-- Freitext -->
   <ptr type="geonames" target="https://geonames.org/2821164"/> <!-- Freitext -->
</place>'```