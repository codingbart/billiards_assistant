from flask import Flask, request, jsonify
import os
import json
from werkzeug.utils import secure_filename
from config import logger, UPLOAD_FOLDER, allowed_file
from image_processing import detect_all_balls
from shot_calculation import find_best_shot

app = Flask(__name__)
app.config['UPLOAD_FOLDER'] = UPLOAD_FOLDER
app.config['MAX_CONTENT_LENGTH'] = 2 * 1024 * 1024  # 2 MB max

# 1. DETEKCJA (Zwraca listę bil)
@app.route('/detect', methods=['POST'])
def detect_endpoint():
    if 'file' not in request.files:
        return jsonify({"error": "Brak pliku"}), 400
    file = request.files['file']

    if file.filename == '':
        return jsonify({"error": "Brak nazwy pliku"}), 400

    if not allowed_file(file.filename):
        return jsonify({"error": "Nieobsługiwany format. Użyj JPG/PNG."}), 400

    table_area = None
    if 'table_area' in request.form:
        try:
            table_area = json.loads(request.form['table_area'])
        except Exception:
            table_area = None

    calibration_point = None
    if 'calibration_point' in request.form:
        try:
            calibration_point = json.loads(request.form['calibration_point'])
        except Exception:
            calibration_point = None

    filename = secure_filename(file.filename) or "temp.jpg"
    filepath = os.path.join(app.config['UPLOAD_FOLDER'], filename)
    file.save(filepath)

    try:
        # Szukamy WSZYSTKICH bil (cue_color bez znaczenia na tym etapie)
        _, _, all_detected = detect_all_balls(
            filepath, api_key=None, cue_ball_color="white",
            table_area=table_area, calibration_point=calibration_point
        )
        return jsonify({"balls": all_detected})
    except Exception as e:
        logger.error(f"Detect Error: {e}", exc_info=True)
        return jsonify({"error": str(e)}), 500
    finally:
        try:
            if os.path.exists(filepath):
                os.remove(filepath)
        except Exception as e:
            logger.warning(f"Nie udało się usunąć pliku tmp: {e}")

# 2. OBLICZENIA (Przyjmuje poprawione bile)
@app.route('/calculate', methods=['POST'])
def calculate_endpoint():
    try:
        data = request.json
        if not data:
            return jsonify({"error": "Brak danych JSON."}), 400

        balls = data.get('balls', [])
        pockets = data.get('pockets', [])
        cue_color = data.get('cue_ball_color', 'white').lower()
        table_area = data.get('table_area', [])

        # Minimalna walidacja
        if not isinstance(balls, list) or len(balls) < 2:
            return jsonify({"error": "Za mało bil."}), 400
        if not isinstance(pockets, list) or len(pockets) == 0:
            return jsonify({"error": "Brak łuz (pockets)."}), 400

        cue_ball = None
        other_balls = []

        for b in balls:
            if not isinstance(b, dict):
                continue
            if b.get('class', '').lower() == 'ignore':
                continue
            b['r'] = int(b.get('r', 15))
            # Normalizacja klasy (może przychodzić "White"/"white")
            cls = b.get('class', '')
            if isinstance(cls, str):
                cls_norm = cls.lower()
            else:
                cls_norm = ''

            if cls_norm == cue_color:
                if cue_ball is None:
                    cue_ball = b
                else:
                    other_balls.append(b)
            else:
                other_balls.append(b)

        if cue_ball is None:
            return jsonify({"error": f"Brak bili {cue_color}."}), 400

        best_shot = find_best_shot(cue_ball, other_balls, pockets, table_area=table_area)

        if best_shot is None:
            return jsonify({"error": "Brak dobrego strzału."}), 400

        return jsonify({"best_shot": best_shot})
    except Exception as e:
        logger.error(f"Calc Error: {e}", exc_info=True)
        return jsonify({"error": str(e)}), 500

if __name__ == '__main__':
    # debug=False na produkcji; host i port można konfigurować przez env
    app.run(host='0.0.0.0', port=int(os.getenv('PORT', 5001)), debug=True)
