# BudgetBites for iOS 🥗

A complete native iOS application for **BudgetBites – Daily Meal Planner**, built with Swift, SwiftUI, WebKit, and configured for **`xtool`** (`xtool-org/xtool`) and **Swift Package Manager**.

---

## 📁 Project Architecture

```
BudgetBites-iOS/
├── Package.swift               # SwiftPM manifest (configured for xtool)
├── xtool.yml                   # xtool configuration manifest (bundle ID, resources)
├── Sources/
│   └── BudgetBites/
│       ├── BudgetBitesApp.swift       # Native SwiftUI entry point
│       ├── Views/
│       │   └── WebViewContainer.swift # WKWebView wrapper with haptics & offline storage
│       └── Resources/
│           ├── Info.plist             # iOS permissions, status bar & orientation
│           ├── Assets.xcassets/       # 1024x1024 AppIcon and image catalogs
│           └── www/                   # Bundled offline web application
│               ├── index.html         # Complete meal planner with safe area & haptic support
│               ├── manifest.json      # Web App manifest for PWA installation
│               └── icon-512.png       # High-resolution app icon
├── BudgetBites.xcodeproj/       # Xcode project file (compatible with Xcode 14+)
├── .github/workflows/
│   └── build-and-sign.yml             # GitHub Actions CI/CD to build & sign with xtool
├── ExportOptions.plist
└── README.md
```

---

## 🛠️ Building with `xtool`

### What is `xtool`?
[`xtool`](https://github.com/xtool-org/xtool) is an open-source, cross-platform CLI tool that builds, signs, and deploys iOS apps directly from standard Swift Package Manager projects without requiring manual `.xcodeproj` maintenance.

### Local Development with `xtool` (macOS or Linux/WSL)
1. Install `xtool`:
   ```bash
   brew tap xtool-org/tap
   brew install xtool
   ```
2. Setup Darwin SDK:
   ```bash
   xtool setup
   ```
3. Authenticate with Apple Developer (for automatic signing):
   ```bash
   xtool auth login --username "YOUR_APPLE_ID"
   ```
4. Build and run:
   ```bash
   # Run on connected iPhone via USB
   xtool dev

   # Run on iOS Simulator (macOS only)
   xtool dev --simulator

   # Build only
   xtool dev build --configuration release
   ```

---

## ☁️ Automated Cloud Build & Signing via GitHub Actions (No Mac Needed)

This repository includes a ready-to-run GitHub Actions workflow in `.github/workflows/build-and-sign.yml` that uses `xtool` on macOS runners:

1. Create a repository on GitHub and push this project:
   ```bash
   cd BudgetBites-iOS
   git remote add origin https://github.com/YOUR_USERNAME/BudgetBites-iOS.git
   git branch -M main
   git push -u origin main
   ```
2. **(Optional) Add Apple Signing Secrets** in GitHub repository **Settings > Secrets and variables > Actions**:
   - `APPLE_ID` & `APPLE_PASSWORD` (for xtool auto-authentication)
   - OR `BUILD_CERTIFICATE_BASE64` & `P12_PASSWORD` & `BUILD_PROVISION_PROFILE_BASE64` (for enterprise/distribution signing)
3. Go to the **Actions** tab in GitHub and run **Build and Sign iOS App with xtool**.
4. Download the generated **`BudgetBites.ipa`** from the artifacts section!

---

## 📲 Installing on Your iPhone

1. **Via Sideloadly / AltStore (Windows / Mac)**:
   - Connect iPhone via USB.
   - Drag `BudgetBites.ipa` into Sideloadly, enter your Apple ID, and click Start.
2. **Via Xcode (Mac)**:
   - Open `BudgetBites.xcodeproj`, select your team, and press Run (Cmd+R).
3. **Instant Safari Web Clip (Zero compile, right now)**:
   - Run `python -m http.server 8080` inside `Sources/BudgetBites/Resources/www`.
   - Open `http://<YOUR_PC_IP>:8080` in Safari on your iPhone, tap Share -> "Add to Home Screen".
