from flask import Flask, request, jsonify
import os
import json
from processing import detect_all_balls, calculate_shot_lines

# Wczytaj klucz API ze zmiennej środowiskowej
# Ustawimy ją w terminalu przed uruchomieniem
ROBOFLOW_API_KEY = os.environ.get("ROBOFLOW_API_KEY")

if not ROBOFLOW_API_KEY:
    print("--- OSTRZEŻENIE ---")
    print("Zmienna środowiskowa ROBOFLOW_API_KEY nie jest ustawiona!")
    print("Przed uruchomieniem serwera, wpisz w terminalu:")
    print("export ROBOFLOW_API_KEY=\"TWÓJ_KLUCZ\"")
    print("-------------------")

app = Flask(__name__)
UPLOAD_FOLDER = 'static/uploads/'
app.config['UPLOAD_FOLDER'] = UPLOAD_FOLDER
os.makedirs(UPLOAD_FOLDER, exist_ok=True)

@app.route('/analyze', methods=['POST'])
def analyze_image():
    # Sprawdź, czy serwer ma klucz API
    if not ROBOFLOW_API_KEY:
        return jsonify({"error": "Klucz API Roboflow nie jest skonfigurowany na serwerze"}), 500

    # Reszta walidacji bez zmian
    if 'file' not in request.files:
        return jsonify({"error": "Brak części 'file' w żądaniu"}), 400
    file = request.files['file']
    if file.filename == '':
        return jsonify({"error": "Nie wybrano pliku"}), 400

    if 'data' not in request.form:
        return jsonify({"error": "Brak części 'data' (z target_ball i pocket)"}), 400

    try:
        form_data = json.loads(request.form['data'])
        target_ball = form_data['target_ball']
        pocket = form_data['pocket']
    except Exception as e:
        return jsonify({"error": f"Nieprawidłowy format danych JSON: {str(e)}"}), 400

    filepath = os.path.join(app.config['UPLOAD_FOLDER'], file.filename)
    file.save(filepath)
    
    try:
        # Przekazujemy klucz API do funkcji przetwarzającej
        white_ball, other_balls = detect_all_balls(filepath, ROBOFLOW_API_KEY)
        
        if white_ball is None:
            return jsonify({"error": "Nie udało się znaleźć białej bili (Model YOLO)"}), 500

        # Logika geometrii pozostaje bez zmian
        default_radius = white_ball.get('r', 18) 
        lines, ghost_ball = calculate_shot_lines(white_ball, target_ball, pocket, default_radius)
        
        return jsonify({
            "white_ball": white_ball,
            "other_balls": other_balls,
            "shot_lines": lines,
            "ghost_ball": ghost_ball
        })
        
    except Exception as e:
        return jsonify({"error": f"Wystąpił błąd podczas przetwarzania: {str(e)}"}), 500
    finally:
        if os.path.exists(filepath):
            os.remove(filepath)

@app.route('/')
def hello():
    return jsonify({"message": "Serwer Asystenta Bilardowego działa! (Tryb detekcji YOLO)"})

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5001, debug=True)