# Platform plugins — recommended approach

Covers `url_launcher`, `permission_handler` and `package_info_plus`. All three need native configuration, which is why they share a file.

Sources, read 2026-10-04: [url_launcher](https://pub.dev/packages/url_launcher), [permission_handler](https://pub.dev/packages/permission_handler) with its [README](https://github.com/Baseflow/flutter-permission-handler/blob/main/permission_handler/README.md) and [changelog](https://pub.dev/packages/permission_handler/changelog), [package_info_plus](https://pub.dev/packages/package_info_plus) and its [changelog](https://pub.dev/packages/package_info_plus/changelog).

Versions documented: `url_launcher 6.3.3`, `permission_handler 13.0.2`, `package_info_plus 10.2.2`.

**Docs** marks what the documentation states; **Recommendation** marks my reading of it. Code samples have not been compiled.

---

## 1. url_launcher

Minimums: Android SDK 24, iOS 13, macOS 10.15, Windows 10.

```dart
Future<bool> openExternal(Uri uri) {
  return launchUrl(uri, mode: LaunchMode.externalApplication);
}

final opened = await openExternal(Uri.parse('https://flutter.dev'));
if (!opened && context.mounted) showError(context);
```

| `LaunchMode` | Result |
|---|---|
| `platformDefault` | The platform decides. |
| `inAppBrowserView` | Custom Tab on Android, Safari view on iOS. The user stays in the app. |
| `inAppWebView` | A web view inside the app. |
| `externalApplication` | The browser, or the app that owns the link. |
| `externalNonBrowserApplication` | Only a non-browser app; fails if there is none. |

Supported schemes: `https`, `mailto`, `tel`, `sms`, and `file` on desktop.

**Docs:**

- `launchUrl` returns `false` when nothing could handle the URL. Check it.
- `canLaunchUrl` is for adapting the UI. It "can return false even if `launchUrl` would work", so do not use it as a gate before launching.
- `canLaunchUrl` only works for schemes declared natively:

```xml
<!-- ios/Runner/Info.plist -->
<key>LSApplicationQueriesSchemes</key>
<array>
  <string>sms</string>
  <string>tel</string>
</array>
```

```xml
<!-- android/app/src/main/AndroidManifest.xml, inside <manifest> -->
<queries>
  <intent>
    <action android:name="android.intent.action.VIEW" />
    <data android:scheme="sms" />
  </intent>
  <intent>
    <action android:name="android.intent.action.VIEW" />
    <data android:scheme="tel" />
  </intent>
</queries>
```

- Build non-web URLs with `Uri`, and encode query parameters yourself for `mailto`:

```dart
String encodeQueryParameters(Map<String, String> params) => params.entries
    .map((e) => '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
    .join('&');

final mail = Uri(
  scheme: 'mailto',
  path: 'support@example.com',
  query: encodeQueryParameters({'subject': 'App feedback'}),
);
```

**Recommendation:**

- One helper per kind of link (`openExternal`, `openInApp`, `callPhone`, `sendEmail`). Widgets do not call `launchUrl` directly.
- Use `externalApplication` for links that belong to other apps (maps, stores, social profiles) and `inAppBrowserView` for reading pages such as terms and privacy.
- Never launch a URL taken from server or user data without checking its scheme against an allow-list.
- For links inside the app's own routes use go_router, not `url_launcher`.

---

## 2. permission_handler

### Native setup

**Android**

- 13.0.0 raised `compileSdk` to 37.
- Declare each permission in `AndroidManifest.xml` with `<uses-permission>`. A permission that is not declared can never be granted.

**iOS**

- Every permission needs its usage-description key in `Info.plist`. **Docs:** a missing key makes iOS terminate the app when the permission is checked.
- With Swift Package Manager (Flutter 3.24+, Xcode 15+) the plugin detects the permissions from the `Info.plist` keys.
- With CocoaPods, enable each one in the `Podfile`:

```ruby
post_install do |installer|
  installer.pods_project.targets.each do |target|
    flutter_additional_ios_build_settings(target)

    target.build_configurations.each do |config|
      config.build_settings['GCC_PREPROCESSOR_DEFINITIONS'] ||= [
        '$(inherited)',
        'PERMISSION_CAMERA=1',
        'PERMISSION_PHOTOS=1',
        'PERMISSION_NOTIFICATIONS=1',
      ]
    end
  end
end
```

| Permission | `Info.plist` key | Macro |
|---|---|---|
| `camera` | `NSCameraUsageDescription` | `PERMISSION_CAMERA` |
| `microphone` | `NSMicrophoneUsageDescription` | `PERMISSION_MICROPHONE` |
| `photos` | `NSPhotoLibraryUsageDescription` | `PERMISSION_PHOTOS` |
| `photosAddOnly` | `NSPhotoLibraryAddUsageDescription` | `PERMISSION_PHOTOS_ADD_ONLY` |
| `locationWhenInUse` | `NSLocationWhenInUseUsageDescription` | `PERMISSION_LOCATION_WHENINUSE` |
| `location`, `locationAlways` | `NSLocationAlwaysAndWhenInUseUsageDescription` and the when-in-use key | `PERMISSION_LOCATION` |
| `contacts` | `NSContactsUsageDescription` | `PERMISSION_CONTACTS` |
| `calendarFullAccess` | `NSCalendarsFullAccessUsageDescription` | `PERMISSION_EVENTS_FULL_ACCESS` |
| `notification` | none | `PERMISSION_NOTIFICATIONS` |
| `appTrackingTransparency` | `NSUserTrackingUsageDescription` | `PERMISSION_APP_TRACKING_TRANSPARENCY` |

Enable only what the app uses. The macros keep unused permission code out of the binary, which App Store review can otherwise flag.

### Usage

```dart
Future<bool> ensureCamera(BuildContext context) async {
  final status = await Permission.camera.request();

  if (status.isGranted || status.isLimited) return true;

  if (status.isPermanentlyDenied || status.isRestricted) {
    if (!context.mounted) return false;
    final goToSettings = await showPermissionDialog(context);
    if (goToSettings) await openAppSettings();
  }
  return false;
}
```

| Status | Meaning |
|---|---|
| `granted` | Allowed. |
| `denied` | Not asked yet, or refused; can be asked again. |
| `permanentlyDenied` | The system will not show the dialog again. Only Settings can change it. |
| `restricted` | Blocked by the OS, for example parental controls (iOS). |
| `limited` | Partial access, for example selected photos (iOS). |
| `provisional` | Quiet notifications (iOS). |

**Docs:**

- On Android, `Permission.x.status` never returns `permanentlyDenied`. Call `request()`; it returns `permanentlyDenied` without showing a dialog when that is the case.
- Android 13+: `Permission.storage` always returns `denied`. Use `Permission.photos`, `Permission.videos` or `Permission.audio`.
- `locationAlways` cannot be asked first. Request `locationWhenInUse`, and after it is granted request `locationAlways`.
- `Permission.locationWhenInUse.serviceStatus.isEnabled` tells whether location services are on at all.
- Several permissions at once: `await [Permission.camera, Permission.microphone].request()` returns a map.
- `Permission.contacts.shouldShowRequestRationale` is Android-only.

**Recommendation:**

- Ask at the moment the feature is used, never at app start. Explain why on your own screen first; a refusal on iOS cannot be asked again.
- Treat `limited` as usable.
- After `openAppSettings()`, check the status again when the app resumes.
- Put each permission behind one function like `ensureCamera`. Notifiers do not request permissions; the widget does, and passes the result in.
- Check whether the feature's own plugin already asks. `image_picker`, `geolocator` and `firebase_messaging` request their permissions themselves, and `permission_handler` is then needed only for the settings redirect.

---

## 3. package_info_plus

Requirements for 10.x: Flutter 3.38.1, Dart 3.10, iOS 13, macOS 10.15, Android Gradle Plugin 8.12.1, Kotlin 2.2.0, Java 17.

```dart
@Riverpod(keepAlive: true)
Future<PackageInfo> packageInfo(Ref ref) => PackageInfo.fromPlatform();
```

```dart
final info = ref.watch(packageInfoProvider).value;
Text(info == null ? '' : '${info.version} (${info.buildNumber})');
```

Fields: `appName`, `packageName`, `version`, `buildNumber`, `buildSignature`, `installerStore`, `installTime`, `updateTime`.

**Docs:**

- If `fromPlatform()` is called before `runApp()`, call `WidgetsFlutterBinding.ensureInitialized()` first.
- iOS: after changing the version in `pubspec.yaml`, clean the Xcode build folder or the old value is reported.
- Web: the values come from a generated `version.json`. Hosting with strict CORS or caching can block or stale it; `fromPlatform(baseUrl: ...)` sets where it is read from.
- Tests: `PackageInfo.setMockInitialValues(...)`.

**Recommendation:**

- The version in `pubspec.yaml` (`version: 1.2.0+34`) is the single source. Do not keep a second version constant in Dart.
- Send `version` and `buildNumber` as a request header or user-agent from the Dio provider; it makes server logs and forced-update checks possible.
- Show version and build number on the settings or about screen; support requests need it.

---

## 4. Review checklist

- [ ] The result of `launchUrl` is checked; `canLaunchUrl` is not used as a gate.
- [ ] Schemes used with `canLaunchUrl` are declared in `Info.plist` and `AndroidManifest.xml`.
- [ ] URLs from outside the app are scheme-checked before launching.
- [ ] Every requested permission is declared on Android and has an `Info.plist` text on iOS.
- [ ] Only used permissions are enabled in the iOS build.
- [ ] Permissions are requested in context, with an explanation, and `permanentlyDenied` leads to Settings.
- [ ] No use of `Permission.storage` for media on Android 13+.
- [ ] App version comes only from `pubspec.yaml` through `package_info_plus`.
