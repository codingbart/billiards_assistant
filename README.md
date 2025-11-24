# Billiards Assistant

Aplikacja mobilna iOS z backendem Python do analizy strzałów bilardowych. Aplikacja wykorzystuje model YOLO z Roboflow do automatycznego wykrywania bil oraz oblicza optymalne linie strzału używając metody "Ghost Ball".

## Funkcje

- **Tryb automatyczny (AI)**: Automatyczne wykrywanie białej bili za pomocą modelu YOLO
- **Tryb ręczny**: Ręczne wskazanie wszystkich trzech punktów (biała bila, bila docelowa, łuza)
- **Wizualizacja**: Wyświetlanie linii strzału, pozycji "ghost ball" oraz innych bil na stole
- **Lupa**: Powiększenie obrazu podczas wyboru punktów

## Struktura projektu

```
billiards_assistant/
├── python-backed/          # Backend Flask
│   ├── app.py             # Główny serwer Flask
│   ├── processing.py      # Logika przetwarzania obrazów i obliczeń
│   ├── requirements.txt   # Zależności Pythona
│   └── static/uploads/    # Tymczasowe pliki (ignorowane w git)
├── ios-app/               # Aplikacja iOS
│   └── BilliardAssistant/
│       ├── CameraView.swift
│       ├── NetworkManager.swift
│       └── ...
└── README.md
```

## Wymagania

### Backend
- Python 3.8+
- Klucz API Roboflow
- Port 5001 dostępny (lub zmień w konfiguracji)

### iOS
- Xcode 14+
- iOS 15.0+
- Urządzenie z kamerą

## Instalacja i konfiguracja

### Backend

1. Przejdź do katalogu backendu:
```bash
cd python-backed
```

2. Utwórz środowisko wirtualne:
```bash
python3 -m venv venv
source venv/bin/activate  # Na Windows: venv\Scripts\activate
```

3. Zainstaluj zależności:
```bash
pip install -r requirements.txt
```

4. Skonfiguruj zmienne środowiskowe:
```bash
cp .env.example .env
# Edytuj .env i dodaj swój klucz API Roboflow
```

5. Uruchom serwer:
```bash
python app.py
```

Serwer będzie dostępny pod adresem `http://localhost:5001`

### iOS

1. Otwórz projekt w Xcode:
```bash
open ios-app/BilliardAssistant/BilliardAssistant.xcodeproj
```

2. Skonfiguruj adres serwera:
   - Otwórz `Info.plist` w projekcie
   - Dodaj klucz `ServerBaseURL` z wartością adresu IP twojego serwera (np. `http://192.168.1.100:5001`)
   - Alternatywnie, zmień domyślną wartość w `NetworkManager.swift` w strukturze `NetworkConfig`

3. Zbuduj i uruchom aplikację w Xcode

## Konfiguracja zmiennych środowiskowych

Utwórz plik `.env` w katalogu `python-backed/` na podstawie `.env.example`:

```env
# Wymagane
ROBOFLOW_API_KEY=twój_klucz_api_roboflow

# Opcjonalne
FLASK_DEBUG=False
FLASK_PORT=5001
ROBOFLOW_CONFIDENCE=20
ROBOFLOW_OVERLAP=30
ROBOFLOW_PROJECT=billiarddet-kyjmh
ROBOFLOW_VERSION=3
```

### Opis zmiennych

- `ROBOFLOW_API_KEY` (wymagane): Klucz API z Roboflow do dostępu do modelu YOLO
- `FLASK_DEBUG`: Włącz tryb debug Flask (domyślnie: False)
- `FLASK_PORT`: Port serwera Flask (domyślnie: 5001)
- `ROBOFLOW_CONFIDENCE`: Próg pewności detekcji (0-100, domyślnie: 20)
- `ROBOFLOW_OVERLAP`: Próg nakładania się detekcji (0-100, domyślnie: 30)
- `ROBOFLOW_PROJECT`: Nazwa projektu Roboflow (domyślnie: billiarddet-kyjmh)
- `ROBOFLOW_VERSION`: Wersja modelu (domyślnie: 3)

## API Endpoints

### `POST /analyze`
Analizuje obraz i wykrywa bile automatycznie.

**Request:**
- `file`: Plik obrazu (multipart/form-data)
- `data`: JSON z `target_ball` i `pocket` (punkty x, y)

**Response:**
```json
{
  "white_ball": {"x": 100, "y": 200, "r": 18},
  "other_balls": [...],
  "shot_lines": [...],
  "ghost_ball": {"center": {"x": 150, "y": 250}, "radius": 18}
}
```

### `POST /calculate_manual`
Oblicza linie strzału na podstawie ręcznie wybranych punktów.

**Request:**
```json
{
  "white_ball": {"x": 100, "y": 200},
  "target_ball": {"x": 300, "y": 400},
  "pocket": {"x": 500, "y": 600}
}
```

**Response:**
```json
{
  "shot_lines": [...],
  "ghost_ball": {...},
  "white_ball": {"x": 100, "y": 200, "r": 18},
  "other_balls": []
}
```

## Rozwiązywanie problemów

### Backend nie uruchamia się
- Sprawdź, czy port 5001 jest wolny: `lsof -i :5001`
- Upewnij się, że zmienna `ROBOFLOW_API_KEY` jest ustawiona
- Sprawdź logi w konsoli

### Aplikacja iOS nie łączy się z serwerem
- Sprawdź, czy serwer działa: `curl http://localhost:5001/`
- Upewnij się, że adres IP w `Info.plist` jest poprawny
- Sprawdź, czy urządzenie i komputer są w tej samej sieci Wi-Fi
- Sprawdź firewall - port 5001 musi być otwarty

### Model nie wykrywa białej bili
- Sprawdź jakość obrazu - powinien być wyraźny i dobrze oświetlony
- Spróbuj dostosować `ROBOFLOW_CONFIDENCE` w `.env` (zmniejsz wartość)
- Użyj trybu ręcznego jako alternatywy

## Bezpieczeństwo

- **Nie commituj** pliku `.env` do repozytorium
- W produkcji ustaw `FLASK_DEBUG=False`
- Użyj HTTPS w produkcji
- Ogranicz dostęp do serwera (firewall, VPN)

## Licencja

[Określ licencję]

## Autor

[Twoje imię/nazwa]


