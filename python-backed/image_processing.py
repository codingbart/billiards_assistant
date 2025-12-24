import numpy as np
import cv2
import logging
from color_detection import adjust_gamma, get_ball_color
from geometry import warp_perspective, transform_point_back, transform_point_forward, is_point_inside_table_area

logger = logging.getLogger(__name__)

DEFAULT_BALL_RADIUS = 18

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

