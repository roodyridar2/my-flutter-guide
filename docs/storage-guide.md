# Local storage — recommended approach

Covers `flutter_secure_storage` and `shared_preferences`.

Sources, read 2026-10-04: [flutter_secure_storage](https://pub.dev/packages/flutter_secure_storage) and its [changelog](https://pub.dev/packages/flutter_secure_storage/changelog), [shared_preferences](https://pub.dev/packages/shared_preferences).

Versions documented: `flutter_secure_storage 11.2.0`, `shared_preferences 2.5.5`.

**Docs** marks what the documentation states; **Recommendation** marks my reading of it. Code samples have not been compiled.

---

## 1. What goes where

| Data | Store | Why |
|---|---|---|
| Access and refresh tokens, anything secret | `flutter_secure_storage` | Keychain on iOS, encrypted storage on Android. |
| Theme, language, "onboarding seen", last selected tab | `shared_preferences` | Small, non-secret settings. |
| Lists, cached API data, anything queried | A database (for example `drift`) | Neither package is built for it. |

**Docs (shared_preferences):** "there is no guarantee that writes will be persisted to disk after returning, so this plugin must not be used for storing critical data."

---

## 2. flutter_secure_storage

### Platform requirements

- Android: `minSdk` 24 since 11.0.0.
- iOS 12 and macOS 10.14 since 10.0.0.
- macOS: add the `keychain-access-groups` entitlement to both `DebugProfile.entitlements` and `Release.entitlements`.
- Linux: `libsecret-1-dev` and a keyring service. Windows: C++ ATL libraries.
- Web: works only on HTTPS or localhost and is described as experimental. Do not keep secrets in a web build.

### Android backup

**Docs:** set `android:allowBackup="false"` in `AndroidManifest.xml`, or exclude the plugin's preferences from backup. A restored backup contains data encrypted with a key that no longer exists and reading it fails.

### Usage

```dart
class TokenStorage {
  TokenStorage(this._storage);
  final FlutterSecureStorage _storage;

  static const _accessKey = 'access_token';
  static const _refreshKey = 'refresh_token';

  Future<String?> readAccessToken() => _storage.read(key: _accessKey);

  Future<void> save({required String access, required String refresh}) async {
    await _storage.write(key: _accessKey, value: access);
    await _storage.write(key: _refreshKey, value: refresh);
  }

  Future<void> clear() async {
    await _storage.delete(key: _accessKey);
    await _storage.delete(key: _refreshKey);
  }
}

@Riverpod(keepAlive: true)
TokenStorage tokenStorage(Ref ref) {
  return TokenStorage(
    const FlutterSecureStorage(
      iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
    ),
  );
}
```

- iOS accessibility defaults to `unlocked`. `first_unlock` lets background work, such as handling a push notification, read the token while the device is locked.
- Android defaults since 10.0.0 are RSA-OAEP for the key and AES-GCM for the data. No options are needed.

### Behaviour to design for

**Recommendation:**

- **Read once, keep in memory.** Read the token at startup into the session provider and write through on change. Reading secure storage on every request is slow.
- **A missing token means signed out.** Since 10.0.0 `resetOnError` defaults to `true` on Android: if stored data cannot be decrypted it is wiped. Never treat a failed read as a crash.
- **iOS keeps Keychain data after uninstall.** On first launch after install, clear secure storage. Detect first launch with a flag in `shared_preferences`, which is removed on uninstall.
- **Delete by key.** Use `delete` for your own keys rather than `deleteAll`.

### Upgrading an existing app

Not relevant to a new project. For an app already in the stores: the changelog requires going to v10 first so existing data is migrated, then to v11. v11 removed `encryptedSharedPreferences`, `sharedPreferencesName` and the old cipher options.

---

## 3. shared_preferences

### Which API

| API | Reads | Notes |
|---|---|---|
| `SharedPreferences` | Sync after `getInstance()` | Legacy. The docs say it will be deprecated. |
| `SharedPreferencesAsync` | Always async | No cache; always the latest value, across isolates too. |
| `SharedPreferencesWithCache` | Sync after `create()` | Cached, with an optional `allowList` of keys. |

**Docs:** "We highly encourage any new users of the plugin to use the newer `SharedPreferencesAsync` or `SharedPreferencesWithCache` APIs."

**Recommendation:** `SharedPreferencesWithCache`, created once in `main`. Theme and language must be known before the first frame, and synchronous reads make that simple. Use `SharedPreferencesAsync` instead if a background isolate writes the same keys.

### Setup

```dart
abstract final class PrefKeys {
  static const themeMode = 'theme_mode';
  static const locale = 'locale';
  static const onboardingDone = 'onboarding_done';
  static const all = {themeMode, locale, onboardingDone};
}

@Riverpod(keepAlive: true)
SharedPreferencesWithCache prefs(Ref ref) {
  throw UnimplementedError('Overridden in main');
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferencesWithCache.create(
    cacheOptions: const SharedPreferencesWithCacheOptions(
      allowList: PrefKeys.all,
    ),
  );

  runApp(
    ProviderScope(
      overrides: [prefsProvider.overrideWithValue(prefs)],
      child: const MyApp(),
    ),
  );
}
```

### Usage

```dart
@riverpod
class ThemeModeSetting extends _$ThemeModeSetting {
  @override
  ThemeMode build() {
    final name = ref.watch(prefsProvider).getString(PrefKeys.themeMode);
    return ThemeMode.values.asNameMap()[name] ?? ThemeMode.system;
  }

  Future<void> set(ThemeMode mode) async {
    await ref.read(prefsProvider).setString(PrefKeys.themeMode, mode.name);
    state = mode;
  }
}
```

- Supported types: `int`, `double`, `bool`, `String`, `List<String>`.
- Key names live in one file. A key not in the `allowList` cannot be read or written through that instance.
- Do not store JSON blobs of model lists here; that is database work.
- Widgets and Notifiers go through a settings provider like the one above, not the raw `prefsProvider`. Tests then override the settings provider.

### Platform notes

- Android: the new APIs store in DataStore Preferences by default; the legacy API uses Android SharedPreferences. They do not see each other's data.
- Minimums: Android SDK 24, iOS 13, macOS 10.15.

---

## 4. Review checklist

- [ ] No token or secret in `shared_preferences`.
- [ ] Android backup disabled or the secure-storage file excluded.
- [ ] Secure storage cleared on first launch after install.
- [ ] A failed or empty secure read is handled as "signed out".
- [ ] Tokens cached in memory; storage is not read per request.
- [ ] `SharedPreferencesWithCache` or `SharedPreferencesAsync`; no new code on the legacy API.
- [ ] Preference keys are constants in one place.
- [ ] Nothing larger than a setting in preferences.
