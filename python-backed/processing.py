import numpy as np
from roboflow import Roboflow
import json
import os
import logging

logger = logging.getLogger(__name__)

# Stałe konfiguracyjne
DEFAULT_BALL_RADIUS = 18
ROBOFLOW_CONFIDENCE = int(os.getenv('ROBOFLOW_CONFIDENCE', '20'))
ROBOFLOW_OVERLAP = int(os.getenv('ROBOFLOW_OVERLAP', '30'))
ROBOFLOW_PROJECT = os.getenv('ROBOFLOW_PROJECT', 'billiarddet-kyjmh')
ROBOFLOW_VERSION = int(os.getenv('ROBOFLOW_VERSION', '3'))

# Cache dla modelu Roboflow
_roboflow_model_cache = None

def _get_roboflow_model(api_key):
    """Pobiera model Roboflow z cache lub tworzy nowy."""
    global _roboflow_model_cache
    
    if _roboflow_model_cache is None:
        logger.info("Inicjalizacja modelu Roboflow...")
        rf = Roboflow(api_key=api_key)
        project = rf.workspace().project(ROBOFLOW_PROJECT)
        _roboflow_model_cache = project.version(ROBOFLOW_VERSION).model
        logger.info(f"Model Roboflow załadowany (wersja {ROBOFLOW_VERSION})")
    
    return _roboflow_model_cache

def calculate_shot_lines(white_ball, target_ball, pocket, ball_radius=None):
    """
    Oblicza linie strzału na podstawie pozycji bil i łuzy.
    Używa metody "Ghost Ball".
    
    Args:
        white_ball: Słownik z kluczami 'x', 'y' (opcjonalnie 'r')
        target_ball: Słownik z kluczami 'x', 'y' (opcjonalnie 'r')
        pocket: Słownik z kluczami 'x', 'y'
        ball_radius: Opcjonalny promień bili (domyślnie DEFAULT_BALL_RADIUS)
    
    Returns:
        Tuple (lines, ghost_ball_position)
    """
    if ball_radius is None:
        ball_radius = DEFAULT_BALL_RADIUS

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

def detect_all_balls(image_path, api_key):
    """
    Używa modelu YOLO z Roboflow do wykrywania bil na obrazie.
    
    Args:
        image_path: Ścieżka do pliku obrazu
        api_key: Klucz API Roboflow
    
    Returns:
        Tuple (white_ball, other_balls) gdzie white_ball to dict z 'x', 'y', 'r' lub None
    """
    logger.info(f"Używam modelu detekcji YOLO z Roboflow (confidence={ROBOFLOW_CONFIDENCE}, overlap={ROBOFLOW_OVERLAP})...")

    try:
        model = _get_roboflow_model(api_key)
        prediction = model.predict(image_path, confidence=ROBOFLOW_CONFIDENCE, overlap=ROBOFLOW_OVERLAP).json()
        logger.debug(f"Otrzymano {len(prediction.get('predictions', []))} detekcji")

    except Exception as e:
        logger.error(f"Błąd Roboflow: {e}", exc_info=True)
        raise ValueError(f"Nie udało się połączyć z Roboflow lub przetworzyć obrazu: {e}")

    white_ball = None
    other_balls = []

    # Przetwórz wyniki z modelu
    for box in prediction.get('predictions', []):
        ball_data = {
            "x": int(box['x']),
            "y": int(box['y']),
            "r": int((box['width'] + box['height']) / 4) 
        }

        if box['class'] == 'White':
            white_ball = ball_data
            logger.debug(f"Znaleziono białą bilę: {ball_data}")
        else:
            other_balls.append(ball_data)

    logger.info(f"Wykryto białą bilę: {white_ball is not None}, inne bile: {len(other_balls)}")
    return white_ball, other_balls

def calculate_manual_shot_lines(white_ball_point, target_ball_point, pocket_point):
    """
    Oblicza linie strzału na podstawie 3 ręcznie wybranych punktów.
    Używa stałego promienia bili (DEFAULT_BALL_RADIUS).
    
    Args:
        white_ball_point: Słownik z kluczami 'x', 'y'
        target_ball_point: Słownik z kluczami 'x', 'y'
        pocket_point: Słownik z kluczami 'x', 'y'
    
    Returns:
        Tuple (lines, ghost_ball_position)
    """
    # Używamy funkcji calculate_shot_lines z domyślnym promieniem
    # Tworzymy obiekty bil z domyślnym promieniem
    white_ball = {"x": white_ball_point['x'], "y": white_ball_point['y'], "r": DEFAULT_BALL_RADIUS}
    target_ball = {"x": target_ball_point['x'], "y": target_ball_point['y'], "r": DEFAULT_BALL_RADIUS}
    
    return calculate_shot_lines(white_ball, target_ball, pocket_point, DEFAULT_BALL_RADIUS)