# Postęp TempCheck

## Stan
- [x] 1. Plan i założenia.
- [x] 2. Odczyty i testy.
- [x] 3. Interfejs.
- [x] 4. Historia i ustawienia.
- [x] 5. Kompilacja obu architektur, render wyglądu i pakowanie.
- [x] Utworzenie prywatnego repo https://github.com/d4rcon/TempCheck.
- [x] Wysłanie kodu do repo — main zawiera komplet źródeł, testów, plan i instrukcję budowania.
- [ ] Ręczny test klikania w GUI — narzędzie komputerowe nie ma uprawnień systemowych.

## Następne zadanie
1. Ręcznie sprawdzić GUI: pasek menu, zmiana zakładek, pauza, jednostki, eksport,
   zamknięcie okna bez kończenia procesu, zakończenie przez menu i wznowienie po uśpieniu.
2. Następne rozszerzenie po weryfikacji: start przy logowaniu albo powiadomienia
   o utrzymującym się wysokim stanie cieplnym; realizować jako osobne małe zadanie.

## Decyzje
Minimum macOS 12; SwiftUI + AppKit; brak zależności sieciowych; dane lokalne;
brak sterowania wentylatorami. Automatyczne wznawianie po limitach nie jest skonfigurowane.

## Weryfikacja
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
- Automatyczny test uruchomionego GUI zablokowany brakiem uprawnień Computer Use.
- Brak testów sprzętowych na Intel i starszych macOS; brak testów długiego działania,
  obciążenia, faktycznie obracających się wentylatorów i uśpienia/wznowienia.

## Pliki wynikowe
`TempCheck.app` i `TempCheck-macOS.zip` znajdują się obok katalogu projektu.
Kod źródłowy i dokumentacja są kompletne lokalnie. Do repo wysyłać śledzone pliki,
nie gotowe binarki ani wyniki lokalnej diagnostyki.

## Publikacja
Źródła opublikowano przez połączony GitHub. Drzewo początkowej opublikowanej wersji
`6183f20e454b937eaa51ec329239b9e9b3227192` odpowiadało dokładnie lokalnym plikom.
Lokalna historia zapisuje osobne etapy; zdalna zawiera ich wspólny snapshot.
Przed przyszłym użyciem `git push` należy pobrać i uzgodnić historie; nie wymuszać push.
Przy publikacji przez API pobrać bieżący zdalny SHA i aktualizować z kontrolą oczekiwanego SHA.
