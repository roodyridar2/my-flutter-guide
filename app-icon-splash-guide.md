# App icon and splash screen — recommended approach

Covers `flutter_launcher_icons` and `flutter_native_splash`. Both are generators: they read a YAML file and write native project files.

Sources, read 2026-10-04: [flutter_launcher_icons](https://pub.dev/packages/flutter_launcher_icons) and its [README](https://github.com/fluttercommunity/flutter_launcher_icons/blob/master/README.md), [flutter_native_splash](https://pub.dev/packages/flutter_native_splash) and its [README](https://github.com/jonbhanson/flutter_native_splash/blob/master/README.md).

Versions documented: `flutter_launcher_icons 0.14.4`, `flutter_native_splash 2.4.8`.

**Docs** marks what the documentation states; **Recommendation** marks my reading of it. The YAML and code have not been run.

---

## 1. Decisions to make once

| Decision | Recommendation |
|---|---|
| Where the config lives | Separate files, `flutter_launcher_icons.yaml` and `flutter_native_splash.yaml`, to keep `pubspec.yaml` short. |
| Generated native files | Commit them. They are part of the Android and iOS projects. |
| When to run | Only when the artwork or config changes. Not part of the normal build. |
| Splash dependency type | `dependencies` if the app holds the splash during startup (section 3); otherwise `dev_dependencies`. |

---

## 2. flutter_launcher_icons

```yaml
dev_dependencies:
  flutter_launcher_icons: ^0.14.4
```

```yaml
# flutter_launcher_icons.yaml
flutter_launcher_icons:
  image_path: "assets/icon/icon.png"

  android: "launcher_icon"
  min_sdk_android: 24
  adaptive_icon_background: "#FFFFFF"
  adaptive_icon_foreground: "assets/icon/foreground.png"
  adaptive_icon_monochrome: "assets/icon/monochrome.png"

  ios: true
  remove_alpha_ios: true

  web:
    generate: true
    image_path: "assets/icon/icon.png"
    background_color: "#FFFFFF"
    theme_color: "#FFFFFF"
```

```bash
dart run flutter_launcher_icons
```

| Attribute | Meaning |
|---|---|
| `image_path` | Source image for all platforms. `image_path_android` and `image_path_ios` override it per platform. |
| `android` | `true`, `false`, or a name for the generated icon resource. |
| `min_sdk_android` | The app's Android `minSdk`. |
| `adaptive_icon_background` | A colour or an image for the adaptive icon's back layer. |
| `adaptive_icon_foreground` | Image for the front layer. `adaptive_icon_foreground_inset` adjusts its padding. |
| `adaptive_icon_monochrome` | Single-colour image used for Android themed icons. |
| `ios` | `true`, `false`, or a name. |
| `remove_alpha_ios` | Removes transparency from the iOS icon. `background_color_ios` is the fill colour. |
| `image_path_ios_dark_transparent`, `image_path_ios_tinted_grayscale` | Dark and tinted variants for iOS 18+. |
| `web`, `windows`, `macos` | Each has `generate` and `image_path`. Web also takes `background_color` and `theme_color` for `manifest.json`; Windows takes `icon_size` (48–256). |

**Docs:**

- `dart run flutter_launcher_icons:generate` creates a starter config file. `-f <file>` runs a specific file.
- Flavours: one file per flavour named `flutter_launcher_icons-<flavor>.yaml`.
- iOS icons should fill the whole image, with no transparent border.
- Colours are `#AARRGGBB`.

**Recommendation:**

- Source image: 1024 × 1024 PNG, square, no rounded corners. The platforms apply their own mask.
- iOS: set `remove_alpha_ios: true`. An icon with transparency is rejected at App Store upload.
- Android: supply the adaptive layers. Keep the logo inside the centre of the foreground image; launchers crop the outer part into circles and squircles.
- Supply the monochrome layer so the icon follows the user's themed-icon setting on Android 13+.

---

## 3. flutter_native_splash

```yaml
dependencies:
  flutter_native_splash: ^2.4.8
```

```yaml
# flutter_native_splash.yaml
flutter_native_splash:
  color: "#FFFFFF"
  image: assets/splash/logo.png
  color_dark: "#121212"
  image_dark: assets/splash/logo_dark.png

  android_12:
    color: "#FFFFFF"
    image: assets/splash/logo_android12.png
    color_dark: "#121212"
    image_dark: assets/splash/logo_android12_dark.png

  web: false
```

```bash
dart run flutter_native_splash:create
```

```bash
dart run flutter_native_splash:remove
```

**Docs:**

- One of `color` or `background_image` is required. They cannot be used together.
- `image` must be a PNG, sized for 4x pixel density.
- The top-level settings do **not** apply to Android 12 and later. That needs the `android_12` block.
- Android 12+ rules:
  - No background image, only a colour.
  - The image is clipped to a circle in the centre. Without `icon_background_color` use 1152 × 1152 with the artwork inside a 768-pixel circle; with it, 960 × 960 inside a 640-pixel circle.
  - If no image is given, the launcher icon is used.
  - A `branding` image must be 800 × 320.
  - The splash is not shown when the app is opened from a notification.
- Per-platform overrides exist for every key (`color_android`, `image_ios`, …), plus `branding`, `android_gravity`, `ios_content_mode`, `web_image_mode` and `fullscreen`.
- Flavours: `flutter_native_splash-<flavor>.yaml`, generated with `--flavor <name>`, `--flavors a,b` or `--all-flavors`. iOS needs the extra storyboard step described in the README.
- The splash cannot follow an in-app theme setting. It is shown before Flutter starts, so only the system light or dark mode applies.

### Holding the splash during startup

```dart
void main() {
  final binding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: binding);
  runApp(const ProviderScope(child: MyApp()));
}
```

```dart
class _EagerInitialization extends ConsumerWidget {
  const _EagerInitialization({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    if (!session.isLoading) FlutterNativeSplash.remove(); // safe to call twice
    return child;
  }
}
```

**Recommendation:**

- Hold the splash only for what decides the first screen: restoring the session and reading saved settings. Everything else loads after the first frame.
- Always reach `remove()`, including when startup fails. A startup error must end on an error screen, not on a splash that never goes away. The check above covers both, because an error state is also "not loading".
- A startup provider that keeps retrying keeps the splash up. Give it a short retry limit ([riverpod-guide.md](riverpod-guide.md), section 8).
- Keep the splash to a colour and a logo. It should match the first Flutter frame so the hand-over is not visible.
- Design the Android 12 image separately. Reusing the general image there is the usual reason a logo appears cropped.

### Troubleshooting from the docs

- iOS shows an old or white splash: uninstall the app, restart the device, reinstall. iOS caches launch screens.
- "A splash screen was provided to Flutter, but this is deprecated": remove the `SplashScreenDrawable` `<meta-data>` entry from `AndroidManifest.xml`.
- Changes not showing: `flutter clean`, then `flutter pub get`, then run `create` again.

---

## 4. Review checklist

- [ ] Icon source is 1024 × 1024, square, opaque for iOS.
- [ ] Android adaptive foreground, background and monochrome layers supplied.
- [ ] The `android_12` splash block is filled in with its own image.
- [ ] Light and dark splash variants set.
- [ ] Generators re-run after artwork changes, and the generated native files committed.
- [ ] `FlutterNativeSplash.remove()` is reached on both success and failure of startup.
- [ ] Checked on a real Android 12+ device and a real iPhone, in light and dark mode.
