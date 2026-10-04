# Firebase — recommended approach

Setup, Crashlytics and Cloud Messaging for this project's stack, plus short rules for the other Firebase products.

Sources, read 2026-10-04:

- **Skill `firebase-basics`** from [firebase/agent-skills](https://github.com/firebase/agent-skills) (official): the skill file and its Flutter setup, CLI and service-init references.
- **Skill `flutter-firebase`** from [dhruvanbhalara/skills](https://github.com/dhruvanbhalara/skills) (community).
- **Firebase docs**, used to check both: [Add Firebase to your Flutter app](https://firebase.google.com/docs/flutter/setup), Crashlytics [get started](https://firebase.google.com/docs/crashlytics/flutter/get-started) and [customize](https://firebase.google.com/docs/crashlytics/flutter/customize-crash-reports), Cloud Messaging [get started](https://firebase.google.com/docs/cloud-messaging/flutter/get-started) and [receive messages](https://firebase.google.com/docs/cloud-messaging/flutter/receive).

Versions that resolve together with the rest of the stack on Flutter 3.47 (dry run): `firebase_core 4.15.0`, `firebase_crashlytics 5.4.0`, `firebase_analytics 12.6.0`, `firebase_messaging 16.7.0`, `firebase_remote_config 6.7.0`, `firebase_auth 6.7.0`, `cloud_firestore 6.10.0`, `flutter_local_notifications 22.3.1`.

**Docs** and **Skill** mark what the sources say (paraphrased). **Adapted** marks my changes for this stack. Code samples have not been compiled.

---

## 1. Which skill is the better one

| Skill | What it is | Verdict |
|---|---|---|
| `firebase-basics` (official) | How an AI agent should operate the Firebase CLI: check the tools, log in, pick or create a project, fetch config files. It deliberately leaves out every product (Crashlytics, Auth, Firestore, …). | Authoritative, but most of it is about running the CLI, not about app code. Its Flutter setup reference is the useful part and matches the Firebase docs. |
| `flutter-firebase` (community) | One file of short rules per product: Auth, Firestore, Messaging, Crashlytics, Analytics, Remote Config. | Broader and closer to what an app needs. Written for Bloc and `injectable`. Its Crashlytics and Messaging rules match the Firebase docs; three rules need correcting (section 7). |

Neither is enough alone. **This guide takes the setup from the official skill and the product rules from the community one**, each checked against the Firebase docs, with Riverpod in place of Bloc.

---

## 2. Decisions to make once

| Decision | Recommendation |
|---|---|
| Which products | Only what a feature needs. For this stack: Crashlytics with Analytics, and Messaging. |
| Environments | A separate Firebase project per environment (development, staging, production). |
| Where Firebase code lives | In `data/services` and `data/repositories` only ([architecture-guide.md](architecture-guide.md)). No widget or Notifier imports a Firebase package. |
| Configuration | The FlutterFire CLI. No manual download of config files. |

---

## 3. Setup

**Docs and official skill:**

```bash
npx -y firebase-tools@latest login
```

```bash
dart pub global activate flutterfire_cli
```

```bash
flutter pub add firebase_core
```

```bash
flutterfire configure --project=<project_id>
```

`flutterfire configure` registers the iOS, Android and web apps and writes `lib/firebase_options.dart`. The docs describe its contents as identifiers that are unique but not secret.

```dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const ProviderScope(child: MyApp()));
}
```

Rules:

- `WidgetsFlutterBinding.ensureInitialized()` comes first. Firebase starts through platform channels, which need the engine running.
- Adding any Firebase plugin is three steps: `flutter pub add <plugin>`, run `flutterfire configure` again, rebuild.
- Run `flutterfire configure` again after changing the bundle identifier or application id, and after adding a platform.
- Minimums: iOS 15, Android API 23.
- iOS: after adding a plugin, run `pod install` if the project has a `Podfile`. Projects on Swift Package Manager have none.
- Web: test on `localhost` with a fixed port and add `localhost` to the authorised domains. Do not disable browser security to get past CORS.

**Adapted:**

- Commit `firebase_options.dart`. It holds no secret; access is controlled by security rules on the server, not by hiding these values.
- Run the configure command once per environment, each against its own project.

---

## 4. Crashlytics

**Docs:**

```bash
flutter pub add firebase_crashlytics firebase_analytics
```

Analytics is added because Crashlytics uses it for breadcrumbs: the user actions that led up to a crash. Then run `flutterfire configure` again.

```dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  await FirebaseCrashlytics.instance
      .setCrashlyticsCollectionEnabled(!kDebugMode);

  // Errors thrown inside the Flutter framework.
  FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;

  // Asynchronous errors the framework does not catch.
  PlatformDispatcher.instance.onError = (error, stack) {
    FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
    return true;
  };

  runApp(const ProviderScope(child: MyApp()));
}
```

| Need | API | Limit |
|---|---|---|
| A caught error worth knowing about | `recordError(error, stack, reason: '…')` | The eight most recent non-fatal errors are kept until sent. |
| Who was affected | `setUserIdentifier(id)`; an empty string clears it | — |
| State at the time of the crash | `setCustomKey(key, value)` | 64 pairs |
| A trail of messages | `log('…')` | 64 kB per session |

- To check the setup, throw an exception from a test button and look at the dashboard a few minutes later.
- Builds made with `--split-debug-info` or `--obfuscate` need their symbols uploaded, or stack traces are unreadable. Android uploads go through the Firebase CLI.

**Adapted:**

- The line with `kDebugMode` keeps development crashes out of the dashboard. It is the community skill's "staging and production only" rule.
- Pass an opaque user id, never an email or a name.
- Crashlytics is the release output of the logger. Implement `CrashReportOutput` from [quality-guide.md](quality-guide.md), section 2, so that warnings call `log` and errors call `recordError`.
- The Riverpod observer's `providerDidFail` ([riverpod-guide.md](riverpod-guide.md), section 12) goes through the same logger, so provider failures are reported once.
- Do not report expected errors: no connection, cancelled requests, validation failures. They bury the real crashes.
- The `--obfuscate` flag is already required by [plugin-practices-guide.md](plugin-practices-guide.md), section 4. The symbol upload belongs in the same release step.

---

## 5. Cloud Messaging

### Platform setup

**Docs:**

- **iOS:** enable the Push Notifications capability and the Background Modes capability in Xcode, and upload the APNs authentication key in the Firebase console. A real device is needed for testing.
- **Android:** a device or emulator with Google Play services. Android 13 and later need the notification permission.
- **Web:** a VAPID key from the console, passed to `getToken(vapidKey: …)`, and a `firebase-messaging-sw.js` service worker.

```bash
flutter pub add firebase_messaging
```

### Permission and token

```dart
final settings = await FirebaseMessaging.instance.requestPermission();
// settings.authorizationStatus: authorized, denied, notDetermined, provisional
```

```dart
// Apple platforms: the APNs token must exist before the FCM token is asked for.
if (Platform.isIOS) await FirebaseMessaging.instance.getAPNSToken();
final token = await FirebaseMessaging.instance.getToken();

FirebaseMessaging.instance.onTokenRefresh.listen(sendTokenToBackend);
```

### The three app states

| State | How the message arrives | What to do |
|---|---|---|
| Foreground | `FirebaseMessaging.onMessage` | The system shows nothing by default. Show it yourself. |
| Background | The system shows the notification; `onBackgroundMessage` runs for data | Keep the handler small. |
| Terminated | The same | The same. |

```dart
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  // No UI and no app state here.
}

// in main(), before runApp
FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
```

**Docs, rules for the background handler:** it must be a top-level function, not anonymous, annotated with `@pragma('vm:entry-point')`. It must initialise Firebase itself. It cannot touch the UI or the app's state, and it should finish within about 30 seconds.

Taps on a notification:

```dart
final initial = await FirebaseMessaging.instance.getInitialMessage();
if (initial != null) handleTap(initial);          // opened from terminated

FirebaseMessaging.onMessageOpenedApp.listen(handleTap); // opened from background
```

- A **notification message** is displayed by the system. A **data message** carries only your payload and shows nothing unless your code does.
- Foreground display on Android needs a high-importance notification channel, or showing the notification yourself with `flutter_local_notifications`. On iOS, set the foreground presentation options.

**Adapted:**

- Wrap all of this in one `PushService` class in `data/services`, behind a keep-alive provider. The rest of the app sees a stream of taps and a `register()` method.
- Ask for permission in context, after explaining why, as in [platform-guide.md](platform-guide.md), section 2. Firebase Messaging shows its own prompt, so `permission_handler` is needed only to send the user to Settings.
- Send the token to **your backend** when the user signs in and on every refresh, and remove it there on sign-out. A device that keeps a token after sign-out keeps receiving the previous user's notifications.
- A tap becomes navigation: turn the message's data into a route location and call `router.go(...)` from the root of the app. Handle `getInitialMessage` only after the router exists and the session is restored, or the redirect will override it.
- The background handler runs in a separate isolate. Providers, the router and the logger from the main isolate do not exist there.

---

## 6. Other products

From the community skill, with Riverpod substituted. I checked the Crashlytics and Messaging rules against the Firebase docs; the rules in this section I did not check against each product's documentation.

**Authentication**

- All calls go through an `AuthRepository`. Nothing else touches `FirebaseAuth`.
- `authStateChanges()` becomes a stream provider. The router's redirect reads it ([go-router-guide.md](go-router-guide.md), section 12).
- On sign-out, user-specific providers reset because they watch the auth provider. No manual clearing.

**Firestore**

- Reads and writes live in the data layer, with typed models and `withConverter<T>()` for typed references.
- Changes to several documents use one batch write, not a series of single writes.
- Security rules start from deny-all and open only what is needed. Rules that require a signed-in user check `request.auth != null`. Client-side checks are never the only protection.
- Test the rules with the Emulator Suite before deploying them.

**Analytics**

- Event names describe what happened (`purchase_completed`). User properties are for segmentation.
- Screen views come from `FirebaseAnalyticsObserver` in the router's `observers`.
- Never send personal data: no emails, phone numbers or names.

**Remote Config**

- Every key has a default in the app. The app must work if the fetch never succeeds.
- Fetch and activate at startup with a timeout, and respect the minimum fetch interval.

---

## 7. Not copied

| From | What | Why |
|---|---|---|
| Community | Bloc, `injectable`, "dispose user-specific BLoCs" | Different stack. Providers that watch the auth state reset themselves. |
| Community | Store auth tokens in secure storage | Firebase Auth keeps its own session. That rule applies only to tokens from your own backend ([storage-guide.md](storage-guide.md)). |
| Community | Store the FCM token in the user's Firestore document | Only if Firestore is the backend. Otherwise it goes to your API. |
| Community | Offer email, Google and Apple sign-in at minimum | A product decision. Check Apple's current review rule on offering Sign in with Apple beside other social logins. |
| Community | `Crashlytics.instance.setCustomKey('userId', id)` | The class is `FirebaseCrashlytics`, and `setUserIdentifier` is the API for a user id. |
| Official | The `npx -y firebase-tools@latest` prefix, MCP tools, agent setup guides | Instructions for an AI agent operating the CLI, not for the app. |
| Official | Web, Android-native and iOS-native setup references | FlutterFire's `configure` covers all three for a Flutter app. |

---

## 8. Review checklist

- [ ] `Firebase.initializeApp` runs before `runApp`, with the generated options.
- [ ] `flutterfire configure` was re-run after the last plugin or bundle-id change.
- [ ] Each environment has its own Firebase project.
- [ ] Firebase packages are imported only in the data layer.
- [ ] Both error handlers are installed; collection is off in debug builds.
- [ ] Symbols are uploaded for obfuscated release builds.
- [ ] No personal data in Crashlytics keys, logs or Analytics events.
- [ ] The background message handler is top-level, annotated, and initialises Firebase.
- [ ] Foreground messages are displayed by the app.
- [ ] Notification taps are handled from both terminated and background states.
- [ ] The push token is registered on sign-in and refresh, and removed on sign-out.
- [ ] Security rules are deny-by-default and tested in the emulator.
