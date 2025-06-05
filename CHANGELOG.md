# Changelog

Alle wichtigen Änderungen am EuroBlick Projekt werden in dieser Datei dokumentiert.

Das Format basiert auf [Keep a Changelog](https://keepachangelog.com/de/1.0.0/),
und dieses Projekt folgt [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Hinzugefügt
- Kontosaldenverlauf in den Auswertungen
  - Visualisierung des Saldenverlaufs über Zeit als Liniendiagramm
  - Farbliche Unterscheidung zwischen positiven (grün) und negativen (rot) Salden
  - Kontoauswahl mit Gruppierung nach Kontogruppen
  - Anzeige des aktuellen Saldos und Endsaldos im ausgewählten Zeitraum
  - Anpassung an verschiedene Zeiträume (Alle Monate, spezifische Monate, benutzerdefinierter Zeitraum)

### Verbessert
- Performance-Optimierungen für Chart-Darstellungen
  - Vereinfachte Chart-Konfiguration für bessere Compiler-Performance
  - Optimierte Datenberechnung für Saldenverlauf

## [1.0.2] - 2024-03-26

### Performance
- Signifikante Verbesserung der Ladezeiten beim Bearbeiten von Transaktionen
  - Sofortiges Laden von Transaktionen aus dem Cache
  - Keine Verzögerungen mehr beim Öffnen des Bearbeitungs-Sheets
  - Optimierte UI-Aktualisierungen ohne Hänger
- Verbesserte Cache-Nutzung
  - Effizientere Cache-Invalidierung
  - Schnellerer Zugriff auf kürzlich bearbeitete Transaktionen

### Logging
- Erweitertes Debug-Logging für bessere Nachverfolgbarkeit
  - Detaillierte Cache-Zugriffsprotokolle
  - Klare Erfolgsmeldungen bei Transaktionsoperationen

## [1.0.1] - 2024-03-26

### Behoben
- Problem beim Laden von Transaktionen im Edit-Modus behoben
  - Sheet wird jetzt sofort mit Ladeindikator angezeigt
  - Verbesserte Fehlerbehandlung beim Laden von Transaktionen
  - "Abbrechen"-Button während des Ladevorgangs hinzugefügt
  - Besseres State-Management für Transaktionsbearbeitung
  - Alle State-Änderungen werden jetzt korrekt auf dem Main-Thread ausgeführt

### Verbessert
- Verbessertes Logging für bessere Fehlerdiagnose
  - Detaillierte Logs für Transaktionslade-Prozess
  - Klarere Fehlermeldungen
- Optimierte Cache-Verwaltung für Transaktionen
  - Bessere Cache-Invalidierung
  - Effizientere Speichernutzung

### Technische Verbesserungen
- Core Data Optimierungen
  - Verbesserte Fehlerbehandlung bei Datenbankoperationen
  - Optimierte Kontext-Verwaltung
- Performance-Verbesserungen
  - Schnelleres Laden von Transaktionen
  - Optimierte UI-Aktualisierungen

## [1.0.0] - Initiale Version

### Hinzugefügt
- Grundlegende Funktionalität für Finanzverwaltung
- Transaktionsverwaltung (Hinzufügen, Bearbeiten, Löschen)
- Kategorieverwaltung
- Import/Export Funktionalität
- Kontoübersicht
- Filterfunktionen für Transaktionen
- Datumbasierte Filterung
- Suchfunktion 