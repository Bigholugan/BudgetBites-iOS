# BudgetBites for iOS 🥗

A complete native iOS wrapper and offline application for **BudgetBites – Daily Meal Planner**, built with Swift, SwiftUI, and WebKit.

---

## 📁 Project Architecture

```
BudgetBites-iOS/
├── BudgetBites.xcodeproj/       # Xcode project file (open in Xcode 14+)
├── BudgetBites/
│   ├── App/
│   │   └── BudgetBitesApp.swift       # Native SwiftUI entry point
│   ├── Views/
│   │   └── WebViewContainer.swift     # WKWebView wrapper with haptics & offline storage
│   ├── Resources/
│   │   ├── Assets.xcassets/           # 1024x1024 AppIcon and image catalogs
│   │   └── Info.plist                 # iOS permissions, status bar & orientation settings
│   └── www/                           # Bundled offline web application
│       ├── index.html                 # Complete meal planner with safe area & haptic support
│       ├── manifest.json              # Web App manifest for PWA installation
│       └── icon-512.png               # High-resolution app icon
├── .github/workflows/
│   └── build-and-sign.yml             # Cloud CI/CD to build & sign .ipa on GitHub's macOS runners
├── ExportOptions.plist                # Archive export configuration
└── README.md
```

---

## 🚀 How to Build and Sign

Because iOS requires Apple Developer cryptographic signatures and the Apple SDK (which runs on macOS), here are the four ways to build, sign, and install this app:

### Method 1: Using Xcode on a Mac (Recommended if you have a Mac)
1. Transfer this folder to your Mac.
2. Open `BudgetBites.xcodeproj` in Xcode.
3. Select the **BudgetBites** target in the left navigator.
4. Under the **Signing & Capabilities** tab:
   - Check **"Automatically manage signing"**.
   - Under **Team**, select your Apple ID (Free Personal Team or Paid Apple Developer Account).
   - If prompted, change the Bundle Identifier from `com.budgetbites.app` to something unique (e.g. `com.yourname.budgetbites`).
5. Connect your iPhone via USB, select your device in the top bar, and press **Run (Cmd + R)**.
6. On your iPhone: Go to **Settings > General > VPN & Device Management**, tap your Apple ID, and tap **Trust**.

---

### Method 2: Free Automated Cloud Build via GitHub Actions (No Mac Required)
This project includes a pre-configured GitHub Actions workflow in `.github/workflows/build-and-sign.yml` that builds on Apple Silicon macOS runners in the cloud:

1. Push this folder to a GitHub repository (Public or Private):
   ```bash
   git init
   git add .
   git commit -m "Initial commit of BudgetBites iOS"
   git branch -M main
   git remote add origin https://github.com/YOUR_USERNAME/budgetbites-ios.git
   git push -u origin main
   ```
2. **If you have Apple Developer Signing Credentials**, add these in GitHub repository **Settings > Secrets and variables > Actions**:
   - `BUILD_CERTIFICATE_BASE64`: Base64 string of your `.p12` distribution certificate
   - `P12_PASSWORD`: Password for your `.p12` file
   - `BUILD_PROVISION_PROFILE_BASE64`: Base64 string of your `.mobileprovision` file
   - `KEYCHAIN_PASSWORD`: Any temporary password string (e.g. `secret123`)
3. Go to the **Actions** tab in your GitHub repository and trigger the **Build & Export iOS App** workflow.
4. Download the generated **`BudgetBites.ipa`** from the Workflow Artifacts.
*(Note: If you don't add secrets, it will produce an unsigned `.ipa` that can be signed with Sideloadly or AltStore).*

---

### Method 3: Sideload onto iPhone on Windows (Using Sideloadly or AltStore)
If you build an unsigned `.ipa` or want to install directly from your Windows PC using your standard Apple ID:
1. Download [Sideloadly](https://sideloadly.io/) or [AltStore](https://altstore.io/) for Windows.
2. Connect your iPhone to your PC via USB.
3. Drag the `BudgetBites.ipa` into Sideloadly.
4. Enter your Apple ID and click **Start**. It will automatically sign the app with your free personal Apple ID and install it directly to your device!

---

### Method 4: Instant Safari Web Clip / PWA (Zero compile, 10 seconds)
You can also run this directly on any iPhone right now without any compilation or signing:
1. In this project directory, run a local web server:
   ```bash
   cd BudgetBites/www
   python -m http.server 8080
   ```
2. Open Safari on your iPhone, navigate to `http://<YOUR_PC_LOCAL_IP>:8080`.
3. Tap the **Share** button (box with upward arrow) at the bottom of Safari.
4. Scroll down and tap **"Add to Home Screen"**.
5. It will install with the custom BudgetBites app icon and run full-screen without browser bars, supporting offline storage and the complete meal planning suite.
