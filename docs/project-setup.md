# New project setup

The order of work for a new app on this stack. Each step names the guide that holds the details. Do the steps in order: later ones depend on earlier ones.

## 1. Create the project

```bash
flutter --version
```

```bash
flutter create --org <reverse.domain> <app_name>
```

The current versions of several packages need a recent Flutter (go_router 18 and cached_network_image 4 need Flutter 3.44 or newer). If the installed SDK is older, say so before going on: pub will resolve older package versions, and parts of the guides will not apply.

## 2. Add the packages

Let pub pick the versions. Do not copy version numbers from the guides.

```bash
flutter pub add flutter_riverpod riverpod_annotation go_router dio freezed_annotation json_annotation flutter_secure_storage shared_preferences logger
```

```bash
flutter pub add flutter_localizations --sdk=flutter
```

```bash
flutter pub add intl:any
```

```bash
flutter pub add dev:build_runner dev:riverpod_generator dev:go_router_builder dev:freezed dev:json_serializable dev:flutter_lints dev:mocktail
```

```bash
flutter pub add "dev:integration_test:{sdk: flutter}"
```

Add these only when a feature needs them: `cached_network_image`, `flutter_svg`, `url_launcher`, `permission_handler`, `package_info_plus`, the Firebase packages, and as dev dependencies `flutter_launcher_icons` and `flutter_native_splash`.

## 3. Analysis, generation and localization config

| File | What goes in it | Guide |
|---|---|---|
| `analysis_options.yaml` | `flutter_lints`, the three strict modes, the `riverpod_lint` plugin, the `invalid_annotation_target` ignore | `quality-guide.md`, section 1 |
| `build.yaml` | `explicit_to_json: true`, and `field_rename` if the API uses snake_case | `models-codegen-guide.md`, section 2 |
| `pubspec.yaml` | `flutter: generate: true` | `localization-guide.md`, section 2 |
| `l10n.yaml` and `lib/l10n/app_en.arb` | ARB folder, template file, `nullable-getter: false` | `localization-guide.md`, sections 2 and 3 |

## 4. Folders

Create the layout from `architecture-guide.md`, section 4:

```text
lib/
├── main.dart
├── app.dart
├── routing/
├── l10n/
├── data/
│   ├── services/
│   └── repositories/
├── domain/
│   └── models/
└── ui/
    ├── core/
    └── features/
```

`test/` mirrors `lib/`, with `test/helpers/` for shared test code.

## 5. Core files, in this order

| File | What it holds | Guide |
|---|---|---|
| `domain/models/app_exception.dart` | The typed error union | `models-codegen-guide.md`, section 4 |
| `data/services/dio_provider.dart` | The one `Dio`, timeouts, interceptors | `dio-guide.md`, sections 2 and 3 |
| `data/services/api_client.dart` | `ApiClient`, `guardDio`, the error mapping | `dio-guide.md`, sections 4 and 5 |
| `data/services/token_storage.dart` | Secure storage wrapper | `storage-guide.md`, section 2 |
| `data/services/prefs_provider.dart` | Preferences instance, overridden in `main` | `storage-guide.md`, section 3 |
| `data/services/logger_provider.dart` | The logger and the provider observer | `quality-guide.md`, section 2; `riverpod-guide.md`, section 12 |
| `data/repositories/auth_repository.dart` and the session provider | Who is signed in | `riverpod-guide.md`, section 9 |
| `routing/router.dart` | Router provider, redirect, refresh listenable, routes | `go-router-guide.md`, sections 4, 6 and 12 |
| `ui/core/theme/` | `buildTheme`, the spacing scale, theme extensions | `plugin-practices-guide.md`, section 5 |
| `ui/core/l10n.dart` | The `context.l10n` extension | `localization-guide.md`, section 4 |
| `app.dart` | `MaterialApp.router` with localization, both themes, the router | `localization-guide.md`, section 2 |
| `main.dart` | Binding, startup overrides, `ProviderScope` with the retry policy and observer | `riverpod-guide.md`, sections 8 and 9; `storage-guide.md`, section 3 |

Build the list of startup overrides in one function that `main` calls, so integration tests can reuse it (`quality-guide.md`, section 4).

## 6. Tests

- `test/helpers/pump_app.dart`: the shared widget-test wrapper (`plugin-practices-guide.md`, section 2).
- One Notifier test and one widget test to prove the wiring, written to the conventions in `quality-guide.md`, section 3.

## 7. Native pieces

- App icon: `app-icon-splash-guide.md`, section 2.
- Splash: `app-icon-splash-guide.md`, section 3, for a static one; `splash-handoff-guide.md` when it should animate on into the app.
- Platform settings that the chosen plugins need (permissions, URL schemes, secure-storage backup): `platform-guide.md`, `storage-guide.md`.

## 8. Generate and check

```bash
dart run build_runner build -d
```

```bash
dart format .
```

```bash
flutter analyze
```

```bash
flutter test
```

All four must be clean before the setup is called done. The same commands, plus coverage, are the CI gate (`quality-guide.md`, section 1; `plugin-practices-guide.md`, section 3).

## Done when

- [ ] The app starts, shows the first route, and the redirect sends a signed-out user to sign-in.
- [ ] No literal UI strings: the first screens already use the generated localizations.
- [ ] Light and dark themes both exist.
- [ ] One request goes through `ApiClient`, a repository and a provider to the screen.
- [ ] Generated files are present and follow the project's policy (committed, or ignored and built in CI).
- [ ] Format, analyze and tests pass.
