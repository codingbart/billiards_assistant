import numpy as np
from roboflow import Roboflow
import json

# Ta funkcja jest poprawna, zostawiamy bez zmian
def calculate_shot_lines(white_ball, target_ball, pocket, ball_radius):
    """
    Oblicza linie strzału na podstawie pozycji bil i łuzy.
    Używa metody "Ghost Ball".
    """

    # Współrzędne jako wektory numpy
    P_pocket = np.array([pocket['x'], pocket['y']])
    P_target = np.array([target_ball['x'], target_ball['y']])
    P_white = np.array([white_ball['x'], white_ball['y']])

    epsilon = 1e-6

    # 1. Stwórz wektor OD ŁUZY DO BILI DOCELOWEJ
    V_from_pocket_to_target = P_target - P_pocket

    # 2. Oblicz jego długość (dystans od bili do łuzy)
    distance_to_pocket = np.linalg.norm(V_from_pocket_to_target) + epsilon

    # 3. Stwórz wektor jednostkowy (kierunek) OD ŁUZY DO BILI
    V_unit_direction = V_from_pocket_to_target / distance_to_pocket

    # 4. Oblicz pozycję "Bili Ducha"
    radius = float(target_ball.get('r', ball_radius))
    P_ghost_ball = P_target + V_unit_direction * (2 * radius)

    # --- Reszta kodu bez zmian ---
    lines = [
        { 
            "start": {"x": int(P_target[0]), "y": int(P_target[1])},
            "end": {"x": int(P_pocket[0]), "y": int(P_pocket[1])}
        },
        { 
            "start": {"x": int(P_white[0]), "y": int(P_white[1])},
            "end": {"x": int(P_ghost_ball[0]), "y": int(P_ghost_ball[1])}
        }
    ]

    ghost_ball_position = {
        "center": {"x": int(P_ghost_ball[0]), "y": int(P_ghost_ball[1])},
        "radius": int(radius)
    }

    return lines, ghost_ball_position

# ---
# --- POPRAWIONA FUNKCJA DETEKCJI (YOLO) ---
# ---
def detect_all_balls(image_path, api_key):
    """
    Używa modelu YOLO z Roboflow do wykrywania bil na obrazie.
    """

    print("INFO: Używam modelu detekcji YOLO v2 z Roboflow...")

    try:
        rf = Roboflow(api_key=api_key)
        project = rf.workspace().project("billiarddet-kyjmh")
        
        # === POPRAWKA 1: Używamy nowej, wytrenowanej wersji 2 ===
        model = project.version(3).model 

        # Używamy wyższego confidence, ponieważ nowy model jest lepiej wytrenowany
        prediction = model.predict(image_path, confidence=20, overlap=30).json()

    except Exception as e:
        print(f"BŁĄD Roboflow: {e}")
        raise ValueError(f"Nie udało się połączyć z Roboflow lub przetworzyć obrazu: {e}")

    white_ball = None
    other_balls = []

    # Przetwórz wyniki z modelu
    for box in prediction['predictions']:
        ball_data = {
            "x": int(box['x']),
            "y": int(box['y']),
            "r": int((box['width'] + box['height']) / 4) 
        }

        # === POPRAWKA 2: Usunęliśmy "hacka" na 'N1' ===
        # Nowy model (v2) jest wytrenowany, aby poprawnie 
        # rozpoznawać bilę białą jako 'White'.
        if box['class'] == 'White':
            white_ball = ball_data
        else:
            other_balls.append(ball_data)

    return white_ball, other_balls

# === NOWA FUNKCJA DLA TRYBU RĘCZNEGO ===
def calculate_manual_shot_lines(white_ball_point, target_ball_point, pocket_point):
    """
    Oblicza linie strzału WYŁĄCZNIE na podstawie 3 ręcznie wybranych punktów.
    Używa stałego promienia bili.
    """
    
    # Używamy stałego, domyślnego promienia.
    # Wartość 18 pochodzi z oryginalnego kodu Roboflow (średnia)
    BALL_RADIUS = 18 

    # Współrzędne jako wektory numpy
    P_pocket = np.array([pocket_point['x'], pocket_point['y']])
    P_target = np.array([target_ball_point['x'], target_ball_point['y']])
    P_white = np.array([white_ball_point['x'], white_ball_point['y']])

    epsilon = 1e-6

    # 1. Stwórz wektor OD ŁUZY DO BILI DOCELOWEJ
    V_from_pocket_to_target = P_target - P_pocket

    # 2. Oblicz jego długość
    distance_to_pocket = np.linalg.norm(V_from_pocket_to_target) + epsilon

    # 3. Stwórz wektor jednostkowy (kierunek)
    V_unit_direction = V_from_pocket_to_target / distance_to_pocket

    # 4. Oblicz pozycję "Bili Ducha"
    radius = float(BALL_RADIUS) # Używamy naszej stałej
    P_ghost_ball = P_target + V_unit_direction * (2 * radius)

    # 5. Przygotuj linie do zwrotu
    lines = [
        { 
            "start": {"x": int(P_target[0]), "y": int(P_target[1])},
            "end": {"x": int(P_pocket[0]), "y": int(P_pocket[1])}
        },
        { 
            "start": {"x": int(P_white[0]), "y": int(P_white[1])},
            "end": {"x": int(P_ghost_ball[0]), "y": int(P_ghost_ball[1])}
        }
    ]

    ghost_ball_position = {
        "center": {"x": int(P_ghost_ball[0]), "y": int(P_ghost_ball[1])},
        "radius": int(radius)
    }

    return lines, ghost_ball_position