# Widget previews — recommended approach

Covers the Flutter Widget Previewer: seeing a widget in its states, themes and text sizes without running the app to that screen.

Sources, read 2026-10-06:

- The skill `flutter-add-widget-preview` from the official Dart and Flutter plugin ([flutter/agent-plugins](https://github.com/flutter/agent-plugins)), installed copy 1.0.5.
- [Flutter Widget Previewer](https://docs.flutter.dev/tools/widget-previewer) on docs.flutter.dev.
- The library itself, `package:flutter/widget_previews.dart`, in Flutter 3.47.2.

Version documented: Flutter 3.47.2.

**Skill** and **Docs** mark what those sources say (paraphrased). **Adapted** marks my additions for this project. The samples in sections 5 and 6 passed `flutter analyze` and were run in the previewer on that version.

---

## 1. Verdict

The idea is worth adopting. The skill itself is out of date for Flutter 3.47, so take the code from this guide, not from the skill:

| The skill says | Flutter 3.47.2 |
|---|---|
| The theme is `PreviewThemeData(materialLight: …, materialDark: …)`. | `PreviewThemeData` is an abstract class with one method, `apply(context, child)`. |
| Finish a builder with `toPreview()`. | The method is `build()`. |
| Needs Flutter 3.38 or newer in the IDE. | The docs call the previewer stable as of 3.47. |

The skill also shows only bare widgets. Sections 5 and 6 add what this stack needs: the app's theme, its translations, and providers.

---

## 2. What it is for

**Docs:** a function marked `@Preview` is rendered in a browser page or an IDE tab, and redrawn on every save. On 3.47.2 each preview card has its own zoom slider, light and dark switch, and restart button.

**Adapted:**

- Use it while building: the empty, loading and error states, dark mode and large text, without tapping through the app to reach each one.
- A preview proves nothing. It is for looking. Behaviour still gets a widget test ([quality-guide.md](quality-guide.md), section 3), and a preview that shows the four states of a screen is a good list of the four tests to write.

---

## 3. Running it

```bash
flutter widget-preview start
```

**Docs:** that opens the previewer in Chrome. Android Studio, IntelliJ and VS Code start it themselves and show it in a "Flutter Widget Preview" tab. Inside an IDE it shows the previews of one project or one pub workspace.

**Adapted:** the previewer keeps its working files in `.widget_preview/` at the project root. `flutter create` on 3.47 already lists that folder in `.gitignore`. A project created on an older version needs the line added.

---

## 4. The annotation

**Docs.** `@Preview` goes on:

- a top-level function, or a static method, that returns a `Widget` or a `WidgetBuilder`;
- a public widget constructor or factory with no required arguments.

| Parameter | Type | Does |
|---|---|---|
| `name` | `String?` | Label shown above the preview. |
| `group` | `String` | Previews with the same group are shown together. Default: `'Default'`. |
| `size` | `Size?` | The space the widget gets. `Size.fromWidth` and `Size.fromHeight` fix one side. |
| `textScaleFactor` | `double?` | Font scaling. |
| `brightness` | `Brightness?` | Light or dark at the start. Default: the system's. |
| `theme` | function returning `PreviewThemeData` | Wraps the widget in a theme. |
| `localizations` | function returning `PreviewLocalizationsData` | Delegates and locales. |
| `wrapper` | `Widget Function(Widget)` | Wraps the widget in anything else it needs. |

- Every value given to the annotation is a constant. A function passed to it must be public and either top-level or static.
- Subclass `Preview` to fix some of these once. Extend `MultiPreview` to get several previews from one annotation.
- Override `transform()` to compute what a constant cannot, such as a name. It works on a builder: `preview.toBuilder()`, set fields, `.build()`.

---

## 5. One annotation for this app

**Adapted.** Without setup a preview has none of the app around it: not its theme, not its translations. Put that setup in one file, so that every preview is one line and the previewer's API is used in one place.

```dart
// lib/ui/core/previews/app_preview.dart

/// The app's own theme, in whichever brightness the preview is showing.
final class AppPreviewTheme extends PreviewThemeData {
  const AppPreviewTheme();

  @override
  Widget apply(BuildContext context, Widget child) {
    final theme = buildTheme(MediaQuery.platformBrightnessOf(context));
    return Theme(
      data: theme,
      child: ListTileTheme(
        data: theme.listTileTheme,
        child: Material(color: theme.colorScheme.surface, child: child),
      ),
    );
  }
}

PreviewThemeData appPreviewTheme() => const AppPreviewTheme();

PreviewLocalizationsData appPreviewLocalizations() =>
    const PreviewLocalizationsData(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
    );

/// A preview with the app's theme and translations already applied.
final class AppPreview extends Preview {
  const AppPreview({
    super.name,
    super.group,
    super.size,
    super.textScaleFactor,
    super.wrapper,
    super.brightness,
  }) : super(theme: appPreviewTheme, localizations: appPreviewLocalizations);
}

/// Light and dark, side by side.
final class AppThemesPreview extends MultiPreview {
  const AppThemesPreview({required this.name});

  final String name;

  @override
  List<Preview> get previews => const [
    AppPreview(brightness: Brightness.light),
    AppPreview(brightness: Brightness.dark),
  ];

  @override
  List<Preview> transform() => [
    for (final preview in super.transform())
      (preview.toBuilder()
            ..group = name
            ..name = preview.brightness!.name)
          .build(),
  ];
}
```

Why each part of `apply` is there:

- **`MediaQuery.platformBrightnessOf(context)`.** The previewer hands the chosen brightness to the widget through `MediaQuery`. Reading it there makes both the `brightness` parameter and the preview's own light and dark switch select the right app theme. `buildTheme` is the function from [plugin-practices-guide.md](plugin-practices-guide.md), section 5.
- **`Material`.** A screen brings its own `Scaffold`. A smaller widget does not, and without a surface under it the text takes the previewer's colours instead of the theme's.
- **`ListTileTheme`.** On 3.47.2 the previewer's own list-tile styling reached a `ListTile` inside a preview. Setting the app's value again stops that.

To preview another language, add a `locale` to a second `PreviewLocalizationsData` function. A right-to-left locale is the quickest way to check a layout for it ([localization-guide.md](localization-guide.md)).

---

## 6. Writing previews

**Adapted.** A widget that takes data in and sends callbacks out needs nothing else:

```dart
// lib/ui/features/events/views/events_previews.dart

@AppThemesPreview(name: 'Events: empty')
Widget eventsEmptyPreview() => EventsEmptyView(onRetry: () {});

@AppPreview(name: 'Events: empty, large text', textScaleFactor: 2)
Widget eventsEmptyLargeTextPreview() => EventsEmptyView(onRetry: () {});
```

A screen that watches providers gets a `ProviderScope` through `wrapper`, with a fake at the same boundary the tests use: the repository.

```dart
class _FakeEventRepository implements EventRepository {
  @override
  Future<List<Event>> fetchAll() async => const [Event(id: 1, title: 'Launch')];
}

Widget withFakeEvents(Widget child) => ProviderScope(
  overrides: [
    eventRepositoryProvider.overrideWithValue(_FakeEventRepository()),
  ],
  retry: (_, _) => null,
  child: child,
);

@AppPreview(name: 'Events: list', size: Size(360, 640), wrapper: withFakeEvents)
Widget eventsScreenPreview() => const EventsScreen();
```

- **Fake the repository, not the Notifier.** The real Notifier then runs in the preview, which is the same rule as in tests. Turn retry off for the same reason as there: a failing fake should show the error state at once.
- **One preview per state.** A fake that returns an empty list, one that throws an `AppException`, and one whose future never completes give the empty, error and loading states.
- **Give a screen a `size`.** An unconstrained widget gets about half the previewer's window, and the docs say that default may change.
- **Where they live.** Put previews in a `<name>_previews.dart` file beside the view. They are ordinary top-level functions that nothing in the app calls.
- **Prefer previewing small widgets.** A widget that takes its data as parameters previews with no fake at all, which is one more reason to keep screens thin and views plain.

---

## 7. Limits

**Docs:**

- The previewer is a Flutter web app. Plugins that call native code, `dart:io` and `dart:ffi` are not available: code that depends on them loads, and throws when it calls them.
- Assets loaded through `dart:ui` need package-based paths: `packages/<package_name>/assets/…`, not `assets/…`.
- Arguments to the annotation must be constants, and functions passed to it public.

**Adapted:**

- The first limit costs little here. Secure storage, shared preferences, Firebase and Dio all sit below the repository, so overriding the repository keeps the preview away from every one of them. A widget that reaches a plugin directly would break the layering rule before it broke a preview.
- The library's own comments still mark `Preview` and `PreviewThemeData` as likely to change. Expect to touch `app_preview.dart` on a Flutter upgrade. That is the reason every preview goes through it.

---

## 8. Review checklist

- [ ] Previews use `@AppPreview` or `@AppThemesPreview`, not a bare `@Preview` with its own theme.
- [ ] The previewer's API (`PreviewThemeData`, `PreviewLocalizationsData`) is used in `app_preview.dart` only.
- [ ] Screens are previewed above a fake repository. No preview overrides a Notifier.
- [ ] Branching screens have a preview per state: loading, data, empty, error.
- [ ] Screen previews set a `size`.
- [ ] Preview functions and the functions passed to annotations are public; fakes are private to the file.
- [ ] `.widget_preview/` is in `.gitignore`.
- [ ] Each previewed state also has a widget test.
