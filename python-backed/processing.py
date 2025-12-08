import numpy as np
from roboflow import Roboflow
import json
import logging
import os
import cv2

logger = logging.getLogger(__name__)

DEFAULT_BALL_RADIUS = 18
ROBOFLOW_CONFIDENCE = int(os.getenv('ROBOFLOW_CONFIDENCE', '20'))
ROBOFLOW_OVERLAP = int(os.getenv('ROBOFLOW_OVERLAP', '30'))
ROBOFLOW_PROJECT = os.getenv('ROBOFLOW_PROJECT', 'billiarddet-kyjmh')
ROBOFLOW_VERSION = int(os.getenv('ROBOFLOW_VERSION', '3'))

_roboflow_model_cache = None

# --- MAPOWANIE KLAS ROBOFLOW (wg Twojego zrzutu) ---
# Klucze to kolory w aplikacji (lowercase), Wartości to klasy z Roboflow
COLOR_MAPPING = {
    # Bila biała
    "white":  ["white"],
    
    # Bile pełne i połówki przypisane do kolorów
    "yellow": ["n1", "n9"],   # 1 i 9
    "blue":   ["n2", "n10"],  # 2 i 10
    "red":    ["n3", "n11"],  # 3 i 11
    "purple": ["n4", "n12"],  # 4 i 12
    "orange": ["n5", "n13"],  # 5 i 13
    "green":  ["n6", "n14"],  # 6 i 14
    "brown":  ["n7", "n15"],  # 7 i 15
    "black":  ["n8"]          # 8
    
    # Klasę "Billiard" ignorujemy, bo to prawdopodobnie stół lub śmieci
}

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
    """Filtr oparty na łuzach - używany gdy nie ma zaznaczonego obszaru."""
    if len(pockets) < 3:
        return True
    
    pocket_points = np.array([[p['x'], p['y']] for p in pockets], dtype=np.int32)
    hull = cv2.convexHull(pocket_points)
    
    # Tolerancja -50px (dla band)
    dist = cv2.pointPolygonTest(hull, (float(point['x']), float(point['y'])), True)
    return dist >= -50.0

def calculate_cut_angle(white_pt, ghost_pt, pocket_pt):
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
    best_shot = None
    min_angle = 180.0
    
    if not white_ball or not other_balls or not pockets:
        return None
        
    valid_other_balls = []
    
    # 1. Priorytet: Filtrowanie obszarem (Table Area)
    if table_area and len(table_area) >= 3:
        valid_other_balls = [b for b in other_balls if is_point_inside_table_area(b, table_area)]
        logger.info(f"Filtrowanie obszarem (Target): {len(other_balls)} -> {len(valid_other_balls)}")
    
    # 2. Alternatywa: Filtrowanie łuzami (jeśli brak obszaru)
    elif len(pockets) >= 3:
        valid_other_balls = [b for b in other_balls if is_point_inside_table(b, pockets)]
        logger.info(f"Filtrowanie łuzami (Target): {len(other_balls)} -> {len(valid_other_balls)}")
    else:
        valid_other_balls = other_balls

    if not valid_other_balls:
        logger.warning("Brak bil do wbicia po filtracji.")
        return None
    
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

# (Zachowaj importy i mapowanie COLOR_MAPPING z poprzedniego kroku)
# ...

def is_point_inside_table_area(point, table_area):
    """
    Filtr oparty na RĘCZNYM OBSZARZE (Żółta ramka).
    Sprawdza czy cała bila (uwzględniając promień) jest wewnątrz obszaru.
    """
    if not table_area or len(table_area) < 3:
        return True
    
    area_points = np.array([[p['x'], p['y']] for p in table_area], dtype=np.int32)
    
    # Logowanie dla debugowania (tylko pierwsze kilka wywołań)
    if not hasattr(is_point_inside_table_area, '_logged'):
        logger.info(f"Obszar stołu: {len(table_area)} punktów")
        for i, p in enumerate(table_area):
            logger.info(f"  Punkt {i+1}: x={p.get('x')}, y={p.get('y')}")
        is_point_inside_table_area._logged = True
    
    hull = cv2.convexHull(area_points)
    
    # Pobierz promień bili (domyślnie DEFAULT_BALL_RADIUS jeśli nie podano)
    ball_radius = float(point.get('r', DEFAULT_BALL_RADIUS))
    
    # Sprawdź odległość środka bili od krawędzi obszaru
    # cv2.pointPolygonTest zwraca:
    # - dodatnią wartość: punkt wewnątrz (odległość od krawędzi)
    # - 0: punkt na krawędzi
    # - ujemną wartość: punkt poza obszarem (odległość od krawędzi)
    point_x = float(point['x'])
    point_y = float(point['y'])
    dist = cv2.pointPolygonTest(hull, (point_x, point_y), True)
    
    # Cała bila jest wewnątrz, jeśli środek jest w odległości >= promienia od krawędzi
    # Jeśli dist >= ball_radius, to cała bila jest wewnątrz obszaru
    result = dist >= ball_radius
    
    # Logowanie dla pierwszych kilku punktów
    if not hasattr(is_point_inside_table_area, '_point_count'):
        is_point_inside_table_area._point_count = 0
    if is_point_inside_table_area._point_count < 5:
        logger.info(f"Punkt ({point_x:.1f}, {point_y:.1f}), promień={ball_radius:.1f}, dist={dist:.1f}, wynik={result}")
        is_point_inside_table_area._point_count += 1
    
    return result
def detect_all_balls(image_path, api_key, cue_ball_color="White", table_area=None):
    logger.info(f"Detekcja YOLO... Szukam bili rozgrywającej: {cue_ball_color}")
    
    try:
        model = _get_roboflow_model(api_key)
        # Zmniejszyłem confidence do 10, żeby upewnić się, że model widzi wszystko
        # Filtracja obszarem i tak odrzuci śmieci.
        prediction = model.predict(image_path, confidence=10, overlap=ROBOFLOW_OVERLAP).json()
    except Exception as e:
        logger.error(f"Błąd Roboflow: {e}")
        raise ValueError(f"Błąd Roboflow: {e}")

    predictions = prediction.get('predictions', [])
    logger.info(f"Wykryto {len(predictions)} obiektów (przed filtracją)")
    
    # Logowanie wymiarów obrazu dla debugowania
    import cv2
    img_debug = cv2.imread(image_path)
    if img_debug is not None:
        h, w = img_debug.shape[:2]
        logger.info(f"Rozmiar obrazu na serwerze: {w}x{h} pikseli")

    cue_ball = None
    other_balls = []
    all_detected_balls = []  # Wszystkie wykryte bile (przed filtracją obszarem)
    
    target_color_lower = cue_ball_color.lower()
    # Pobierz listę klas (np. ["n3", "n11"] dla "red")
    accepted_classes = COLOR_MAPPING.get(target_color_lower, [target_color_lower])
    
    for box in predictions:
        cls_name = box['class'].lower() # np. "n1", "white"
        
        # Ignoruj klasę "Billiard"
        if cls_name == "billiard":
            continue
            
        ball_data = {
            "x": int(box['x']),
            "y": int(box['y']),
            "r": int((box['width'] + box['height']) / 4),
            "class": cls_name,
            "confidence": box['confidence']
        }
        
        # Zbierz wszystkie wykryte bile (przed filtracją obszarem) dla debugowania
        all_detected_balls.append({
            "x": ball_data["x"],
            "y": ball_data["y"],
            "r": ball_data["r"],
            "class": ball_data["class"],
            "confidence": ball_data["confidence"]
        })

        # KRYTYCZNY MOMENT: Filtracja obszarem
        # Jeśli zdefiniowano table_area, wyrzucamy wszystko co nie jest w środku
        if table_area:
            is_inside = is_point_inside_table_area(ball_data, table_area)
            if not is_inside:
                logger.info(f"Odrzucono {cls_name} na poz ({ball_data['x']},{ball_data['y']}) - poza obszarem")
                continue
            else:
                logger.debug(f"Zaakceptowano {cls_name} na poz ({ball_data['x']},{ball_data['y']}) - w obszarze")

        # Czy to nasza bila rozgrywająca?
        # Sprawdzamy czy wykryta klasa (np. "n3") jest na liście akceptowanych dla koloru "red")
        if cls_name in accepted_classes:
            if cue_ball is None or box['confidence'] > cue_ball.get('confidence', 0):
                if cue_ball is not None:
                    del cue_ball['confidence']
                    other_balls.append(cue_ball)
                cue_ball = ball_data
            else:
                other_balls.append(ball_data)
        else:
            other_balls.append(ball_data)
            
    if cue_ball and 'confidence' in cue_ball:
        del cue_ball['confidence']
        
    logger.info(f"Po filtracji: Cue={cue_ball is not None}, Other={len(other_balls)}")

    return cue_ball, other_balls, all_detected_balls