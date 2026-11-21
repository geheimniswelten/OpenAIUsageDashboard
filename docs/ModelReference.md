# Modellvergleich im Dashboard

Die Benchmarkwerte und die Preisreferenz für den Offline-Start sind mit Stand
**20.11.2026** in `Dashboard.ModelReference.pas` eingebunden. Seit 21.11.2026
aktualisiert der Windows-Sammler die Modellpreise automatisch über die öffentliche
[OpenAI-Preisseite als Markdown](https://developers.openai.com/api/docs/pricing.md).
Die Models-API liefert keine Preise; für diesen Abruf wird kein API-Key benötigt.

`Dashboard.Pricing.pas` liest ausschließlich die ausdrücklich bezeichnete
Standard-Preistabelle (kurzer Kontext, Eingabe/Ausgabe). Batch, Flex, Fast,
Ultrafast und andere Einheiten werden nicht eingemischt. Ein erfolgreicher
Abruf wird 24 Stunden lokal zwischengespeichert; nach einem Fehler wird frühestens
nach einer Stunde erneut versucht. Bei Netzwerk- oder Formatfehlern bleibt der
letzte gültige Preisstand erhalten, ohne Cache die integrierte Referenz.
Der Cache liegt unter `%LOCALAPPDATA%\OpenAIUsageDashboard\openai-pricing.json`.

Neue Modell-IDs aus der Preistabelle werden automatisch übernommen. Die jeweils
neueste Version der Astra-, Sol-, Terra- und Luna-Familie erscheint zuerst, nach
Version absteigend. Ein neuer Modellname übernimmt keinen Index eines Vorgängers;
fehlende Benchmarkwerte werden mit `–` angezeigt. Android erhält den Katalog im
Sammler-Snapshot. Ältere Sammler ohne Katalog bleiben mit der integrierten
Referenz kompatibel. Der sichtbare Preisstand und der Benchmarkstand sind getrennt.

## Darstellung und Preisbasis

Rechts neben den sechs API-Diensten erscheinen so viele vollständige Modellzeilen,
wie bei der aktuellen Bildschirmhöhe passen. Der Modellname hat die Größe der
Anfragezahlen in den Top-Modellkarten; die kleinere Datenzeile zeigt drei Spalten:
Eingabepreis, Ausgabepreis und Intelligence Index. Die Kopf- und Fußzeilen nennen Einheit, Quellen,
Benchmark-Version, Reasoning-Stufe und Datenstand. `+N` nennt die weiteren
vorhandenen Modelle, die nicht mehr hineinpassen. Ein Klick oder Tippen auf den
Preisvergleich öffnet die vollständige, scrollbare Liste mit demselben Preisstand.
Die folgende Tabelle dokumentiert die integrierte Startreferenz; der automatische
Katalog kann zusätzliche Modelle und neuere Preise enthalten.

Die beiden Kostenwerte sind die Standardpreise für **jeweils 1 Million Tokens**,
getrennt nach nicht gecachter Eingabe und Ausgabe, in USD. Es sind Tarifpreise,
keine Kostenprognose für eine Anfrage. Cache-Schreiben/-Lesen, längere Kontexte,
Fast/Flex/Batch, Werkzeuge, regionale Zuschläge und individuelle Verträge sind
in dieser kompakten Referenz nicht eingerechnet.

## Daten und Quellen

| Modell | Eingabe USD/1M | Ausgabe USD/1M | AA v5.0.1, max |
|---|---:|---:|---:|
| GPT-6.2 Astra | 8,00 | 40,00 | 62 |
| GPT-6.2 Sol | 2,00 | 10,00 | 57 |
| GPT-6 Astra | 10,00 | 50,00 | 57 |
| GPT-6.1 Sol | 2,00 | 10,00 | 55 |
| GPT-6.1 Terra | 1,00 | 5,00 | 51 |
| GPT-6 Luna | 0,10 | 0,50 | 28 |
| GPT-5.6 Sol | 4,00 | 20,00 | – |
| GPT-5.6 Terra | 2,00 | 12,00 | – |
| GPT-5.4 mini | 0,75 | 4,50 | – |
| GPT-5.3 Codex | 1,75 | 14,00 | – |
| GPT-5.4 | 2,50 | 15,00 | – |

Preise der sechs aktuellen Modelle und GPT-5.6 Sol:
[OpenAI API Pricing](https://developers.openai.com/api/docs/pricing).
Weitere Preisquellen:
[GPT-5.6 Terra](https://developers.openai.com/api/docs/models/gpt-5.6-terra),
[GPT-5.4 mini](https://developers.openai.com/api/docs/models/gpt-5.4-mini),
[GPT-5.3 Codex](https://developers.openai.com/api/docs/models/gpt-5.3-codex),
[GPT-5.4](https://developers.openai.com/api/docs/models/gpt-5.4).

Intelligence-Werte:
[Artificial Analysis, OpenAI-Vergleich](https://artificialanalysis.ai/providers/openai),
[GPT-6.2 Astra](https://artificialanalysis.ai/models/gpt-6-2-astra),
[GPT-6.2 Sol](https://artificialanalysis.ai/models/gpt-6-2-sol),
[GPT-6 Astra](https://artificialanalysis.ai/models/gpt-6-astra),
[GPT-6.1 Sol](https://artificialanalysis.ai/models/gpt-6-1-sol),
[GPT-6.1 Terra](https://artificialanalysis.ai/models/gpt-6-1-terra),
[GPT-6 Luna](https://artificialanalysis.ai/models/gpt-6-luna).
Es werden ausschließlich Ergebnisse des **Intelligence Index v5.0.1** mit
**max** Reasoning angezeigt. Der Index ist eine Punktzahl, keine Prozentangabe.
Ältere v4-Ergebnisse werden nicht eingemischt; für ein fehlendes vergleichbares
Ergebnis steht `–`. Die Liste beschreibt Referenzkonfigurationen, nicht die
Reasoning-Einstellung eurer tatsächlich ausgeführten Anfragen.

Die ChatGPT-Enterprise-Preisliste betrifft einen anderen Abrechnungsbereich und
wird für diese API-Modellübersicht nicht verwendet.

## Sortierung der API-Dienste

Die Anzeige sortiert eine Kopie der Dienste: zuerst verfügbare Dienste mit
positiver Nutzung, dann gemeldete Nullwerte, zuletzt nicht verfügbare Daten.
Innerhalb der genutzten Dienste zählt die Anfragezahl absteigend. Gleichstände
behalten ihre bisherige Reihenfolge. Bytes, Sekunden, Bilder und Tokens werden
nicht numerisch gegeneinander verglichen. Auch ein Speicherverbrauch ohne
Anfragen gilt als Nutzung.

Die ersten sechs Dienste stehen in einem Raster aus zwei Spalten und drei Zeilen.
Der Fußtext nennt ausgeblendete Dienste und gegebenenfalls deren Anzahl mit
Nutzung. Der Snapshot und seine JSON-Übertragung behalten sämtliche Dienste.

## Ergänzende Modelldaten

Veröffentlichung, Wissensstand, ausdrücklich dokumentierte Modellupdates,
Kontextgröße, Status und Abschaltdatum werden im Preislistenfenster ergänzt.
Eine Symbolspalte unterscheidet Eingabe und Ausgabe für Text, Bild, Audio und Video.
Quellen, unbekannte Werte und Cache-Verhalten beschreibt [ModelMetadata.md](ModelMetadata.md).

## Vollständige Listen

Die gesamten Bereiche **Top API-Modelle**, **Weitere API-Dienste** und
**Preisvergleich** reagieren auf Klick oder Tippen. Das Detailfenster zeigt
sämtliche Einträge der jeweiligen Snapshot-Liste. Modelle bleiben nach Tokens,
Dienste nach Nutzung sortiert; der Preisvergleich bevorzugt die aktuellen
Modellfamilien. Die Listen lassen sich per Mausrad oder Touch scrollen.
Schließen funktioniert über den Button, den abgedunkelten Hintergrund,
Escape oder Android-Zurück. Fenstergröße und sichere Bildschirmränder werden
bei Größenänderung berücksichtigt.

## Prüfung

- `tests/Pricing.Tests.dpr`: Standard-/Batch-Trennung, zusätzliche Modelle ohne
  Index, numerische Versionssortierung, ungültige und doppelte Preise,
  JSON-Übertragung und beschädigter Cache.
- `tests/Details.Tests.dpr`: Trefferbereiche bei verschiedenen Größen und
  verschobenem Ursprung, Snapshot-Kopien, fehlende Preise/Indizes und
  Kompatibilität mit älteren Sammler-Snapshots.
- Live-Abruf der öffentlichen Preisliste mit 30 Modellen erfolgreich; vorhandene
  Dashboard-, OpenAI- und Dienstesortierungs-Tests bestanden.

- `tests/ServiceOrder.Tests.dpr`: leere Listen, aktive Dienste ohne Anfragezahl,
  gemeldete Nullwerte, fehlende Daten, stabile Gleichstände, Int64-Anfragezahlen,
  unabhängige Sortierkopie und unveränderte JSON-Übertragung.
- Bestehende Dashboard- und OpenAI-Fixture-Tests bestanden.
- Win64 und Android64 gebaut; Vorschauen in 1920×1080, 1920×1200 und 1280×800
  geprüft. Live-Anzeige auf Active 10 Pro mit Android 14 geprüft.
