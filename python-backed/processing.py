import numpy as np
from roboflow import Roboflow
import json
import logging
import os
import cv2  # <--- TO JEST KONIECZNE, ABY FILTROWAĆ BŁĘDY SPOZA STOŁU

logger = logging.getLogger(__name__)

DEFAULT_BALL_RADIUS = 18
ROBOFLOW_CONFIDENCE = int(os.getenv('ROBOFLOW_CONFIDENCE', '20'))
ROBOFLOW_OVERLAP = int(os.getenv('ROBOFLOW_OVERLAP', '30'))
ROBOFLOW_PROJECT = os.getenv('ROBOFLOW_PROJECT', 'billiarddet-kyjmh')
ROBOFLOW_VERSION = int(os.getenv('ROBOFLOW_VERSION', '3'))

_roboflow_model_cache = None

def _get_roboflow_model(api_key):
    global _roboflow_model_cache
    if _roboflow_model_cache is None:
        logger.info("Inicjalizacja modelu Roboflow...")
        rf = Roboflow(api_key=api_key)
        project = rf.workspace().project(ROBOFLOW_PROJECT)
        _roboflow_model_cache = project.version(ROBOFLOW_VERSION).model
        logger.info(f"Model Roboflow załadowany (wersja {ROBOFLOW_VERSION})")
    return _roboflow_model_cache

# --- FUNKCJE MATEMATYCZNE ---

def is_point_inside_table(point, pockets):
    """
    Sprawdza, czy punkt (bila) znajduje się wewnątrz obszaru wyznaczonego przez łuzy.
    Używa OpenCV pointPolygonTest.
    Uwaga: Ta funkcja może być zbyt restrykcyjna - lepiej użyć table_area jeśli jest dostępny.
    """
    if len(pockets) < 3:
        return True # Za mało łuz, by wyznaczyć obszar, więc akceptujemy wszystko
    
    # Tworzymy kontur z punktów łuz
    pocket_points = np.array([[p['x'], p['y']] for p in pockets], dtype=np.int32)
    
    # Obliczamy otoczkę wypukłą (Convex Hull) - to tworzy ładny wielokąt wokół łuz
    hull = cv2.convexHull(pocket_points)
    
    # Sprawdzamy czy punkt jest wewnątrz
    # True oznacza, że obliczamy dystans (ze znakiem)
    dist = cv2.pointPolygonTest(hull, (float(point['x']), float(point['y'])), True)
    
    # Zwiększona tolerancja: jeśli dist >= -50 (jest w środku lub max 50px na zewnątrz), to akceptujemy
    # To pozwala na większą elastyczność, ponieważ łuzy są na krawędziach stołu
    return dist >= -50.0

def is_point_inside_table_area(point, table_area):
    """
    Sprawdza, czy punkt znajduje się wewnątrz zaznaczonego obszaru stołu.
    table_area: lista punktów narożników prostokąta [{"x": x1, "y": y1}, ...]
    """
    if not table_area or len(table_area) < 3:
        return True  # Jeśli nie podano obszaru, akceptujemy wszystko
    
    # Tworzymy kontur z punktów obszaru stołu
    area_points = np.array([[p['x'], p['y']] for p in table_area], dtype=np.int32)
    
    # Sprawdzamy czy punkt jest wewnątrz
    dist = cv2.pointPolygonTest(area_points, (float(point['x']), float(point['y'])), True)
    
    # Jeśli dist >= 0 (jest w środku), to akceptujemy
    return dist >= 0.0

def calculate_cut_angle(white_pt, ghost_pt, pocket_pt):
    """
    Oblicza kąt cięcia (w stopniach).
    0 stopni = strzał prosty (najłatwiejszy).
    """
    # Wektory
    v_shot = np.array([ghost_pt[0] - white_pt[0], ghost_pt[1] - white_pt[1]])
    v_pot = np.array([pocket_pt[0] - ghost_pt[0], pocket_pt[1] - ghost_pt[1]])
    
    len_shot = np.linalg.norm(v_shot)
    len_pot = np.linalg.norm(v_pot)
    
    if len_shot == 0 or len_pot == 0:
        return 180.0 
        
    dot_product = np.dot(v_shot, v_pot)
    cos_angle = dot_product / (len_shot * len_pot)
    cos_angle = np.clip(cos_angle, -1.0, 1.0)
    
    angle_rad = np.arccos(cos_angle)
    return np.degrees(angle_rad)

def calculate_shot_lines(white_ball, target_ball, pocket, ball_radius=None):
    """Generuje współrzędne linii i bili-ducha dla konkretnego strzału."""
    if ball_radius is None: ball_radius = DEFAULT_BALL_RADIUS
    
    P_pocket = np.array([pocket['x'], pocket['y']])
    P_target = np.array([target_ball['x'], target_ball['y']])
    P_white = np.array([white_ball['x'], white_ball['y']])

    V_pocket_to_target = P_target - P_pocket
    distance = np.linalg.norm(V_pocket_to_target) + 1e-6
    V_unit = V_pocket_to_target / distance
    
    P_ghost = P_target + V_unit * (2 * float(ball_radius))

    lines = [
        { 
            "start": {"x": int(P_target[0]), "y": int(P_target[1])},
            "end": {"x": int(P_pocket[0]), "y": int(P_pocket[1])}
        },
        { 
            "start": {"x": int(P_white[0]), "y": int(P_white[1])},
            "end": {"x": int(P_ghost[0]), "y": int(P_ghost[1])}
        }
    ]

    ghost_ball_pos = {
        "center": {"x": int(P_ghost[0]), "y": int(P_ghost[1])},
        "radius": int(ball_radius)
    }

    return lines, ghost_ball_pos

def find_best_shot(white_ball, other_balls, pockets, table_area=None):
    """
    Sprawdza wszystkie kombinacje i filtruje bile spoza stołu.
    
    Args:
        white_ball: pozycja bili cue
        other_balls: lista innych bil
        pockets: lista łuz
        table_area: opcjonalny obszar stołu - jeśli podany, używany zamiast filtrowania przez łuzy
    """
    best_shot = None
    min_angle = 180.0
    
    if not white_ball or not other_balls or not pockets:
        logger.warning(f"Brak danych: white_ball={white_ball is not None}, other_balls={len(other_balls) if other_balls else 0}, pockets={len(pockets) if pockets else 0}")
        return None
        
    # === FILTRACJA: Odrzucamy bile spoza stołu ===
    # Jeśli mamy table_area, używamy go (bardziej precyzyjne)
    # W przeciwnym razie używamy łuz (mniej precyzyjne, ale lepsze niż nic)
    if table_area and len(table_area) >= 3:
        valid_other_balls = [b for b in other_balls if is_point_inside_table_area(b, table_area)]
        logger.info(f"Filtrowanie przez table_area: {len(other_balls)} wykrytych -> {len(valid_other_balls)} na stole")
        # Jeśli wszystkie bile zostały odrzucone przez table_area, nie filtrujmy w ogóle
        if not valid_other_balls:
            logger.warning("Wszystkie bile zostały odrzucone przez table_area. Pomijam filtrowanie.")
            valid_other_balls = other_balls
    else:
        # Filtrowanie przez łuzy - tylko jeśli mamy wystarczająco dużo łuz
        if len(pockets) >= 3:
            valid_other_balls = [b for b in other_balls if is_point_inside_table(b, pockets)]
            logger.info(f"Filtrowanie przez łuzy: {len(other_balls)} wykrytych -> {len(valid_other_balls)} na stole")
            # Jeśli wszystkie bile zostały odrzucone przez łuzy, nie filtrujmy w ogóle
            # (może łuzy są źle zaznaczone)
            if not valid_other_balls:
                logger.warning("Wszystkie bile zostały odrzucone przez filtr łuz. Możliwe że łuzy są źle zaznaczone - pomijam filtrowanie.")
                valid_other_balls = other_balls
        else:
            # Za mało łuz, nie filtrujmy
            logger.info(f"Za mało łuz ({len(pockets)}), pomijam filtrowanie")
            valid_other_balls = other_balls
    
    P_white = np.array([white_ball['x'], white_ball['y']])
    
    for target in valid_other_balls:
        P_target = np.array([target['x'], target['y']])
        radius = float(target.get('r', DEFAULT_BALL_RADIUS))
        
        for pocket in pockets:
            P_pocket = np.array([pocket['x'], pocket['y']])
            
            V_pocket_to_target = P_target - P_pocket
            dist = np.linalg.norm(V_pocket_to_target)
            if dist == 0: continue
            
            V_dir = V_pocket_to_target / dist
            P_ghost = P_target + V_dir * (2 * radius)
            
            angle = calculate_cut_angle(P_white, P_ghost, P_pocket)
            
            if angle < min_angle:
                min_angle = angle
                lines, ghost_data = calculate_shot_lines(white_ball, target, pocket, radius)
                
                best_shot = {
                    "target_ball": target,
                    "pocket": pocket,
                    "angle": angle,
                    "shot_lines": lines,
                    "ghost_ball": ghost_data
                }
                
    return best_shot

# --- DETEKCJA AI ---

def detect_all_balls(image_path, api_key, cue_ball_color="White", table_area=None):
    """
    Używa modelu YOLO z Roboflow do wykrywania bil na obrazie.
    
    Args:
        image_path: ścieżka do obrazu
        api_key: klucz API Roboflow
        cue_ball_color: kolor bili cue (domyślnie "White", może być np. "Red", "Yellow", itp.)
        table_area: opcjonalna lista punktów narożników obszaru stołu [{"x": x1, "y": y1}, ...]
                    Jeśli podana, detekcje poza tym obszarem będą ignorowane
    """
    logger.info(f"Używam modelu detekcji YOLO z Roboflow (confidence={ROBOFLOW_CONFIDENCE})...")
    logger.info(f"Szukam bili cue w kolorze: {cue_ball_color}")
    if table_area:
        logger.info(f"Filtrowanie detekcji w obszarze stołu: {len(table_area)} punktów")

    try:
        model = _get_roboflow_model(api_key)
        prediction = model.predict(image_path, confidence=ROBOFLOW_CONFIDENCE, overlap=ROBOFLOW_OVERLAP).json()
    except Exception as e:
        logger.error(f"Błąd Roboflow: {e}", exc_info=True)
        raise ValueError(f"Nie udało się połączyć z Roboflow lub przetworzyć obrazu: {e}")

    cue_ball = None
    other_balls = []
    total_detections = len(prediction.get('predictions', []))
    filtered_out = 0

    for box in prediction.get('predictions', []):
        ball_data = {
            "x": int(box['x']),
            "y": int(box['y']),
            "r": int((box['width'] + box['height']) / 4) 
        }

        # Filtrowanie po obszarze stołu (jeśli podano)
        if table_area and not is_point_inside_table_area(ball_data, table_area):
            filtered_out += 1
            continue

        # Sprawdzamy czy to bila cue (w wybranym kolorze)
        if box['class'] == cue_ball_color:
            if cue_ball is None or box['confidence'] > 0.5: 
                cue_ball = ball_data
        else:
            other_balls.append(ball_data)

    logger.info(f"Wykryto {total_detections} bil, odrzucono {filtered_out} spoza obszaru stołu")
    logger.info(f"Wykryto bilę cue ({cue_ball_color}): {cue_ball is not None}, inne bile: {len(other_balls)}")
    return cue_ball, other_balls

def calculate_manual_shot_lines(white_ball_point, target_ball_point, pocket_point):
    white_ball = {"x": white_ball_point['x'], "y": white_ball_point['y'], "r": DEFAULT_BALL_RADIUS}
    target_ball = {"x": target_ball_point['x'], "y": target_ball_point['y'], "r": DEFAULT_BALL_RADIUS}
    return calculate_shot_lines(white_ball, target_ball, pocket_point, DEFAULT_BALL_RADIUS)