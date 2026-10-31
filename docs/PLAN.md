# TempCheck — plan

## Podstawowe funkcje
- Temperatury udostępnianych czujników, w tym rozpoznane CPU, GPU i bateria.
- Aktualne RPM każdego wykrytego wentylatora, odróżnione od braku danych.
- Pasek menu i natywne okno SwiftUI z jasnym/ciemnym wyglądem.
- Historia z ostatnich 15 minut, godziny, doby i 7 dni; wybór czujnika, min./średnia/maks.
- Interwał 1/2/5/10 s, jednostki °C/°F, pauza i odświeżenie.
- Stan cieplny macOS, obciążenie CPU i GPU, obsługa braku dostępu do sprzętu, eksport CSV.

## Etapy rozwoju
1. Repo, założenia i dokumentacja. Wynik: README, plan i zasady rozwoju.
2. Odczyty. Wynik: tylko odczyt SMC, walidacja danych, diagnostyka CLI i testy dekodowania.
3. Interfejs. Wynik: pulpit, lista czujników, wentylatory i pasek menu.
4. Historia i ustawienia. Wynik: wykresy, pauza, jednostki, eksport.
5. Weryfikacja i pakowanie. Wynik: testy, build arm64/x86_64, aplikacja .app i ZIP.

Każdy etap kończy się aktualizacją `PROGRESS.md` i commitem.

## Zakres wersji 0.2

1. Powiadomienia: domyślnie 90°C przez 60 sekund, ponowne uzbrojenie po spadku o 5°C,
   odstęp 15 minut między alertami i wyciszenie na godzinę. Włączenie oraz zgoda systemowa
   pozostają decyzją użytkownika.
2. Start przy logowaniu: natywna rejestracja przez `SMAppService` na macOS 13+,
   ręczna konfiguracja na macOS 12; uruchomienie w tle bez głównego okna.
3. Pasek menu: wybór temperatury CPU, GPU, baterii, najcieplejszego czujnika albo RPM
   konkretnego wentylatora.
4. Trwała historia: zapis lokalny, retencja 7 dni, zakresy 15 min/1 godz./24 godz./7 dni
   i średnie w odstępach 1/5/30 minut dla dłuższych zakresów.
5. Obciążenie CPU i GPU: odczyty systemowe bez zastępowania braku danych zerem,
   wykresy na wspólnej osi czasu i eksport wraz z temperaturami oraz RPM.

Końcowa weryfikacja obejmuje testy jednostkowe, kompilację obu architektur i kontrolę
wyglądu. Osobnego testu na działającym systemie wymagają dostarczenie powiadomienia,
wylogowanie i logowanie, obsługa interfejsu oraz uśpienie i wznowienie.

## Kolejne rozszerzenia

- Tryb oszczędzania energii z rzadszymi pomiarami podczas pracy na baterii.
- Wykresy RPM pokazujące reakcję wentylatorów na zmiany temperatury.
- Ulubione czujniki i dodatkowe, potwierdzone nazwy elementów sprzętu.
- Kompaktowy panel pomiarów otwierany pod ikoną w pasku menu.
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
