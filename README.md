# PrimeYard Workspace — Android App v7

Flutter-based Android business management app for PrimeYard lawn & property services.

## ⚡ Quickest build method (GitHub Actions)

1. Upload this entire folder to a GitHub repository
2. Go to **Actions** tab → **Build PrimeYard APK** → **Run workflow**
3. Wait ~5 minutes
4. Download the APK from the **Artifacts** section of the finished run

## 📁 IMPORTANT — Assets required

Before building, copy your 4 image files into the `assets/` folder:
- `assets/logo-full.png`
- `assets/logo-mark.png`
- `assets/mascot.png`
- `assets/app_icon.png`

These are in your previous download (the zip from before). The build will fail without them.

## Project structure

```
primeyard_workspace/
├── .github/workflows/build.yml   ← GitHub Actions auto-build
├── android/
│   ├── app/
│   │   ├── build.gradle
│   │   ├── google-services.json  ← Firebase config (already filled in)
│   │   └── src/main/
│   │       ├── AndroidManifest.xml
│   │       ├── kotlin/com/primeyard/workspace/MainActivity.kt
│   │       └── res/
├── assets/                       ← PUT YOUR 4 IMAGE FILES HERE
├── lib/main.dart                 ← Full app code
└── pubspec.yaml
```
