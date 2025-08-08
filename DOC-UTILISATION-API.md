# Descriptif de l’API d’adresse (géocodage)

Il existe 2 types de géocodage (direct et inverse) :

- Géocodage direct : permet de fournir les coordonnées géographiques d’une adresse postale, d’un lieu ou de parcelles
  cadastrales à partir d’une requête HTTP.
- Géocodage inverse : a pour but de retourner, à partir d’un ou plusieurs points géographiques indiqués en
  latitude/longitude, la ou les entités géolocalisées les plus proches correspondantes, parmi les adresses, toponymes,
  parcelles cadastrales, et/ou unités administratives.

Ces deux types de géocodage se déclinent sous la forme d'appels unitaires (HTTP), ou regroupés par fichiers (géocodage
en masse de fichiers CSV).

## Environnements et bases d’URL

- Développement: https://dev.apim.gateway.pack-solutions.gravitee.cloud/adresse
- Recette: https://recette.apim.gateway.pack-solutions.gravitee.cloud/adresse
- Production: https://apim.gateway.pack-solutions.gravitee.cloud/adresse

Dans vos appels, remplacez {BASE_URL} par l’URL de l’environnement ciblé.

---

## 1. Géocodage direct (forward)

Endpoint: GET {BASE_URL}/search

Description : recherche plein texte d’adresses/lieux et retour des entités correspondantes en GeoCodeJSON.

Paramètres usuels:

- q (string, requis) : texte recherché (ex : « 8 bd du port amiens »)
- limit (int, 1..100, défaut 5) : nombre maximum de résultats
- autocomplete (bool, défaut true) : active/désactive l’autocomplétion
- lat / latitude (float) : latitude d’un centre pour prioriser les résultats proches
- lon / lng / long / longitude (float): longitude du centre
- Filtres additionnels : selon configuration (ex : type, postcode, city, etc.), peuvent être fournis en paramètres
  additionnels pour restreindre les résultats.

Exemples d’appels curl:

- Recherche simple

```bash
curl "{BASE_URL}/search?q=8+bd+du+port+amiens"
```

- Recherche avec centrage et limite

```bash
curl "{BASE_URL}/search?q=bd+du+port&lat=49.8974&lon=2.2901&limit=3"
```

Réponse (extrait typique) :

- type: FeatureCollection
- features: liste de Feature GeoJSON, chaque élément contenant geometry (Point [lon, lat]) et properties (id, label,
  score, type, housenumber, postcode, city, context, ...)
- attribution, licence, query, center, limit, filters

Codes d’erreur :

- 400 Invalid parameter (ex: lat/long invalide)
- 413 Query too long (requête texte trop longue)

---

## 2. Géocodage inverse (reverse)

Endpoint: GET {BASE_URL}/reverse

Description : retourne les entités géolocalisées les plus proches d’un point donné (lat/lon), au format GeoCodeJSON.

Paramètres:

- lat / latitude (float, requis) : latitude du point
- lon / lng / long / longitude (float, requis) : longitude du point
- limit (int, 1..100, défaut 1) : nombre maximum de résultats proches
- Filtres additionnels : comme pour /search, selon configuration (ex: type, postcode, etc.)

Exemples d’appels curl:

- Plus proche adresse d’un point

```bash
curl "{BASE_URL}/reverse?lat=49.897446&lon=2.29009"
```

- Top 3 entités à proximité

```bash
curl "{BASE_URL}/reverse?lat=49.897446&lon=2.29009&limit=3"
```

Réponse : identique en structure à /search (FeatureCollection, features de type Point, properties).

Erreurs possibles :

- 400 Paramètres manquants/invalides.

---

## 3. Cas d’utilisation usuels

- Autocomplétion d’adresse au fil de la saisie (front-end)
    - Utiliser GET /search avec autocomplete=true (par défaut) et limit réduit (ex: 5)
    - Optionnel : fournir lat/lon si l’utilisateur a accepté la géolocalisation pour prioriser des résultats locaux

- Normalisation d’adresse côté back-end
    - Utiliser GET /search avec q la chaîne saisie utilisateur, puis stocker id/label/coordinates de la meilleure
      correspondance

- Rattachement d’un objet métier à l’adresse la plus proche
    - Utiliser GET /reverse avec lat/lon de l’objet pour obtenir l’adresse/geohash/commune la plus proche

- Filtrage par territoire/postcode/type
    - Ajouter des paramètres de filtre (ex : postcode=80000, type=street) si configurés dans l’instance

---

## 4. Géocodage en masse par API (CSV)

Deux endpoints permettent de traiter des fichiers CSV directement via l’API HTTP.

### 4.1 POST {BASE_URL}/search/csv/

- Objet: géocodage direct en masse à partir d’un CSV uploadé (multipart/form-data).
- Champs de formulaire acceptés :
    - data (fichier, requis) : le fichier CSV à traiter
    - columns (répétable) : les colonnes, dans l’ordre, à utiliser pour le géocodage ; si aucune colonne n’est fournie,
      toutes les colonnes seront utilisées
    - encoding (optionnel) : encodage du fichier (peut aussi être indiqué via le charset du mimetype), ex: 'utf-8' ou '
      iso-8859-1' (défaut 'utf-8-sig')
    - delimiter (optionnel) : délimiteur CSV (, ou ;) ; si non fourni, le serveur tente de le deviner
    - with_bom (optionnel) : si true et si l’encodage est utf-8, le CSV retourné contiendra un BOM (utile pour Excel)
    - lat et lon (optionnels) : noms des colonnes contenant latitude et longitude, pour fournir un centre de préférence
      lors du géocodage de chaque ligne
- Filtres dynamiques : tout paramètre de requête supplémentaire peut servir de mapping filtre=nomColonne (ex :
  citycode=code_insee) ; la valeur est le nom de la colonne du CSV qui porte la valeur du filtre pour chaque ligne.

Exemples:

```bash
curl -f -X POST "{BASE_URL}/search/csv/" \
  -F "columns=voie" -F "columns=ville" -F "data=@path/to/file.csv"
curl -f -X POST "{BASE_URL}/search/csv/?postcode=code%20postal" \
  -F "columns=rue" -F "data=@path/to/file.csv"
```

Réponse: text/csv (flux binaire) contenant les colonnes d’origine et les colonnes de résultats (ex: result_label,
result_score, lon, lat, …). En cas d’erreur de requête: JSON 400 (voir OpenAPI).

### 4.2 POST {BASE_URL}/reverse/csv/

- Objet: géocodage inverse en masse à partir d’un CSV uploadé (multipart/form-data).
- Champs de formulaire acceptés :
    - data (fichier, requis) : le fichier CSV à traiter ; il doit contenir des colonnes latitude (ou lat) et longitude (ou lon ou lng)
    - encoding (optionnel) : encodage du fichier (ex: 'utf-8' ou 'iso-8859-1', défaut 'utf-8-sig')
    - delimiter (optionnel) : délimiteur CSV (, ou ;) ; si non fourni, le serveur tente de le deviner
- Filtres dynamiques : tout paramètre de requête supplémentaire peut servir de mapping filtre=nomColonne. Exemple : si le
  CSV possède une colonne "code_insee" et qu’on souhaite l’utiliser pour filtrer par citycode, on passera
  citycode=code_insee dans la query string.

Exemples:

```bash
curl -f -X POST "{BASE_URL}/reverse/csv/" -F "data=@path/to/file.csv"
```

Réponse : text/csv (flux binaire) avec colonnes d’origine et colonnes d’adresse(s) la/les plus proche(s). En cas d’erreur
de requête : JSON 400.

Remarques générales :

- Préférez des fichiers encodés en UTF-8 (avec ou sans BOM selon votre usage Excel), première ligne d’en-têtes.
- Si le séparateur n’est pas standard, indiquez-le via delimiter.
- Les noms de colonnes à utiliser (columns, lat, lon ou pour les filtres dynamiques) doivent correspondre exactement aux
  en-têtes de votre CSV.

---

## 5. Référence rapide des endpoints

- GET /search — géocodage direct (q requis, options: autocomplete, limit, lat/lon, filtres…)
- GET /reverse — géocodage inverse (lat/lon requis, option: limit, filtres…)
- POST /search/csv/ — géocodage direct en masse via CSV (multipart/form-data)
- POST /reverse/csv/ — géocodage inverse en masse via CSV (multipart/form-data)
- GET /health — vérification de l’état du service

Pour le détail complet des schémas de réponse et des exemples, consulter la documentation OpenAPI.