# 🌾 Farm Planting App

**Orefox AI Limited | QUT IFB399 Capstone Project (2025)**  

A digital solution for farmers, gardeners, and orchard owners to **plan, manage, and optimise agricultural layouts** through interactive mapping, crop tracking, and AI-powered insights.

---

## 🚀 Overview

This app combines a **Django REST backend** and a **Flutter mobile frontend**, providing:

- 🗺️ **Map-based layout planning** (plots, polygons, markers)
- 🌱 **Crop tagging**, growth tracking, and yield monitoring
- ☁️ **Weather integration** with AI planting insights (Gemini API)
- 🧾 **Task management** and scheduling tools
- 👤 **User authentication** (JWT + Djoser)
- 🧠 **Smart recommendations** via Gemini AI

---

## 🧩 Project Structure

farming-app/

│
├── django_auth_api/ # Django REST backend

│ ├── config/ # Settings, URLs, WSGI/ASGI

│ ├── accounts/ # User authentication

│ ├── crops/ # Crop data management

│ ├── plots/ # Farm layout and mapping

│ ├── crop_app/ # AI + weather integrations

│ ├── manage.py
│ └── ...
│
├── lib/ # Flutter frontend (mobile app)

│ ├── main.dart

│ ├── screens/ # App screens (Map, Tasks, Weather, etc.)

│ ├── services/ # API, auth, and DB helpers

│ ├── widgets/ # Reusable UI components

│ └── ...
│
└── README.md

---

## ⚙️ Backend Setup (Django)

### 1️⃣ Clone the repository

```bash
cd ~/Desktop
git clone --branch main https://github.com/RichardrahciR0/farming-app.git
cd farming-app/django_auth_api

2️⃣ Create and activate virtual environment

python3 -m venv .venv
source .venv/bin/activate

3️⃣ Install dependencies

pip install -r requirements.txt
If the file is missing, install manually:
pip install Django djangorestframework djangorestframework-gis django-cors-headers django-filter djoser psycopg2-binary python-dotenv Pillow

4️⃣ Configure environment variables

Create .env inside django_auth_api/:
DJANGO_SECRET_KEY=dev-secret-key
DEBUG=True
DATABASE_URL=sqlite:///db.sqlite3
ALLOWED_HOSTS=127.0.0.1,localhost,10.0.2.2
For PostgreSQL/PostGIS:
DATABASE_URL=postgresql://username:password@localhost:5432/planting_app

5️⃣ Apply migrations

python manage.py migrate

6️⃣ Create a superuser

python manage.py createsuperuser

7️⃣ Run the backend

python manage.py runserver 0.0.0.0:8000
Access it at:
👉 http://127.0.0.1:8000/

📱 Frontend Setup (Flutter)
1️⃣ Navigate to the project root

cd ~/Desktop/farming-app

2️⃣ Get dependencies

flutter pub get

3️⃣ Add your Gemini API key

Run the app with:
flutter run --dart-define=GEMINI_API_KEY=YOUR_API_KEY_HERE
🔒 Replace YOUR_API_KEY_HERE with your Gemini API key from Google AI Studio.

4️⃣ Connect to Backend

In lib/services/api_service.dart, ensure:
Environment	Base URL
Android Emulator	http://10.0.2.2:8000/api/
Chrome / iOS / macOS	http://127.0.0.1:8000/api/
Example:
const String baseUrl = "http://10.0.2.2:8000/api/";

5️⃣ Run the app

Use Android Studio or VS Code:
flutter run --dart-define=GEMINI_API_KEY=YOUR_API_KEY_HERE

🧠 Tech Stack
Component	Technology
Backend	Django 5.2.7, Django REST Framework
Frontend	Flutter 3.22+
Database	SQLite / PostgreSQL + PostGIS
Auth	Djoser + JWT
AI	Google Gemini API
Mapping	flutter_map, latlong2, flutter_map_dragmarker
🧾 Common Commands
Task	Command
Activate venv	source .venv/bin/activate
Run backend	python manage.py runserver 0.0.0.0:8000
Run frontend	flutter run --dart-define=GEMINI_API_KEY=YOUR_API_KEY_HERE
Stop server	Ctrl + C
Apply migrations	python manage.py makemigrations && python manage.py migrate
Create admin	python manage.py createsuperuser
🏁 Quick Start Summary
# Clone repo
git clone --branch main https://github.com/RichardrahciR0/farming-app.git
cd farming-app/django_auth_api

# Setup backend

python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
python manage.py migrate
python manage.py runserver 0.0.0.0:8000

# In a new terminal

cd ~/Desktop/farming-app

flutter pub get
flutter run --dart-define=GEMINI_API_KEY=YOUR_API_KEY_HERE
✅ Backend runs on port 8000, and Flutter connects automatically.
🚢 Deployment Notes
Set DEBUG=False in .env
Run python manage.py collectstatic
Use Gunicorn + Nginx (or Django ASGI for production)
Store API keys securely
Use PostgreSQL/PostGIS for persistence
Always avoid pushing .env or secret keys
