🌾 Farm Planting App
Orefox AI Limited | QUT IFB399 Capstone Project (2025)
This project provides farmers, gardeners, and orchard owners with a digital platform to plan, manage, and optimise agricultural layouts.
It includes a Django REST backend and a Flutter mobile app frontend, enabling:
🗺️ Map-based layout planning (plots, markers, polygons)
🌱 Crop tagging, growth tracking, and yield monitoring
☁️ Weather integration with AI planting insights (Gemini API)
🧾 Task management and scheduling
👤 User authentication (JWT + Djoser)
🧠 Smart recommendations via Gemini API
🧩 Project Structure
Farming_QUT/
│
├── django_auth_api/        # Django REST backend
│   ├── manage.py
│   ├── config/             # Settings, URLs, WSGI/ASGI
│   ├── accounts/           # User authentication
│   ├── crops/              # Crop data management
│   ├── plots/              # Farm layout data
│   ├── crop_app/           # AI + weather integrations
│   └── ...
│
├── lib/                    # Flutter frontend (mobile app)
│   ├── main.dart
│   ├── pages/
│   ├── services/
│   └── widgets/
│
└── README.md               # You are here
⚙️ Backend Setup (Django)
1️⃣ Clone the repository
cd ~/Desktop
git clone --branch mobile https://github.com/OreFox/Farming_QUT.git
cd Farming_QUT/django_auth_api
2️⃣ Create and activate a virtual environment
python3 -m venv .venv
source .venv/bin/activate
3️⃣ Install dependencies
If a requirements.txt file exists:
pip install -r requirements.txt
Otherwise, install manually:
pip install Django djangorestframework djangorestframework-gis django-cors-headers django-filter djoser psycopg2-binary python-dotenv Pillow
4️⃣ Configure environment variables
Create a .env file in django_auth_api/ and add:
DJANGO_SECRET_KEY=dev-secret-key
DEBUG=True
DATABASE_URL=sqlite:///db.sqlite3
ALLOWED_HOSTS=127.0.0.1,localhost,10.0.2.2
(Optional) For PostgreSQL / PostGIS:
DATABASE_URL=postgresql://username:password@localhost:5432/planting_app
5️⃣ Apply migrations
python manage.py migrate
6️⃣ Create a superuser (admin)
python manage.py createsuperuser
Follow prompts and enter:
Email: admin@example.com
Password: ********
7️⃣ Run the backend server
python manage.py runserver 0.0.0.0:8000
Then open:
👉 http://127.0.0.1:8000/
You should see:
Starting development server at http://0.0.0.0:8000/
System check identified no issues (0 silenced).


📱 Frontend Setup (Flutter)
1️⃣ Go to the project root
cd ~/Desktop/Farming_QUT
2️⃣ Get dependencies
flutter pub get
3️⃣ Add your Gemini API key (for AI features)
You can provide the Gemini API key at runtime using:
flutter run --dart-define=GEMINI_API_KEY=YOUR_API_KEY_HERE
🔒 Replace YOUR_API_KEY_HERE with your own Gemini API key from Google AI Studio.
4️⃣ Run the app
🧩 Using Android Studio
Open the project folder (Farming_QUT) in Android Studio.
In the top menu, go to Run ▸ Edit Configurations.
Under Additional run args, add:
--dart-define=GEMINI_API_KEY=YOUR_API_KEY_HERE
Select an emulator or physical device.
Click Run ▶️.
🧩 Using VS Code
Open the project folder.
Press Ctrl + Shift + P → “Flutter: Select Device” → choose your emulator.
Run in terminal:
flutter run --dart-define=GEMINI_API_KEY=YOUR_API_KEY_HERE
5️⃣ Connecting to the Backend
In your Flutter code (e.g., lib/services/api_service.dart), ensure the base URL matches your environment:
Environment	Base URL
Android Emulator	http://10.0.2.2:8000/api/
Chrome / iOS / macOS	http://127.0.0.1:8000/api/
Example:
const String baseUrl = "http://10.0.2.2:8000/api/";
🧠 Tech Stack
Component	Technology
Backend	Django 5.2.7, Django REST Framework
Frontend	Flutter 3.22+
Database	SQLite / PostgreSQL with PostGIS
Authentication	Djoser + JWT
AI Model	Google Gemini API
Mapping	flutter_map, latlong2, flutter_map_dragmarker
🧾 Common Commands
Task	Command
Activate virtual environment	source .venv/bin/activate
Run backend	python manage.py runserver 0.0.0.0:8000
Run frontend	flutter run --dart-define=GEMINI_API_KEY=YOUR_API_KEY_HERE
Stop server	Ctrl + C
Apply migrations	python manage.py makemigrations && python manage.py migrate
Create admin	python manage.py createsuperuser
🧑‍🤝‍🧑 Team Credits
Orefox AI Limited x QUT IFB399 Capstone Team (2025)
Richard Lim — Backend Integration & Mobile Development
Shivanshi — Frontend & UI/UX Design
Gauri — Risk Management & Documentation
Anshika — Research & Client Liaison
🏁 Quick Start Summary
# Clone repository
git clone --branch mobile https://github.com/OreFox/Farming_QUT.git
cd Farming_QUT/django_auth_api

# Backend setup
python3 -m venv .venv
source .venv/bin/activate
pip install Django djangorestframework djangorestframework-gis django-cors-headers django-filter djoser psycopg2-binary python-dotenv Pillow
python manage.py migrate
python manage.py runserver 0.0.0.0:8000
Then in a new terminal:
cd ~/Desktop/Farming_QUT
flutter pub get
flutter run --dart-define=GEMINI_API_KEY=YOUR_API_KEY_HERE
✅ The backend will run on port 8000, and the Flutter app will connect automatically.
🚀 Deployment Notes
For production deployment:
Set DEBUG=False in .env
Run python manage.py collectstatic
Use Gunicorn + Nginx or Django ASGI
Store API keys securely (never in public code)
Use PostgreSQL/PostGIS for data persistence
