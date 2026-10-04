# Lints, logging and tests — recommended approach

Covers `flutter_lints`, `riverpod_lint`, `logger` and `mocktail`.

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
class MockEventRepository extends Mock implements EventRepository {}

final repository = MockEventRepository();

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
void main() {
  late MockEventRepository repository;

  setUp(() => repository = MockEventRepository());

  ProviderContainer makeContainer() => ProviderContainer.test(
    overrides: [eventRepositoryProvider.overrideWithValue(repository)],
    retry: (_, _) => null,
  );

  test('loads events', () async {
    when(() => repository.fetchAll()).thenAnswer(
      (_) async => [const Event(id: 1, title: 'A')],
    );
    final container = makeContainer();

    container.listen(eventsProvider, (_, _) {}); // keeps auto-dispose alive
    final events = await container.read(eventsProvider.future);

    expect(events, hasLength(1));
    verify(() => repository.fetchAll()).called(1);
  });

  test('exposes the error', () async {
    when(() => repository.fetchAll()).thenThrow(const AppException.timeout());
    final container = makeContainer();

    container.listen(eventsProvider, (_, _) {});
    await expectLater(container.read(eventsProvider.future), throwsA(anything));

    // The future rethrows a ProviderException; the state holds the original.
    expect(container.read(eventsProvider).error, isA<RequestTimeout>());
  });
}
```

### A widget test

```dart
testWidgets('shows the list', (tester) async {
  when(() => repository.fetchAll()).thenAnswer(
    (_) async => [const Event(id: 1, title: 'A')],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [eventRepositoryProvider.overrideWithValue(repository)],
      child: const MaterialApp(home: EventsScreen()),
    ),
  );
  await tester.pumpAndSettle();

  expect(find.text('A'), findsOneWidget);
});
```

**Recommendation:**

- Mock at the repository boundary. The Riverpod docs advise against mocking Notifiers; test the real Notifier with a mocked repository.
- Turn automatic retry off in tests so a failure is reported at once.
- Every Notifier gets at least a success test and a failure test. Screens with branching UI get one widget test per branch (loading, data, empty, error).
- For simple dependencies a hand-written fake (`class FakeEventRepository implements EventRepository`) reads better than a mock.

---

## 4. Review checklist

- [ ] `flutter analyze` is clean; no blanket `ignore_for_file` outside generated code.
- [ ] Format, analyze and test run in CI.
- [ ] One `Logger` from a provider; no `print`.
- [ ] Release builds log warnings and above, to crash reporting, with no secrets.
- [ ] Async stubs use `thenAnswer`; fallback values registered in `setUpAll`.
- [ ] Tests override repositories, not Notifiers.
- [ ] Retry disabled in test containers.
