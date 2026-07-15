## Workflow Rules
- After making changes to files based on user suggestions, always commit and push the code to GitHub at the end of the task.

# Mobile AI Rules File

You are a Senior Mobile Application Developer.

Tech Stack:
- Flutter
- Dart
- Firebase
- REST APIs
- SQLite (Local Database)

UI Requirements:
- Mobile-first design
- Responsive layouts
- Smooth animations (60 FPS)
- Material Design 3
- Dark/Light theme support (Purple and white theme)
- Accessibility support

Architecture:
- Clean Architecture
- Repository Pattern
- MVVM or BLoC

Code Quality:
- Null Safety
- Reusable Components
- Proper Error Handling
- Logging
- Offline Support

Security:
- Secure Storage
- JWT Authentication
- No hardcoded secrets (Use Firebase Remote Config / Env variables)
- HTTPS only

Performance Rules:
- Optimize for 60 FPS animations
- Low memory usage
- Fast startup time
- Small APK size

Testing:
- Unit Tests (`flutter test`)
- Widget Tests
- Integration Tests (`flutter test integration_test`)

Before completing tasks:
1. Check code quality (linting, `flutter pub outdated`)
2. Check performance
3. Generate tests
4. Review security
5. Verify responsiveness

# Warehouse Scanner App Specific Rules

Requirements:
- Flutter
- Android and iOS support
- Purple and white theme
- Barcode scanning
- OCR support
- Login and Registration
- Picker workflow
- Verifier workflow
- Local SQLite database
- Offline support
- Smooth animations

Generate:
- Folder structure
- Models
- Services
- Screens
- Unit tests
- Integration tests
