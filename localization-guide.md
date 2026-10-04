# Localization — recommended approach

Covers `flutter_localizations` and `intl`.

Sources, read 2026-10-04: [Internationalizing Flutter apps](https://docs.flutter.dev/ui/internationalization), [Localized messages are generated into source](https://docs.flutter.dev/release/breaking-changes/flutter-generate-i10n-source), [intl](https://pub.dev/packages/intl).

Versions: `flutter_localizations` comes from the Flutter SDK; `intl 0.20.3` is what resolves with Flutter 3.47.

**Docs** marks what the documentation states; **Recommendation** marks my reading of it. Code samples have not been compiled.

---

## 1. Decisions to make once

| Decision | Recommendation | What the docs say |
|---|---|---|
| Tool | Flutter's built-in `gen-l10n` with ARB files. | The official workflow. |
| Where code is generated | Into `lib/l10n`, imported as a normal file. | Since Flutter 3.32 the synthetic `package:flutter_gen` is no longer generated. |
| `intl` version | `intl: any`. | `flutter_localizations` pins the version; the docs install it with `intl:any`. |
| Null handling | `nullable-getter: false`. | Default is `true`, which forces `!` at every call. |
| Text outside widgets | None. Notifiers and repositories return typed errors; widgets translate them. | — |

---

## 2. Setup

```bash
flutter pub add flutter_localizations --sdk=flutter
```

```bash
flutter pub add intl:any
```

```yaml
# pubspec.yaml
flutter:
  generate: true
```

```yaml
# l10n.yaml
arb-dir: lib/l10n
template-arb-file: app_en.arb
output-localization-file: app_localizations.dart
output-class: AppLocalizations
nullable-getter: false
untranslated-messages-file: build/untranslated.json
```

**Docs:** `generate: true` is required. Do not set `synthetic-package`; importing `package:flutter_gen/...` no longer works. Files are written to `arb-dir` unless `output-dir` is set.

Generation runs on `flutter pub get` and `flutter run`, or explicitly:

```bash
flutter gen-l10n
```

```dart
import 'package:flutter_localizations/flutter_localizations.dart';
import 'l10n/app_localizations.dart';

MaterialApp.router(
  routerConfig: router,
  locale: ref.watch(localeSettingProvider), // null = follow the device
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
);
```

`AppLocalizations.localizationsDelegates` already includes the Material, Cupertino and Widgets delegates.

**iOS:** in Xcode, open Runner → Info → Localizations and add each supported language. The App Store listing uses this.

---

## 3. ARB files

`app_en.arb` is the template. It carries descriptions and placeholder types; the other files carry only translations.

```json
{
  "appTitle": "My App",
  "@appTitle": { "description": "Application name" },

  "hello": "Hello {userName}",
  "@hello": {
    "description": "Greeting on the home screen",
    "placeholders": {
      "userName": { "type": "String", "example": "Bob" }
    }
  },

  "nEvents": "{count, plural, =0{No events} =1{1 event} other{{count} events}}",
  "@nEvents": {
    "placeholders": { "count": { "type": "num", "format": "compact" } }
  },

  "pronoun": "{gender, select, male{he} female{she} other{they}}",
  "@pronoun": {
    "placeholders": { "gender": { "type": "String" } }
  },

  "startsOn": "Starts on {date}",
  "@startsOn": {
    "placeholders": { "date": { "type": "DateTime", "format": "yMMMd" } }
  }
}
```

```dart
final l10n = AppLocalizations.of(context);
Text(l10n.hello('John'));
Text(l10n.nEvents(5));
Text(l10n.startsOn(event.startsAt));
```

Rules:

- Never build a sentence by joining strings. Word order differs between languages; use placeholders.
- Counts use `plural`, variants use `select`. Do not write `if (count == 1)` in Dart.
- Dates and numbers are formatted by the placeholder's `format`, so each language gets its own style. Number formats include `compact`, `currency`, `decimalPattern`, `percentPattern`.
- Literal braces need `use-escaping: true` in `l10n.yaml` and single quotes around them.
- Every key in the template has a `description`. Translators see nothing else.

**Recommendation:** fail CI when `build/untranslated.json` is not empty.

---

## 4. Using it in code

```dart
extension L10nX on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}

Text(context.l10n.eventsTitle);
```

- No user-visible literal strings in widgets.
- Notifiers and repositories do not produce text. They throw a typed error (see `AppException` in [models-codegen-guide.md](models-codegen-guide.md)) and the widget maps it to a message with a `switch`.
- For right-to-left languages use the directional variants: `EdgeInsetsDirectional`, `AlignmentDirectional`, `start`/`end`.

### Letting the user choose the language

```dart
@riverpod
class LocaleSetting extends _$LocaleSetting {
  @override
  Locale? build() {
    final code = ref.watch(prefsProvider).getString(PrefKeys.locale);
    return code == null ? null : Locale(code);
  }

  Future<void> set(Locale? locale) async {
    final prefs = ref.read(prefsProvider);
    if (locale == null) {
      await prefs.remove(PrefKeys.locale);
    } else {
      await prefs.setString(PrefKeys.locale, locale.languageCode);
    }
    state = locale;
  }
}
```

`prefsProvider` is defined in [storage-guide.md](storage-guide.md). The current locale is `Localizations.localeOf(context)`.

---

## 5. `intl` directly

For values formatted in Dart rather than in an ARB placeholder:

```dart
final locale = Localizations.localeOf(context).toString();

DateFormat.yMMMd(locale).format(date);
DateFormat('HH:mm', locale).format(date);
NumberFormat.compact(locale: locale).format(12500);
NumberFormat.currency(locale: locale, symbol: r'$').format(25);
```

- Always pass the locale. Without it `intl` uses `Intl.defaultLocale`, which is not the app's locale.
- **Docs (intl):** date symbols must be loaded with `initializeDateFormatting` before `DateFormat` is used with a locale.
- Do not use `Intl.message` for app strings; ARB files replace it.

---

## 6. Review checklist

- [ ] `generate: true` in `pubspec.yaml`; no `synthetic-package`; no `package:flutter_gen` import.
- [ ] One template ARB with descriptions and typed placeholders.
- [ ] No concatenated sentences; plurals and selects in ICU syntax.
- [ ] No literal UI strings in widgets, Notifiers or repositories.
- [ ] Dates and numbers formatted with a locale.
- [ ] `supportedLocales` and delegates come from `AppLocalizations`.
- [ ] Languages added in Xcode for iOS.
- [ ] Untranslated-messages file checked in CI.
- [ ] Directional padding and alignment where the app supports RTL.
