from flask import Flask, request, jsonify
import os
import json
import logging
from werkzeug.utils import secure_filename
from dotenv import load_dotenv
from processing import detect_all_balls, find_best_shot

load_dotenv()

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = Flask(__name__)
UPLOAD_FOLDER = 'static/uploads/'
app.config['UPLOAD_FOLDER'] = UPLOAD_FOLDER
os.makedirs(UPLOAD_FOLDER, exist_ok=True)

# --- ENDPOINT 1: TYLKO DETEKCJA ---
@app.route('/detect', methods=['POST'])
def detect_endpoint():
    if 'file' not in request.files:
        return jsonify({"error": "Brak pliku"}), 400
    
    file = request.files['file']
    
    # Obszar stołu (opcjonalny, do filtrowania śmieci)
    table_area = None
    if 'table_area' in request.form:
        try:
            table_area = json.loads(request.form['table_area'])
        except:
            logger.warning("Błąd parsowania obszaru")

    # Zapisz plik
    filename = secure_filename(file.filename) or "temp.jpg"
    filepath = os.path.join(app.config['UPLOAD_FOLDER'], filename)
    file.save(filepath)
    
    try:
        # Uruchamiamy detekcję. Kolor Cue nie ma tu znaczenia, szukamy wszystkiego.
        # Funkcja detect_all_balls zwraca (cue, other, all_detected). Interesuje nas to trzecie.
        _, _, all_detected = detect_all_balls(
            filepath, 
            api_key=None, 
            cue_ball_color="white", 
            table_area=table_area
        )
        
        # Zwracamy surową listę bil do edycji na telefonie
        return jsonify({
            "balls": all_detected
        })
        
    except Exception as e:
        logger.error(f"Błąd detekcji: {e}", exc_info=True)
        return jsonify({"error": str(e)}), 500
    finally:
        if os.path.exists(filepath):
            os.remove(filepath)

# --- ENDPOINT 2: OBLICZENIA (BEZ ZDJĘCIA) ---
@app.route('/calculate', methods=['POST'])
def calculate_endpoint():
    try:
        data = request.json
        if not data:
            return jsonify({"error": "Brak danych JSON"}), 400
            
        balls = data.get('balls', [])      # Lista bil poprawiona przez użytkownika
        pockets = data.get('pockets', [])
        cue_color = data.get('cue_ball_color', 'white').lower()
        table_area = data.get('table_area', [])
        
        if len(balls) < 2:
            return jsonify({"error": "Za mało bil na stole, by wykonać strzał."}), 400
            
        # Segregacja bil na podstawie kolorów wybranych przez użytkownika
        cue_ball = None
        other_balls = []
        
        for b in balls:
            # Ignorujemy bile oznaczone jako "ignore" (np. kreda wykryta jako bila)
            if b.get('class') == 'ignore':
                continue
                
            # Upewniamy się, że promień jest intem
            b['r'] = int(b.get('r', 15))
            
            if b.get('class', '').lower() == cue_color:
                if cue_ball is None:
                    cue_ball = b
                else:
                    # Jeśli jest druga biała (rzadkie), traktujemy jako przeszkodę/cel
                    other_balls.append(b)
            else:
                other_balls.append(b)
        
        if cue_ball is None:
            return jsonify({"error": f"Nie zaznaczono bili rozgrywającej ({cue_color}). Kliknij na bilę, by zmienić jej kolor."}), 400
            
        # Obliczenia fizyczne
        best_shot = find_best_shot(cue_ball, other_balls, pockets, table_area=table_area)
        
        if best_shot is None:
            return jsonify({"error": "Nie znaleziono łatwego strzału (kąt zbyt ostry lub brak bil)."}), 400
            
        return jsonify({
            "best_shot": best_shot
        })

    except Exception as e:
        logger.error(f"Błąd obliczeń: {e}", exc_info=True)
        return jsonify({"error": str(e)}), 500

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5001, debug=True)