# Native splash to Flutter splash — a seamless hand-off

How to make the operating system's launch screen turn into an animated Flutter splash with no visible cut.

Sources, read 2026-10-04:

- A production Flutter app given to me as a reference. I read its Dart, Android and iOS launch code and the tests that guard it. I did not run it.
- Flutter docs: [Android splash screen](https://docs.flutter.dev/platform-integration/android/splash-screen), [iOS launch screen](https://docs.flutter.dev/platform-integration/ios/splash-screen).
- Android docs: [Splash screens](https://developer.android.com/develop/ui/views/launch/splash-screen).

**Reference** marks what the reference app does. **Docs** marks what the platform documentation says. **Adapted** marks my additions. The code is the reference app's, renamed and trimmed; I have not compiled this version.

Related: [app-icon-splash-guide.md](app-icon-splash-guide.md) covers generating a static native splash with `flutter_native_splash`. This guide is for when the splash should animate.

---

## 1. The idea

There are two splash screens. The **native** one is drawn by the OS before any Dart code runs, and it cannot animate freely. The **Flutter** one is a normal widget and can do anything.

The hand-off is invisible when **Flutter's first frame is the same picture as the native screen**: same background, same logo, same size, same place. Nothing changes on screen at the moment of the switch. Only then does Flutter start moving things.

So the work is not an animation between the two. It is making two independently drawn screens identical, and then animating from that pose.

---

## 2. What has to match

| Thing | Rule |
|---|---|
| Background colour | One value, used by the native screens and by the Flutter splash. |
| Logo artwork | The same image, including any clipping. If Flutter clips it to a circle, the native file is already cut to that circle. |
| Logo size | The same number of logical pixels on every screen density. |
| Logo position | The exact centre of the screen on both sides. |
| The switch itself | No fade from the OS, no blank frame from Flutter. |
| What happens next | The logo only moves. New elements fade in around it. |

---

## 3. One source of truth

**Reference:** the Flutter splash page owns the values. The native files copy them, and a test fails if they drift apart (section 10).

```dart
class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  /// Also the colour of the native launch screens.
  static const Color backgroundColor = Color(0xFF090909);

  /// The logo's size in logical pixels. The native screens draw it this big.
  static const double logoSize = 96;

  static const String logoAsset = 'assets/images/logo.png';

  // ...
}
```

---

## 4. The logo files

**Reference:** a script produces the native images from the Flutter asset, so they cannot differ.

| Platform | Files | Pixel size for a 96-point logo |
|---|---|---|
| iOS | `SplashLogo.png`, `@2x`, `@3x` in an image set | 96, 192, 288 |
| Android | `drawable-mdpi` … `drawable-xxxhdpi/splash_logo.png` | 96, 144, 192, 288, 384 |

- The size is `logoSize` multiplied by the density factor: 1, 1.5, 2, 3, 4 on Android; 1, 2, 3 on iOS.
- If the Flutter splash shows the image inside a circle (`ClipOval`), the script cuts the same circle into the native files, with antialiased edges.
- Re-run the script whenever the logo or `logoSize` changes.

---

## 5. Android before 12

**Reference and Docs:** the launch screen is the activity window's background.

```xml
<!-- res/values/colors.xml -->
<color name="splash_background">#090909</color>
```

```xml
<!-- res/drawable/launch_background.xml and res/drawable-v21/launch_background.xml -->
<layer-list xmlns:android="http://schemas.android.com/apk/res/android">
    <item android:drawable="@color/splash_background" />
    <item>
        <bitmap android:gravity="center" android:src="@drawable/splash_logo" />
    </item>
</layer-list>
```

```xml
<!-- res/values/styles.xml and res/values-night/styles.xml -->
<style name="LaunchTheme" parent="@android:style/Theme.Light.NoTitleBar">
    <item name="android:windowBackground">@drawable/launch_background</item>
</style>
<style name="NormalTheme" parent="@android:style/Theme.Light.NoTitleBar">
    <item name="android:windowBackground">@color/splash_background</item>
</style>
```

- `LaunchTheme` is the activity's theme in `AndroidManifest.xml`. It is what the user sees while the process starts.
- `NormalTheme` is named by the `io.flutter.embedding.android.NormalTheme` meta-data. It is the window behind Flutter afterwards, so it uses the same colour. A different colour here shows as a flash during the switch and on rotation.
- The night variant uses a dark parent theme and the **same** items.

---

## 6. Android 12 and later

Android 12 replaced the window-background splash with a system splash screen: a background colour and a centred icon.

```xml
<!-- res/values-v31/styles.xml and res/values-night-v31/styles.xml -->
<style name="LaunchTheme" parent="@android:style/Theme.Light.NoTitleBar">
    <item name="android:windowBackground">@drawable/launch_background</item>
    <item name="android:windowSplashScreenBackground">@color/splash_background</item>
    <item name="android:windowSplashScreenAnimatedIcon">@drawable/splash_icon</item>
</style>
<style name="NormalTheme" parent="@android:style/Theme.Light.NoTitleBar">
    <item name="android:windowBackground">@color/splash_background</item>
</style>
```

Four things make it line up.

**Both `values-v31` and `values-night-v31` must exist.** **Reference:** when Android picks resources, night mode outranks the API level. With only `values-v31`, a phone in dark mode uses `values-night` and gets the default icon.

**The icon's size on screen.** **Docs:** an icon without an icon background is drawn in a 288 dp box, of which the central circle of 192 dp is visible. With an icon background the box is 240 dp and the circle 160 dp. To show the logo at 96 dp, make it the central third of the icon's canvas.

**Keep the icon sharp.** **Reference:** a static icon was rendered by the system into a small bitmap and scaled up. It looked soft and then visibly sharpened at the hand-off. An animated vector is drawn live at full size. So the icon is an `animated-vector` whose animation does nothing:

```xml
<!-- res/drawable/splash_icon.xml -->
<animated-vector xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:aapt="http://schemas.android.com/aapt">
    <aapt:attr name="android:drawable">
        <vector
            android:width="288dp"
            android:height="288dp"
            android:viewportWidth="3240"
            android:viewportHeight="3240">
            <!-- The logo occupies 1080 of 3240 units: the central third. -->
            <group android:name="logo" android:translateX="1080" android:translateY="1080">
                <!-- the logo's vector paths, in a 1080 x 1080 space -->
            </group>
        </vector>
    </aapt:attr>
    <!-- No-op animation: it only makes the system treat the icon as animated. -->
    <target android:name="logo">
        <aapt:attr name="android:animation">
            <objectAnimator
                android:duration="1"
                android:propertyName="translateX"
                android:valueFrom="1080"
                android:valueTo="1080"
                android:valueType="floatType" />
        </aapt:attr>
    </target>
</animated-vector>
```

This needs the logo as vector paths. The reference app traced them from the PNG, and its script checks that the trace still matches the image.

**Remove the system's fade-out.** **Docs and Reference:** by default Android fades its splash out over Flutter's first frame. With an identical logo underneath, that reads as the logo dimming and coming back. Drop the splash at once instead:

```kotlin
class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            splashScreen.setOnExitAnimationListener { splashView -> splashView.remove() }
        }
    }
}
```

### The vertical offset

The native splash is centred on the whole display. On Android versions where the app is not edge-to-edge, the Flutter view ends above the navigation bar, so its centre is higher by half the bar's height. The reference app measured a jump of about 12 dp with gesture navigation. There are two ways to remove it.

- **Docs:** make the window edge-to-edge, with `WindowCompat.setDecorFitsSystemWindows(window, false)` in `MainActivity.onCreate`. The Flutter view then covers the display, and every screen must handle the system insets itself.
- **Reference:** leave the window alone and start the logo lower by the difference, which eases away during the animation (`nativeLogoOffset` in section 8).

---

## 7. iOS

**Reference:** the launch screen is `ios/Runner/Base.lproj/LaunchScreen.storyboard`, named by `UILaunchStoryboardName` in `Info.plist`.

- The root view's background is the splash colour, set in the **sRGB** colour space.
- One image view shows the `SplashLogo` image set.
- Four constraints: width and height equal to `logoSize`, and centre X and centre Y equal to the **root view's**. Use the root view, not the safe area, or the logo sits off the true centre on phones with a notch.
- iOS removes the launch screen with a short fade of its own. The reference app's notes put it at about 0.2 seconds; I did not verify the number. Section 8 allows for it.

iOS caches launch screens. After changing one, delete the app and restart the device before judging the result.

---

## 8. The Flutter side

### Decode the logo before the first frame

**Reference:** an image is decoded asynchronously. Without this step the first frame draws an empty space where the logo should be, for a few frames. That is a visible dip exactly at the hand-off.

```dart
static Future<void> precacheLogo() {
  final done = Completer<void>();
  final stream = const AssetImage(logoAsset).resolve(ImageConfiguration.empty);
  late final ImageStreamListener listener;
  void finish() {
    if (!done.isCompleted) done.complete();
    stream.removeListener(listener);
  }

  listener = ImageStreamListener((_, _) => finish(), onError: (_, _) => finish());
  stream.addListener(listener);
  return done.future;
}
```

```dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final splashLogo = SplashPage.precacheLogo(); // starts now, in parallel

  // ... the rest of the startup work ...

  await splashLogo; // the native screen is still showing
  runApp(const ProviderScope(child: MyApp()));
}
```

It never throws: a failed decode must not block the app from starting.

### Draw the first frame in the native pose

The final layout is usually a logo with a title under it, centred as a group. In that layout the logo is above the centre, which is not where the native screen drew it.

**Reference:** put an invisible copy of everything below the logo **above** it. While the copy is at full height the two sides balance, so the logo is exactly centred, whatever the text's size, font or scale, and without measuring anything. Collapse the copy's height to zero and the group slides up into its final centred position.

```dart
class SplashHandoff extends StatelessWidget {
  const SplashHandoff({
    super.key,
    required this.progress,
    required this.logo,
    required this.below,
    this.gap = 36,
    this.nativeOffset = 0,
  });

  /// 0 = the native launch screen's pose, 1 = the final layout.
  final double progress;
  final Widget logo;
  final Widget below;
  final double gap;
  final double nativeOffset;

  @override
  Widget build(BuildContext context) {
    final lower = Padding(padding: EdgeInsets.only(top: gap), child: below);
    return Center(
      child: Transform.translate(
        offset: Offset(0, nativeOffset * (1 - progress)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // The invisible twin. It paints nothing and is hidden from
            // screen readers; only its height matters.
            ExcludeSemantics(
              child: Align(
                alignment: Alignment.bottomCenter,
                widthFactor: 1,
                heightFactor: (1 - progress).clamp(0.0, 1.0),
                child: Opacity(opacity: 0, child: lower),
              ),
            ),
            logo,
            lower,
          ],
        ),
      ),
    );
  }
}
```

The offset for Android windows that are not edge-to-edge (section 6):

```dart
/// How far below the centre of [view] the native screen drew the logo.
double nativeLogoOffset(FlutterView view) {
  final display = view.display.size.height;
  if (display <= 0) return 0;
  final gap = (display - view.physicalSize.height) / 2 / view.devicePixelRatio;
  // Clamped so split screen or an odd display cannot push the logo away.
  return gap.clamp(0.0, 32.0);
}
```

It is zero on iOS and wherever the view already covers the display.

### Start the animation at the right moment

**Reference:** timers started in `initState` begin before anything is visible. On a slow first frame the animation is already part-way through when the user first sees it. Start from the moment the first frame is actually on screen, then hold the native pose briefly:

```dart
static const _nativeHold = Duration(milliseconds: 250);

@override
void initState() {
  super.initState();
  _handoff = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1000),
  );
  // The logo glides during the first 80%.
  _rise = CurvedAnimation(
    parent: _handoff,
    curve: const Interval(0, 0.8, curve: Curves.easeInOutCubic),
  );
  // Everything new appears a little later.
  _reveal = CurvedAnimation(
    parent: _handoff,
    curve: const Interval(0.25, 1, curve: Curves.easeOut),
  );

  WidgetsBinding.instance.waitUntilFirstFrameRasterized.then((_) {
    Future.delayed(_nativeHold, () {
      if (mounted) _handoff.forward();
    });
  });
}
```

The hold is longer than the OS's own removal of its launch screen, so the logo does not start moving underneath a fading native copy.

```dart
AnimatedBuilder(
  animation: _handoff,
  builder: (context, _) => SplashHandoff(
    progress: _rise.value,
    nativeOffset: nativeLogoOffset(View.of(context)),
    logo: const SplashLogo(), // SplashPage.logoSize, same clipping as native
    below: Opacity(opacity: _reveal.value, child: const SplashTitle()),
  ),
);
```

### Rules for the animation

**Reference:**

- The scaffold's background is `SplashPage.backgroundColor`.
- The logo never fades in and never scales at the start. It is already on screen; it only moves.
- Everything the native screen did not show (title, tagline, glow, progress line) starts at zero opacity and fades in.

**Adapted:**

- Fonts used on the splash must be bundled with the app. A font fetched at runtime swaps in late and makes the text jump.
- When the system asks for reduced motion (`MediaQuery.disableAnimationsOf`), set the controller straight to its end value.
- Take durations and curves from the app's motion constants ([animations-guide.md](animations-guide.md)).

---

## 9. Leaving the splash

**Reference:** the splash is the router's first route. The router's redirect keeps the user there until two things are true: the session state is known, and a minimum time has passed so the animation can finish. A change in either one refreshes the router, which then redirects to sign-in or home.

**Adapted** to the pattern in [go-router-guide.md](go-router-guide.md), section 12:

```dart
final splashMinimumProvider = FutureProvider<void>((ref) {
  return Future<void>.delayed(const Duration(milliseconds: 1800));
});

// inside the router provider
ref.listen(splashMinimumProvider, (_, _) => refresh.value++);

redirect: (context, state) {
  final auth = ref.read(authProvider);
  final shown = ref.read(splashMinimumProvider).hasValue;
  final onSplash = state.matchedLocation == '/';

  if (auth.isLoading || !shown) return onSplash ? null : '/';
  // ... the usual signed-in and signed-out rules ...
}
```

- A minimum display time delays every cold start. Keep it no longer than the animation.
- While the app waits on the splash, a deep link is redirected there too. Remember the requested location and go to it afterwards, or it is lost.
- With an animated Flutter splash, do not also hold the native one with `FlutterNativeSplash.preserve()`. Hand over as soon as the logo is decoded and let the Flutter splash cover the startup work.

---

## 10. Tests that keep the two sides in sync

**Reference:** ordinary Dart tests read the native files as text and compare them with the Dart constants. A change on either side that would break the hand-off fails the test run.

```dart
test('Android splash colour is the Flutter splash colour', () {
  final xml = File('android/app/src/main/res/values/colors.xml').readAsStringSync();
  final colour = RegExp(r'<color name="splash_background">(#[0-9A-Fa-f]{6})</color>')
      .firstMatch(xml)
      ?.group(1);
  expect(colour?.toLowerCase(), hexOf(SplashPage.backgroundColor));
});
```

What the reference app checks this way:

- The colour in `colors.xml` and in the storyboard equals `backgroundColor`.
- Every logo PNG is `logoSize` times its density, on both platforms.
- `launch_background.xml` centres the logo on the colour.
- All four styles files (`values`, `values-night`, `values-v31`, `values-night-v31`) set the window backgrounds, and the two `v31` files set the splash attributes.
- The Android 12 icon is an animated vector with the logo as its central third.
- `MainActivity` installs the exit listener and removes the splash.
- The storyboard's image view has the size and centre constraints.
- `main` starts the logo precache and awaits it before `runApp`.

And as widget tests for the hand-off widget:

- At progress 0 the logo's centre is the screen's centre, including with a much larger text scale.
- At progress 1 the logo, gap and text are centred as one group.
- The offset function returns 0 when the view is the display, half the bar height otherwise, and is clamped for small windows.

---

## 11. The launcher icon

**Reference:** some launchers, Samsung's among them, expand the app icon into the window when the app opens, and show the adaptive icon's **background layer** for a moment. If that layer is another colour, such as Android Studio's default green grid, there is a flash before the splash. Make the adaptive icon's background the splash colour or the brand colour, and supply the monochrome layer for themed icons.

---

## 12. Symptoms and causes

| What you see | Cause | Fix |
|---|---|---|
| The logo dims and returns at the switch (Android 12+) | The system fades its splash out over Flutter's frame. | Remove it in the exit listener. |
| The logo is soft, then sharpens (Android 12+) | A static icon is rendered small and scaled. | Animated vector with a no-op animation. |
| The logo jumps a few pixels vertically (Android) | The native splash is centred on the display, Flutter on a shorter view. | Edge-to-edge window, or the Dart offset. |
| An empty space where the logo should be, briefly | The image is not decoded on the first frame. | Precache before `runApp`. |
| The logo starts off-centre | It is centred as part of a group with text. | The invisible twin. |
| The default icon appears in dark mode (Android 12+) | `values-night` outranks `values-v31`. | Add `values-night-v31`. |
| A flash of another colour before the splash | The launcher shows the icon's background layer. | Match the icon background. |
| A flash of colour after the splash or on rotation | `NormalTheme` has a different window background. | Use the splash colour there. |
| The animation is already running when the screen appears | Timers started in `initState`. | Start after the first frame is rasterised, plus a hold. |
| The colour is slightly off on iOS | The storyboard colour is in another colour space. | Set it to sRGB. |
| iOS still shows the old launch screen | iOS cached it. | Delete the app and restart the device. |

---

## 13. With `flutter_native_splash`

**Adapted.** The package can produce the simple parts: the background colour, a centred image on iOS and on Android before 12, and an Android 12 icon. A source image four times `logoSize` wide gives a logo of `logoSize` logical pixels there, since the package treats its input as the 4x density.

Not covered by its configuration, as far as I know: removing the Android 12 exit fade, and the animated-vector icon. Those are hand edits, and re-running the generator can overwrite hand-edited files. Either keep the native files by hand as the reference app does, or re-apply and re-test after each run. The tests in section 10 catch a silent overwrite.

---

## 14. Review checklist

- [ ] One colour and one logo size, defined in Dart and mirrored natively.
- [ ] Native logo images are generated from the Flutter asset at every density.
- [ ] Android: `LaunchTheme` and `NormalTheme` in all four `values` folders.
- [ ] Android 12+: animated-vector icon sized to the logo, and the exit fade removed.
- [ ] The vertical offset on Android is handled one way or the other.
- [ ] iOS: sRGB background, logo centred on the root view at the exact size.
- [ ] The logo is decoded before `runApp`.
- [ ] The first Flutter frame shows only the logo, centred, on the same colour.
- [ ] The animation starts after the first frame is on screen, plus a short hold.
- [ ] The logo only moves; everything else fades in.
- [ ] Reduced motion is honoured.
- [ ] The router leaves the splash when startup is done and the minimum time has passed.
- [ ] The adaptive icon's background matches.
- [ ] Tests compare the native files with the Dart constants.
- [ ] Checked on real devices: Android before 12, Android 12 or later in light and dark mode with gesture and button navigation, and an iPhone.
