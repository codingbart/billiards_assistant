import numpy as np
import logging
from geometry import is_point_inside_table_area

logger = logging.getLogger(__name__)

DEFAULT_BALL_RADIUS = 18

def calculate_cut_angle(white_pt, ghost_pt, pocket_pt):
    """Oblicza kąt cięcia między białą bilą, ghost ball i łuzą."""
    v_shot = np.array([ghost_pt[0] - white_pt[0], ghost_pt[1] - white_pt[1]], dtype=float)
    v_pot = np.array([pocket_pt[0] - ghost_pt[0], pocket_pt[1] - ghost_pt[1]], dtype=float)
    len_shot = np.linalg.norm(v_shot)
    len_pot = np.linalg.norm(v_pot)
    if len_shot == 0 or len_pot == 0:
        return 180.0
    cos_angle = np.dot(v_shot, v_pot) / (len_shot * len_pot)
    return float(np.degrees(np.arccos(np.clip(cos_angle, -1.0, 1.0))))

def calculate_shot_lines(white_ball, target_ball, pocket, ball_radius=None):
    """Oblicza linie strzału i pozycję ghost ball."""
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
    """
    Znajduje najlepszy strzał dla białej bili.
    Zwraca dict z informacjami o najlepszym strzale lub None.
    """
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

