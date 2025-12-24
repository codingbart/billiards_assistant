import cv2
import numpy as np

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
    """Korekta gamma dla lepszego kontrastu."""
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

