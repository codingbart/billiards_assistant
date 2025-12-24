import os
import logging
from dotenv import load_dotenv

load_dotenv()

# Logging - plikowy + stdout
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)
file_handler = logging.FileHandler("server.log")
file_handler.setLevel(logging.INFO)
formatter = logging.Formatter('%(asctime)s %(levelname)s %(message)s')
file_handler.setFormatter(formatter)
logger.addHandler(file_handler)

# Flask config
UPLOAD_FOLDER = 'static/uploads/'
MAX_CONTENT_LENGTH = 2 * 1024 * 1024  # 2 MB max
ALLOWED_EXT = {'.jpg', '.jpeg', '.png'}

# Tworzenie folderu uploads jeśli nie istnieje
os.makedirs(UPLOAD_FOLDER, exist_ok=True)

def allowed_file(filename):
    fn = filename.lower()
    return any(fn.endswith(ext) for ext in ALLOWED_EXT)

