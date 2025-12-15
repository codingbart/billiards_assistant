import numpy as np
import cv2
import logging

logger = logging.getLogger(__name__)

DEFAULT_BALL_RADIUS = 18

# --- KOLORY (zakresy HSV) ---
COLOR_RANGES = {
    "white":  ([0, 0, 160], [180, 50, 255]),
    "yellow": ([20, 80, 80], [35, 255, 255]),
    "blue":   ([90, 80, 40], [130, 255, 255]),
    "red":    ([0, 100, 80], [10, 255, 255]),
    "red2":   ([165, 100, 80], [180, 255, 255]),
    "purple": ([125, 40, 40], [165, 200, 200]),
    "orange": ([10, 100, 80], [25, 255, 255]),
    "green":  ([35, 60, 60], [88, 255, 255]),
    "brown":  ([0, 40, 30], [20, 200, 160]),
    "black":  ([0, 0, 0], [180, 255, 50])
}

def adjust_gamma(image, gamma=1.5):
    invGamma = 1.0 / gamma
    table = np.array([((i / 255.0) ** invGamma) * 255 for i in np.arange(0, 256)]).astype("uint8")
    return cv2.LUT(image, table)

def get_ball_color(roi_hsv):
    """
    Zwraca kolor (lowercase). Opiera się o średnie HSV w ROI.
    """
    mean_color = cv2.mean(roi_hsv)[:3]
    h, s, v = mean_color

    # prosty regułowy klasyfikator
    if s < 60 and v > 130:
        return "white"
    if v < 50:
        return "black"

    # czerwony przy 0 lub przy 180
    if (0 <= h <= 10) or (170 <= h <= 180):
        if s > 70:
            return "red"
        else:
            return "brown"
    if 11 <= h <= 25:
        if v > 140:
            return "orange"
        else:
            return "brown"
    if 26 <= h <= 35:
        return "yellow"
    if 36 <= h <= 88:
        return "green"
    if 89 <= h <= 135:
        return "blue"
    if 136 <= h <= 170:
        return "purple"

    # fallbacky uwzględniające niską jasność
    if v < 90:
        if 130 <= h <= 170:
            return "purple"
        if 0 <= h <= 25:
            return "brown"

    return "unknown"

def filter_overlapping_circles(circles, min_dist=25):
    """
    Usuwa okręgi, które są zbyt blisko siebie (duplikaty).
    Zostawia największe (najbardziej pewne).
    circles: array-like of [x, y, r]
    Zwraca numpy array of circles.
    """
    if circles is None or len(circles) == 0:
        return np.array([])

    circles = sorted(circles, key=lambda c: c[2], reverse=True)
    filtered = []

    for c in circles:
        x, y, r = c
        is_duplicate = False
        for f in filtered:
            fx, fy, fr = f
            dist = np.hypot(x - fx, y - fy)
            if dist < min_dist:
                is_duplicate = True
                break
        if not is_duplicate:
            filtered.append([int(x), int(y), int(r)])
    return np.array(filtered)

# GEOMETRIA I WARP
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
    widthA = np.hypot(br[0] - bl[0], br[1] - bl[1])
    widthB = np.hypot(tr[0] - tl[0], tr[1] - tl[1])
    maxWidth = max(int(widthA), int(widthB))
    heightA = np.hypot(tr[0] - br[0], tr[1] - br[1])
    heightB = np.hypot(tl[0] - bl[0], tl[1] - bl[1])
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

def transform_point_forward(x, y, M):
    pt = np.array([[[x, y]]], dtype="float32")
    dst = cv2.perspectiveTransform(pt, M)
    return int(dst[0][0][0]), int(dst[0][0][1])

# --- GŁÓWNA DETEKCJA ---

def is_point_inside_table_area(point, table_area):
    if not table_area or len(table_area) < 3:
        return True
    area_points = np.array([[p['x'], p['y']] for p in table_area], dtype=np.int32)
    hull = cv2.convexHull(area_points)
    dist = cv2.pointPolygonTest(hull, (float(point['x']), float(point['y'])), True)
    return dist >= 0.0

def detect_all_balls(image_path, api_key=None, cue_ball_color="White", table_area=None, calibration_point=None):
    """
    Zwraca: cue_ball (dict or None), other_balls (list of dicts), all_detected_balls (list of dicts)
    Każda bila: {"x": int, "y": int, "r": int, "class": "Red", "confidence": 0.9}
    """
    logger.info(f"Detekcja OpenCV... Szukam: {cue_ball_color}")

    img = cv2.imread(image_path)
    if img is None:
        raise ValueError("Błąd odczytu pliku")

    # Warp jeśli podano table_area
    if table_area and len(table_area) == 4:
        processing_img, M, M_inv = warp_perspective(img, table_area)
        calib_hsv = None
        if calibration_point:
            try:
                calib_x, calib_y = transform_point_forward(calibration_point['x'], calibration_point['y'], M)
                calib_x = max(0, min(calib_x, processing_img.shape[1] - 1))
                calib_y = max(0, min(calib_y, processing_img.shape[0] - 1))
                roi_c = processing_img[max(0, calib_y - 2):min(processing_img.shape[0], calib_y + 3),
                                       max(0, calib_x - 2):min(processing_img.shape[1], calib_x + 3)]
                if roi_c.size > 0:
                    roi_hsv = cv2.cvtColor(roi_c, cv2.COLOR_BGR2HSV)
                    calib_hsv = cv2.mean(roi_hsv)[:3]
                    logger.info(f"Skalibrowano tło (HSV): {calib_hsv}")
            except Exception as e:
                logger.warning(f"Problem z kalibracją: {e}")
    else:
        processing_img = img
        M_inv = None
        M = None
        calib_hsv = None

    # Preprocessing
    enhanced_color_img = adjust_gamma(processing_img, gamma=1.6)
    gray = cv2.cvtColor(processing_img, cv2.COLOR_BGR2GRAY)
    clahe = cv2.createCLAHE(clipLimit=3.0, tileGridSize=(8, 8))
    gray_enhanced = clahe.apply(gray)
    gray_blurred = cv2.GaussianBlur(gray_enhanced, (9, 9), 2)

    # Hough params (różne czułości)
    circle_params = [
        {"param2": 22, "minDist": 25},
        {"param2": 18, "minDist": 25},
        {"param2": 15, "minDist": 20},
    ]

    circles = None
    for params in circle_params:
        circles_found = cv2.HoughCircles(
            gray_blurred, cv2.HOUGH_GRADIENT, dp=1,
            minDist=params["minDist"],
            param1=40,
            param2=params["param2"],
            minRadius=8, maxRadius=70
        )
        if circles_found is not None and len(circles_found[0]) > 0:
            circles = np.round(circles_found[0, :]).astype("int")
            logger.info(f"Znaleziono okręgi przy param: {params}")
            break

    # Fallback: jeśli Hough nic nie znalazł -> kontury + minEnclosingCircle
    if circles is None:
        logger.info("Fallback: używam adaptiveThreshold + kontury")
        circles = []
        try:
            thresh = cv2.adaptiveThreshold(gray_enhanced, 255, cv2.ADAPTIVE_THRESH_MEAN_C,
                                           cv2.THRESH_BINARY_INV, 11, 2)
            contours, _ = cv2.findContours(thresh, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
            for cnt in contours:
                (x, y), r = cv2.minEnclosingCircle(cnt)
                if 8 < r < 80:
                    circles.append([int(x), int(y), int(r)])
            if len(circles) == 0:
                circles = None
            else:
                circles = np.array(circles, dtype=int)
        except Exception as e:
            logger.warning(f"Fallback error: {e}")
            circles = None

    cue_ball = None
    other_balls = []
    all_detected_balls = []
    target_color_lower = cue_ball_color.lower()
    hsv_img = cv2.cvtColor(enhanced_color_img, cv2.COLOR_BGR2HSV)

    if circles is not None and len(circles) > 0:
        # Usuń dublujące się okręgi
        raw_circles = circles
        clean_circles = filter_overlapping_circles(raw_circles, min_dist=20)
        logger.info(f"Po filtracji duplikatów: {len(raw_circles)} -> {len(clean_circles)}")

        for (x, y, r) in clean_circles:
            # filtry prostoty
            if r < 8 or r > 80:
                continue

            roi_size = int(max(6, r / 2.5))
            y1, y2 = max(0, y - roi_size), min(processing_img.shape[0], y + roi_size)
            x1, x2 = max(0, x - roi_size), min(processing_img.shape[1], x + roi_size)

            detected_color = "unknown"
            is_background = False

            if y2 > y1 and x2 > x1:
                roi = hsv_img[y1:y2, x1:x2]
                if roi.size == 0:
                    continue
                ball_mean_hsv = cv2.mean(roi)[:3]

                # Filtracja tła względem skalibrowanego HSV (jeśli podano)
                if calib_hsv is not None:
                    diff_h = abs(ball_mean_hsv[0] - calib_hsv[0])
                    if diff_h > 90:
                        diff_h = 180 - diff_h
                    if diff_h <= 15 and abs(ball_mean_hsv[1] - calib_hsv[1]) <= 80 and abs(ball_mean_hsv[2] - calib_hsv[2]) <= 80:
                        is_background = True

                # filtr cieni: niska jasność i niskie nasycenie
                if not is_background:
                    if ball_mean_hsv[2] < 40 and ball_mean_hsv[1] < 60:
                        # prawdopodobny cień - pomijamy
                        is_background = True

                if not is_background:
                    detected_color = get_ball_color(roi)

            if is_background:
                continue

            # Powrót do współrzędnych oryginalnego obrazu jeśli był warp
            if M_inv is not None:
                try:
                    orig_x, orig_y = transform_point_back(x, y, M_inv)
                    scale_check_x, _ = transform_point_back(x + r, y, M_inv)
                    orig_r = abs(scale_check_x - orig_x)
                    if orig_r <= 0:
                        orig_r = r
                except Exception as e:
                    logger.debug(f"Transform back error: {e}")
                    orig_x, orig_y, orig_r = int(x), int(y), int(r)
            else:
                orig_x, orig_y, orig_r = int(x), int(y), int(r)

            # Sprawdź czy punkt jest w obszarze stołu (jeśli podano)
            if table_area and not is_point_inside_table_area({"x": orig_x, "y": orig_y}, table_area):
                logger.debug(f"Bila poza stołem: {(orig_x, orig_y)}, ignoruję")
                continue

            # Confidence prosty: większy promień = większe prawdopodobieństwo
            conf = max(0.25, min(1.0, orig_r / 70.0))

            # normalizacja nazwy klasy (capitalize) - ułatwia front-end (Swift oczekuje np. "White")
            detected_color_normalized = detected_color.capitalize() if isinstance(detected_color, str) else "Unknown"

            ball_data = {
                "x": int(orig_x),
                "y": int(orig_y),
                "r": int(max(4, orig_r)),
                "class": detected_color_normalized,
                "confidence": float(conf)
            }
            all_detected_balls.append(ball_data)

            # rozdzielenie cue ball / others
            if detected_color.lower() == target_color_lower:
                if cue_ball is None:
                    cue_ball = ball_data
                else:
                    other_balls.append(ball_data)
            else:
                other_balls.append(ball_data)

    # Sortowanie opcjonalne po pewności/promieniu
    all_detected_balls = sorted(all_detected_balls, key=lambda b: b['confidence'], reverse=True)

    return cue_ball, other_balls, all_detected_balls

# --- OBLICZENIA STRZAŁU ---

def calculate_cut_angle(white_pt, ghost_pt, pocket_pt):
    v_shot = np.array([ghost_pt[0] - white_pt[0], ghost_pt[1] - white_pt[1]], dtype=float)
    v_pot = np.array([pocket_pt[0] - ghost_pt[0], pocket_pt[1] - ghost_pt[1]], dtype=float)
    len_shot = np.linalg.norm(v_shot)
    len_pot = np.linalg.norm(v_pot)
    if len_shot == 0 or len_pot == 0:
        return 180.0
    cos_angle = np.dot(v_shot, v_pot) / (len_shot * len_pot)
    return float(np.degrees(np.arccos(np.clip(cos_angle, -1.0, 1.0))))

def calculate_shot_lines(white_ball, target_ball, pocket, ball_radius=None):
    if ball_radius is None:
        ball_radius = DEFAULT_BALL_RADIUS
    P_pocket = np.array([pocket['x'], pocket['y']], dtype=float)
    P_target = np.array([target_ball['x'], target_ball['y']], dtype=float)
    P_white = np.array([white_ball['x'], white_ball['y']], dtype=float)
    V = P_target - P_pocket
    normV = np.linalg.norm(V)
    if normV == 0:
        V_unit = np.array([0.0, 0.0])
    else:
        V_unit = V / normV
    P_ghost = P_target + V_unit * (2.0 * float(ball_radius))
    lines = [
        {"start": {"x": int(P_target[0]), "y": int(P_target[1])}, "end": {"x": int(P_pocket[0]), "y": int(P_pocket[1])}},
        {"start": {"x": int(P_white[0]), "y": int(P_white[1])}, "end": {"x": int(P_ghost[0]), "y": int(P_ghost[1])}}
    ]
    ghost = {"center": {"x": int(P_ghost[0]), "y": int(P_ghost[1])}, "radius": int(ball_radius)}
    return lines, ghost

def find_best_shot(white_ball, other_balls, pockets, table_area=None):
    if not white_ball or not other_balls or not pockets:
        return None
    best_shot = None
    min_angle = 180.0
    P_white = np.array([white_ball['x'], white_ball['y']], dtype=float)
    for target in other_balls:
        P_target = np.array([target['x'], target['y']], dtype=float)
        radius = float(target.get('r', DEFAULT_BALL_RADIUS))

        # Jeśli target poza stołem pomiń
        if table_area and not is_point_inside_table_area(target, table_area):
            continue

        # Jeśli target bardzo blisko białej => omijamy (nakładanie)
        if np.linalg.norm(P_white - P_target) < (white_ball.get('r', DEFAULT_BALL_RADIUS) + radius) * 0.6:
            continue

        for pocket in pockets:
            P_pocket = np.array([pocket['x'], pocket['y']], dtype=float)
            # Bezpieczna normalizacja kierunku
            V = P_target - P_pocket
            normV = np.linalg.norm(V)
            if normV == 0:
                continue
            # Ghost point (bezpiecznie)
            V_unit = V / normV
            P_ghost = P_target + V_unit * (2.0 * radius)

            angle = calculate_cut_angle(P_white, P_ghost, P_pocket)
            # Preferuj mniejsze kąty
            if angle < min_angle:
                min_angle = angle
                lines, ghost = calculate_shot_lines(white_ball, target, pocket, radius)
                best_shot = {"target_ball": target, "pocket": pocket, "angle": float(angle), "shot_lines": lines, "ghost_ball": ghost}
    return best_shot
