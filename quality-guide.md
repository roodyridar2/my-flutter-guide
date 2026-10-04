# Lints, logging and tests — recommended approach

Covers `flutter_lints`, `riverpod_lint`, `logger`, `mocktail` and `integration_test`.

Sources, read 2026-10-04: [flutter_lints](https://pub.dev/packages/flutter_lints), [riverpod_lint](https://pub.dev/packages/riverpod_lint), [logger](https://pub.dev/packages/logger), [mocktail](https://pub.dev/packages/mocktail), and the Riverpod [testing guide](https://riverpod.dev/docs/how_to/testing).

Versions documented: `flutter_lints 6.0.0`, `riverpod_lint 3.1.9`, `logger 2.8.0`, `mocktail 1.0.5`.

**Docs** marks what the documentation states; **Recommendation** marks my reading of it. Code samples have not been compiled.

---

## 1. Lints

### Setup

```bash
flutter pub add dev:flutter_lints
```

```yaml
# analysis_options.yaml
include: package:flutter_lints/flutter.yaml

analyzer:
  language:
    strict-casts: true
    strict-inference: true
    strict-raw-types: true
  errors:
    invalid_annotation_target: ignore   # @JsonKey on Freezed parameters

plugins:
  riverpod_lint: 3.1.9

linter:
  rules:
    unawaited_futures: true
    avoid_dynamic_calls: true
    prefer_single_quotes: true
```

**Docs:** `flutter_lints` is the Flutter team's recommended set, built on the `recommended` set of `package:lints`. Rules are switched per project under `linter: rules:`, and silenced locally with `// ignore: rule_name` or `// ignore_for_file: rule_name`. New lints arrive only in major versions, roughly once a year.

**Recommendation:** the three `strict-*` modes and the extra rules above are mine. They catch implicit `dynamic`, which is where most JSON-handling bugs start. `riverpod_lint` is set up under `plugins:`, not in `pubspec.yaml`; its rules are listed in [riverpod-guide.md](riverpod-guide.md).

### In CI

```bash
dart format --output=none --set-exit-if-changed .
```

```bash
flutter analyze
```

```bash
flutter test
```

A warning is either fixed or ignored on that line with a reason. Do not leave a standing list of warnings.

---

## 2. Logging

### Levels

| Call | Use for |
|---|---|
| `logger.t` | Trace: very detailed flow |
| `logger.d` | Debug: values useful while developing |
| `logger.i` | Info: notable events (signed in, sync finished) |
| `logger.w` | Warning: handled problems (retry, fallback used) |
| `logger.e` | Error: an operation failed |
| `logger.f` | Fatal: the app cannot continue |

### Setup

```dart
@Riverpod(keepAlive: true)
Logger logger(Ref ref) {
  final logger = Logger(
    filter: kReleaseMode ? ProductionFilter() : DevelopmentFilter(),
    level: kReleaseMode ? Level.warning : Level.debug,
    printer: PrettyPrinter(
      methodCount: 0,
      errorMethodCount: 8,
      colors: false,
      printEmojis: false,
    ),
    output: kReleaseMode ? CrashReportOutput() : ConsoleOutput(),
  );
  ref.onDispose(logger.close);
  return logger;
}

class CrashReportOutput extends LogOutput {
  @override
  void output(OutputEvent event) {
    final e = event.origin;
    // Forward e.level, e.message, e.error and e.stackTrace to crash reporting.
  }
}
```

```dart
logger.i('Signed in');
logger.e('Loading events failed', error: error, stackTrace: stackTrace);
```

**Docs:**

- The default `DevelopmentFilter` logs only in debug mode. In a release build nothing is logged unless a different filter is supplied.
- `Logger.level` sets a global minimum level.
- ANSI colours do not render in the Xcode console, which is why `colors: false` above.
- Other outputs: `FileOutput`, `AdvancedFileOutput`, `MemoryOutput`, `StreamOutput`, and `MultiOutput` to combine them. Other printers: `SimplePrinter`, `LogfmtPrinter`, `PrefixPrinter`, `HybridPrinter`.

**Recommendation:**

- One logger, provided through Riverpod. No `print` (the `avoid_print` lint is in `flutter_lints`).
- Never log tokens, passwords, or full request and response bodies in release.
- Route the two automatic sources into it: Dio's `LogInterceptor` in debug ([dio-guide.md](dio-guide.md)), and a Riverpod `ProviderObserver` whose `providerDidFail` calls `logger.e` ([riverpod-guide.md](riverpod-guide.md), section 12).
- Log an error once, where it is handled. Logging at every layer it passes through produces duplicates.

---

## 3. Tests with mocktail

### The API

```dart
class _MockEventRepository extends Mock implements EventRepository {}

final repository = _MockEventRepository();

when(() => repository.fetchAll()).thenAnswer((_) async => [event]);
when(() => repository.delete(any())).thenThrow(const AppException.timeout());

verify(() => repository.fetchAll()).called(1);
verifyNever(() => repository.delete(any()));
final id = verify(() => repository.delete(captureAny())).captured.single;
```

**Docs:**

- No code generation. A mock is `extends Mock implements X`.
- Stubs and verifications take a closure: `when(() => mock.method())`.
- A method returning a `Future` or `Stream` is stubbed with `thenAnswer`, not `thenReturn`.
- An unstubbed method returns `null`, which shows up as a `TypeError` for non-nullable return types. Stub every method the test reaches.
- `any()` with a custom type needs `registerFallbackValue(FakeX())` once, in `setUpAll`.
- Extension methods and top-level functions cannot be mocked. Mock the object they call.
- `reset(mock)` clears stubs and recorded calls.

### A Notifier test

```dart
class _MockEventRepository extends Mock implements EventRepository {}

void main() {
  group('eventsProvider', () {
    late _MockEventRepository repository;
    late ProviderContainer container;

    setUp(() {
      repository = _MockEventRepository();
      container = ProviderContainer.test(
        overrides: [eventRepositoryProvider.overrideWithValue(repository)],
        retry: (_, _) => null,
      );
      container.listen(eventsProvider, (_, _) {}); // keeps auto-dispose alive
    });

    test('returns the events from $EventRepository', () async {
      when(() => repository.fetchAll()).thenAnswer(
        (_) async => [const Event(id: 1, title: 'A')],
      );

      final events = await container.read(eventsProvider.future);

      expect(events, hasLength(1));
      verify(() => repository.fetchAll()).called(1);
    });

    test('exposes the error when loading fails', () async {
      when(() => repository.fetchAll())
          .thenThrow(const AppException.timeout());

      await expectLater(
        container.read(eventsProvider.future),
        throwsA(anything),
      );

      // The future rethrows a ProviderException; the state holds the original.
      expect(container.read(eventsProvider).error, isA<RequestTimeout>());
    });
  });
}
```

### A widget test

```dart
testWidgets('shows the list when loading succeeds', (tester) async {
  when(() => repository.fetchAll()).thenAnswer(
    (_) async => [const Event(id: 1, title: 'A')],
  );

  await tester.pumpApp(
    const EventsScreen(),
    overrides: [eventRepositoryProvider.overrideWithValue(repository)],
  );
  await tester.pump(); // the future completes, the screen rebuilds

  expect(find.text('A'), findsOneWidget);
});
```

`pumpApp` is the shared helper defined in [plugin-practices-guide.md](plugin-practices-guide.md), section 2, along with the naming and layout conventions used here.

**Recommendation:**

- Mock at the repository boundary. The Riverpod docs advise against mocking Notifiers; test the real Notifier with a mocked repository.
- Turn automatic retry off in tests so a failure is reported at once.
- Every Notifier gets at least a success test and a failure test. Screens with branching UI get one widget test per branch (loading, data, empty, error).
- For simple dependencies a hand-written fake (`class FakeEventRepository implements EventRepository`) reads better than a mock.

---

## 4. Integration tests

Sources, read 2026-10-04: the skill `flutter-add-integration-test` from the official Dart and Flutter plugin (installed copy; unchanged in the current repository), checked against [Check app functionality with an integration test](https://docs.flutter.dev/testing/integration-tests) on docs.flutter.dev. **Skill** and **Docs** mark what they say; **Adapted** marks my changes.

**Verdict:** useful, with two corrections from the docs.

- The skill runs everything with `flutter drive`. The docs use `flutter test integration_test/…` on phones and desktop, and `flutter drive` only for the browser.
- The skill adds `enableFlutterDriverExtension()` to the app's entry point. That is needed only for its interactive exploration through the Flutter MCP tools, not for `integration_test`. Never put it in the real `main.dart`; if you want that exploration, use a separate `lib/main_test.dart`.

### Setup

```bash
flutter pub add "dev:integration_test:{sdk: flutter}"
```

Tests live in `integration_test/` at the project root, in files named `<name>_test.dart`.

### Writing

**Skill and Docs:**

- Call `IntegrationTestWidgetsFlutterBinding.ensureInitialized()` first in `main()`.
- The API is the widget-test API: `testWidgets`, `tester.tap`, `tester.enterText`, finders and `expect`.
- After an interaction, `pumpAndSettle()` waits for the resulting animations and frames.
- Give the widgets a test must find a `Key`. Text changes with the language; keys do not.
- Bring off-screen items into view with `tester.scrollUntilVisible(item, 500, scrollable: list)` before touching them.

```dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('signs in and shows the home screen', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...await testOverrides(),
          apiClientProvider.overrideWithValue(FakeApiClient()),
        ],
        child: const MyApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(AppKeys.emailField), 'user@example.com');
    await tester.enterText(find.byKey(AppKeys.passwordField), 'secret');
    await tester.tap(find.byKey(AppKeys.signInButton));
    await tester.pumpAndSettle();

    expect(find.byType(HomeScreen), findsOneWidget);
  });
}
```

**Adapted:**

- Start the real `MyApp` under a `ProviderScope`. Override only the outermost dependency, the `ApiClient`, with a fake or a test server, so that everything above it runs for real.
- `main.dart` builds a list of startup overrides, such as the preferences instance. Put that in one function that both `main()` and the tests call (`testOverrides()` above).
- Keys are constants in one file (`AppKeys`), not strings repeated in widgets and tests.
- Keep these few: sign-in, the main journey, anything involving payment. They are slow, and each one that breaks for an unrelated reason costs trust in the suite.
- `pumpAndSettle()` times out on a screen with an endless animation. Use `pump(duration)` there.

### Running

**Docs:**

```bash
flutter test integration_test/app_test.dart
```

That one command covers a connected phone, an emulator or simulator, and desktop. The browser needs ChromeDriver and a small driver file:

```dart
// test_driver/integration_test.dart
import 'package:integration_test/integration_test_driver.dart';

Future<void> main() => integrationDriver();
```

```bash
chromedriver --port=4444
```

```bash
flutter drive --driver=test_driver/integration_test.dart --target=integration_test/app_test.dart -d chrome
```

Use `-d web-server` for a headless run.

**Skill and Docs**, Firebase Test Lab on Android: build the debug APK and the instrumentation test APK, upload both, and run them as an instrumentation test.

```bash
flutter build apk --debug
```

```bash
cd android && ./gradlew app:assembleAndroidTest
```

```bash
cd android && ./gradlew app:assembleDebug -Ptarget=integration_test/app_test.dart
```

The third command is in the docs but not in the skill; it points the build at the test file.

**Skill**, performance: wrap the actions in `binding.traceAction()` and use a driver script that writes the timeline summary to a file.

### When a test fails

**Skill:**

- `PumpAndSettleTimedOutException`: something on screen animates forever.
- A widget is not found: it is in a lazy list and not built yet. Scroll to it first.

---

## 5. Review checklist

- [ ] `flutter analyze` is clean; no blanket `ignore_for_file` outside generated code.
- [ ] Format, analyze and test run in CI.
- [ ] One `Logger` from a provider; no `print`.
- [ ] Release builds log warnings and above, to crash reporting, with no secrets.
- [ ] Async stubs use `thenAnswer`; fallback values registered in `setUpAll`.
- [ ] Tests override repositories, not Notifiers.
- [ ] Retry disabled in test containers.
- [ ] The critical journeys have an integration test that runs the real app above a fake `ApiClient`.
- [ ] Integration tests find widgets by key, and the keys are constants.
- [ ] `enableFlutterDriverExtension()` is not in the production entry point.
