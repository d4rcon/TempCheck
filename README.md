# TempCheck

Natywny monitor temperatur i prędkości wentylatorów dla Maca. SwiftUI + AppKit,
pasek menu, systemowy jasny i ciemny wygląd. Interfejs po polsku.

![TempCheck — podgląd z jawnymi danymi demonstracyjnymi](docs/preview.png)

## Funkcje wersji 0.2

- Temperatury dostępnych czujników SMC; grupy CPU, GPU i baterii dla rozpoznanych kluczy.
- Aktualne RPM każdego wentylatora; zero RPM pozostaje odróżnione od braku danych.
- Wybór odczytu w pasku menu: CPU, GPU, bateria, najcieplejszy czujnik lub RPM wybranego wentylatora.
- Historia z ostatnich 15 minut, godziny, doby i 7 dni, zachowywana między uruchomieniami.
- Wykres temperatury oraz obciążenia CPU i GPU dla tego samego zakresu czasu.
- Alerty o utrzymującej się wysokiej temperaturze, z progiem, opóźnieniem i wyciszeniem.
- Start przy logowaniu w tle, obsługiwany przez system macOS.
- Jednostki °C/°F, odświeżanie co 1/2/5/10 sekund, pauza i ręczne odświeżenie.
- Eksport wybranego zakresu temperatur, RPM i obciążenia do CSV; brakujące wartości jako puste pola.
- Pomiary w tle, wstrzymanie podczas uśpienia, ponowne połączenie po utracie SMC.
- Brak ruchu sieciowego i zewnętrznych bibliotek. Wyłącznie odczyt sprzętu.

Zamknięcie okna pozostawia monitor w pasku menu. Zakończenie: menu TempCheck →
„Zamknij TempCheck” albo ⌘Q.

## Powiadomienia i start przy logowaniu

Alerty są początkowo wyłączone. Włączenie ich w ustawieniach aplikacji wymaga
zgody macOS na powiadomienia. Domyślnie alert pojawia się po 60 sekundach ciągłych
odczytów CPU lub GPU wynoszących co najmniej 90°C. Próg można zmienić.
Brak odczytu, pauza lub uśpienie przerywają odliczanie.

Po alercie ponowne powiadomienie wymaga spadku temperatury przynajmniej o 5°C
poniżej ustawionego progu i upływu co najmniej 15 minut od poprzedniego alertu.
Powiadomienia można wyciszyć na godzinę. Alert opisuje pomiar; nie stanowi diagnozy
stanu sprzętu.

Na macOS 13 i nowszym przełącznik startu przy logowaniu korzysta z `SMAppService`.
Jeżeli system wymaga zatwierdzenia, aplikacja pokazuje ten stan i pozwala otworzyć
ustawienia logowania. Na macOS 12 należy ręcznie dodać `TempCheck.app` w Preferencjach
systemowych → Użytkownicy i grupy → Logowanie. Przy uruchomieniu jako element logowania
aplikacja pozostaje w pasku menu bez otwierania głównego okna.

Powiadomieniami i rejestracją logowania należy zarządzać z uruchomionej paczki
`TempCheck.app`; sam plik wykonywalny uruchomiony przez `swift run` nie udostępnia
tych funkcji systemowych. Przenieś aplikację do folderu Aplikacje przed włączeniem
startu przy logowaniu.

## Historia, obciążenie i prywatność

Historia jest zapisywana wyłącznie lokalnie w pliku:

```text
~/Library/Application Support/TempCheck/history.plist
```

Zapis używa binarnego formatu plist i atomowej wymiany pliku. Odbywa się co około
60 sekund, po wstrzymaniu pomiarów, przed uśpieniem oraz podczas zwykłego zamykania aplikacji. Nagłe przerwanie
procesu może spowodować utratę pomiarów od ostatniego zapisu. Dane starsze niż 7 dni
są usuwane podczas kolejnego odczytu lub zapisu historii.

Jeżeli zapisanego pliku nie można odczytać, aplikacja zachowuje go i wstrzymuje dalszy
zapis, pokazując komunikat. Bieżące pomiary oraz ich eksport pozostają dostępne.

Ostatnie 15 minut zachowuje pojedyncze pomiary. Zakres godzinny pokazuje średnie
z minut, dobowy — z 5 minut, a tygodniowy — z 30 minut. Dzięki temu rozmiar historii
pozostaje ograniczony również przy dużej liczbie czujników. Statystyki i eksport
dłuższych zakresów opisują te średnie, a nie każdy krótkotrwały szczyt temperatury.
Brakujące odczyty nie są zastępowane zerem ani dopisywane do przerw w historii.

Obciążenie CPU wynika z różnicy systemowych liczników między pomiarami i jest
procentem aktywności wszystkich logicznych procesorów. Pierwszy pomiar po uruchomieniu
lub wznowieniu służy ustaleniu punktu odniesienia. Obciążenie GPU pochodzi ze statystyk
sterownika w IORegistry; przy wielu akceleratorach pokazywany jest największy poprawny
odczyt. Sterowniki nieudostępniające tych statystyk otrzymują oznaczenie „—”.
Wykresy i CSV zachowują wspólne znaczniki czasu dla temperatur i obciążenia.

TempCheck nie wysyła pomiarów do sieci. Tryb demonstracyjny nie zapisuje historii,
nie zmienia ustawień użytkownika i nie włącza powiadomień ani startu przy logowaniu.

## Uruchomienie i budowanie

Gotowa paczka `TempCheck-macOS.zip` zawiera `TempCheck.app`. Rozpakuj i uruchom
aplikację. Możesz przenieść ją do folderu Aplikacje. Paczka testowa ma podpis
lokalny ad hoc; nie jest podpisana certyfikatem Developer ID ani notaryzowana.

Do budowania potrzebne są macOS, Xcode i Swift 5.9 lub nowszy. Sprawdzony zestaw:
macOS 27.0.1, Xcode z SDK 27, Swift 6.4.

```sh
swift test
swift run TempCheck
swift run TempCheck --diagnose
```

Pakowanie aplikacji dla Intel i Apple Silicon:

```sh
./scripts/build-app.sh
# Tylko architektura bieżącego komputera:
./scripts/build-app.sh --native
```

Wynik trafia do `dist/`. Można ustawić `TEMPCHECK_BUILD_ROOT` oraz
`TEMPCHECK_OUTPUT_DIR`, aby wskazać inne katalogi budowania i wyników.
Skrypt korzysta z silnika SwiftPM `native`, dostępnego również w starszych
toolchainach; Swift 6.4 zgłasza jego wycofywanie.

Przykładowe dane do demonstracji wyglądu:

```sh
swift run TempCheck --demo
```

Ten tryb jest jawnie oznaczony w oknie i pasku menu. Nie uruchamia się automatycznie
w razie braku dostępu do czujników.

## Zakres zgodności

Docelowe minimum: **macOS 12**. Paczka zawiera **arm64 i x86_64**.
Sprawdzono rzeczywiste odczyty na bieżącym Macu Apple Silicon z macOS 27.0.1.
Starsze systemy i fizyczny Mac Intel wymagają osobnych testów sprzętowych.

SMC nie jest stabilnym, publicznie udokumentowanym API temperatur Apple. Dostępność
czujników zależy od modelu i systemu. Nie obiecujemy działania na każdej wersji
macOS ani na przyszłych modelach. Brak danych powoduje komunikat i „—”, nigdy
zastępcze zero. Aplikacji nie należy uruchamiać z `sudo`.

Klucze nierozpoznanych czujników pozostają widoczne. Apple Silicon grupuje strefy
Tp/Te jako CPU i Tg jako GPU zgodnie z konwencjami społeczności, z zachowaniem
surowego identyfikatora; nie przypisuje im numerów fizycznych rdzeni. Rodzina Tf
zawiera zarówno CPU, jak i GPU, dlatego rozpoznawane są konkretne klucze.
Nie każdy czujnik jest pojedynczym rdzeniem i nie każda temperatura opisuje obudowę.

`FNum = 0` oznacza, że SMC zgłasza brak wentylatorów. Nieudany odczyt `FNum`
oznacza brak informacji. `0 RPM` oznacza poprawnie odczytany zatrzymany wentylator.
Zakres odczytów temperatur w tej wersji jest ograniczony do (0, 150] °C;
nieaktywne kanały i wartości poza zakresem są traktowane jako niedostępne.

## Rozwój projektu

- [Plan funkcji i etapów](docs/PLAN.md)
- [Postęp, testy i następne zadanie](docs/PROGRESS.md)
- [Zasady rozwoju](docs/DEVELOPMENT.md)

## Źródła techniczne

- [Apple: ProcessInfo.thermalState](https://developer.apple.com/documentation/foundation/processinfo/thermalstate-swift.property) — ocena stanu cieplnego przez system.
- [Apple: SMAppService.mainApp](https://developer.apple.com/documentation/servicemanagement/smappservice/mainapp) — rejestracja aplikacji przy logowaniu od macOS 13.
- [Apple: UNUserNotificationCenter](https://developer.apple.com/documentation/usernotifications/unusernotificationcenter) — uprawnienia i lokalne powiadomienia.
- [Stats: interfejs AppleSMC](https://github.com/exelban/stats/blob/master/SMC/smc.swift) — odniesienie do protokołu i formatów danych.
- [Stats: identyfikatory czujników](https://github.com/exelban/stats/blob/master/Modules/Sensors/values.swift) — konwencje nazw stref; lokalizacja może zmieniać się między modelami.

TempCheck ma własną małą implementację mostu w C. Nie dołącza kodu aplikacji Stats
ani funkcji zapisu do SMC.
