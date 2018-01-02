# MoneyMoney BAWAG PSK extension

_Für eine deutsche Anleitung runter scrollen._

This is an extension for [MoneyMoney.app](http://moneymoney-app.com) to be used with accounts from the Austrian bank [BAWAG PSK](https://www.bawagpsk.com). It has only been tested with the *Einfach Online Konto* but should probably work with other account types, too. The extension is localized in German, but don't hesitate to send a pull request with an English translation.

## Installation

- Open the _Help_ menu in MoneyMoney
- Click on _Show Database in Finder_
- Drop `mm-bawagpsk.lua` from the git repo into the `Extensions` directory

## Account setup
- Open the _Account_ menu
- Click _Add account..._
- Select _Other_
- Select the __BAWAG PSK__ entry near the end of the drop-down list
- Fill in your _Disposer Number_ \[sic\] (_Verfügernummer_) as username and _PIN_ as password

From now on, every refresh will fetch new transactions which will be showed in the transaction overview for the respective account.

# MoneyMoney BAWAG PSK Erweiterung

Dies ist eine Erweiterung für [MoneyMoney.app](http://moneymoney-app.com) zur Benutzung von Konten der österreichischen [BAWAG PSK](https://www.bawagpsk.com). Es wurde bisher nur mit dem *Einfach Online Konto* getestet, sollte aber auch für andere Kontotypen funktionieren.

## Installation

- Öffne das Menü _Hilfe_ in MoneyMoney
- Klicke auf _Zeige Datenbank im Finder_
- Kopiere die Datei `mm-bawagpsk.lua` in den Ordner `Extensions`

## Konto einrichten
- Öffne das Menü _Konto_
- Klicke _Konto hinzufügen..._
- Wähle _Andere_ aus
- Wähle den __BAWAG PSK__ Eintrag am unteren Ende der Drop-Down Liste aus
- Trage die _Verfügernummer_ als Username und die _PIN_ als Passwort ein

Von nun an werden mit jede Aktualisierung die neuen Umsätze geladen und in der Umsatzanzeige für das entsprechende Konto angezeigt.
