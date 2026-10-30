# Modellvergleich im Dashboard

Referenzstand: **30.10.2026**. Die Werte sind in `Dashboard.ModelReference.pas`
eingebunden und deshalb auch offline auf Windows und Android verfügbar.
Dies ist ein geprüfter Datenstand, kein automatischer Abruf der Preis- oder
Benchmark-Webseiten. Bei einer Aktualisierung müssen Werte und Standdatum
gemeinsam geändert werden.

## Darstellung und Preisbasis

Rechts neben den sechs API-Diensten erscheinen so viele vollständige Modellzeilen,
wie bei der aktuellen Bildschirmhöhe passen. Der Modellname hat die Größe der
Anfragezahlen in den Top-Modellkarten; die kleinere Datenzeile zeigt drei Spalten:
Eingabepreis, Ausgabepreis und Intelligence Index. Die Kopf- und Fußzeilen nennen Einheit, Quellen,
Benchmark-Version, Reasoning-Stufe und Datenstand. `+N` nennt die weiteren
vorhandenen Modelle, die nicht mehr hineinpassen.

Die beiden Kostenwerte sind die Standardpreise für **jeweils 1 Million Tokens**,
getrennt nach nicht gecachter Eingabe und Ausgabe, in USD. Es sind Tarifpreise,
keine Kostenprognose für eine Anfrage. Cache-Schreiben/-Lesen, längere Kontexte,
Fast/Flex/Batch, Werkzeuge, regionale Zuschläge und individuelle Verträge sind
in dieser kompakten Referenz nicht eingerechnet.

## Daten und Quellen

| Modell | Eingabe USD/1M | Ausgabe USD/1M | AA v5.0, max |
|---|---:|---:|---:|
| GPT-6 Astra | 10,00 | 50,00 | 57 |
| GPT-6.1 Sol | 2,00 | 10,00 | 55 |
| GPT-6.1 Terra | 1,00 | 5,00 | 51 |
| GPT-6 Luna | 0,10 | 0,50 | 28 |
| GPT-5.6 Sol | 4,00 | 20,00 | – |
| GPT-5.6 Terra | 2,00 | 12,00 | – |
| GPT-5.4 mini | 0,75 | 4,50 | – |
| GPT-5.3 Codex | 1,75 | 14,00 | – |
| GPT-5.4 | 2,50 | 15,00 | – |

Preise der vier aktuellen Modelle und GPT-5.6 Sol:
[OpenAI API Pricing](https://developers.openai.com/api/docs/pricing).
Weitere Preisquellen:
[GPT-5.6 Terra](https://developers.openai.com/api/docs/models/gpt-5.6-terra),
[GPT-5.4 mini](https://developers.openai.com/api/docs/models/gpt-5.4-mini),
[GPT-5.3 Codex](https://developers.openai.com/api/docs/models/gpt-5.3-codex),
[GPT-5.4](https://developers.openai.com/api/docs/models/gpt-5.4).

Intelligence-Werte:
[Artificial Analysis, OpenAI-Vergleich](https://artificialanalysis.ai/providers/openai),
[GPT-6.1 Terra](https://artificialanalysis.ai/models/releases/gpt-6-1-terra),
[GPT-6 Luna](https://artificialanalysis.ai/models/releases/gpt-6-luna).
Es werden ausschließlich Ergebnisse des **Intelligence Index v5.0** mit
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

## Prüfung

- `tests/ServiceOrder.Tests.dpr`: leere Listen, aktive Dienste ohne Anfragezahl,
  gemeldete Nullwerte, fehlende Daten, stabile Gleichstände, Int64-Anfragezahlen,
  unabhängige Sortierkopie und unveränderte JSON-Übertragung.
- Bestehende Dashboard- und OpenAI-Fixture-Tests bestanden.
- Win64 und Android64 gebaut; Vorschauen in 1920×1080, 1920×1200 und 1280×800
  geprüft. Live-Anzeige auf Active 10 Pro mit Android 14 geprüft.
