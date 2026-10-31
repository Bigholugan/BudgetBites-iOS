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

---

## 🛒 Live Kroger Pricing & "Send to Kroger Cart" Setup

BudgetBites integrates directly with the Kroger Developer Platform to provide **live localized product pricing**, **package size conversion**, and **OAuth2 cart sync**.

### 1. Kroger Developer Portal App Setup
1. Go to [Kroger Developer Portal](https://developer.kroger.com/) and register or log in.
2. Under **My Apps**, click **Create New App**.
3. Fill in the app details:
   - **App Name**: `BudgetBites`
   - **Scopes**: Select `product.compact`, `cart.basic:write`, and `profile.compact`.
   - **Redirect URI**: Set to your backend's HTTPS universal link callback endpoint:
     `https://your-backend-domain.com/callback` (must be exact match, HTTPS).
4. Save the generated **Client ID** and **Client Secret**.

### 2. Backend Deployment & Environment Variables
The client secret is never stored on the iOS device. A secure backend microservice is included in `/backend`.

1. Deploy the `backend/` directory to your hosting provider (Vercel, Render, Railway, AWS Lambda, or Docker):
   ```bash
   cd backend
   npm install
   ```
2. Configure environment variables on your server:
   | Variable | Description |
   |---|---|
   | `KROGER_CLIENT_ID` | Your Kroger App Client ID |
   | `KROGER_CLIENT_SECRET` | Your Kroger App Client Secret (never put this in iOS app) |
   | `KROGER_REDIRECT_URI` | `https://your-backend-domain.com/callback` |
   | `APPLE_APP_ID` | `<TeamID>.<BundleIdentifier>` (e.g. `TEAM123456.com.budgetbites.app`) |
   | `PORT` | `3000` (or default port) |
   | `SESSION_SECRET` | Random 32+ character secret for session signing |

3. Verify Universal Link association:
   - Visit `https://your-backend-domain.com/.well-known/apple-app-site-association` in your browser. It should return the JSON payload specifying `paths: ["/callback", "/callback/*"]`.

### 3. Xcode Associated Domains & Backend URL
1. In Xcode, select the **BudgetBites** target > **Signing & Capabilities**.
2. Click **+ Capability** and add **Associated Domains**.
3. Add: `applinks:your-backend-domain.com`.
4. In `Info.plist`, set `KROGER_BACKEND_URL` to `https://your-backend-domain.com` and `KROGER_CLIENT_ID` to your Client ID.

### 4. Testing with a Kroger Test Account
1. Open BudgetBites and proceed to **Step 5** of the setup or the **Shop** tab.
2. In the **Live Kroger Pricing** card, enter a ZIP code (e.g., `45202` for Cincinnati / Kroger HQ) or tap **📍 Use My Current Location**.
3. Select your local store. The app queries the Kroger Products API via your backend and converts package sizes to servings, showing green **LIVE** price badges on matching items.
4. Go to the **Shop** tab: whole packages assigned to Kroger display an active **🛒 Send to Kroger Cart** button.
5. Tap **Send to Kroger Cart**. The app opens `ASWebAuthenticationSession` with PKCE.
6. Sign in with a Kroger customer or developer test account.
7. Upon successful authentication, items are added to your Kroger cart.
8. Tap **Open My Kroger Cart to Check Out** to review your items directly on Kroger.com or in the native Kroger iOS app!

