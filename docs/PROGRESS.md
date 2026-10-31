# Postęp TempCheck

## Stan wersji 0.2

- [x] Implementacja alertów o utrzymującej się wysokiej temperaturze, wyciszenia i kontroli uprawnień.
- [x] Implementacja startu przy logowaniu: macOS 13+ przez systemowe API, ręczna konfiguracja na macOS 12.
- [x] Wybór odczytu w pasku menu: CPU, GPU, bateria, najcieplejszy czujnik lub wskazany wentylator.
- [x] Trwała historia do 7 dni z ograniczoną liczbą próbek i średnimi dla dłuższych zakresów.
- [x] Obciążenie CPU/GPU, wykresy na wspólnej osi czasu i CSV.
- [x] Końcowa weryfikacja testów, paczki arm64/x86_64 i renderów wyglądu wersji 0.2.
- [x] Publikacja zmian wersji 0.2 w https://github.com/d4rcon/TempCheck.
- [ ] Ręczne testy dostarczania powiadomień, logowania, obsługi GUI i uśpienia/wznowienia.

## Następne zadania

1. Sprawdzić na działającym systemie: udzielenie/odmowę zgody i dostarczenie powiadomienia,
   zatwierdzenie startu przy logowaniu, rzeczywiste wylogowanie i ponowne logowanie,
   pauzę, zmianę zakresów i jednostek, eksport, zamknięcie okna bez kończenia procesu,
   zakończenie aplikacji oraz uśpienie/wznowienie.
2. Po weryfikacji wybrać kolejne rozszerzenie z `PLAN.md`.

## Decyzje wersji 0.2

Minimum macOS 12; SwiftUI + AppKit; brak zależności sieciowych; dane lokalne;
brak sterowania wentylatorami.

- Alerty są domyślnie wyłączone; włączenie wymaga zgody systemowej. Próg początkowy 90°C,
  czas 60 s, odstęp 15 min, histereza 5°C i wyciszenie na 1 godz. Pauza, sen oraz brak danych
  przerywają odliczanie. Tryb demonstracyjny nie wysyła powiadomień.
- Start przy logowaniu jest zmieniany wyłącznie przez użytkownika. Stan przełącznika
  pochodzi z systemu; na macOS 12 wyświetlana jest instrukcja ręcznej konfiguracji.
- Historia: `~/Library/Application Support/TempCheck/history.plist`, binarny plist,
  atomowy zapis co około 60 s, przy pauzie, przed uśpieniem i przy zwykłym zamykaniu aplikacji.
  Retencja 7 dni; zakresy 15 min/1 godz./24 godz./7 dni. Dłuższe zakresy i ich CSV
  zawierają średnie z 1/5/30 minut, więc nie zachowują wszystkich krótkich szczytów.
  Nieczytelny plik historii pozostaje zachowany; dalszy zapis jest wstrzymywany,
  a bieżące pomiary i eksport nadal działają.
- CPU: różnica systemowych liczników między pomiarami. GPU: procent ze statystyk
  sterownika w IORegistry; przy wielu akceleratorach największy dostępny odczyt.
  Brak obsługi sterownika pozostaje brakiem danych. Pierwszy pomiar CPU ustala bazę.
- Tryb demonstracyjny nie zapisuje historii ani ustawień i nie rejestruje startu przy logowaniu.
- Podpis paczki pozostaje lokalny ad hoc; brak certyfikatu Developer ID i notaryzacji.

## Weryfikacja wersji 0.2

- `swift test`: 30 testów, 0 błędów. Obejmuje również powiązanie ustawień z historią
  i paskiem menu oraz odroczone zakończenie zapisu podczas zamykania aplikacji.
- Test siedmiodniowej historii z 200 czujnikami potwierdza ograniczenie rozmiaru
  archiwum i odtworzenie odczytów po ponownym wczytaniu.
- Gotowa paczka 0.2.0 zawiera arm64 i x86_64; oba warianty mają minimum macOS 12.0.
- Podpis ad hoc sprawdzony przez `codesign --verify --deep --strict`.
- Render pulpitu sprawdzony w jasnym i ciemnym motywie; sprawdzono też render ustawień.
- Diagnostyka gotowej paczki na macOS 27.0.1 potwierdziła rzeczywiste odczyty
  temperatur, wentylatorów oraz obciążenia CPU i GPU bez błędu odczytu.
- Zakres testów: formaty i walidacja SMC, obciążenie CPU/GPU, brak danych versus zero,
  historia i retencja, trwały zapis, CSV oraz reguły alertów.
- Faktyczne dostarczenie powiadomień i start po ponownym logowaniu nie zostały jeszcze potwierdzone.
- Ręczna obsługa GUI, praca przez wiele dni oraz uśpienie/wznowienie wymagają dalszej weryfikacji.

## Sprawdzenia poprzedniej wersji 0.1

- 2026-10-31: macOS 27.0.1, arm64, Swift 6.4.
- `swift test`: 7 testów, 0 błędów; dekodery SMC, walidacja, brak danych vs zero,
  retencja 15 minut, CSV, jednostki i grupowanie stref.
- Diagnostyka realnego sprzętu poza sandboxem odczytała temperatury i dwa wentylatory.
  Oba w chwili testu zgłaszały 0 RPM. Nie wymagało to roota.
- Sandbox blokuje SMC, co daje prawidłowy komunikat zamiast fikcyjnych odczytów.
- Kompilacja produkcyjna arm64 i x86_64; `lipo` potwierdza obie architektury.
- `vtool` potwierdza minimum macOS 12.0 i SDK 27.0 w obu częściach binarki.
- `codesign --verify --deep --strict` przechodzi; podpis ad hoc, brak notaryzacji.
- Render SwiftUI sprawdzony wizualnie w jasnym i ciemnym motywie, z jawnymi danymi demo.
- Brak testów sprzętowych na Intel i starszych macOS; brak testów długiego działania,
  obciążenia, faktycznie obracających się wentylatorów i uśpienia/wznowienia.

## Pliki wynikowe
`TempCheck.app` i `TempCheck-macOS.zip` znajdują się obok katalogu projektu.
Kod źródłowy i dokumentacja są kompletne lokalnie. Do repo wysyłać śledzone pliki,
nie gotowe binarki ani wyniki lokalnej diagnostyki.

## Repozytorium
Lokalna historia zapisuje osobne etapy; zdalna zawiera ich wspólną wersję.
Przed przyszłym użyciem `git push` należy pobrać i uzgodnić historie; nie wymuszać push.
Przy publikacji przez API pobrać bieżący zdalny SHA i aktualizować z kontrolą oczekiwanego SHA.
