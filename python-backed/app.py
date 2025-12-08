from flask import Flask, request, jsonify
import os
import json
import logging
import secrets
from werkzeug.utils import secure_filename
from dotenv import load_dotenv
from processing import detect_all_balls, find_best_shot

load_dotenv()

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

ROBOFLOW_API_KEY = os.environ.get("ROBOFLOW_API_KEY")

app = Flask(__name__)
UPLOAD_FOLDER = 'static/uploads/'
app.config['UPLOAD_FOLDER'] = UPLOAD_FOLDER
os.makedirs(UPLOAD_FOLDER, exist_ok=True)

@app.route('/analyze_best_shot', methods=['POST'])
def analyze_best_shot():
    if not ROBOFLOW_API_KEY:
        return jsonify({"error": "Brak klucza API Roboflow"}), 500

    if 'file' not in request.files:
        return jsonify({"error": "Brak pliku"}), 400
    
    file = request.files['file']
    
    # 1. Odbiór Łuz
    if 'pockets' not in request.form:
        return jsonify({"error": "Musisz zaznaczyć łuzy!"}), 400
        
    try:
        pockets = json.loads(request.form['pockets'])
    except Exception as e:
        logger.error(f"Błąd parsowania pockets: {e}")
        return jsonify({"error": "Błąd formatu łuz"}), 400

    # 2. Odbiór Obszaru Stołu (Kluczowe dla Twojego problemu)
    table_area = None
    if 'table_area' in request.form:
        try:
            raw_area = request.form['table_area']
            logger.info(f"Otrzymano table_area (raw): {raw_area}") # Podgląd danych
            table_area = json.loads(raw_area)
            logger.info(f"Pomyślnie sparsowano table_area: {len(table_area)} punktów")
            # Logowanie współrzędnych obszaru dla debugowania
            if table_area:
                for i, point in enumerate(table_area):
                    logger.info(f"  Punkt {i+1}: x={point.get('x')}, y={point.get('y')}")
        except Exception as e:
            logger.error(f"KRYTYCZNY BŁĄD parsowania table_area: {e}")
            # Nie ustawiamy table_area na None po cichu - logujemy błąd!
            table_area = None
    else:
        logger.info("Brak parametru table_area w żądaniu")

    cue_ball_color = request.form.get('cue_ball_color', 'Red') # Domyślnie Red

    # Zapisz plik
    filename = secure_filename(file.filename) or "temp.jpg"
    filepath = os.path.join(app.config['UPLOAD_FOLDER'], filename)
    file.save(filepath)
    
    try:
        # Logowanie wymiarów obrazka dla sprawdzenia skali
        import cv2
        img_check = cv2.imread(filepath)
        if img_check is not None:
            h, w = img_check.shape[:2]
            logger.info(f"Otrzymano obraz o wymiarach: {w}x{h}")
            # Tutaj zobaczysz, czy wymiary pasują do współrzędnych table_area!

        # 1. DETEKCJA AI
        cue_ball, other_balls, all_detected_balls = detect_all_balls(
            filepath, 
            ROBOFLOW_API_KEY,
            cue_ball_color=cue_ball_color,
            table_area=table_area
        )
        
        if cue_ball is None:
            return jsonify({"error": f"Nie widzę bili cue ({cue_ball_color})."}), 500
            
        if not other_balls:
            return jsonify({"error": f"Widzę bilę cue, ale nie widzę innych bil w zaznaczonym obszarze."}), 500
            
        # 2. OBLICZANIE
        best_shot = find_best_shot(cue_ball, other_balls, pockets, table_area=table_area)
        
        if best_shot is None:
             return jsonify({"error": "Nie znalazłem strzału (może kąt jest zbyt trudny?)"}), 500
             
        return jsonify({
            "white_ball": cue_ball,
            "other_balls": other_balls,
            "best_shot": best_shot,
            "all_detected_balls": all_detected_balls  # Wszystkie wykryte bile (przed filtracją obszarem)
        })
        
    except Exception as e:
        logger.error(f"Błąd aplikacji: {e}", exc_info=True)
        return jsonify({"error": str(e)}), 500
    finally:
        if os.path.exists(filepath):
            os.remove(filepath)

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5001, debug=True)