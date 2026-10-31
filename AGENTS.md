# TempCheck — krótkie sesje pracy

1. Najpierw przeczytaj `docs/PROGRESS.md`, potem tylko pliki dotyczące bieżącego kroku.
2. Realizuj małe zadania, aktualizuj postęp i zapisuj logiczne commity.
3. Nie powtarzaj pełnej analizy ani wszystkich testów, jeśli zmiana tego nie wymaga.
4. Zachowaj minimum macOS 12, AppKit/SwiftUI, Intel i Apple Silicon.
5. Aplikacja tylko odczytuje czujniki. Nie dodawaj sterowania SMC ani helpera root bez zmiany zakresu.
6. Brak danych to brak danych. Nie zastępuj nieudanego pomiaru zerem ani danymi demonstracyjnymi.
7. Nie obiecuj zgodności ze wszystkimi wersjami macOS. Zapisuj faktyczne wyniki testów.
8. Dane demonstracyjne wyłącznie z jawnym `--demo`; GUI musi wyświetlać ich oznaczenie.

Polecenia: `swift test`, `swift run TempCheck --diagnose`, `scripts/build-app.sh`.
