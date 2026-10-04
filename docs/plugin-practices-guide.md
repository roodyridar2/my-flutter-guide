# Practices taken from the two Flutter plugins

What is worth keeping from the two installed plugins, adapted to this project's stack (Riverpod, go_router, Dio, Freezed, feature-first layout).

Sources, read 2026-10-04:

- **Very Good Ventures `vgv-ai-flutter-plugin` 0.0.5**: 15 skills plus reference files, hooks and one reviewer agent. Read through a delegated review; I then checked the sections cited below against the source files.
- **`flutter-skills` 1.0.0** by Andrea D.: read directly, except its Flame game skill.

**Plugin** marks what a plugin teaches (paraphrased). **Adapted** marks how I changed it for this stack. Code samples have not been compiled.

---

## 1. Verdict

| Plugin | Is it best practice? |
|---|---|
| Very Good Ventures | Mostly yes for the topics that do not depend on the state manager: tests, security, theming, accessibility, localization, navigation. It is written for a different stack, though: Bloc, `very_good_analysis`, Very Good CLI and separate packages per layer. Those parts do not transfer, and a few of its samples are out of date or break its own rules (section 12). |
| flutter-skills | No. It is one app's house style. Its Riverpod patterns contradict Riverpod's documentation, and its templates import that app's own classes. A few small ideas are worth taking (sections 2 and 10). |

---

## 2. Tests

Extends [quality-guide.md](quality-guide.md), section 3.

**Plugin (VGV testing skill):**

- `test/` mirrors `lib/`, one test file per source file.
- Names read as a sentence: a group for the class, a nested group for the method, a test for the behaviour. Refer to types by interpolation (`'returns $Event'`) so a rename updates the name.
- Mocks are private to the file (`_MockX`). A mock is never imported from another test file.
- `setUp` and `tearDown` live inside a `group`, never at the top of `main()`. Mutable objects are declared `late` and created in `setUp`.
- No state shared between tests. Every test passes alone, in any order.
- `mocktail`, not `mockito`.
- Widgets are pumped through one shared `pumpApp` helper, never an inline `MaterialApp`.
- Prefer `pump()` to `pumpAndSettle()`. The second never returns while something animates forever, such as a progress indicator.
- Finders: by type first, by text for what the user reads, by key only when the others are ambiguous.
- Widget tests assert behaviour. Appearance belongs to golden tests, which carry a tag from a constants class so they can run separately.

**Plugin (flutter-skills and VGV both):** run with a random order to expose tests that depend on each other.

```bash
flutter test --coverage --test-randomize-ordering-seed random
```

**Adapted:** the VGV skill mocks the Bloc in widget tests. With Riverpod the opposite holds: keep the real Notifier and override the repository. The helper therefore takes provider overrides.

```dart
// test/helpers/pump_app.dart
extension PumpApp on WidgetTester {
  Future<void> pumpApp(
    Widget widget, {
    List<Override> overrides = const [],
  }) {
    return pumpWidget(
      ProviderScope(
        overrides: overrides,
        retry: (_, _) => null,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: widget,
        ),
      ),
    );
  }
}
```

```dart
class _MockEventRepository extends Mock implements EventRepository {}

void main() {
  group(EventsScreen, () {
    late _MockEventRepository repository;

    setUp(() => repository = _MockEventRepository());

    group('renders', () {
      testWidgets('the list when loading succeeds', (tester) async {
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
    });
  });
}
```

In Riverpod 3 the `Override` type may need the `misc.dart` import; confirm when writing the helper.

---

## 3. Quality gate

Extends [quality-guide.md](quality-guide.md), section 1.

**Plugin (VGV green-gate skill):**

- Fixed order: analyze, then format, then test, then coverage. All four must pass in the same run; a fix for one can break another.
- Never weaken a gate to pass it: no deleted assertions, no lowered threshold, no `// coverage:ignore` on reachable code.
- Generated code is excluded from coverage: `*.g.dart`, `*.freezed.dart`, `*.gen.dart` and the localization output.
- Their default threshold is 100% of hand-written code.

**Adapted:**

- Keep the order and the "never weaken" rule as they are.
- Coverage: 100% is VGV's house standard and is expensive on UI code. Set a number the team will actually hold, enforce it in CI, and only ever raise it. Notifiers and repositories should be fully covered whatever the overall number is.
- The gate is the CI commands in the quality guide plus the coverage step. Nothing in it needs Very Good CLI.

---

## 4. Security

Extends [dio-guide.md](dio-guide.md) section 7, [storage-guide.md](storage-guide.md) section 2 and [quality-guide.md](quality-guide.md) section 2.

**Plugin (VGV static-security skill):**

- **Nothing shipped in the app is secret.** API keys and passwords in source or config can be extracted from the binary. `--dart-define`, `String.fromEnvironment`, a bundled `.env` file, a native config file and obfuscation all leave the value in the app. A real secret stays on a backend.
- Tokens and personal data go in secure storage, never in shared preferences.
- HTTPS only. Certificate validation is never disabled outside local development.
- `Random.secure()` for anything security-related. No home-made cryptography.
- Authorisation is enforced by the server and the data layer. Hiding a button is not access control.
- No sensitive data in logs, and no raw exception text shown to the user.
- `android:allowBackup="false"`.
- Release builds are obfuscated:

```bash
flutter build apk --obfuscate --split-debug-info=build/symbols/
```

```bash
flutter build ipa --obfuscate --split-debug-info=build/symbols/
```

- Before each release, scan the resolved dependency tree. The lockfile is what gets scanned, because advisories usually land on transitive packages:

```bash
osv-scanner --lockfile=pubspec.lock
```

```bash
dart pub outdated
```

- An advisory may be ignored only with the reason written beside the entry in `pubspec.yaml`.
- Apps handling money or health data can add runtime checks for rooted devices and tampering (the plugin names `freerasp`).

**Adapted:**

- `String.fromEnvironment('API_BASE_URL')` in the Dio guide is fine. A base URL is configuration, not a secret. The rule is about keys and passwords.
- Keep the `build/symbols/` output of each release. Crash reports from an obfuscated build cannot be read without it.
- The plugin also says not to build your own authentication and to use a provider such as Firebase Auth or Auth0. That is a product decision. If the backend issues its own tokens, the refresh flow in the Dio guide stands.
- The plugin rates missing certificate pinning as a warning everywhere. I keep it optional: pin when the app handles payments or similar, and plan for certificate rotation first.

---

## 5. Theming

New topic; no existing guide covers it.

**Plugin (VGV material-theming and ui-package skills):**

- `ThemeData` is the only source of colours and text styles.
- In widgets, colours come from `Theme.of(context).colorScheme` and text styles from `textTheme`. No `Colors.blue`, no raw `Color(...)`, and no `fontSize` or `fontWeight` inside a `build` method.
- Repeated styling goes into component themes (`FilledButtonThemeData`, `InputDecorationTheme`, …), not into wrapper widgets or shared style constants.
- Spacing comes from a named scale built on one base unit. No arbitrary pixel values.
- Light and dark themes exist from the first day. Widgets never branch on brightness.
- App-specific tokens that Material has no slot for go in a `ThemeExtension`.

**Adapted:**

```dart
abstract final class AppSpacing {
  static const double unit = 8;
  static const double xs = unit / 2; // 4
  static const double sm = unit;     // 8
  static const double md = unit * 2; // 16
  static const double lg = unit * 3; // 24
  static const double xl = unit * 4; // 32
}

@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({required this.success});
  final Color success;

  @override
  AppColors copyWith({Color? success}) =>
      AppColors(success: success ?? this.success);

  @override
  AppColors lerp(AppColors? other, double t) {
    if (other == null) return this;
    return AppColors(success: Color.lerp(success, other.success, t)!);
  }
}

ThemeData buildTheme(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF2E6BE6),
    brightness: brightness,
  );
  return ThemeData(
    colorScheme: scheme,
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
    ),
    inputDecorationTheme: const InputDecorationTheme(
      border: OutlineInputBorder(),
    ),
    extensions: [
      AppColors(
        success: brightness == Brightness.light
            ? const Color(0xFF1B7F3B)
            : const Color(0xFF6FD08C),
      ),
    ],
  );
}
```

```dart
MaterialApp.router(
  theme: buildTheme(Brightness.light),
  darkTheme: buildTheme(Brightness.dark),
  themeMode: ref.watch(themeModeSettingProvider),
);

final success = Theme.of(context).extension<AppColors>()!.success;
```

The one brightness check lives in the theme builder, not in widgets. The theme-mode setting is the one in [storage-guide.md](storage-guide.md).

---

## 6. Accessibility

New topic; no existing guide covers it.

**Plugin (VGV accessibility skill):**

- Decide the target level first (WCAG A, AA or AAA) and which platforms.
- Every meaningful image has a semantic label. Decorative ones are excluded from semantics.
- Tappable things are real buttons or `InkWell`, not a bare `GestureDetector`, which keyboard and switch users cannot reach.
- Touch targets are at least 48 × 48 dp. WCAG's own floor is 24.
- Icon-only buttons have a tooltip or a semantic label.
- Colour is never the only signal. Pair it with text, an icon or a shape.
- Text is never placed in a fixed-height box. Use a minimum height so large font sizes do not clip.
- Text and controls meet the contrast ratio for the chosen level.
- Fields for personal data (email, password, name, phone, one-time code) set `autofillHints`.
- A drag gesture always has a non-drag alternative: a delete button beside a swipe-to-dismiss, for example.
- Changes that happen without user action (loading finished, error appeared) are announced, for example with `Semantics(liveRegion: true)`.
- Animations respect the system's reduce-motion setting.

**Adapted:** test with the real screen readers (TalkBack and VoiceOver) and with the largest system font size before each release. Several of the plugin's sample tests only check that the text they just built exists, so they are not a substitute.

---

## 7. Localization additions

Extends [localization-guide.md](localization-guide.md).

**Plugin (VGV internationalization skill):**

- Shared, reusable widgets receive their strings as constructor parameters. They do not call `AppLocalizations` themselves.
- Set `preferred-supported-locales` in `l10n.yaml`. Without it the locale list is alphabetical, and the first entry is the fallback.
- Directional Material icons, such as the forward arrow, mirror themselves in right-to-left layouts. Images do not; set `matchTextDirection: true` on images that point somewhere.
- The backend returns error **codes**. The app maps each code to a translated message, with a generic fallback.
- The client tells the backend which language the user has, so server-provided content arrives translated.

**Adapted:** send the language as an `Accept-Language` header from the Dio provider. The error-code mapping is the `switch` over `AppException` already in the models guide.

---

## 8. Navigation additions

Extends [go-router-guide.md](go-router-guide.md).

**Plugin (VGV navigation skill):**

- URL segments use hyphens: `/event-details`, never underscores or camelCase.
- Two levels of guard. The root redirect answers "is the user signed in?". A route-level redirect answers "may this user see this section?".
- Navigation is unit-tested: the widget is pumped under a mocked router, and the test verifies which navigation call was made.

**Adapted:**

```dart
class _MockGoRouter extends Mock implements GoRouter {}

testWidgets('opens the details route on tap', (tester) async {
  final router = _MockGoRouter();

  await tester.pumpApp(
    InheritedGoRouter(goRouter: router, child: const HomeScreen()),
  );
  await tester.tap(find.text('View details'));

  verify(
    () => router.go(
      const DetailsRoute(id: 1).location,
      extra: any(named: 'extra'),
    ),
  ).called(1);
});
```

Redirect logic is easiest to test as a plain function: call the guard with a signed-in and a signed-out state and assert the returned path.

The plugin's own route samples are not usable as written; see section 12.

---

## 9. Animations

The full treatment is now in [animations-guide.md](animations-guide.md); this section is the part that came from the VGV plugin.

**Plugin (VGV animations skill):**

- Use the simplest tool that works. Implicit widgets (`AnimatedOpacity`, `AnimatedContainer`, `AnimatedSwitcher`) come before an `AnimationController`.
- Durations and curves come from Flutter's Material 3 motion tokens, `Durations` and `Easing`, not from literal numbers.
- Every controller is disposed. One controller uses `SingleTickerProviderStateMixin`.
- Keep the animated subtree small, and pass the unchanging part through the builder's `child`.
- Page transitions are set on the route with `CustomTransitionPage`.

**Adapted:** the accessibility skill requires respecting reduce-motion, but the animations skill never shows it. Combine them:

```dart
AnimatedOpacity(
  opacity: visible ? 1 : 0,
  duration: MediaQuery.disableAnimationsOf(context)
      ? Duration.zero
      : Durations.medium2,
  curve: Easing.standard,
  child: child,
);
```

---

## 10. Architecture boundaries

Extends [architecture-guide.md](architecture-guide.md), which holds the layers and the folder layout.

**Plugin (VGV layered-architecture skill):**

- Dependencies run one way: presentation → business logic → repository → data. No layer is skipped or reversed.
- A repository never depends on another repository. Combining two of them is the business-logic layer's job.
- A repository receives its API client through its constructor. It never creates one itself.
- The shape of an API response does not leak upward. When the response and the app's model differ, the repository converts.

**Plugin (flutter-skills):** features do not import each other. Anything shared moves to a common folder.

**Adapted:**

- Keep these rules inside the single-package layout of the architecture guide. In this stack "business logic" is the Notifier, and "combining repositories" happens in a provider that watches both.
- VGV puts each data client and each repository in its own Dart package. That enforces the rules by construction, at the cost of many `pubspec.yaml` files. It is worth it for a large team or shared packages; for one app, folders plus review are enough.
- Use one Freezed model while the API shape and the app's needs match. Split into a response model and a domain model only where they diverge.
- Other small points from flutter-skills: put domain helpers in extensions on the model, mark read-only fields with `includeToJson: false`, and put a timeout on calls the app's startup waits for.

---

## 11. Maintenance

**Plugin (VGV SDK-upgrade and license-compliance skills):**

- An SDK upgrade is its own pull request. It changes only the CI Flutter version and the `environment` block in `pubspec.yaml`: no dependency bumps and no code changes.
- `sdk:` in `pubspec.yaml` is the **Dart** version. Look up which Dart ships with a Flutter release; do not guess it from the Flutter number.
- CI pins the Flutter version instead of using "latest stable".
- Licences are checked across all dependencies, including transitive ones. A package with no licence is a finding.

**Adapted:** the same single-purpose rule works for lint-set upgrades: one pull request with the version bump and the fixes for newly reported lints, nothing else.

---

## 12. Left out, and why

| From | What | Why it was not adopted |
|---|---|---|
| VGV | Bloc skill, `RepositoryProvider`, `blocTest` | Different state manager. |
| VGV | Mock the Bloc in widget tests | With Riverpod, mocking the Notifier is what the docs advise against. |
| VGV | `very_good_analysis` | A stricter lint set than `flutter_lints`, and a reasonable alternative. The guides already add strict modes and `riverpod_lint`; use one base set, not both. |
| VGV | 100% coverage as the default | Their house standard. See section 3. |
| VGV | A package per data client and repository | See section 10. Their "no Flutter SDK in data packages" rule also cannot hold for secure storage or shared preferences. |
| VGV | Typed-route samples | They omit the generated mixin that `go_router_builder` 4 requires. |
| VGV | Auth redirect sample | It reads the Bloc state but has nothing that re-runs the redirect when the user signs in or out. The go_router guide uses `refreshListenable` for that. |
| VGV | "Never use `Navigator`" | Stricter than go_router's own docs, and the plugin's own samples call `Navigator` in several places. |
| VGV | Use both typed routes and `goNamed` | Pick one. The guides use typed routes. |
| VGV | Legacy `SharedPreferences.getInstance()` in samples | The package now recommends the newer APIs. |
| VGV | Scaffolding only through Very Good CLI | A tool choice. `flutter create` is fine. |
| VGV | `formz` required for form validation | A library preference, not a security control. |
| flutter-skills | `init()` called from `initState` | Riverpod's docs say providers initialise themselves. |
| flutter-skills | A `status` enum in state instead of `AsyncValue` | Re-implements what Riverpod provides, and loses the error. |
| flutter-skills | `keepAlive: true` on every generated notifier | The docs default to auto-dispose. |
| flutter-skills | Only `ref.read` getters, never `ref.watch` in `build` | Dependencies stop being reactive. |
| flutter-skills | `pushNamed` as the default navigation | go_router's docs default to `go`. |
| flutter-skills | `mockito` with generated mocks | The stack uses `mocktail`. |
| flutter-skills | All templates | They import `package:aworld/...` and that app's classes, so they do not compile elsewhere. |

Inconsistencies inside the VGV plugin, for awareness: several of its own samples use public mocks, top-level `setUp` and inline `MaterialApp`, against its testing rules; and its pubspec samples name `very_good_analysis ^7.0.0` while its upgrade skill refers to 10.0.0.

---

## 13. Running the plugins themselves

What the VGV plugin does when it is enabled in a Claude session:

- After every edit of a `.dart` file it runs `dart analyze` and `dart format` on that file.
- It blocks `flutter test`, `dart test`, `flutter create` and `dart create` in the shell and redirects to Very Good CLI. Without that CLI installed (version 1.3.0 or newer) those commands are simply refused.
- Its reviewer agent always loads the Bloc skill, so it will review Riverpod code against Bloc rules.

**Recommendation:**

- **flutter-skills:** disable it for this project. Its `flutter-dev` skill applies automatically and pushes the patterns rejected above.
- **VGV:** useful as a reference, and its accessibility, theming and security skills can be invoked on demand. Leaving it fully enabled means installing Very Good CLI and accepting Bloc-oriented reviews. A file written before its generated `part` exists will also probably fail the analyze hook.

---

## 14. Review checklist

- [ ] Tests mirror `lib/`, read as sentences, and use private mocks with `setUp` inside groups.
- [ ] Widgets are pumped through `pumpApp` with provider overrides; no inline `MaterialApp`.
- [ ] The suite passes with a random test order.
- [ ] CI runs analyze, format, test and coverage, in that order; no gate was weakened to pass.
- [ ] No key, password or secret is compiled into the app.
- [ ] Release builds are obfuscated and their symbol files kept.
- [ ] Dependencies were scanned before release; every ignored advisory has a written reason.
- [ ] No hard-coded colours, font sizes or spacing values in widgets.
- [ ] Light and dark themes both exist; widgets do not branch on brightness.
- [ ] Images are labelled, icon buttons have tooltips, and touch targets are at least 48 dp.
- [ ] No fixed-height box around text; the app was checked at the largest font size.
- [ ] Animations use motion tokens and respect reduce-motion.
- [ ] Shared widgets take their strings as parameters.
- [ ] URL segments use hyphens.
- [ ] Features do not import each other; repositories do not depend on each other.
- [ ] SDK and lint upgrades are single-purpose pull requests.
