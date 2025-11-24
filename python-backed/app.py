from flask import Flask, request, jsonify
import os
import json
import logging
import secrets
from pathlib import Path
from werkzeug.utils import secure_filename
from werkzeug.exceptions import RequestEntityTooLarge
from dotenv import load_dotenv
from PIL import Image
from processing import detect_all_balls, calculate_shot_lines, calculate_manual_shot_lines

# Wczytaj zmienne środowiskowe z pliku .env
load_dotenv()

# Konfiguracja logowania
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Wczytaj klucz API ze zmiennej środowiskowej
ROBOFLOW_API_KEY = os.environ.get("ROBOFLOW_API_KEY")

if not ROBOFLOW_API_KEY:
    logger.warning("--- OSTRZEŻENIE ---")
    logger.warning("Zmienna środowiskowa ROBOFLOW_API_KEY nie jest ustawiona!")
    logger.warning("Przed uruchomieniem serwera, wpisz w terminalu:")
    logger.warning("export ROBOFLOW_API_KEY=\"TWÓJ_KLUCZ\"")
    logger.warning("lub dodaj do pliku .env")
    logger.warning("-------------------")

app = Flask(__name__)
UPLOAD_FOLDER = 'static/uploads/'
app.config['UPLOAD_FOLDER'] = UPLOAD_FOLDER
app.config['MAX_CONTENT_LENGTH'] = 10 * 1024 * 1024  # 10MB limit
app.config['ALLOWED_EXTENSIONS'] = {'jpg', 'jpeg', 'png', 'gif', 'webp'}
os.makedirs(UPLOAD_FOLDER, exist_ok=True)

def allowed_file(filename):
    """Sprawdza, czy plik ma dozwolone rozszerzenie."""
    return '.' in filename and \
           filename.rsplit('.', 1)[1].lower() in app.config['ALLOWED_EXTENSIONS']

def validate_image_file(filepath):
    """Waliduje plik obrazu - sprawdza czy to prawidłowy obraz."""
    try:
        with Image.open(filepath) as img:
            img.verify()
        # Otwórz ponownie po weryfikacji (verify() zamyka plik)
        img = Image.open(filepath)
        width, height = img.size
        if width < 10 or height < 10:
            raise ValueError("Obraz jest za mały (minimum 10x10 pikseli)")
        if width > 10000 or height > 10000:
            raise ValueError("Obraz jest za duży (maksimum 10000x10000 pikseli)")
        return True
    except Exception as e:
        logger.error(f"Błąd walidacji obrazu: {e}")
        raise ValueError(f"Nieprawidłowy plik obrazu: {str(e)}")

@app.errorhandler(RequestEntityTooLarge)
def handle_file_too_large(e):
    logger.warning("Próba przesłania zbyt dużego pliku")
    return jsonify({"error": "Plik jest za duży (maksimum 10MB)"}), 413

@app.route('/analyze', methods=['POST'])
def analyze_image():
    # Sprawdź, czy serwer ma klucz API
    if not ROBOFLOW_API_KEY:
        logger.error("Brak klucza API Roboflow")
        return jsonify({"error": "Klucz API Roboflow nie jest skonfigurowany na serwerze"}), 500

    # Walidacja pliku
    if 'file' not in request.files:
        logger.warning("Brak części 'file' w żądaniu")
        return jsonify({"error": "Brak części 'file' w żądaniu"}), 400
    
    file = request.files['file']
    if file.filename == '':
        logger.warning("Nie wybrano pliku")
        return jsonify({"error": "Nie wybrano pliku"}), 400

    if not allowed_file(file.filename):
        logger.warning(f"Nieprawidłowe rozszerzenie pliku: {file.filename}")
        return jsonify({"error": "Nieprawidłowy typ pliku. Dozwolone: jpg, jpeg, png, gif, webp"}), 400

    if 'data' not in request.form:
        logger.warning("Brak części 'data' w żądaniu")
        return jsonify({"error": "Brak części 'data' (z target_ball i pocket)"}), 400

    try:
        form_data = json.loads(request.form['data'])
        target_ball = form_data['target_ball']
        pocket = form_data['pocket']
    except (json.JSONDecodeError, KeyError) as e:
        logger.error(f"Błąd parsowania JSON: {e}")
        return jsonify({"error": f"Nieprawidłowy format danych JSON: {str(e)}"}), 400

    # Bezpieczna nazwa pliku
    original_filename = secure_filename(file.filename)
    if not original_filename:
        original_filename = "upload"
    # Dodaj losowy prefix, aby uniknąć kolizji nazw
    safe_filename = f"{secrets.token_hex(8)}_{original_filename}"
    filepath = os.path.join(app.config['UPLOAD_FOLDER'], safe_filename)
    
    try:
        file.save(filepath)
        logger.info(f"Zapisano plik: {safe_filename}")
        
        # Walidacja obrazu
        validate_image_file(filepath)
        
        # Przekazujemy klucz API do funkcji przetwarzającej
        white_ball, other_balls = detect_all_balls(filepath, ROBOFLOW_API_KEY)
        
        if white_ball is None:
            logger.warning("Nie udało się znaleźć białej bili")
            return jsonify({"error": "Nie udało się znaleźć białej bili (Model YOLO)"}), 500

        default_radius = white_ball.get('r', 18) 
        lines, ghost_ball = calculate_shot_lines(white_ball, target_ball, pocket, default_radius)
        
        logger.info("Zwracam pełne dane z ghost_ball")
        
        return jsonify({
            "white_ball": white_ball,
            "other_balls": other_balls,
            "shot_lines": lines,
            "ghost_ball": ghost_ball
        })
        
    except ValueError as e:
        logger.error(f"Błąd walidacji: {e}")
        return jsonify({"error": str(e)}), 400
    except Exception as e:
        logger.error(f"Błąd podczas przetwarzania: {e}", exc_info=True)
        return jsonify({"error": f"Wystąpił błąd podczas przetwarzania: {str(e)}"}), 500
    finally:
        if os.path.exists(filepath):
            os.remove(filepath)
            logger.debug(f"Usunięto plik: {safe_filename}")
            
@app.route('/calculate_manual', methods=['POST'])
def calculate_manual():
    logger.info("Otrzymano żądanie obliczeń ręcznych...")

    if not request.is_json:
        logger.warning("Żądanie nie zawiera JSON")
        return jsonify({"error": "Żądanie musi zawierać JSON"}), 400

    try:
        data = request.json

        # Sprawdzamy, czy mamy wszystkie 3 punkty
        if not data or 'white_ball' not in data or 'target_ball' not in data or 'pocket' not in data:
            logger.warning("Brak wymaganych punktów w żądaniu")
            return jsonify({"error": "Brak wymaganych punktów (white_ball, target_ball, pocket)"}), 400

        white_ball_point = data['white_ball']
        target_ball_point = data['target_ball']
        pocket_point = data['pocket']

        # Walidacja punktów
        for point_name, point in [('white_ball', white_ball_point), ('target_ball', target_ball_point), ('pocket', pocket_point)]:
            if not isinstance(point, dict) or 'x' not in point or 'y' not in point:
                logger.warning(f"Nieprawidłowy format punktu: {point_name}")
                return jsonify({"error": f"Nieprawidłowy format punktu {point_name}"}), 400
            if not isinstance(point['x'], (int, float)) or not isinstance(point['y'], (int, float)):
                logger.warning(f"Współrzędne punktu {point_name} nie są liczbami")
                return jsonify({"error": f"Współrzędne punktu {point_name} muszą być liczbami"}), 400

    except Exception as e:
        logger.error(f"Błąd parsowania żądania: {e}")
        return jsonify({"error": f"Nieprawidłowy format danych JSON: {str(e)}"}), 400

    try:
        # Używamy nowej funkcji, która nie wymaga AI
        lines, ghost_ball = calculate_manual_shot_lines(white_ball_point, target_ball_point, pocket_point)

        logger.info("Zwracam pełne dane z ghost_ball (kalkulacja ręczna)")

        return jsonify({
            "shot_lines": lines,
            "ghost_ball": ghost_ball,
            "white_ball": {"x": white_ball_point['x'], "y": white_ball_point['y'], "r": 18},
            "other_balls": []
        })

    except ValueError as e:
        logger.error(f"Błąd obliczeń: {e}")
        return jsonify({"error": f"Błąd podczas obliczeń: {str(e)}"}), 400
    except Exception as e:
        logger.error(f"Nieoczekiwany błąd podczas obliczeń: {e}", exc_info=True)
        return jsonify({"error": f"Wystąpił błąd podczas obliczeń: {str(e)}"}), 500
@app.route('/')
def hello():
    return jsonify({"message": "Serwer Asystenta Bilardowego działa! (Tryb detekcji YOLO)"})

if __name__ == '__main__':
    debug_mode = os.getenv('FLASK_DEBUG', 'False').lower() == 'true'
    port = int(os.getenv('FLASK_PORT', '5001'))
    logger.info(f"Uruchamianie serwera Flask (debug={debug_mode}, port={port})")
    app.run(host='0.0.0.0', port=port, debug=debug_mode)