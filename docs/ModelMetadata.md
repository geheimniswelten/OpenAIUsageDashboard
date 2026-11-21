# Modelldaten im Preisvergleich

Seit 21.11.2026 zeigt das Listenfenster neben den Preisen zusätzliche Modellinformationen.

- **Veröffentlicht:** recherchierter öffentlicher API-Start laut OpenAI-Changelog; für die elf integrierten Referenzmodelle vorhanden. Andere Modelle bleiben bis zu einem belegten Datum bei `–`.
- **Modellupdate:** nur ein ausdrücklich veröffentlichtes Änderungsdatum; derzeit unbekannt. Weder API-Erstellungsdatum noch Wissensstand, Preisabruf oder Cache-Zeitpunkt werden dafür verwendet.
- **Wissensstand:** `knowledge cutoff` der offiziellen Modellseite.
- **Kontext:** dokumentiertes Kontextfenster in Tokens, getrennt von der maximalen Ausgabe.
- **Status:** aktiv, abgekündigt oder abgeschaltet, aus dem öffentlichen Modellkatalog, den Abschaltungsankündigungen und – falls der vorhandene Key dafür berechtigt ist – der Models-API.
- **Abschaltung:** dokumentiertes Datum aus `shutdown_date` oder der Abschaltungstabelle. Ein bekanntes API-`null` bedeutet keine angekündigte Abschaltung, ein fehlendes Feld bedeutet unbekannt. Fehlende Modelle in der API-Liste werden niemals als abgeschaltet eingestuft.
- **Inhalte:** Symbolspalte für Text, Bild, Audio und Video. IN (grün) und OUT (blau) unterscheiden Eingabe und Ausgabe; nicht unterstützte Arten sind abgedunkelt, unbekannte Fähigkeiten werden ausdrücklich als unbekannt angezeigt. Bildgenerierung als Werkzeug bedeutet nicht automatisch Bildausgabe des Modells.

API-`created` wird bewusst nicht angezeigt oder als Veröffentlichung ausgewertet. Die Models-API beschreibt verfügbare Modelle; das Erstellungsdatum ist keine zuverlässige Vorankündigung künftiger Modelle.

## Quellen und Aktualisierung

- [Models-API](https://developers.openai.com/api/reference/resources/models/methods/list)
- [OpenAI-Modellkatalog](https://developers.openai.com/api/docs/models/all.md)
- [OpenAI-Abschaltungsankündigungen](https://developers.openai.com/api/docs/deprecations.md)
- [OpenAI-Changelog](https://developers.openai.com/api/docs/changelog)
- Modellseiten unter `https://developers.openai.com/api/docs/models/<modell-id>.md`

Die elf belegten Startdatensätze und ihre Quellen sind in `ModelMetadata.sources.json` dokumentiert (Stand 21.11.2026). Sie stehen auch offline zur Verfügung. Veröffentlichungsdaten werden nicht aus Versionsnamen oder API-Erstellungsdaten geraten.

Der Windows-Sammler ergänzt Daten im vorhandenen Hintergrund-Worker, speichert den letzten gültigen Stand unter `%LOCALAPPDATA%\OpenAIUsageDashboard\model-metadata.json` und überträgt ihn im Preis-Katalog des Snapshots an Android. Öffentliche Abfragen benötigen keinen Key. Die optionale Models-API-Abfrage nutzt den bereits eingerichteten Lesezugang; eine fehlende Berechtigung beeinträchtigt weder Nutzungsdaten noch Preise.

Aktuelle Daten werden höchstens täglich erneuert; nach fehlgeschlagenen öffentlichen Modellabrufen wird frühestens nach einer Stunde erneut versucht. Der Abruf bevorzugt Lebenszyklusdaten und arbeitet Modellkarten innerhalb eines begrenzten Zeitbudgets ab. Ein Rest wird beim nächsten Sammlerzyklus ergänzt. Cache- und Abruffehler bewahren den letzten gültigen Stand. Preise, Benchmarkstand, Wissensstand und Modellupdate bleiben unterschiedliche Angaben.

## Prüfung

- `tests/ModelMetadata.Tests.dpr`: exakte Modell-IDs, kein Release aus `created`, ISO-Abschaltdaten, unbekannte/null-Werte, Abkündigung und Abschaltung, Modalinhalte unabhängig von Werkzeugen, alte JSON-Daten.
- `tests/MetadataTransport.Tests.dpr`: Übertragung der Datumsangaben, Kontextgröße, Inhalte und Abschaltungszustände über den Android-Snapshot; GET `/models` als schlüsselfreie Test-Fixture.
- Öffentlicher Live-Abruf: 30 Preis-Katalogmodelle mit technischen Angaben und Lebenszyklusstatus.
- Windows-Build, Vorschauen bei 1280×800 und 480×800 sowie Android64-Übersetzung und Linken erfolgreich. Eine neue Android-APK setzt weiterhin die fehlenden Android-JARs der lokalen Delphi-Installation voraus.
