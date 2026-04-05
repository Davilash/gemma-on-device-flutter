# Gemma 4 Agentic - On-Device AI Assistant

A powerful, private, and fully on-device AI assistant built with Flutter and **Gemma 4**. This application leverages multimodal vision and agentic tool-calling to perform real-world actions directly on your mobile device.

## 🚀 Features

- **Gemma 4 Multimodal**: Analyze images and text locally using the latest Gemma 4 E2B model.
- **Agentic Capabilities**: The assistant can automatically invoke tools to help you:
  - 📞 **Make Calls**: Search contacts and open the dialler.
  - 🌐 **Web Search**: Get up-to-date information via DuckDuckGo.
  - ⏰ **Set Alarms**: Schedule reminders and alarms on Android.
  - 📱 **Open Apps**: Launch any installed application by name.
- **Interactive Messaging**: Beautiful dark mode UI with markdown support, image previews, and smooth animations.
- **Voice Features**: Integrated **Speech-to-Text** for hands-free input and **Text-to-Speech** for audio responses.
- **Full Privacy**: No data leaves your device. All inference and tool execution happen locally.

## 🏗️ Architecture

This project follows a **Feature-First Architecture** with a clear separation of concerns (Clean Architecture principles):

- **Data Layer**: Handles persistence (`HistoryService`) and external APIs (`WebSearchService`).
- **Domain Layer**: Contains plain models (`ChatMessage`, `ChatHistory`).
- **Logic Layer**: Manages the core business logic (`ChatService`) and tool execution (`ToolHandler`).
- **Presentation Layer**: UI screens and widgets (`ChatScreen`).

## 🛡️ Security Best Practices

To ensure project security before pushing to public repositories:

1. **Secret Management**: Do not hardcode API keys or tokens (e.g., Hugging Face tokens). 
2. **Environment Variables**: Use `--dart-define` or `.env` files. This app is configured to use:
   ```bash
   flutter run --dart-define=HF_TOKEN=your_token_here
   ```
3. **Data Privacy**: All chat history is stored locally using `SharedPreferences`. For production apps with high-security needs, consider `flutter_secure_storage`.

## 📦 Getting Started

1. **Clone the repository**:
   ```bash
   git clone https://github.com/your-username/flutter_gemma.git
   ```
2. **Install dependencies**:
   ```bash
   flutter pub get
   ```
3. **Download the Model**:
   Upon first launch, the app will prompt you to download the **Gemma 4 E2B** model (~390MB) from Hugging Face.

## 🏁 How to Build

If you encounter issues with the standard `flutter build apk` command due to custom build outputs, you can build directly using Gradle:

```bash
cd android
./gradlew assembleDebug
```

The APK will be generated at:
`build/app/outputs/apk/debug/app-debug.apk`

---
*Built with ❤️ using Google Gemma 4.*
