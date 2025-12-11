import numpy as np
import cv2
import logging

logger = logging.getLogger(__name__)

DEFAULT_BALL_RADIUS = 18

# --- ZAAWANSOWANE ZAKRESY KOLORÓW (HSV) ---
# Dostosowane do wykrywania "wyblakłych" kolorów w cieniu
COLOR_RANGES = {
    "white":  ([0, 0, 160], [180, 50, 255]),
    "yellow": ([20, 80, 80], [35, 255, 255]),
    "blue":   ([90, 80, 40], [130, 255, 255]), # Obniżone V i S
    "red":    ([0, 100, 80], [10, 255, 255]),
    "red2":   ([165, 100, 80], [180, 255, 255]),
    "purple": ([125, 40, 40], [165, 200, 200]), # Fiolet jest ciemny, niższe V
    "orange": ([10, 100, 80], [25, 255, 255]),
    "green":  ([35, 60, 60], [88, 255, 255]),
    "brown":  ([0, 40, 30], [20, 200, 160]),    # Brąz to bardzo ciemny pomarańcz
    "black":  ([0, 0, 0], [180, 255, 50])
}

def adjust_gamma(image, gamma=1.5):
    """
    Rozjaśnia cienie na obrazie.
    gamma > 1.0 rozjaśnia ciemne obszary.
    """
    invGamma = 1.0 / gamma
    table = np.array([((i / 255.0) ** invGamma) * 255 for i in np.arange(0, 256)]).astype("uint8")
    return cv2.LUT(image, table)

def get_ball_color(roi_hsv):
    """
    Inteligentne rozpoznawanie koloru z uwzględnieniem cieni.
    """
    # Średnia z obszaru
    mean_color = cv2.mean(roi_hsv)[:3]
    h, s, v = mean_color
    
    # --- LOGIKA DLA CIENI ---
    
    # 1. Bardzo jasne = Biała
    if s < 60 and v > 130: return "white"
    
    # 2. Bardzo ciemne (ale nie kolorowe) = Czarna
    if v < 50: return "black"
    
    # 3. Kolory (kolejność ma znaczenie!)
    
    # Czerwony (specyficzny, bo jest na początku i końcu skali)
    if (0 <= h <= 10) or (170 <= h <= 180):
        if s > 70: return "red"
        else: return "brown" # Mało nasycony czerwony to brąz
        
    # Pomarańczowy vs Brązowy
    if 11 <= h <= 25:
        if v > 140: return "orange" # Jasny = pomarańcz
        else: return "brown"        # Ciemny = brąz
        
    if 26 <= h <= 35: return "yellow"
    if 36 <= h <= 88: return "green"
    
    # Niebieski
    if 89 <= h <= 135: return "blue"
    
    # Fioletowy (często mylony z ciemnym niebieskim lub czarnym)
    if 136 <= h <= 170: return "purple"
    
    # Fallback dla bardzo ciemnych kolorów w cieniu
    if v < 90:
        if 130 <= h <= 170: return "purple"
        if 0 <= h <= 25: return "brown"
        
    return "unknown"

# --- TRANSFORMACJA I GEOMETRIA (Bez zmian) ---

def order_points(pts):
    rect = np.zeros((4, 2), dtype="float32")
    s = pts.sum(axis=1)
    rect[0] = pts[np.argmin(s)]
    rect[2] = pts[np.argmax(s)]
    diff = np.diff(pts, axis=1)
    rect[1] = pts[np.argmin(diff)]
    rect[3] = pts[np.argmax(diff)]
    return rect

def warp_perspective(image, corners):
    rect = order_points(np.array([[p['x'], p['y']] for p in corners], dtype="float32"))
    (tl, tr, br, bl) = rect
    widthA = np.sqrt(((br[0] - bl[0]) ** 2) + ((br[1] - bl[1]) ** 2))
    widthB = np.sqrt(((tr[0] - tl[0]) ** 2) + ((tr[1] - tl[1]) ** 2))
    maxWidth = max(int(widthA), int(widthB))
    heightA = np.sqrt(((tr[0] - br[0]) ** 2) + ((tr[1] - br[1]) ** 2))
    heightB = np.sqrt(((tl[0] - bl[0]) ** 2) + ((tl[1] - bl[1]) ** 2))
    maxHeight = max(int(heightA), int(heightB))
    dst = np.array([[0, 0], [maxWidth - 1, 0], [maxWidth - 1, maxHeight - 1], [0, maxHeight - 1]], dtype="float32")
    M = cv2.getPerspectiveTransform(rect, dst)
    M_inv = cv2.getPerspectiveTransform(dst, rect)
    warped = cv2.warpPerspective(image, M, (maxWidth, maxHeight))
    return warped, M, M_inv

def transform_point_back(x, y, M_inv):
    pt = np.array([[[x, y]]], dtype="float32")
    dst = cv2.perspectiveTransform(pt, M_inv)
    return int(dst[0][0][0]), int(dst[0][0][1])

# --- GŁÓWNA DETEKCJA ---

def detect_all_balls(image_path, api_key=None, cue_ball_color="White", table_area=None):
    logger.info(f"Detekcja OpenCV... Szukam: {cue_ball_color}")
    img = cv2.imread(image_path)
    if img is None: raise ValueError("Błąd odczytu")

    if table_area and len(table_area) == 4:
        processing_img, M, M_inv = warp_perspective(img, table_area)
    else:
        processing_img = img
        M_inv = None

    # Preprocessing
    gray = cv2.cvtColor(processing_img, cv2.COLOR_BGR2GRAY)
    
    # MULTI-PASS: Próbujemy różnych parametrów, jeśli nic nie znajdziemy
    # (param2: próg wykrywania - im mniejszy, tym więcej kółek)
    circle_params = [
        {"param2": 25, "minDist": 15}, # Standardowe
        {"param2": 15, "minDist": 15}, # Agresywne
        {"param2": 12, "minDist": 10}, # Bardzo agresywne
    ]
    
    circles = None
    for params in circle_params:
        gray_blurred = cv2.GaussianBlur(gray, (9, 9), 2)
        circles = cv2.HoughCircles(
            gray_blurred, cv2.HOUGH_GRADIENT, dp=1, 
            minDist=params["minDist"], param1=40, param2=params["param2"], 
            minRadius=8, maxRadius=70
        )
        if circles is not None and len(circles[0]) > 0:
            logger.info(f"Znaleziono okręgi przy parametrach: {params}")
            break
            
    cue_ball = None; other_balls = []; all_detected_balls = []
    target_color_lower = cue_ball_color.lower()
    hsv_img = cv2.cvtColor(processing_img, cv2.COLOR_BGR2HSV)

    if circles is not None:
        circles = np.round(circles[0, :]).astype("int")
        for (x, y, r) in circles:
            roi_size = int(r / 2.5)
            y1, y2 = max(0, y-roi_size), min(processing_img.shape[0], y+roi_size)
            x1, x2 = max(0, x-roi_size), min(processing_img.shape[1], x+roi_size)
            detected_color = "unknown"
            if y2 > y1 and x2 > x1:
                detected_color = get_ball_color(hsv_img[y1:y2, x1:x2])

            if M_inv is not None:
                orig_x, orig_y = transform_point_back(x, y, M_inv)
                scale_check_x, _ = transform_point_back(x + r, y, M_inv)
                orig_r = abs(scale_check_x - orig_x)
            else:
                orig_x, orig_y, orig_r = x, y, r

            ball_data = { "x": int(orig_x), "y": int(orig_y), "r": int(orig_r), "class": detected_color, "confidence": 1.0 }
            all_detected_balls.append(ball_data)
            
            if detected_color == target_color_lower:
                if cue_ball is None: cue_ball = ball_data
                else: other_balls.append(ball_data)
            else: other_balls.append(ball_data)

    return cue_ball, other_balls, all_detected_balls
# --- POZOSTAŁE FUNKCJE (Bez zmian) ---

def is_point_inside_table_area(point, table_area):
    if not table_area or len(table_area) < 3: return True
    area_points = np.array([[p['x'], p['y']] for p in table_area], dtype=np.int32)
    dist = cv2.pointPolygonTest(cv2.convexHull(area_points), (float(point['x']), float(point['y'])), True)
    return dist >= 0.0

def calculate_cut_angle(white_pt, ghost_pt, pocket_pt):
    v_shot = np.array([ghost_pt[0] - white_pt[0], ghost_pt[1] - white_pt[1]])
    v_pot = np.array([pocket_pt[0] - ghost_pt[0], pocket_pt[1] - ghost_pt[1]])
    len_shot = np.linalg.norm(v_shot); len_pot = np.linalg.norm(v_pot)
    if len_shot == 0 or len_pot == 0: return 180.0 
    cos_angle = np.dot(v_shot, v_pot) / (len_shot * len_pot)
    return np.degrees(np.arccos(np.clip(cos_angle, -1.0, 1.0)))

def calculate_shot_lines(white_ball, target_ball, pocket, ball_radius=None):
    if ball_radius is None: ball_radius = DEFAULT_BALL_RADIUS
    P_pocket = np.array([pocket['x'], pocket['y']])
    P_target = np.array([target_ball['x'], target_ball['y']])
    P_white = np.array([white_ball['x'], white_ball['y']])
    V_unit = (P_target - P_pocket) / (np.linalg.norm(P_target - P_pocket) + 1e-6)
    P_ghost = P_target + V_unit * (2 * float(ball_radius))
    
    return [
        { "start": {"x": int(P_target[0]), "y": int(P_target[1])}, "end": {"x": int(P_pocket[0]), "y": int(P_pocket[1])} },
        { "start": {"x": int(P_white[0]), "y": int(P_white[1])}, "end": {"x": int(P_ghost[0]), "y": int(P_ghost[1])} }
    ], { "center": {"x": int(P_ghost[0]), "y": int(P_ghost[1])}, "radius": int(ball_radius) }

def find_best_shot(white_ball, other_balls, pockets, table_area=None):
    if not white_ball or not other_balls or not pockets: return None
    best_shot = None; min_angle = 180.0
    P_white = np.array([white_ball['x'], white_ball['y']])
    
    for target in other_balls:
        P_target = np.array([target['x'], target['y']])
        radius = float(target.get('r', DEFAULT_BALL_RADIUS))
        for pocket in pockets:
            P_pocket = np.array([pocket['x'], pocket['y']])
            angle = calculate_cut_angle(P_white, P_target + (P_target - P_pocket)/np.linalg.norm(P_target-P_pocket) * 2 * radius, P_pocket)
            if angle < min_angle:
                min_angle = angle
                lines, ghost = calculate_shot_lines(white_ball, target, pocket, radius)
                best_shot = {"target_ball": target, "pocket": pocket, "angle": angle, "shot_lines": lines, "ghost_ball": ghost}
    return best_shot