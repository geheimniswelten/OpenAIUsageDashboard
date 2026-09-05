# OpenAI Usage Dashboard (Delphi FMX)

Native FireMonkey-Anwendung für **Win64 und Android64**. Das Ziel wird im selben
RAD-Studio-Projekt über den Plattform-Selektor umgeschaltet; PowerShell und ein
Browser werden zur Laufzeit nicht benötigt.

## Funktionsumfang

- OpenAI-Organisationskosten der letzten 30 Tage sowie Kosten/Anfragen/Tokens heute
  und in den letzten sieben Tagen
- bis zu fünf Top-Modelle in einem kompakten 2×3-Kartenraster sowie weitere
  API-Dienste (Bilder, Embeddings, Web-/Dateisuche, Audio, Code Interpreter,
  Vector Stores und Moderation)
- Modellnamen etwa 25 %, Anfragen 80 % und Tokens 50 % größer als ursprünglich;
  die Zusatzdienste verwenden dieselbe Caption-/Wert-/Detail-Typografie wie die
  Codex-Kennzahlen
- Ausgabenlimit mit Prozentbalken und Limitlinie im Kostendiagramm
- 14 Tagesbalken; ausschließlich der Hintergrund von Wochenenden ist abgesetzt
- kumulierter Ist-Verbrauch und kalenderbasierte Trendberechnung; der noch
  unvollständige heutige Tag wird aus der Prognosesteigung ausgeschlossen
- vier kompakte Prognosepunkte für +7, +14, +21 und +28 Tage; der prognostizierte
  Betrag steht oben, ein Abrechnungswechsel als zweite Zeile darunter
- sichtbarer Neustart von Ist-/Trendlinie am konfigurierten Abrechnungstag
- lokale Codex-App-Server-Daten unter Windows: Rate-Limits, Reset-Zeitpunkte,
  Reset-Credits und Tokenstatistiken
- vergrößerte Kleinbeschriftungen für bessere Lesbarkeit auf Wand- und
  Tablet-Displays
- Wachhalten Montag bis Freitag von 10:00 bis 18:00 Uhr Ortszeit
- Vollbild- und Mehrmonitorbetrieb

## Projekt öffnen und Target wechseln

1. `OpenAIUsageDashboard.dproj` in RAD Studio öffnen.
2. Im Projektmanager unter **Target Platforms** entweder `Win64` oder `Android64`
   aktivieren.
3. `Debug` oder `Release` wählen und normal bauen/deployen.

Das Projekt wurde mit RAD Studio 37/Delphi 13 erstellt. Für Android müssen SDK,
NDK, Gerät und Signierung in RAD Studio eingerichtet sein. Das Manifest fordert
Internetzugriff an, verwendet die beiden Landscape-Ausrichtungen und erlaubt für
den hausinternen HTTP-Sammler Klartextverkehr.

## Windows einrichten

Beim ersten Start öffnet sich die Einstellungskarte. Die Beschriftungen sind für
den dunklen Hintergrund fest auf helle Schrift gesetzt; Eingabefelder behalten
ihren hellen FMX-Standardstil mit dunkler Schrift. Edit- und Button-Schrift ist
für Touchbedienung um 80 % vergrößert. Später öffnet ein Klick oder Fingertipp auf
den Statusblock oben rechts (`Aktuell` / `Stand`) die Karte; `F2` bleibt als
Tastaturkürzel erhalten. Über **App beenden** lässt sich die Anwendung auch auf
einem Touch-Gerät vollständig schließen.

1. Einen OpenAI **Organization Admin Key** eingeben.
2. Falls das gewünschte Periodenlimit nicht über die API verfügbar ist, das Limit
   in USD manuell eintragen.
3. Abrechnungstag (`1` bis `28`) und den Dashboard-Monitor in der beschrifteten
   Auswahlliste setzen. **Automatisch** wählt bevorzugt den ersten nicht primären
   Monitor; Auflösung und Hauptbildschirm sind direkt in der Liste erkennbar.
4. Für einen Android-Viewer einen ausreichend langen, zufälligen Viewer-Token
   setzen. Ohne Token lauscht der Snapshot-Server nur auf `127.0.0.1`; mit Token
   auf allen lokalen Adressen, standardmäßig TCP-Port `8787`.

Der Viewer-Token ist ein selbst gewähltes gemeinsames Kennwort für den
Statistikabruf. Bei reinem Windows-Betrieb kann das Feld leer bleiben. Bei einem
Android-Viewer auf beiden Geräten denselben Wert eintragen, beispielsweise eine
mit dem Passwortmanager erzeugte Zeichenfolge mit 32 Zeichen. Es ist kein
OpenAI-API-Key und wird nicht von OpenAI vergeben.

Der Admin-Key wird nicht in der INI gespeichert. Die Speicherung erfolgt in der
vereinbarten Kette:

`API-Key → AES-256-GCM mit Programmschlüssel → CryptProtectData (aktueller Windows-Nutzer) → CredWrite`

Credential-Target: `OpenAIUsageDashboard/AdminKey/v1`. Temporäre Klartext- und
Schlüssel-Bytepuffer werden nach Gebrauch überschrieben. Der eingebettete
Programmschlüssel ist eine zusätzliche interne Schicht; die eigentliche
Nutzerbindung liefert DPAPI.

Delphi 13 projiziert das WinRT-OUT-Array von `CopyToByteArray` unter Win64 nicht
ABI-sicher. Die Anwendung liest die AES-GCM-Puffer deshalb über das native
`IBufferByteAccess`-Interface aus; der geliehene Zeiger wird sofort kopiert und
nicht freigegeben. Damit wird insbesondere der frühere Schreibzugriff auf Adresse
`0x000C` beim 12-Byte-Nonce vermieden.

Für Codex muss die lokale Codex-CLI installiert und angemeldet sein. Die App sucht
auch die mit der Desktop-App ausgelieferte CLI unter
`%LOCALAPPDATA%\OpenAI\Codex\bin\<Version>\codex.exe`, sodass ein Start aus dem
Explorer ohne Codex im PATH funktioniert. Sie startet `codex app-server` unsichtbar und
hält den Prozess für spätere Aktualisierungen offen. Ein Codex-Fehler verhindert
nicht die Anzeige der OpenAI-API-Daten.

Fehlende Codex-Werte erscheinen als `–`; ein tatsächlich gemeldeter Nullwert
bleibt `0`. Gesamttokens und Tagesstatistiken können unabhängig verfügbar sein.
Die konkrete Fehlermeldung steht unten in den Einstellungen (bei Bedarf scrollen).
Der Header unterscheidet eine teilweise von einer vollständig fehlgeschlagenen
Codex-Abfrage.

API-Kosten, Tagesbuckets und Abrechnungsgrenzen werden konsistent in UTC
ausgewertet. Liefert die API für heute noch keinen Kostenbetrag, steht dort
`–` mit entsprechendem Hinweis. Kosten können später als Anfragen eintreffen.
Codex-Tokenstatistiken verwenden weiterhin den lokalen Kalendertag.

## Android mit Windows-Sammler

Android enthält absichtlich **keinen OpenAI-Admin-Key**. In der Android-App werden
eingetragen:

- Sammler: `http://<LAN-IP-des-Windows-PCs>:8787/snapshot`
- derselbe Viewer-Token wie unter Windows

Gegebenenfalls muss TCP 8787 in der Windows-Firewall für das private Netz
freigegeben werden. Der Snapshot enthält ausschließlich aufbereitete Statistik,
nicht den Admin-Key. HTTP ist für ein vertrauenswürdiges internes LAN gedacht; für
andere Netze sollte davor ein HTTPS-Reverse-Proxy eingesetzt werden.

Bei einem eigenständigen USB-C-/HDMI-Anzeigegerät verwendet Android eine
`Presentation`: Das Dashboard erscheint auf dem externen Display, während das
Tablet schwarz bleibt. Ein Tippen beziehungsweise Eingabe auf dem Tablet blendet
die App-Steuerung ein; nach der eingestellten Inaktivitätszeit (Standard zehn
Minuten) wird sie wieder schwarz. Bei reinem Display-Mirroring kann Android die
beiden Bildschirme technisch nicht unterschiedlich darstellen.

Die Bildschirmauswahl bietet auf Android **Automatisch**, den integrierten
Tablet-Bildschirm und jedes aktuell angeschlossene Presentation-Display mit Name
und Auflösung an. Bei mehreren externen Displays erhält nur das ausgewählte das
Dashboard; alle übrigen bleiben schwarz. Ist ein ausdrücklich gewähltes externes
Display nicht angeschlossen, fällt die Anzeige sicher auf das Tablet zurück.

Die App kann auf Android nur ihre eigene Activity schwärzen beziehungsweise
anzeigen; fremde Apps oder die Android-Systemoberfläche werden nicht global
überlagert.

## Mehrmonitor- und Wachhalteverhalten

- Windows: Das Dashboard bleibt sichtbar; alle anderen Monitore erhalten schwarze,
  rahmenlose Topmost-Fenster. Globale Maus-, Tastatur- oder Touch-Eingabe deckt sie
  auf, nach zehn Minuten ohne Eingabe werden sie erneut schwarz. Monitoranzahl und
  -geometrie werden laufend geprüft.
- Windows: `SetThreadExecutionState(ES_CONTINUOUS | ES_DISPLAY_REQUIRED |
  ES_SYSTEM_REQUIRED)` wird im Zeitfenster regelmäßig erneuert und außerhalb mit
  `ES_CONTINUOUS` zurückgenommen.
- Android: `FLAG_KEEP_SCREEN_ON` wird im selben Zeitfenster dynamisch auf Activity
  und Presentation gesetzt beziehungsweise entfernt.

## Einstellungen

Unkritische Einstellungen liegen pro Nutzer in
`Dokumente\OpenAIUsageDashboard.ini`. Dort können bei Bedarf auch diese Werte
angepasst werden:

```ini
[Network]
ListenPort=8787

[Usage]
RefreshSeconds=30
UseDemoWhenUnavailable=1

[Display]
KeepAwakeStartHour=10
KeepAwakeEndHour=18
OtherDisplayIdleMinutes=10
```

## Verifikation

- Win64-Anwendung kompiliert; Dashboard- und Einstellungsansicht wurden als
  Vorschauen gerendert und visuell geprüft.
- Alle gemeinsam genutzten Units einschließlich Android-Presentation-Code wurden
  mit dem Android64-Compiler übersetzt und zur ARM64-Shared-Library gelinkt.
- `tests/Dashboard.Tests.dpr` prüft Prognose (inklusive Ausschluss des heutigen
  Tages), JSON-Roundtrip und authentifizierten Snapshot-Transport.
- `tests/OpenAI.Tests.dpr` prüft ohne API-Aufruf UTC-Tages-/Monatsgrenzen,
  Anfragezeiträume, leere oder fehlende Kostenbuckets gegenüber gemeldeten Nullen
  sowie Kalenderdaten beim Übertragen auf einen Viewer.
- `tests/Codex.Tests.dpr` prüft ohne Serveraufruf Teilantworten, fehlende bzw.
  null-Werte, Tagesaggregation und den Rückgriff auf die Legacy-Limitantwort.
- `tests/Secrets.Tests.dpr` prüft ohne Credential-Schreibzugriff den
  AES-256-GCM-Rundlauf, den sicheren WinRT-Pufferzugriff sowie die Ablehnung eines
  manipulierten Authentifizierungstags. Der optionale DPAPI-Teil benötigt einen
  normalen interaktiven Windows-Benutzerkontext.
- `tests/Codex.Smoke.dpr` ist ein optionaler Live-Test gegen eine lokal angemeldete
  Codex-CLI; `--discover` prüft nur die Programmsuche. Diese findet hier die
  Desktop-CLI auch bei reduziertem PATH. Der angemeldete Liveabruf konnte in der
  Codex-Sandbox wegen Schreibbeschränkungen des Benutzerprofils nicht geprüft werden.

Eine Android-APK wird anschließend von RAD Studio mit der lokal konfigurierten
SDK-/NDK-Toolchain und Signierung erzeugt.
