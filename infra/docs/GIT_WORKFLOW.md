# SafeVision — Git & Team Workflow

## Branch Strategy: GitFlow

```
main          ← production releases (tag: v1.x.x)
  ↑
develop       ← integration branch, always deployable to staging
  ↑
feature/*     ← new features (branches from develop)
fix/*         ← bug fixes (branches from develop)
hotfix/*      ← urgent prod fixes (branches from main)
release/*     ← release preparation (branches from develop)
```

## Branch Naming Convention

```
feature/SV-XXX-short-description
fix/SV-XXX-short-description
hotfix/SV-XXX-short-description
release/v1.2.0
```

**Examples:**
```
fix/SV-001-tts-double-enqueue
fix/SV-002-isolate-busy-reset
feature/SV-050-object-history-log
hotfix/SV-099-crash-on-camera-switch
release/v1.1.0
```

## Commit Convention (Conventional Commits)

Format: `type(scope): description`

### Types
| Type     | Khi nào dùng |
|----------|--------------|
| `feat`   | Tính năng mới |
| `fix`    | Bug fix |
| `perf`   | Performance improvement |
| `refactor` | Code refactor (không thay đổi behavior) |
| `test`   | Thêm / sửa tests |
| `docs`   | Documentation |
| `chore`  | Build, CI, dependency updates |
| `style`  | Format, whitespace (không thay đổi logic) |

### Scopes
`tts` | `detection` | `camera` | `settings` | `ui` | `di` | `ci` | `model`

### Examples
```
fix(tts): remove double _enqueue() call in speakWarning (SV-001)
fix(detection): reset _isolateBusy in finally block (SV-002)
fix(detection): add CloseModelUsecase for clean architecture (SV-007)
feat(detection): use droppable() transformer for frame processing (SV-009)
perf(ui): add version counter to BoundingBoxPainter.shouldRepaint (SV-011)
test(tts): add unit tests for speakWarning cooldown logic
chore(ci): add GitHub Actions CI pipeline
fix(settings): pass speechRate when changing TTS language (SV-006)
```

### Breaking Changes
```
feat(detection)!: replace DetectionRepository injection with CloseModelUsecase

BREAKING CHANGE: DetectionBloc constructor no longer accepts repository parameter.
Use closeModel: CloseModelUsecase instead.
```

## PR Checklist

Copy vào PR description:

```markdown
## Description
<!-- Mô tả ngắn gọn thay đổi này làm gì -->

Closes #XXX

## Type of change
- [ ] Bug fix (SV-XXX)
- [ ] New feature
- [ ] Performance improvement
- [ ] Refactoring
- [ ] Documentation

## Testing
- [ ] Unit tests added/updated
- [ ] Widget tests added/updated
- [ ] Tested on Android (physical device or emulator)
- [ ] Tested on iOS (physical device or simulator)
- [ ] All existing tests pass (`flutter test`)

## Code Quality
- [ ] `flutter analyze` passes with no issues
- [ ] `dart format` applied
- [ ] No hardcoded strings (use constants)
- [ ] No `print()` statements (use `debugPrint()` with kDebugMode guard)

## Review Notes
<!-- Điểm cần reviewer chú ý đặc biệt -->
```

## Local Development Setup

```bash
# Clone và setup
git clone https://github.com/your-org/safe_vision_app.git
cd safe_vision_app
flutter pub get

# Chạy tests
flutter test

# Chạy specific test file
flutter test test/features/tts/tts_service_fix_test.dart

# Chạy tests với coverage
flutter test --coverage
genhtml coverage/lcov.info -o coverage/html
open coverage/html/index.html

# Format code
dart format lib/ test/

# Analyze
flutter analyze --fatal-infos
```

## Semantic Versioning

```
v{MAJOR}.{MINOR}.{PATCH}+{BUILD}

MAJOR: Breaking API changes
MINOR: New features (backward compatible)
PATCH: Bug fixes
BUILD: Auto-incremented by CI
```

Ví dụ: `1.2.3+47` trong `pubspec.yaml`:
```yaml
version: 1.2.3+47
```
