# Gemma 4 Agentic - On-Device AI Assistant

A powerful, private, and fully on-device AI assistant built with Flutter and **Gemma 4**. This application leverages multimodal vision and agentic tool-calling to perform real-world actions directly on your mobile device.

## 🚀 Features

- **Gemma 4 & Multi-Model Support**: Analyze images and text locally using Gemma 4 E2B, with built-in auto-detection for Gemma 2b, 7b, and 3n versions.
- **Agentic Capabilities**: The assistant can automatically invoke tools to help you:
  - 📞 **Make Calls**: Search contacts and open the dialler.
  - 🌐 **Web Search**: Get private, up-to-date information via DuckDuckGo.
  - ⏰ **Set Alarms**: Schedule reminders and alarms on Android.
  - 📱 **Open Apps**: Launch any installed application by name.
- **Advanced History Management**: 
  - **Granular Deletion**: Delete individual conversations with a safety confirmation dialog.
  - **Auto-Sync**: History is automatically saved and synced to the sidebar.
- **Professional UI/UX**: 
  - **Clean Sidebar**: Distraction-free chat with settings and history managed in a slide-out drawer.
  - **Dark Mode**: Optimized for OLED screens with modern glassmorphism elements.
  - **Voice Integration**: Hands-free **Speech-to-Text** (STT) and rhythmic **Text-to-Speech** (TTS).
- **Full Privacy**: No data leaves your device. All inference and tool execution happen locally.

## 🏗️ Architecture

This project follows a **Feature-First Architecture** inspired by Clean Architecture:

- **Data Layer**: Handles persistence (`HistoryService`) and external APIs (`WebSearchService`).
- **Domain Layer**: Contains plain models (`ChatMessage`, `ChatHistory`).
- **Logic Layer**: Manages core business logic (`ChatService`) and tool execution (`ToolHandler`).
- **Presentation Layer**: Modular UI components and screens (`ChatScreen`).

## 🛡️ Security Best Practices

Before pushing to public repositories:

1. **Secret Management**: Do not hardcode API keys or tokens. 
2. **Environment Variables**: Use `--dart-define` for secure builds:
   ```bash
   flutter run --dart-define=HF_TOKEN=your_token_here
   ```
3. **Git Hygiene**: Sensitive files like `.env`, `*.keystore`, and `local.properties` are excluded via `.gitignore`.

## 📦 Getting Started

1. **Clone the repository**:
   ```bash
   git clone https://github.com/Davilash/gemma-on-device-flutter.git
   ```
2. **Install dependencies**:
   ```bash
   flutter pub get
   ```
3. **Download the Model**:
   Upon first launch, the app scans for existing models. If none are found, you'll be prompted to download the **Gemma 4** model (~390MB).

## 🏁 How to Build

If `flutter build apk` fails to find the output on your system, build directly via Gradle:

```bash
cd android
./gradlew assembleDebug
```

The APK will be generated at:
`android/app/build/outputs/apk/debug/app-debug.apk`

*Note: For easy access, look for `flutter_gemma_debug.apk` in the project root after running our custom copy script.*

---
*Built with ❤️*
