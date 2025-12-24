import numpy as np
import cv2

def order_points(pts):
    """Porządkuje punkty w kolejności: top-left, top-right, bottom-right, bottom-left."""
    rect = np.zeros((4, 2), dtype="float32")
    s = pts.sum(axis=1)
    rect[0] = pts[np.argmin(s)]
    rect[2] = pts[np.argmax(s)]
    diff = np.diff(pts, axis=1)
    rect[1] = pts[np.argmin(diff)]
    rect[3] = pts[np.argmax(diff)]
    return rect

def warp_perspective(image, corners):
    """
    Wykonuje transformację perspektywy na obrazie.
    Zwraca: warped_image, M (macierz transformacji), M_inv (macierz odwrotna)
    """
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
    """Transformuje punkt z przetworzonego obrazu z powrotem do oryginalnego."""
    pt = np.array([[[x, y]]], dtype="float32")
    dst = cv2.perspectiveTransform(pt, M_inv)
    return int(dst[0][0][0]), int(dst[0][0][1])

def transform_point_forward(x, y, M):
    """Transformuje punkt z oryginalnego obrazu do przetworzonego."""
    pt = np.array([[[x, y]]], dtype="float32")
    dst = cv2.perspectiveTransform(pt, M)
    return int(dst[0][0][0]), int(dst[0][0][1])

def is_point_inside_table_area(point, table_area):
    """Sprawdza czy punkt znajduje się wewnątrz obszaru stołu."""
    if not table_area or len(table_area) < 3:
        return True
    area_points = np.array([[p['x'], p['y']] for p in table_area], dtype=np.int32)
    hull = cv2.convexHull(area_points)
    dist = cv2.pointPolygonTest(hull, (float(point['x']), float(point['y'])), True)
    return dist >= 0.0

