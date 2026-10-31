# TempCheck — plan

## Podstawowe funkcje
- Temperatury udostępnianych czujników, w tym rozpoznane CPU, GPU i bateria.
- Aktualne RPM każdego wykrytego wentylatora, odróżnione od braku danych.
- Pasek menu i natywne okno SwiftUI z jasnym/ciemnym wyglądem.
- Historia z ostatnich 15 minut, wybór czujnika, min./średnia/maks.
- Interwał 1/2/5/10 s, jednostki °C/°F, pauza i odświeżenie.
- Stan cieplny macOS, obsługa braku dostępu do sprzętu, eksport CSV.

## Etapy rozwoju
1. Repo, założenia i dokumentacja. Wynik: README, plan i zasady rozwoju.
2. Odczyty. Wynik: tylko odczyt SMC, walidacja danych, diagnostyka CLI i testy dekodowania.
3. Interfejs. Wynik: pulpit, lista czujników, wentylatory i pasek menu.
4. Historia i ustawienia. Wynik: wykresy, pauza, jednostki, eksport.
5. Weryfikacja i pakowanie. Wynik: testy, build arm64/x86_64, aplikacja .app i ZIP.

Każdy etap kończy się aktualizacją `PROGRESS.md` i commitem.

## Dodatki po pierwszej wersji
- Powiadomienia o utrzymującym się wysokim stanie cieplnym, z opóźnieniem i wyciszeniem.
- Start przy logowaniu, z obsługą uprawnień danej wersji macOS.
- Dłuższa historia na dysku, retencja i ograniczenie zużycia energii.
- Dodatkowe źródło HID na modelach, które nie udostępniają temperatur przez SMC.
- Potwierdzone mapowania nazw czujników dla kolejnych generacji układów.
- Developer ID, notaryzacja i wydania GitHub po udostępnieniu podpisu przez właściciela.

## Zgodność
Cel: macOS 12+, Intel i Apple Silicon. Bieżący system użytkownika: 27.0.1.
Budowanie dla danej wersji nie jest równoznaczne z testem na jej sprzęcie.
Interfejs SMC nie ma stabilnego, publicznego kontraktu Apple; nazwy i dostępność
czujników zależą od modelu i systemu. Nieznane czujniki zachowują surowy klucz.
Brak FNum nie stanowi dowodu, że Mac nie ma wentylatora. FNum = 0 oznacza, że SMC
zgłasza zero wentylatorów. 0 RPM to poprawny odczyt zatrzymanego wentylatora.
Nie odczytujemy temperatury powierzchni obudowy ani nie diagnozujemy awarii.
