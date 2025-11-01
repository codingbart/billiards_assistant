import numpy as np
from roboflow import Roboflow  # Importujemy nową bibliotekę

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
    #    Zacznij od bili docelowej (P_target)
    #    i przesuń ją WZDŁUŻ wektora kierunkowego (V_unit_direction)
    #    o dystans równy średnicy bili (2 * radius)
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
# --- NOWA, PRAWDZIWA FUNKCJA DETEKCJI (YOLO) ---
# ---
def detect_all_balls(image_path, api_key):
    """
    Używa modelu YOLO z Roboflow do wykrywania bil na obrazie.
    """
    
    print("INFO: Używam modelu detekcji YOLO z Roboflow...")
    
    try:
        rf = Roboflow(api_key=api_key)
        # ID modelu i wersja są z Twojego panelu Roboflow
        # Model URL: billiarddet-kyjmh
        # Wersja: v2
        project = rf.workspace().project("billiarddet-kyjmh")
        model = project.version(1).model # Używamy wersji 2, którą właśnie wytrenowałeś
        
        # Wyślij obraz do Roboflow i pobierz predykcje
        prediction = model.predict(image_path, confidence=20, overlap=30).json()
        
    except Exception as e:
        print(f"BŁĄD Roboflow: {e}")
        raise ValueError(f"Nie udało się połączyć z Roboflow lub przetworzyć obrazu: {e}")

    white_ball = None
    other_balls = []

    # Przetwórz wyniki z modelu
    for box in prediction['predictions']:
        # Konwertuj bounding box [x_center, y_center, width, height] na nasz format
        ball_data = {
            "x": int(box['x']),
            "y": int(box['y']),
            "r": int((box['width'] + box['height']) / 4) # Przybliżony promień
        }
        
        # TUTAJ ŁĄCZYMY KLASY (tak jak planowaliśmy)
        if box['class'] == 'White': # Zgodnie z oryginalnym datasetem
            white_ball = ball_data
        else:
            # Wszystkie inne (N1, N2 itd.) traktujemy jako 'other_ball'
            other_balls.append(ball_data)
            
    return white_ball, other_balls