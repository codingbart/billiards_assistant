from flask import Flask, request, jsonify
import os
import json
import logging
import secrets
from werkzeug.utils import secure_filename
from dotenv import load_dotenv
from processing import detect_all_balls, find_best_shot

load_dotenv()

# Konfiguracja logowania
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

ROBOFLOW_API_KEY = os.environ.get("ROBOFLOW_API_KEY")

app = Flask(__name__)
UPLOAD_FOLDER = 'static/uploads/'
app.config['UPLOAD_FOLDER'] = UPLOAD_FOLDER
os.makedirs(UPLOAD_FOLDER, exist_ok=True)

@app.route('/analyze_best_shot', methods=['POST'])
def analyze_best_shot():
    """
    1. Odbiera zdjęcie i listę łuz.
    2. Wykrywa wszystkie bile (AI).
    3. Znajduje matematycznie najlepszy strzał.
    
    Opcjonalne parametry:
    - cue_ball_color: kolor bili cue (domyślnie "White", może być np. "Red", "Yellow")
    - table_area: JSON z listą punktów narożników obszaru stołu [{"x": x1, "y": y1}, ...]
    """
    if not ROBOFLOW_API_KEY:
        return jsonify({"error": "Brak klucza API Roboflow"}), 500

    if 'file' not in request.files:
        return jsonify({"error": "Brak pliku"}), 400
    
    file = request.files['file']
    
    # Odbieramy łuzy jako JSON string
    if 'pockets' not in request.form:
        return jsonify({"error": "Musisz zaznaczyć łuzy!"}), 400
        
    try:
        pockets = json.loads(request.form['pockets'])
    except:
        return jsonify({"error": "Błąd formatu łuz"}), 400

    # Opcjonalne parametry
    cue_ball_color = request.form.get('cue_ball_color', 'White')
    table_area = None
    if 'table_area' in request.form:
        try:
            table_area = json.loads(request.form['table_area'])
        except:
            logger.warning("Błąd parsowania table_area, ignoruję")
            table_area = None

    # Zapisz plik
    filename = secure_filename(file.filename) or "temp.jpg"
    filepath = os.path.join(app.config['UPLOAD_FOLDER'], filename)
    file.save(filepath)
    
    try:
        # 1. DETEKCJA AI
        cue_ball, other_balls = detect_all_balls(
            filepath, 
            ROBOFLOW_API_KEY,
            cue_ball_color=cue_ball_color,
            table_area=table_area
        )
        
        if cue_ball is None:
            return jsonify({"error": f"Nie widzę bili cue ({cue_ball_color}). Upewnij się, że jest w kadrze."}), 500
            
        if not other_balls:
            return jsonify({"error": f"Widzę bilę cue ({cue_ball_color}), ale nie widzę innych bil do wbicia."}), 500
            
        # 2. OBLICZANIE NAJLEPSZEGO STRZAŁU
        # Przekazujemy table_area jeśli jest dostępny, aby użyć go do filtrowania
        best_shot = find_best_shot(cue_ball, other_balls, pockets, table_area=table_area)
        
        if best_shot is None:
             return jsonify({"error": "Nie znalazłem łatwego strzału. Sprawdź czy wszystkie bile są na stole i czy łuzy są poprawnie zaznaczone."}), 500
             
        # Sukces!
        return jsonify({
            "white_ball": cue_ball,  # Zachowujemy nazwę "white_ball" dla kompatybilności
            "other_balls": other_balls,
            "best_shot": best_shot 
        })
        
    except Exception as e:
        logger.error(f"Błąd: {e}")
        return jsonify({"error": str(e)}), 500
    finally:
        if os.path.exists(filepath):
            os.remove(filepath)

@app.route('/')
def hello():
    return jsonify({"message": "Serwer Asystenta Bilardowego działa!"})

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5001, debug=True)