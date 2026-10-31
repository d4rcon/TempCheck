# Zasady rozwoju TempCheck

- Minimum macOS 12; interfejs AppKit/SwiftUI; architektury Intel i Apple Silicon.
- Aplikacja wyłącznie odczytuje czujniki. Sterowanie SMC i helper wymagający roota
  stanowią osobny zakres projektu.
- Nieudany pomiar pozostaje oznaczony jako brak danych, bez zastępowania go zerem.
- Dane demonstracyjne są dostępne wyłącznie w jawnym trybie `--demo` i mają
  widoczne oznaczenie w interfejsie.
- Zgodność z wersjami systemu i modelami sprzętu należy potwierdzać testami.
- Zmiany powinny mieć osobne commity i aktualny wpis w dokumentacji postępu.

## Polecenia

```sh
swift test
swift run TempCheck --diagnose
./scripts/build-app.sh
```
