# Terminbuchung von Revision Dynamics

Dieses Repository enthält den Quellcode der Terminbuchung, die die Revision Dynamics GmbH
unter revisiondynamics.com betreibt. Sie ist **abgeleitet von [Tymeslot](https://github.com/Tymeslot/tymeslot)**
(Version 1.46.0) und steht wie das Original unter der **GNU Affero General Public License v3**
(siehe [LICENSE](LICENSE)). Wir veröffentlichen sie, damit alle, die die Buchung über das Netz
nutzen, den Quellcode genau der laufenden Fassung erhalten (AGPL-3.0, § 13).

Dies ist **keine offizielle Tymeslot-Version** und wird nicht von den Tymeslot-Entwicklern
(Diletta Luna OÜ) betreut oder unterstützt. „Tymeslot“ ist eine Marke von Diletta Luna OÜ
(siehe [TRADEMARK.md](TRADEMARK.md)).

## Was wir geändert haben

Gegenüber Tymeslot 1.46.0:

- **Erscheinungsbild:** Buchungsseite, Bestätigungs-, Absage- und Umbuchungsseiten sowie
  Fehlerseiten im Design von Revision Dynamics (Paper-Theme mit `revision.css`, Schriften Outfit
  und Urbanist unter SIL Open Font License, siehe `priv/static/fonts/OFL-*.txt`).
- **Kalender über Microsoft Graph:** Outlook-Kalender werden höchstens zu zweit gleichzeitig
  gelesen; bei Drosselung (HTTP 429) wartet die Abfrage die angegebene Zeit ab.
- **Uhrzeit:** 24-Stunden-Format auch für englischsprachige Gäste.
- **Pflichtfeld „Einrichtung oder Unternehmen“:** Es erscheint im Titel des Termins beim Gastgeber.
- **E-Mails:** Alle Mails in unserem Mail-Design, mit deutschen und englischen Texten; Fehlerseiten,
  Favicon und Seitentitel ohne Tymeslot-Marke.
- **Vor-Ort-Termine:** ein interner, nicht öffentlicher Dienst, über den die Website belegte Zeiten
  liest und Termine mit Anfahrt und Rückfahrt einträgt.

Jede Änderung ist im Git-Verlauf als eigener Commit nachvollziehbar. Konfiguration, Zugangsdaten
und Serverdetails sind nicht enthalten.

## Kontakt

Revision Dynamics GmbH, Schulstraße 27, 65824 Schwalbach am Taunus ·
tim.thielmann@revisiondynamics.com · https://revisiondynamics.com
