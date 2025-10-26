Farming_QUT
Monorepo for the Farming_QUT project:
Flutter mobile app (Android & iOS)
Django backend API (optional local backend for authentication and data access)
This repository excludes all generated build artifacts (Gradle/NDK .cxx, iOS DerivedData, etc.).
These files are recreated automatically when you build or run the app.
Table of Contents
Tech Stack
Repo Layout
Prerequisites
Quick Start
Clone the Repository
Mobile App (Flutter)
Auth API (Django)
Configuration
Flutter Configuration
Django Configuration
Gemini API Key Setup
API Keys Overview
Build & Run
Troubleshooting
Branching & PRs
Contributing
License
Tech Stack
Flutter (Dart) — cross-platform UI
Android Studio — IDE for Android development and Gradle integration
Xcode — iOS builds (macOS only)
Django (Python) — backend API
PostgreSQL / PostGIS — optional for spatial data
Google Gemini API — AI features (crop suggestions, weather insights)
Git + GitHub — version control & collaboration
Repo Layout
Farming_QUT/
├─ android/               # Android project for Flutter
├─ ios/                   # iOS project for Flutter
├─ lib/                   # Flutter app Dart source code
├─ assets/                # Images, fonts, and icons
├─ django_auth_api/       # Django backend API (local/dev)
├─ test/                  # Flutter tests
├─ pubspec.yaml           # Flutter dependencies
└─ README.md
Ignored build directories:
.dart_tool/, build/, .gradle/, Pods/, DerivedData/, and android/app/.cxx/ (NDK/CMake artifacts)
Prerequisites
To set up this project on a new machine, you must have the following:
Requirement	Description
Android Studio	Required. Install from https://developer.android.com/studio. Includes Android SDK, NDK, AVD (emulator), and Gradle.
Flutter SDK	Install the version specified in .flutter-version or run flutter --version to confirm compatibility.
Xcode (macOS only)	For iOS builds and testing.
Python 3.10+	For the Django backend.
Git	For version control and cloning this repository.
CocoaPods	Required for iOS dependencies (sudo gem install cocoapods).
We recommend using Android Studio as your main development environment.
It handles Gradle builds, emulators, and Flutter integration out of the box.
Make sure it is installed and configured before running flutter run.
Quick Start
Clone the Repository
To clone only the mobile branch:
git clone --branch mobile --single-branch https://github.com/OreFox/Farming_QUT.git
cd Farming_QUT
If you already have an old copy, remove it first:
rm -rf ~/Farming_QUT
Mobile App (Flutter)
Make sure Android Studio is installed before running these commands:
flutter clean
flutter pub get
flutter run -d android
flutter build apk --release
If using an emulator, open Android Studio → Device Manager → Start a virtual device (Pixel or similar).
iOS (macOS only)
cd ios
pod install
cd ..
flutter run -d ios
Auth API (Django)
cd django_auth_api
python -m venv .venv
source .venv/bin/activate   # Windows: .venv\Scripts\activate
pip install -r requirements.txt

python manage.py migrate
python manage.py runserver
Access the backend at: http://127.0.0.1:8000
Configuration
Flutter Configuration
You can inject configuration values when running the app:
flutter run --dart-define=API_BASE_URL=http://127.0.0.1:8000
Important — Update Your Local IP:
You must set your computer’s local IP address in the following files:
lib/services/api_service.dart
const String baseUrl = "http://192.168.1.101:8000";  // Replace with your own IP
If using the Android Emulator, use http://10.0.2.2:8000.
If using a real device, replace with your local IP (e.g., 192.168.x.x).
Both your phone/emulator and computer must be on the same Wi-Fi network.
Django Configuration
Your backend configuration must also reference your IP address.
Open django_auth_api/config/settings.py
Update the ALLOWED_HOSTS line:
ALLOWED_HOSTS = ["127.0.0.1", "localhost", "192.168.1.101"]
Restart your Django server after editing.
Example .env file:
DJANGO_SECRET_KEY=replace_me
DJANGO_DEBUG=True
ALLOWED_HOSTS=127.0.0.1,localhost,192.168.1.101
DATABASE_URL=sqlite:///db.sqlite3
Gemini API Key Setup
The app uses the Google Gemini API for AI-driven planting suggestions, crop management, and weather recommendations.
Visit https://makersuite.google.com/app/apikey and sign in with your Google account.
Generate a new Gemini API key.
Add it when running the Flutter app:
flutter run --dart-define=GEMINI_API_KEY=your_api_key_here
You can combine it with your backend define:
flutter run --dart-define=API_BASE_URL=http://192.168.1.101:8000 --dart-define=GEMINI_API_KEY=your_api_key_here
(Optional) You can also store the key securely in a .env file or flutter_secure_storage if you prefer not to expose it in command line arguments.
Security Notes:
Never commit your API key to GitHub.
Do not hard-code your API key directly in Dart files.
If your key is leaked, revoke it immediately via Google AI Studio → API Keys.
API Keys Overview
Feature	Uses External API?	API Key Needed?	Shared or Personal?
Map (flutter_map + OpenStreetMap)	No (OSM tiles)	❌ None required	Shared automatically
Calendar	No (Local Flutter widget)	❌ None required	Shared automatically
Gemini AI	Yes (Google Gemini API)	✅ Required	Each developer must get their own
Summary:
The map and calendar work out-of-the-box — no key setup required.
Only the Gemini AI requires a personal API key for AI and weather features.
Build & Run
Android
flutter run -d android         # debug
flutter build apk --release    # release
iOS
cd ios && pod install && cd ..
flutter build ios --release
Troubleshooting
Issue	Solution
Gradle build failed	Run flutter clean && flutter pub get or open in Android Studio and let it sync Gradle.
CocoaPods error	Run sudo gem install cocoapods && cd ios && pod install.
No emulator detected	Open Android Studio → Device Manager → Start an emulator.
Django missing deps	Ensure django_auth_api/requirements.txt exists and run pip install -r requirements.txt.
AI features not working	Verify your GEMINI_API_KEY is valid and properly defined when running the Flutter app.
IP connection failed	Ensure your local IP is set correctly in both api_service.dart and settings.py, and both devices are on the same Wi-Fi network.
Branching & PRs
Active branch: mobile
Create feature branches off mobile.
Use Conventional Commit style:
Example:
feat: add weather AI integration
fix: map marker sync bug
Contributing
Clone the repo and set up prerequisites.
Use Android Studio for all builds and testing.
Keep build artifacts out of Git (flutter clean before committing).
