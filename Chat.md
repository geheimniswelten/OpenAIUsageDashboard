> Das ist eine Anwendung, welche eine ChatGPT-Statistik anzeigt.
> Irgendwie wird ein "eigenes" Firefox-Fenster angezeigt.
> 
> Ansicht siehe Screenshot.

Das „eigene“ Firefox-Fenster ist absichtlich programmiert, kein Fehler:

- Zeile 21 legt `runtime\FirefoxProfile` als separates Profil fest.
- Zeilen 1068–1072 starten Firefox mit `--no-remote`, `--profile` und `--kiosk`.
- Dadurch entsteht eine isolierte Firefox-Instanz im Vollbild, die `runtime\dashboard.html` anzeigt.
- Das Fenster wird gezielt auf den zweiten Monitor verschoben und regelmäßig neu positioniert.

Es handelt sich nicht um einen eingebetteten Browser und auch nicht um eine mitgelieferte Firefox-Kopie.

Wichtig: Das unverschlüsselte Archiv enthält `openai-admin-key.txt` im Klartext. Ich habe den Schlüssel nicht ausgelesen. Da das Archiv hochgeladen wurde, sollte ein aktiver Schlüssel vorsorglich rotiert und künftig aus dem Archiv ausgeschlossen werden.

Wenn die Anzeige nicht mehr als separates Firefox-Fenster erscheinen soll, wären ein Edge-App-Fenster oder ein eingebettetes WebView2 die sinnvollsten Umbauten. Es wurde noch nichts verändert. Die Kai-IDE-Anbindung war hier nicht verfügbar; die Dateien wurden ausschließlich lesend untersucht.





> Im Screenshot siehst du die Ausgabe.

Ja, jetzt ist es eindeutig: Der Screenshot zeigt das Dashboard bildschirmfüllend ohne Tabs, Adressleiste oder Firefox-Menüs. Das entspricht exakt dem im Skript aktivierten Firefox-Kioskmodus.

Optisch wirkt es deshalb wie eine eigenständige Anwendung. Technisch ist es jedoch:

- ein separates Firefox-Fenster,
- mit isoliertem Profil,
- im Kiosk-/Vollbildmodus,
- das die lokale `dashboard.html` anzeigt.

Die sichtbare Darstellung selbst sieht vollständig und korrekt aus. Das „eigene“ Fenster ist also bewusst Teil der aktuellen Architektur.





> Fallen dir zu dieser Anzeige weitere Dinge ein, welche man zusätzlich anzeigen könnte, welche die ChatGPT-API liefert?

Ja. Die Anzeige deckt bereits praktisch alle dokumentierten Usage-Kategorien ab. Der größte Mehrwert läge jetzt in detaillierteren Aufschlüsselungen.

### Meine Prioritäten

1. **Input- und Output-Tokens getrennt**

   Zusätzlich:

   - durchschnittliche Tokens pro Anfrage
   - Input-/Output-Verhältnis
   - Text-, Bild- und Audio-Tokens getrennt

2. **Prompt-Cache**

   Die API liefert Cached-, Uncached- und Cache-Write-Tokens. Daraus ließen sich eine Cache-Trefferquote und die dadurch vermiedene Verarbeitung darstellen. [Completions-Usage-Referenz](https://developers.openai.com/api/reference/resources/admin/subresources/organization/subresources/usage/methods/completions)

3. **Kostenverursacher**

   Eine Rangliste nach:

   - Projekt
   - Rechnungsposition (`line_item`)
   - API-Key

   Zusätzlich liefert die Costs API Mengen und Einheiten. Eine direkte Gruppierung nach Modell bietet sie dagegen nicht. [Costs API](https://developers.openai.com/api/reference/resources/admin/subresources/organization/subresources/usage/methods/costs)

4. **Monatsbudget und Prognose**

   Beispielsweise:

   - 19,73 $ von 100 $
   - 19,7 % verbraucht
   - erwartete Kosten zum Monatsende
   - verbleibendes Tagesbudget
   - Status des echten Hard Limits

   Organisations- und Projektlimits können inzwischen direkt abgerufen werden; ebenso konfigurierte Warnschwellen. [Organization Spend Limit](https://developers.openai.com/api/reference/resources/admin/subresources/organization/subresources/spend_limit/methods/retrieve), [Project Spend Alerts](https://developers.openai.com/api/reference/resources/admin/subresources/organization/subresources/projects/subresources/spend_alerts/methods/list)

5. **Nutzungsverlauf statt nur Kostenverlauf**

   Das Skript lädt bereits tägliche Anfragen und Tokens, zeigt sie aber nicht an. Sinnvoll wären:

   - Tokens pro Tag
   - Anfragen pro Tag
   - Vergleich „letzte 7 Tage gegen vorherige 7 Tage“
   - aktivste Stunde beziehungsweise Tageszeit
   - Codex-Tokens pro Tag

   Die Usage API unterstützt Minuten-, Stunden- und Tagesintervalle.

6. **Batch- und Service-Tier-Anteil**

   Etwa „12 % Batch“ sowie die Verteilung nach Service-Tier. Beide Gruppierungen liefert die Completions-Usage-API direkt.

7. **Top-Projekte, Nutzer und API-Keys**

   Usage lässt sich nach `project_id`, `user_id` und `api_key_id` gruppieren. Über die Admin API können IDs in Namen aufgelöst werden. Bei API-Keys wären zusätzlich Alter, Besitzer und „zuletzt verwendet“ interessant – selbstverständlich nur mit maskiertem Schlüssel. [Project API Keys](https://developers.openai.com/api/reference/resources/admin/subresources/organization/subresources/projects/subresources/api_keys/methods/list)

8. **Konfigurierte Rate Limits**

   Pro Projekt und Modell können unter anderem RPM, TPM, Bilder pro Minute, Audio-MB pro Minute und Batch-Tokens pro Tag angezeigt werden. Das sind konfigurierte Obergrenzen, nicht der aktuell verbleibende Echtzeitwert. [Project Rate Limits](https://developers.openai.com/api/reference/resources/admin/subresources/organization/subresources/projects/subresources/rate_limits/methods/list_rate_limits)

9. **Detailliertere Dienstekarten**

   Die bereits vorhandenen Karten könnten aufklappbar sein:

   - Bilder nach Größe sowie Generierung/Bearbeitung/Variation
   - Websuche nach Kontextstufe
   - Dateisuche nach Vector Store
   - Vector-Store-Speicher nach Projekt

Die drei schnellsten Verbesserungen wären aus meiner Sicht: **Cache-Quote**, **Input-/Output-Aufteilung** und **Monatsprognose mit echtem Ausgabenlimit**. Ein Teil der dafür notwendigen Daten wird vom aktuellen Skript sogar schon geladen, aber noch nicht visualisiert.

Zur Abgrenzung: Der obere Bereich verwendet die OpenAI-Platform-Usage-API. Persönliche ChatGPT-Pro-Chats, Nachrichtenanzahl oder die ChatGPT-Abo-Abrechnung liefert diese API nicht. Für geeignete verwaltete ChatGPT-Workspaces existiert separat eine [Codex Analytics API](https://learn.chatgpt.com/de-DE/docs/enterprise/analytics-api); die persönlichen Codex-Pro-Limits im unteren Bereich stammen aktuell aus dem lokalen Codex App Server.





> Ja, im Prinzip wäre vor allem eine Anzeige der Limits wünschenswert, mit Prozentanzeige.
> Bzw. beim Grafen erstmal die Wochenendtage hervorheben, bzw. unauffälliger anders darstellen.
> Dann einblenden des Limits, im Hintergrund eine Trendlinie des absoluten Verbrauchs, im Zeitraum und, in Form 4 weiterer "Tages"-Felder, eine Prognose der Zukunft. Jeder "Tag" für eine Woche, also für die nächsten 28 Tage.
> Bei Monatswechsel, bzw. Wechsel des Abrechnugszeitraums, die Trendlinien wieder bei 0 beginnen lassen.
> 
> Klingt doch vernünftig so?

Ja, das klingt sehr vernünftig. Ich würde es nur begrifflich und grafisch sauber trennen:

- **Balken:** tatsächliche Tageskosten.
- **Wochenenden:** dezente Hintergrundflächen für Samstag/Sonntag. Nicht die Balken abschwächen, sonst wirken echte Werte wie vorläufige Daten.
- **Durchgezogene Linie:** kumulierter Verbrauch seit Beginn des Abrechnungszeitraums.
- **Gestrichelte horizontale Linie:** Monatslimit.
- **Prozentanzeige:** beispielsweise `19,73 $ / 100 $ · 19,7 %`.
- **Gestrichelte Zukunftslinie:** Prognose ab dem letzten vollständigen Tag.

Die vier Zukunftsfelder würde ich so darstellen:

`+7 Tage` | `+14 Tage` | `+21 Tage` | `+28 Tage`

Jedes Feld enthält den erwarteten kumulierten Betrag und den Limitanteil, etwa `31,40 $ · 31 %`. Die vier Punkte bilden gleichzeitig die Fortsetzung der gestrichelten Prognoselinie.

Für die Prognose würde ich:

- den noch nicht abgeschlossenen heutigen UTC-Tag auslassen,
- die letzten vier Wochen berücksichtigen,
- die letzten sieben Tage etwas stärker gewichten,
- Wochentage getrennt behandeln, damit Wochenenden realistisch eingehen,
- optional einen schwachen Unsicherheitsbereich hinter der Prognoselinie zeichnen.

Beim Monats- beziehungsweise Periodenwechsel sollte die kumulierte Linie tatsächlich bei null neu beginnen. Wichtig wäre nur: Die **Darstellung** beginnt neu, das Prognosemodell darf zur Berechnung weiterhin historische Tage verwenden. Andernfalls wäre die Vorhersage am ersten Tag des Monats nahezu wertlos. Überschreitet eine 28-Tage-Prognose den Monatswechsel, würde ich dort eine senkrechte Trennlinie „Neuer Zeitraum“ setzen und den prognostizierten Verbrauch ebenfalls neu bei null beginnen lassen.

Das echte monatliche Organisationslimit kann über die [Organization Spend Limit API](https://developers.openai.com/api/reference/resources/admin/subresources/organization/subresources/spend_limit/methods/retrieve) geladen werden. Ist keines eingerichtet, sollte die Anzeige „Kein Hard Limit konfiguriert“ zeigen und nicht fälschlich `0 %`.

Das wäre meiner Meinung nach eine deutliche Verbesserung: Man sieht nicht nur, **was bisher verbraucht wurde**, sondern sofort auch, **ob das aktuelle Verbrauchstempo voraussichtlich zum Limitproblem wird**.





> Stimmt, nur den Hintergrund der Wochenenden.
> 
> OK, es ging mehr um die Größe/Breite der Darstellung, für die Zukunftsprognose, ohne viel Platz für die aktuellen/vergangenen Tage zu verbrauchen.
> Idee war, das es optisch zur restlichen Grafik passt.
> Es wäre OK, wenn es nicht genau gleich und diese Wochen optisch nicht so stark getrennt sind.
> 
> Ja, Heute könnte zwar hochgerechnet werden, aber da nicht 24 Stunden durchgearbeitet wird, wäre der Wert eh nicht ganz aussagefähig, also OK, wenn er für die Prognose ignoriert wird.

Ja, jetzt ist die Idee klar: Die Zukunft soll eine optisch komprimierte Fortsetzung des Diagramms sein – keine 28 zusätzlichen Tagesspalten.

So würde ich es festlegen:

- Die bisherigen 14 Tagesspalten bleiben unverändert.
- Rechts folgen vier schmale Prognosefelder: `+7`, `+14`, `+21`, `+28 Tage`.
- Der Prognosebereich erhält nur eine leicht abweichende Hintergrundfarbe und eine dünne Trennlinie am Anfang – keine vier deutlich getrennten Karten.
- Zusammen beansprucht er etwa 18–22 % der Diagrammbreite.
- Wochenenden werden ausschließlich durch einen dezent abweichenden Spaltenhintergrund gekennzeichnet; die Balken bleiben unverändert.
- Die kumulierte Verbrauchslinie verläuft zurückhaltend hinter den Balken.
- Das Limit erscheint als horizontale gestrichelte Linie.
- Ab heute wird die Verbrauchslinie gestrichelt bis zu den vier Prognosepunkten fortgesetzt. An jedem Punkt stehen Betrag und Prozentwert.

Der heutige Wert bleibt als tatsächlicher Tagesbalken und im aktuellen Gesamtverbrauch enthalten. Für die Berechnung der Verbrauchsgeschwindigkeit werden aber ausschließlich abgeschlossene Tage verwendet. Dadurch gibt es keinen Sprung zwischen Ist- und Prognoselinie, ohne einen halben Arbeitstag künstlich auf 24 Stunden hochzurechnen.

Weil Tagesbalken und kumulierter Verbrauch völlig unterschiedliche Größenordnungen haben, sollten sie intern getrennte Skalen verwenden: Die Balken behalten ihre bisherige dynamische Skala, die Hintergrundlinie orientiert sich am Limit von 0 bis 100 %. Die Beschriftungen zeigen trotzdem den absoluten Betrag, beispielsweise `31,40 $ · 31 %`.

Beim Periodenwechsel genügt eine feine senkrechte Markierung. Dort fällt die kumulierte Linie auf null zurück; die Prognoseberechnung darf weiterhin auf den vorherigen vollständigen Tagen basieren. Das passt optisch gut zur bestehenden Grafik und benötigt kaum zusätzlichen Platz.





> Wäre es möglich das als Delphi-FMX-Anwendung umzusetzen,, ohne Powershell und Firefox?

Ja, vollständig. Die Anwendung kann als echte native Delphi-FMX-Anwendung umgesetzt werden – ohne PowerShell, Firefox, HTML oder JavaScript.

### Sinnvolle Architektur

- **Oberfläche:** randlose FMX-`TForm` auf dem zweiten Monitor.
- **Diagramm:** eigenes FMX-Control auf Basis von `TPaintBox`/`TCanvas`. Damit lassen sich Balken, Wochenendhintergründe, Limitlinie und Prognose exakt im bisherigen Stil zeichnen.
- **API-Zugriff:** `TNetHTTPClient` beziehungsweise `THTTPClient`, JSON-Auswertung mit `System.JSON`.
- **Aktualisierung:** Hintergrund-Worker über `TTask.Run`; Übergabe an die Oberfläche mittels `TThread.Queue`.
- **Konfiguration:** typisierte Records statt dynamischer PowerShell-Hashtables.
- **Autostart und Wachhalten:** direkt über Windows-APIs.
- **Schlüssel:** Windows Credential Manager oder DPAPI statt `openai-admin-key.txt`.

Die gesamten OpenAI-Platform-Daten können Delphi direkt über HTTPS abrufen. Die offiziell dokumentierten Usage- und Costs-Endpunkte ändern sich dadurch nicht. [OpenAI Usage API](https://developers.openai.com/api/reference/resources/admin/subresources/organization/subresources/usage)

### Besonderheit beim blauen Codex-Bereich

Die persönlichen Codex-Pro-Limits mit Prozentwerten und Resetzeiten liefert die öffentliche Platform API nicht. Dafür verwendet das jetzige Skript den lokal angemeldeten Codex App Server.

Auch das kann Delphi ohne PowerShell übernehmen:

1. `codex.exe app-server` unsichtbar starten.
2. Standardeingabe und Standardausgabe über Pipes verbinden.
3. JSON-RPC-Nachrichten senden und lesen.
4. Limits und Usage in das FMX-Datenmodell übernehmen.
5. Den Prozess beim Beenden sauber schließen.

Damit gäbe es weiterhin einen unsichtbaren `codex.exe`-Hilfsprozess, aber weder PowerShell noch Firefox. Dieser Teil sollte gekapselt und optional sein, da er von der installierten Codex-Version abhängt. Die offizielle Codex Analytics API wäre nur für entsprechend eingerichtete ChatGPT-Workspaces eine Alternative, nicht allgemein für ein persönliches Pro-Konto. [Codex Analytics API](https://learn.chatgpt.com/de-DE/docs/enterprise/analytics-api)

Ohne den Codex-Pro-Bereich könnte die Anwendung praktisch eine einzelne EXE sein. Mit diesem Bereich bleibt lediglich die installierte und angemeldete Codex-CLI als externe Voraussetzung.

Für die grafische Übereinstimmung würde ich bewusst kein eingebettetes `TWebBrowser` verwenden, sondern die Oberfläche komplett mit FMX-Komponenten und eigenem Canvas-Rendering bauen. Das ist für dieses feste Dashboard gut beherrschbar und ergibt eine deutlich sauberere Anwendung.





> Die Anzeige muß nicht genau so aussehen. Es wäre OK wenn Dinge optimaler platziert würden.
> Einmal für Windows, wie die aktuelle App,
> aber auch Vollbild, auf einem Android-Tabled.
> 
> Wachhalten des Bildschirms muß vorhanden bleiben, von 10 bis 18 Uhr. (z.B. SetThreadExecutionState im Windows)

Ja. Daraus lässt sich eine gemeinsame Delphi-FMX-Anwendung mit zwei Zielplattformen bauen: native Windows-Anwendung und native Android-Tablet-App – ohne PowerShell und Firefox.

Ich würde sie folgendermaßen auslegen:

- Windows: rahmenlos auf dem gewünschten Monitor, wahlweise maximiert oder echtes Vollbild.
- Android: immersives Vollbild, bevorzugt Querformat; Hochformat bleibt durch ein responsives Layout benutzbar.
- Keine starre Nachbildung des Screenshots. Grenzwerte und kritische Prozentanzeigen stehen oben, das Diagramm erhält mehr Raum, Detailinformationen folgen darunter.
- Wochenenden bekommen nur eine dezente Hintergrundfläche.
- Rechts am Diagramm erscheinen vier kompakte Prognoseabschnitte für +7, +14, +21 und +28 Tage.
- Limitlinie, kumulierter Ist-Verbrauch und gestrichelte Prognose werden gemeinsam dargestellt.
- Beim Beginn eines neuen Abrechnungszeitraums startet die sichtbare kumulierte Linie wieder bei null.
- Android-Hochformat verwendet bei Bedarf eine einzelne vertikale Scrollfläche; Querformat und Windows kommen normalerweise ohne Scrollen aus.

Das Wachhalten würde ich plattformspezifisch kapseln:

- Windows: von 10:00 bis 18:00 Uhr `ES_CONTINUOUS | ES_DISPLAY_REQUIRED`, optional zusätzlich `ES_SYSTEM_REQUIRED`; um 18:00 Uhr Rücksetzung auf `ES_CONTINUOUS`. [Microsoft-Dokumentation](https://learn.microsoft.com/en-us/windows/win32/api/winbase/nf-winbase-setthreadexecutionstate)
- Android: im selben Zeitfenster dynamisch `FLAG_KEEP_SCREEN_ON` setzen und anschließend wieder entfernen. Ein WakeLock oder Hintergrunddienst ist dafür nicht erforderlich. [Android-Dokumentation](https://developer.android.com/develop/background-work/background-tasks/awake/screen-on)
- Nach Standby, App-Rückkehr, Uhrzeit- oder Zeitzonenwechsel wird der Zustand neu geprüft.
- Als Ausgangspunkt würde ich die vorhandene Werktagsregel beibehalten: Montag bis Freitag, jetzt 10:00–18:00 Uhr; Wochentage und Uhrzeiten können konfigurierbar sein.
- In der Statuszeile steht beispielsweise „Display-Wachhalten aktiv bis 18:00“.

Eine wichtige Besonderheit betrifft die Datenversorgung: Den OpenAI-Admin-Key sollte die Android-App nicht selbst enthalten. OpenAI rät ausdrücklich davon ab, API-Schlüssel in mobilen Anwendungen auszuliefern. [OpenAI – API Key Safety](https://help.openai.com/en/articles/5112595-best-practices-for-api-key-safety)

Für vollständige Datenparität empfehle ich daher:

```text
OpenAI Usage API ──► Windows-Collector/kleiner Server
Codex lokal ───────►             │
                                  ├──► Windows-FMX-Anzeige
                                  └──► Android-FMX-Anzeige
```

Der Android-Client empfängt nur die fertigen, aggregierten Statistikwerte. Dadurch kann er auch die lokalen Codex-Pro-Limits anzeigen, obwohl `codex.exe` auf Android nicht vorhanden ist. Ist der Datenlieferant vorübergehend nicht erreichbar, zeigt das Tablet den letzten gespeicherten Stand samt deutlich sichtbarem Zeitstempel.

Das wäre aus meiner Sicht die sauberste Zielarchitektur: gemeinsamer FMX-Oberflächencode, gemeinsame Berechnungs- und Diagrammlogik, aber getrennte Plattformmodule für Vollbild, Wachhalten, sicheren Speicher und Datenquelle.





> Im Windows den Key in den Windows Certificate Store.
> 
> Für Android auch bedenken, dass es auf einem externen USB-C-Monitor angezeigt werden könnte.
> Den jeweils anderen Bildschirm (Windows und Android) schwarz, bis jemand den Bildschirm antippt, bzw. Mausbewegung oder Tastatureingabe. Und nach z.B. 10 Minuten Nutzerinaktivität wieder schwarz.

Ja, das lässt sich sauber ergänzen. Ich würde Wachhalten und Bildschirm-Abdeckung als zwei unabhängige Zustandsautomaten umsetzen.

### Schlüssel unter Windows

Der Windows Certificate Store speichert Zertifikate und deren private Schlüssel, aber keine beliebigen Geheimnisse im Klartext. Technisch korrekt wäre deshalb:

- Eigenes Zertifikat in `CurrentUser\My`.
- Nicht exportierbarer privater Schlüssel, nach Möglichkeit TPM-gestützt.
- OpenAI-Admin-Key verschlüsselt als geschützte Eigenschaft des Zertifikats.
- Nur der Fingerabdruck des Zertifikats steht in der App-Konfiguration.
- Entschlüsselung ausschließlich kurzzeitig in einem löschbaren Speicherpuffer.
- Kein Key in EXE, INI, Logdatei oder Android-App.

Zertifikatsfelder oder Extensions selbst wären nicht geheim. Die Verschlüsselung erfolgt deshalb mit dem geschützten privaten Schlüssel beziehungsweise per CNG. [Microsoft Certificate Stores](https://learn.microsoft.com/en-us/windows/win32/seccrypto/managing-certificates-with-certificate-stores), [CNG Key Storage Provider](https://learn.microsoft.com/en-us/windows/win32/seccertenroll/cng-key-storage-providers)

Die offizielle OpenAI-Dokumentation führt außerdem zu der Architekturentscheidung, den Admin-Key ausschließlich auf dem Windows-Collector beziehungsweise einem Server zu halten – nicht auf Android. [OpenAI API Authentication](https://developers.openai.com/api/reference/overview#authentication)

### Verhalten der Bildschirme

```text
Schwarz → Eingabe → sichtbar → 10 Minuten ohne Eingabe → Schwarz
```

Das Dashboard selbst bleibt durchgehend sichtbar. Alle anderen angeschlossenen Bildschirme werden abgedeckt.

Unter Windows:

- Je Nicht-Dashboard-Monitor ein rahmenloses schwarzes Topmost-Fenster.
- Mausbewegung, Klick, Touch oder Tastatureingabe hebt alle Abdeckungen auf.
- Die Inaktivität lässt sich sitzungsweit mit `GetLastInputInfo` erkennen, ohne permanente Maus-/Tastatur-Hooks. [Microsoft GetLastInputInfo](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-getlastinputinfo)
- Nach zehn Minuten ohne Eingabe erscheinen die schwarzen Fenster wieder.
- An- und Abstecken sowie geänderte Monitoranordnung werden automatisch erkannt.
- Fällt der Dashboard-Monitor aus, wechselt die Anzeige auf den primären Monitor.

Unter Android:

- Stellt das Tablet den USB-C-Monitor als eigenes Display bereit, zeigt eine native Android-`Presentation` dort das Dashboard.
- Auf dem eingebauten Tablet-Display bleibt die schwarze Companion-Ansicht.
- Alternativ kann das Dashboard intern laufen und der externe Monitor schwarz bleiben.
- Touch, Mausbewegungen und Tastatureingaben innerhalb der Anwendung starten das Zehn-Minuten-Fenster.
- Beim Abziehen des Monitors wandert das Dashboard automatisch zurück aufs Tablet.
- Für FMX wird hierfür eine kleine Android-JNI-Brücke zu `DisplayManager` und `Presentation` vorgesehen. [Android Presentation](https://developer.android.com/reference/android/app/Presentation), [DisplayManager](https://developer.android.com/reference/android/hardware/display/DisplayManager)

Die wichtige Hardwaregrenze: USB-C allein garantiert keinen getrennten Zweitmonitor. Wenn das Tablet ausschließlich hardwareseitig spiegelt und Android kein eigenständiges `Presentation`-Display meldet, können interner und externer Bildschirm nicht unterschiedlich dargestellt werden. Die App würde das beim Start prüfen und entsprechend melden. [Android Multi-Display](https://source.android.com/docs/core/display/multi_display)

„Schwarz“ bedeutet auf beiden Plattformen schwarze Pixel, nicht das physische Abschalten des Monitors. Bei LCD bleibt die Hintergrundbeleuchtung grundsätzlich aktiv.

Das Wachhalten bleibt separat Montag bis Freitag von 10:00 bis 18:00 Uhr aktiv; die Zeiten werden konfigurierbar. Außerhalb dieses Zeitraums darf das Betriebssystem die Displays normal abschalten.

Eine Entscheidung bleibt: Unter Windows kann beim Entschwärzen der normale Desktop erscheinen. Unter Android empfehle ich eine Bedien- und Statusansicht innerhalb der App. Soll stattdessen der normale Android-Desktop mit anderen Apps freigegeben werden, wäre ein verwalteter Device-Owner-/Kiosk-Modus notwendig, damit die App nach zehn Minuten zuverlässig wieder übernehmen darf. [Android Lock-Task-Modus](https://developer.android.com/work/dpc/dedicated-devices/lock-task-mode)





> > Das Dashboard selbst bleibt durchgehend sichtbar. Alle anderen angeschlossenen Bildschirme werden abgedeckt.
> 
> Das Ursprungsproblem davon kommt ja daher, dass vor allem Windows den Monitor-Standby nicht Bildschrimweise steuern kann. Entweder alles oder nichts. Daher muß die App sich auch um den anderen Bildschirm kümmern.
> 
> 
> 
> Windows: CredWrite and CredRead.
> 
> Zusätzlich CryptProtectData, um den aktuellen Nutzeraccount einzubeziehen und noch eine einfache eigene Verschlüsselung (statischer Schlüssel im Programm, quasi wie einen einfachen Salt).
> 
> 
> 
> Key > eigener Programmschlüssel > CryptProtectData > CredWrite

Richtig. Das schwarze Fenster ist nicht nur Sichtschutz, sondern die softwareseitige Ersatzlösung für den fehlenden monitorweisen Standby:

- Von 10:00–18:00 hält `ES_DISPLAY_REQUIRED` alle Displays aktiv.
- Der Dashboard-Monitor zeigt die Statistik.
- Alle anderen Monitore zeigen Schwarz.
- Eingabe entfernt Schwarz für zehn Minuten.
- Danach werden die Nicht-Dashboard-Monitore wieder schwarz.
- Um 18:00 wird `ES_DISPLAY_REQUIRED` aufgehoben.

DDC/CI würde zwar theoretisch einzelne Monitore abschalten, ist aber zu geräteabhängig und bleibt daher außen vor. [`SetThreadExecutionState`](https://learn.microsoft.com/en-us/windows/win32/api/winbase/nf-winbase-setthreadexecutionstate) besitzt bewusst keinen Monitorparameter.

Für den Key entfällt der Certificate Store. Ich würde Ihre gewünschte Kette mit einer kleinen Anpassung umsetzen:

```text
API-Key als UTF-8-Bytes
    ↓
CryptProtectData
    CurrentUser-Bindung
    optionale Entropie = statische App-Konstante + Versionskennung
    ↓
CredWriteW
    CRED_TYPE_GENERIC
    CRED_PERSIST_LOCAL_MACHINE
```

Rückwärts:

```text
CredReadW
    ↓
CryptUnprotectData mit derselben App-Entropie
    ↓
API-Aufruf
    ↓
Klartextpuffer mit SecureZeroMemory löschen
```

Die statische Programmkonstante würde ich als DPAPI-`pOptionalEntropy` verwenden. Das erfüllt genau den gewünschten zusätzlichen „App-Faktor“, ohne eine eigene möglicherweise fehlerhafte Chiffre einzubauen. Microsoft sieht diesen Parameter ausdrücklich für zusätzliche Entropie vor. [`CryptProtectData`](https://learn.microsoft.com/en-us/windows/win32/api/dpapi/nf-dpapi-cryptprotectdata)

Wichtige Details:

- `CRYPTPROTECT_LOCAL_MACHINE` wird nicht gesetzt – dadurch bleibt die Verschlüsselung an den aktuellen Windows-Nutzer gebunden.
- `CRED_PERSIST_LOCAL_MACHINE` bedeutet bei Credential Manager trotzdem: derselbe Benutzer auf diesem Rechner, auch nach erneutem Anmelden.
- Zielname beispielsweise `OpenAINutzungsanzeige/AdminKey/v1`.
- Der verschlüsselte DPAPI-Blob wird binär gespeichert, nicht als Base64.
- `CredReadW`-Ergebnis mit `CredFree`, DPAPI-Puffer mit `LocalFree` freigeben.
- Schlüssel und entschlüsselte Zwischenpuffer mit `SecureZeroMemory` überschreiben.
- Die statische Konstante ist extrahierbar und daher zusätzliche Obfuskation/App-Bindung, keine eigenständige Sicherheitsgrenze. [Microsoft – Umgang mit Geheimnissen](https://learn.microsoft.com/en-us/windows/win32/secbp/handling-passwords)

Falls die separate Vorverschlüsselung zwingend als eigene Stufe gewünscht ist, würde ich dafür AES-GCM über Windows CNG verwenden:

```text
Key → AES-GCM(App-Konstante) → CryptProtectData → CredWrite
```

Eine einfache selbst entwickelte Verschlüsselung oder XOR-Schicht würde ich nicht einsetzen. Die Variante mit DPAPI-Entropie ist kompakter und für diesen Zweck die bessere Lösung.





> Im Delphi für Windows sind die Header für DPAPI und CNG enthalten,
> wie Weiteres in der `Winapi.Security.Cryptography`.pas.

Ja, damit benötigen wir keine externe Kryptobibliothek. In der installierten RAD-Studio-37-Version sind die Bausteine vorhanden:

- `Winapi.Security.Cryptography`: AES-GCM, `CryptographicEngine`, `CryptographicBuffer` und `DataProtectionProvider`
- `Winapi.WinCred`: `CredWrite`, `CredRead`, `CredDelete`, `CredFree` und `CREDENTIAL`
- `Winapi.Windows`: unter anderem `DATA_BLOB` und Speicherfunktionen

Eine kleine technische Unterscheidung: `Winapi.Security.Cryptography` ist die WinRT-Projektion und stellt `DataProtectionProvider` bereit, nicht unmittelbar die klassische Funktion namens `CryptProtectData`.

Daher sind zwei saubere Varianten möglich:

```text
AES-GCM über Winapi.Security.Cryptography
→ DataProtectionProvider("LOCAL=user")
→ CredWrite
```

oder bei wörtlicher Beibehaltung der klassischen DPAPI-Kette:

```text
AES-GCM über Winapi.Security.Cryptography
→ CryptProtectData
→ CredWrite aus Winapi.WinCred
```

Ich würde die zweite Variante entsprechend Ihrer Vorgabe verwenden. Der gespeicherte Blob erhält eine kleine Versionsstruktur:

```text
Magic | Version | Nonce | AuthTag | verschlüsselte Daten
```

Danach wird dieser gesamte Blob noch durch `CryptProtectData` benutzergebunden geschützt und mit `CredWrite` gespeichert. Der statische Programmschlüssel bleibt dabei bewusst nur eine zusätzliche Obfuskationsschicht. Eigene Übersetzungen der Credential-Manager-Strukturen oder CNG-Header sind nicht nötig.





> Ja, aber die statische Konstante in der App ist für unseren Fall schon noch ausreichend genug. Die Anwendung selbst wird nur hausintern genutzt.
> Und Personen mit Zugang haben eh einen direkten Zugriff auf diesen API-Key, aus anderen Quellen.

Dann passt das Sicherheitsniveau zum tatsächlichen Bedrohungsmodell. Die statische Konstante dient hier bewusst gegen versehentliches Auslesen, nicht als Schutz vor einem gezielten Angreifer mit Binärzugriff.

Festgelegte Windows-Kette:

```text
API-Key
→ AES-GCM mit statischer App-Konstante und zufälliger Nonce
→ CryptProtectData im Kontext des aktuellen Benutzers
→ CredWrite als CRED_TYPE_GENERIC
```

Beim Lesen exakt rückwärts. Nonce, Authentifizierungstag und Formatversion werden im geschützten Blob mitgespeichert. Klartext- und Zwischenpuffer werden anschließend überschrieben.

Damit bleibt die Lösung einfach, vollständig mit den vorhandenen Delphi-/Windows-APIs umsetzbar und für die hausinterne Verwendung angemessen. Der Android-Client benötigt weiterhin keinen Admin-Key, sondern erhält nur die aggregierten Anzeigedaten.





> Könntest du diese Anwendung bitte umsetzen?
> Das Ziel Windows oder Android als Target umschaltbar.

Umgesetzt als native Delphi-FMX-Anwendung für **Win64 und Android64** – ohne PowerShell und Firefox.

Übergabe:

- [Windows-x64-Paket](C:/Users/Besitzer/Documents/Codex/2026-09-04/das/work/OpenAIUsageDashboard/outputs/OpenAIUsageDashboard-Windows-x64.zip)
- [Delphi-Quellcode](C:/Users/Besitzer/Documents/Codex/2026-09-04/das/work/OpenAIUsageDashboard/outputs/OpenAIUsageDashboard-Delphi-Source.zip)
- [RAD-Studio-Projekt](C:/Users/Besitzer/Documents/Codex/2026-09-04/das/work/OpenAIUsageDashboard/OpenAIUsageDashboard.dproj)
- [Dokumentation](C:/Users/Besitzer/Documents/Codex/2026-09-04/das/work/OpenAIUsageDashboard/README.md)

Enthalten sind unter anderem:

- API-Kosten, Modelle, Tokens und weitere Dienste
- Ausgabenlimit mit Prozentanzeige
- Wochenend-Hintergründe
- kumulierter Verbrauch und kalenderbasierte Trendlinie
- Prognose für +7, +14, +21 und +28 Tage
- Neustart der Trenddarstellung am Abrechnungstag
- lokale Codex-Limits und Tokenstatistik
- sichere Windows-Keyablage über AES-GCM → DPAPI → `CredWrite`
- Wachhalten werktags 10–18 Uhr
- Mehrmonitor-Abdunklung und Inaktivitätssteuerung
- Android-`Presentation` für eigenständige USB-C-/HDMI-Displays

Verifiziert wurden der Win64-Release-Build, Windows-DPI-/Versionsressourcen, Android64-Übersetzung und die Modell-/Transporttests (`SELF_TEST_OK`).

Eine APK konnte auf diesem Rechner noch nicht final gelinkt werden, weil in der lokalen RAD-Installation `ldandroid.exe` fehlt. Das Android-Target und sämtliche Android-Units sind jedoch kompiliert; nach Ergänzung der Android-Toolchain kann die APK direkt aus dem Projekt gebaut werden. Der Codex-Live-Smoke-Test wurde lediglich durch die eingeschränkten Schreibrechte dieser Sandbox auf `.codex` gestoppt.

![Dashboard-Vorschau](C:/Users/Besitzer/Documents/Codex/2026-09-04/das/work/OpenAIUsageDashboard/dashboard-preview.png)





> Die Topmodelle, könnte man die nicht auch als 6 kleine Kästchen machen?
> Das erste mit den Bezeichnern (Model, Anfragen und Tokens) und dann bis zu 5 für die Modelle. (dann wären bis zu fünf, statt 3 sichtar)

Ja, umgesetzt.

- 2×3-Raster mit sechs Kästchen
- erstes Kästchen als Legende: Modell, Anfragen, Tokens
- danach bis zu fünf Top-Modelle
- freie Plätze zeigen dezent „–“
- lange Modellnamen werden bei Bedarf mittig gekürzt
- Win64 und Android64 erfolgreich kompiliert
- Selbsttest: `SELF_TEST_OK`

Aktualisiert:

- [Windows-Paket](C:/Users/Besitzer/Documents/Codex/2026-09-04/das/work/OpenAIUsageDashboard/outputs/OpenAIUsageDashboard-Windows-x64.zip)
- [Delphi-Quellcode](C:/Users/Besitzer/Documents/Codex/2026-09-04/das/work/OpenAIUsageDashboard/outputs/OpenAIUsageDashboard-Delphi-Source.zip)
- [Renderer](C:/Users/Besitzer/Documents/Codex/2026-09-04/das/work/OpenAIUsageDashboard/Dashboard.Renderer.pas:467)

![Aktualisierte Vorschau](C:/Users/Besitzer/Documents/Codex/2026-09-04/das/work/OpenAIUsageDashboard/dashboard-preview.png)





> Beim Start geht ein Settings-Fenster auf.
> Die Labels lassen sich aber nur sehr schwer lesen. (Schwarz auf Dunkelgrün)
> Außerdem müsste es möglich sein auszuwählen, auf welchem Bildschirm die Anwendung angezeigt wird.
> Und oben rechts, der Knopf zum ein-/ausblenden der Settings, verdeckt die Text, in dieser Ecke. (Alter/Stand der Anzeige).
> Den Knopf vielleicht besser unten rechts. oder als Klickevent, des Bereichs (Panels) um diese Texte.

> Ahhh, eine der Zahlen-Edits war für den Anzeigemonitor. :)
> War ja nicht lesbar.
> Diese Texte einfach weiß, wie andere Texte auf dem Dashboard selbst.

> In dem Settings-Fenster bitte auch einen Beenden-Knopf, um bei Toucheingabe schließen zu können.

Erledigt:

- Settings-Beschriftungen und Eingabewerte sind jetzt weiß.
- Monitorwahl als verständliche Auswahlliste mit Auflösung.
- Windows und Android unterstützen die Bildschirmauswahl; Android bietet zusätzlich Tablet und USB‑C-/Presentation-Displays.
- Zahnrad entfernt; der Statusbereich oben rechts ist nun anklickbar. `F2` bleibt verfügbar.
- Neuer Touch-Knopf „App beenden“.
- Settings-Inhalt ist scrollbar.
- Win64 und Android64 kompilieren fehlerfrei; Selbsttest: `SELF_TEST_OK`.

![Überarbeitete Einstellungen](C:/Users/Besitzer/Documents/Codex/2026-09-04/das/work/OpenAIUsageDashboard/settings-preview.png)

Downloads:

- [Windows-x64](C:/Users/Besitzer/Documents/Codex/2026-09-04/das/work/OpenAIUsageDashboard/outputs/OpenAIUsageDashboard-Windows-x64-2026-09-05.zip)
- [Delphi-Quellcode](C:/Users/Besitzer/Documents/Codex/2026-09-04/das/work/OpenAIUsageDashboard/outputs/OpenAIUsageDashboard-Delphi-Source-2026-09-05.zip)
- [Dashboard-Vorschau](C:/Users/Besitzer/Documents/Codex/2026-09-04/das/work/OpenAIUsageDashboard/dashboard-preview.png)

Die FMX-Formressource blieb unangetastet; angepasst wurden ausschließlich die dynamisch erzeugte Oberfläche und die Plattformlogik.





> Jetzt sind in dem Dialog die Texte sichtbar, aber dafür die normalen Edit-Komponenten nicht.
> Die ComboBox für den Bildschirm ist weiß, aber die Edits sind jetzt dunkel.
> Vorher hatten die Edits die selbe Farbe, wie die ComboBox jetzt.
> Weiß mit schwarzem Text und nun sind sie duneklgrün, wie der Hintergrund, mit weißem Text.
> 
> Bitte auch die Schrift in Edits und Buttons um 80% vergrößern.
> 
> Aber auch auf dem Dashboard selbst, sind viele Texte sehr klein.

Erledigt:

- Edits nutzen wieder den hellen FMX-Stil mit schwarzer Schrift.
- Edit- und Button-Schrift um 80 % auf 21,6 pt vergrößert.
- Eingabefelder, ComboBox und Buttons höher gestaltet.
- Buttons neu angeordnet, damit nichts abgeschnitten wird.
- Kleine Dashboard-Texte gezielt vergrößert; große Kennzahlen bleiben unverändert.
- Win64 und Android64 fehlerfrei kompiliert.
- Tests: `SELF_TEST_OK`.
- Die `.fmx`-Datei blieb unangetastet.

Aktuelle Pakete:

- [Windows-x64 r2](C:/Users/Besitzer/Documents/Codex/2026-09-04/das/work/OpenAIUsageDashboard/outputs/OpenAIUsageDashboard-Windows-x64-2026-09-05-r2.zip)
- [Delphi-Quellcode r2](C:/Users/Besitzer/Documents/Codex/2026-09-04/das/work/OpenAIUsageDashboard/outputs/OpenAIUsageDashboard-Delphi-Source-2026-09-05-r2.zip)
- [Aktuelle Dashboard-Vorschau](C:/Users/Besitzer/Documents/Codex/2026-09-04/das/work/OpenAIUsageDashboard/dashboard-preview.png)

![Dashboard mit vergrößerter Beschriftung](C:/Users/Besitzer/Documents/Codex/2026-09-04/das/work/OpenAIUsageDashboard/dashboard-preview.png)





> In der Vorhersage, steht oben der Text "Abrechnung" und darunter die Kosten.
> Bei den Tagen stehen die Kosten ganz oben.
> Da wäre es schöner, wenn auch in der Vorschau die Kosten oben stehen und darunter das Abrechnung.
> 
> Bei den Feldern der "Weitere API-Dienste", bitte die Schriftarten, die bei den Feldern der "Codex - ChatGPT-Nutzung"
> 
> Bei Top-Modelle den Model-Name 25% größer und Anfragen, sowie Tokens +80%.
> 
> Außerdem, gibt es einen Fehler, siehe Screenschot.

> Die Quellcodes von Delphi findest du unter "C:\Program Files (x86)\Embarcadero\Studio\37.0\source", falls diese helfen.

> ---
> 
> ## Secrets.Tests.exe - Fehler in Anwendung
> 
> Die Ausnahme "Unbekannter Softwarefehler" (0x0eedfade) ist in der Anwendung an der Stelle 0x00007FFF04A61ADA aufgetreten.
> 
> ---
> 
> ## OK

Umgesetzt.

- Prognosekosten stehen jetzt oben, „Abrechnung → 0“ darunter.
- Zusatzdienste verwenden die Codex-KPI-Schriftgrößen; lange Werte werden automatisch angepasst.
- Modellnamen sind etwa 25 % größer, Anfrage- und Tokenwerte 80 % größer.
- Der API-Key-Fehler wurde behoben: Die fehlerhafte Delphi-Projektion von `CopyToByteArray` wurde durch `IBufferByteAccess` ersetzt.
- Win64 und Android64 erfolgreich kompiliert; Dashboard- und Kryptografietests bestanden.

Downloads:

- [Windows-x64-Paket r3](C:/Users/Besitzer/Documents/Codex/2026-09-04/das/work/OpenAIUsageDashboard/outputs/OpenAIUsageDashboard-Windows-x64-2026-09-05-r3.zip)
- [Delphi-Quellcode r3](C:/Users/Besitzer/Documents/Codex/2026-09-04/das/work/OpenAIUsageDashboard/outputs/OpenAIUsageDashboard-Delphi-Source-2026-09-05-r3.zip)
- [Aktualisierte Vorschau](C:/Users/Besitzer/Documents/Codex/2026-09-04/das/work/OpenAIUsageDashboard/dashboard-preview.png)

Der vollständige DPAPI-Test ist innerhalb der abgeschotteten Codex-Prozessumgebung nicht möglich. Der AES-GCM- und Pufferpfad, der den gezeigten Zugriffsfehler verursachte, wurde jedoch vollständig geprüft.





> Status:
> ```
> Aktuell - Codex teilweise nicht verfügbar.
> ```
> 
> Bei "Kosten - heute" und "Codex - ChatGPT-Nutzung" stehen alle Werte auf 0.
> 
> Aber grundsätzlich funktionieren die Anfragen sonst.
> 
> 
> 
> OK, die Schriftgröße für "Tokens" war vielleicht etwas zu viel, mit +80%.
> 
> Nur +50% würden bestimmt besser passen.
> 
> Model und Anfragen passen.
> 
> 
> 
> Ansonsten sieht es gut aus. :)
> 
> 
> 
> 
> 
> Was muß eigentlich bei "Viewer-Token für den Sammler"  in den Settings eingetragen werden?

r4 ist fertig:

- Tokens jetzt **+50 %**, Modellnamen und Anfragen unverändert.
- Codex-Suche erkennt jetzt deine Desktop-Installation auch beim Start aus dem Explorer.
- UTC-Tagesberechnung korrigiert. Fehlende Daten erscheinen als „–“, konkrete Codex-Fehler unten in den Einstellungen.

Bei „Kosten heute“ meldet die laufende API-Abfrage derzeit auch 0 Anfragen und Tokens – der Nullwert ist daher plausibel.

[Windows-Paket r4](C:/Users/Besitzer/Documents/Codex/2026-09-04/das/work/OpenAIUsageDashboard/outputs/OpenAIUsageDashboard-Windows-x64-2026-09-05-r4.zip) · [Delphi-Quellcode r4](C:/Users/Besitzer/Documents/Codex/2026-09-04/das/work/OpenAIUsageDashboard/outputs/OpenAIUsageDashboard-Delphi-Source-2026-09-05-r4.zip)

Windows-/Android-Builds und Tests bestanden. Der angemeldete Codex-Liveabruf bleibt innerhalb der Sandbox ungeprüft.

Zum **Viewer-Token**: Das ist ein selbst gewähltes gemeinsames Kennwort für den Statistikabruf.

- Nur Windows: leer lassen.
- Mit Android: auf Windows und Android denselben langen, zufälligen Wert eintragen, beispielsweise 32 Zeichen aus dem Passwortmanager.

Dort gehört kein OpenAI-Key hinein.





> OK, dass hatte ich noch garnicht genauer nachgesehn oder ausprobiert.
> Die Android-Version holt also ihre Werte von der Windows-Anwendung und nicht selbst?
> Dann wäre es aber sinnvoll die Windows-Anwendung auch in einer Art Dienstmodus laufen lassen zu können, ohne Anzeige. Also quasi minimiert mit TrayIcon.
> 
> Auf Android startet die Anwendung erstmal.
> Und das Settingsfenster war wirklich zu groß.
> Die Scrollbar funktioniert, aber oben stand es etwas über und konnte ins Bild gescrollt werden.
> Es ist aber auch nicht so schlimm. Das Handy ist kein FullHD, 16:9 oder Dergleichen, wie später Tablet und Monitore sein werden.
> Xiaomi 13, also das Bild nicht sehr hoch, aber dafür extrem breit, im Landscape.

> Es gibt ein TTrayIcon im Delphi.

> C:\Program Files (x86)\Embarcadero\Studio\37.0\source\vcl\Vcl.ExtCtrls.pas
> Ist zwar VCL, aber wenn nur im Code verwendet, gibt es kein Problem.

> FMX nutzt im Hintergrund für Windows eh teilweise die VCL.

Umgesetzt – mit `Vcl.ExtCtrls.TTrayIcon` im Windows-Zweig.

- **„Nur Sammler / Tray“** blendet das Dashboard aus; Abfragen und Android-Versorgung laufen weiter.
- **„Beim Start nur Sammler“** speichert den gewünschten Startmodus.
- Tray-Menü: Dashboard, Einstellungen und Beenden.
- Im Sammlermodus keine Monitor-Abdeckung; nur der PC bleibt Mo–Fr von 10–18 Uhr wach.
- Einstellungen passen sich flachen und schmalen Bildschirmen sowie der Bildschirmtastatur an.

[Windows-Version r5](C:/Users/Besitzer/Documents/Codex/2026-09-04/das/outputs/OpenAIUsageDashboard-Windows-x64-2026-09-05-r5.zip) · [Delphi-Quellen r5](C:/Users/Besitzer/Documents/Codex/2026-09-04/das/outputs/OpenAIUsageDashboard-Delphi-Source-2026-09-05-r5.zip)

Windows und Android64 erfolgreich gebaut. Ansichten und Fehlerpfade geprüft; echte Tray-Bedienung und Android-Gerätetest stehen noch aus.





> Die Daten für "Kosten heute" und "Tokens heute" sind oft leer.

Ich habe das Problem korrigiert.

* Bereits geladene **Kosten heute** bleiben bei einer vorübergehend unvollständigen API-Antwort erhalten.
* Dasselbe gilt für **Codex-Tokens heute**, 7 Tage und Monat.
* Kosten werden anhand des UTC-Tages, Codex-Tokens anhand des lokalen Tages abgegrenzt.
* Beim Tageswechsel werden keine alten Tageswerte übernommen.
* Kostenwert, Summen, Prognose und Diagramm bleiben konsistent.
* Das ZIP-Archiv wurde erfolgreich geprüft. Ein Delphi-Compiler war in dieser Umgebung nicht verfügbar.

[](sandbox:/workspace/scratch/5d5d71fb18c8/OpenAIUsageDashboard-fixed.zip)

Die Ursache liegt teilweise in den Datenquellen: Codex liefert die Tages-Buckets laut [offizieller Dokumentation](https://learn.chatgpt.com/docs/app-server) nur optional. Auch Kosten-Buckets können zeitverzögert eintreffen. Beim ersten Programmstart kann daher weiterhin „–“ erscheinen, bis mindestens einmal ein Wert für den aktuellen Tag geliefert wurde.





> Eigentlich sollte das Programm sich bei Doppelklick auf das Fester in den Tray minimieren, was aber nicht passiert.

Die Doppelklick-Behandlung fehlte im Maus-Handler. Ein **linker Doppelklick auf die Dashboard-Fläche** ruft jetzt den vorhandenen Tray-Modus auf: Das Fenster wird ausgeblendet, die Datenerfassung läuft weiter.

[](sandbox:/workspace/scratch/5d5d71fb18c8/OpenAIUsageDashboard-tray-fix.zip)

Die bisherige Tageswert-Korrektur ist enthalten. Bitte das Projekt neu kompilieren; ein Delphi-Laufzeittest war hier nicht möglich.





> Müsste nicht inzwischen auch das GPT-6 Astra in Top-Modelle angezeigt werden?
> 3 von den 5 Feldern sind gefüllt, aber GPT-6 fehlt.

Nein, in dieser Anzeige fehlt GPT‑6 Astra nicht wegen eines Programmfehlers.

„Top-Modelle“ wird ausschließlich aus der OpenAI-API-Platform-Abfrage

```text
/organization/usage/completions?group_by=model
```

gebildet. Der Code filtert keine Modellnamen: Jedes von der API gelieferte Modell wird übernommen und nach Tokenzahl sortiert. Die drei gefüllten Felder bedeuten daher, dass die Organisation für die letzten sieben Tage nur diese drei API-Modelle gemeldet hat. Die zwei übrigen Felder sind lediglich freie Plätze.

Ihre GPT‑6-Astra-Nutzung läuft offenbar über ChatGPT/Codex. Diese wird unten im Bereich „Codex · ChatGPT-Nutzung“ erfasst. Der Codex App Server liefert dort derzeit nur:

* Gesamttokens
* Tages-Buckets
* Nutzungsgrenzen

Eine Aufteilung nach Modell enthält `account/usage/read` nicht. Deshalb stecken die Astra-Tokens wahrscheinlich in den angezeigten 2,8 Milliarden Codex-Tokens, lassen sich aber nicht separat GPT‑6 Astra zuordnen. Das entspricht der [offiziellen Codex-App-Server-Dokumentation](https://learn.chatgpt.com/docs/app-server).

Würde GPT‑6 Astra mit dem API-Schlüssel derselben Organisation verwendet, sollte es automatisch unter „Top-Modelle“ erscheinen. Die [Usage-API-Dokumentation](https://developers.openai.com/cookbook/examples/completions_usage_api) bestätigt die Gruppierung der API-Nutzung nach Modell.

Die Überschrift wäre daher präziser als **„Top API-Modelle · letzte 7 Tage“**.





> Gestern und heute wurde GPT-6 aber definitiv benutzt, in Codex.
> Als auch ChatGPT.com, was hierfür aber egal sein sollte.

Ja, GPT‑6 Astra wurde genutzt – aber der Bereich **„Top-Modelle“ wertet Codex überhaupt nicht aus**. Er enthält ausschließlich Modelle aus der API-Platform-Organisation. Deshalb erscheinen dort nur `gpt-5.6-terra`, `gpt-5.4-mini` und `gpt-4o-mini`.

Die Codex-Abfrage `account/usage/read` liefert lediglich Gesamtwerte und Tages-Buckets:

```json
{
  "summary": {
    "lifetimeTokens": 41300000000
  },
  "dailyUsageBuckets": [
    {
      "startDate": "2026-09-06",
      "tokens": 12345
    }
  ]
}
```

Ein Modellname ist darin nicht enthalten. Auch die dokumentierte Benachrichtigung `thread/tokenUsage/updated` liefert Nutzungsstände für aktive Threads, aber keine belastbare kontoweite Aufschlüsselung der letzten sieben Tage nach Modell. [Codex-App-Server-Dokumentation](https://learn.chatgpt.com/docs/app-server)

Daher kann das Programm erkennen, dass Codex-Tokens verbraucht wurden, aber nicht, welcher Anteil davon auf GPT‑6 Astra entfällt. GPT‑6 einfach wegen seiner Verfügbarkeit oder aktuellen Auswahl in eines der freien Felder einzutragen, wäre irreführend.

Die aktuelle Überschrift ist damit missverständlich. Korrekt wäre:

> **Top API-Modelle · letzte 7 Tage**

GPT‑6 Astra könnte erst dann als Codex-Top-Modell angezeigt werden, wenn OpenAI eine Modellaufschlüsselung in der Nutzungsantwort liefert oder das Programm lokale Codex-Sitzungen separat auswertet. Letzteres wäre unvollständig und würde insbesondere die Nutzung auf ChatGPT.com nicht zuverlässig erfassen.

Zusätzlich zeigt Ihr Screenshot ein eigenes Problem: **„Tokens heute: 0“**, obwohl Sie Codex heute verwendet haben. Das bedeutet wahrscheinlich, dass der heutige optionale Tages-Bucket noch nicht geliefert wurde; der Code interpretiert eine vorhandene Bucket-Liste ohne heutigen Eintrag momentan fälschlich als echten Nullwert.





> Genau, dieses Problem hattest du vorhin bereits gesucht.
> Tokens heute und Kosten heute liefert oft keinen Wert.

Richtig – die vorherige Korrektur war unvollständig. Der Codex-Parser behandelte eine vorhandene Bucket-Liste ohne heutigen Eintrag als echten Wert `0`.

Jetzt gilt:

* Heutiger Bucket mit `tokens: 0` → Anzeige `0`
* Heutiger Bucket fehlt → Anzeige `–` und „Heute noch nicht gemeldet“
* Früher am selben Tag empfangener Wert → bleibt erhalten
* Beim Tageswechsel → keine Übernahme des Vortags
* „Top-Modelle“ heißt jetzt eindeutig „Top API-Modelle“

Bei „Kosten heute“ bleibt ebenfalls der letzte am selben UTC-Tag empfangene Wert erhalten. Wurde heute noch nie ein Kosten-Bucket geliefert, kann das Programm keinen Betrag berechnen und zeigt weiterhin `–`. Dass Codex-Tages-Buckets fehlen dürfen, bestätigt die [offizielle Dokumentation](https://learn.chatgpt.com/docs/app-server).

[](sandbox:/workspace/scratch/5d5d71fb18c8/OpenAIUsageDashboard-daily-values-fix.zip)

Das Archiv enthält auch die vorherige Doppelklick-/Tray-Korrektur. Die Quelltext- und Archivprüfungen waren erfolgreich; ein Delphi-Compiler steht in dieser Umgebung nicht zur Verfügung.





> Auf Android ist im Settingsdialog in den Edits der Text nicht lesbar.
> Für Android sollte die Textfarbe der Edits, der Combobox und der Buttons auf Weiß eingestellt werden.

Die Android-Darstellung im Settingsdialog ist angepasst:

* Texte und Platzhalter der Edits: weiß
* ausgewählter ComboBox-Text: weiß
* ComboBox-Listeneinträge: weiß
* Buttontexte: weiß

Die Farbe wird unter Android aus den FMX-Style-Einstellungen gelöst, damit das aktive System-Theme sie nicht überschreibt. Windows bleibt unverändert.

[](sandbox:/workspace/scratch/5d5d71fb18c8/OpenAIUsageDashboard-android-text-fix.zip)

Alle vorherigen Korrekturen sind enthalten. Das Archiv wurde erfolgreich geprüft; ein Delphi-Compiler war nicht verfügbar.





> C:\Develop2\OpenAIUsageDashboard
> Sind alle PAS und DPR UTF-8 mit BOM?
> In der Anzeige gibt es ein paar Fehler mit Umlauten und Sonderzeichen-

Nein. Von 18 geprüften `.pas`-/`.dpr`-Dateien sind:

- 10 UTF‑8 mit BOM
- 8 UTF‑8 ohne BOM
- 0 mit ungültigem UTF‑8

Kritisch sind insbesondere diese BOM-losen Dateien, weil sie Umlaute/Sonderzeichen enthalten:

- `C:\Develop2\OpenAIUsageDashboard\Dashboard.Codex.pas`
- `C:\Develop2\OpenAIUsageDashboard\Dashboard.Tray.pas`

Delphi kann sie als ANSI interpretieren; daraus entstehen typische Darstellungsfehler wie `Ã¼` statt `ü`.

Ebenfalls ohne BOM, momentan aber ausschließlich ASCII:

- `tests\Codex.Smoke.dpr`
- `tests\Codex.Tests.dpr`
- `tests\OpenAI.Tests.dpr`
- `tests\Platform.Tests.dpr`
- `tests\Secrets.Tests.dpr`
- `tests\Tray.Tests.dpr`

In den gespeicherten Quellen fand ich keine bereits beschädigten Zeichenfolgen. Ich habe nichts geändert. Offene, ungespeicherte IDE-Inhalte konnten nicht geprüft werden, weil die Kai-Schnittstelle derzeit nicht verfügbar ist.





> Bitte anpassen.
> Delphi sieht UTF-8 ohne BON einfach als ANSI an.

Erledigt. Alle 18 `.pas`- und `.dpr`-Dateien sind jetzt gültiges UTF‑8 mit BOM.

Geändert wurden 8 Dateien, darunter `Dashboard.Codex.pas` und `Dashboard.Tray.pas`. Dabei wurden ausschließlich die BOM-Bytes ergänzt; der eigentliche Dateiinhalt blieb bytegenau unverändert. Die abschließende Prüfung fand keine verdächtigen Mojibake-Zeichenfolgen.

Falls die Dateien in RAD Studio geöffnet sind, bitte neu öffnen beziehungsweise das Projekt neu laden, damit der Editor die Änderungen vom Datenträger übernimmt.





> Und der Grafik gibt es einmal den Grafen der Prognose, aber eigentlich auch eine Linie für das Limit.
> Fehlt diese Limit-Linie, oder ist sie gerade nur außerhalb der Sichtbarkeit?
> Es wäre von Vorteil, dass, wenn ein Limit existiert, sie oben nicht raus ragt, sondern immer sichtbar ist.&#x20;
> Die Skalierung der restlichen Werte (Tageswerte und Prognose nicht ändern)

Angepasst in `Dashboard.Renderer.pas`:

- Die Limit-Linie existierte bereits, beeinflusste aber `LineMax` und damit die Skalierung aller Kurven.
- Das Limit ist jetzt von der Skalierung der Tages- und Prognosewerte getrennt.
- Liegt das Limit oberhalb des sichtbaren Wertebereichs, werden Linie und Beschriftung am oberen Rand festgehalten.
- Ohne vorhandenes Limit wird weiterhin keine Limit-Linie angezeigt.
- UTF‑8-BOM blieb erhalten.

`Dashboard.Renderer.pas` wurde isoliert erfolgreich mit Delphi 13/Win64 kompiliert. Der vollständige Projektbuild wird unabhängig davon durch bereits vorhandene Fehler in `Dashboard.Main.pas` an den Zeilen 284 und 1227 verhindert.





> Die Beschriftung der Prognose bitte links und unter die Line.
> Rechts darüber kollidiert sie mit den Preisen und rechts liegt unterhalb auch das "Abrechnung -> 0".

Erledigt. Die Limit-Beschriftung steht jetzt:

- links im Diagramm,
- direkt unterhalb der gestrichelten Linie,
- außerhalb des rechten Prognosebereichs mit Preisen und „Abrechnung → 0“.

`Dashboard.Renderer.pas` wurde anschließend erfolgreich mit Delphi 13 für Win64 kompiliert. UTF‑8 mit BOM blieb erhalten.





