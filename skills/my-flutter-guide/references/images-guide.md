# Images — recommended approach

Covers `cached_network_image` and `flutter_svg`.

Sources, read 2026-10-04: [cached_network_image](https://pub.dev/packages/cached_network_image) and its [changelog](https://pub.dev/packages/cached_network_image/changelog), [flutter_svg](https://pub.dev/packages/flutter_svg).

Versions documented: `cached_network_image 4.0.4`, `flutter_svg 2.3.0`.

**Docs** marks what the documentation states; **Recommendation** marks my reading of it. Code samples have not been compiled.

---

## 1. Which one for what

| Image | Use |
|---|---|
| Photos and other raster images from a URL | `cached_network_image` |
| Icons, logos and illustrations shipped with the app | `flutter_svg` with asset files |
| Raster images shipped with the app | Flutter's own `Image.asset` |
| SVG from a URL | `SvgPicture.network`, only when the server really sends SVG |

---

## 2. cached_network_image

**Requirement:** 4.0.0 needs Flutter 3.44 and Dart 3.12 or newer.

```dart
CachedNetworkImage(
  imageUrl: event.imageUrl,
  width: 120,
  height: 120,
  fit: BoxFit.cover,
  memCacheWidth: 360, // decode at display size x device pixel ratio
  placeholder: (context, url) => const ColoredBox(color: Colors.black12),
  errorWidget: (context, url, error) => const Icon(Icons.broken_image),
);
```

**Docs:**

- `placeholder` and `progressIndicatorBuilder` cannot be used together. The second one receives `downloadProgress.progress`.
- `imageBuilder` gives the loaded `ImageProvider` for use in a `DecorationImage`.
- `CachedNetworkImageProvider(url)` is the provider form, for `Image`, `CircleAvatar` and similar.
- Files are stored and fetched by `flutter_cache_manager`.
- On web there is no caching by this package; the browser's own cache applies.
- A failed load can appear in the debugger and in crash-reporting tools even though the app shows the `errorWidget` and keeps running.

**Recommendation:**

- **Give every image a size.** A fixed `width`/`height` or an `AspectRatio` parent stops lists from jumping as images arrive.
- **Decode small.** Set `memCacheWidth` or `memCacheHeight` for thumbnails. A full-size photo decoded for a 60-pixel avatar is the usual cause of image memory problems.
- **Wrap it once.** Make an `AppNetworkImage` widget with the project's placeholder and error look, and use it everywhere.
- **Signed URLs:** if the query string changes on every request, pass a stable `cacheKey`, or each load is a cache miss.
- **Auth headers:** pass `httpHeaders` when images need a token.
- **Filter image-load errors** in the crash reporter so a broken URL is not counted as a crash.

Cache limits, when the defaults are not right (add `flutter_cache_manager` as a direct dependency to import `CacheManager`):

```dart
final imageCache = CacheManager(
  Config(
    'appImages',
    stalePeriod: const Duration(days: 14),
    maxNrOfCacheObjects: 300,
  ),
);

CachedNetworkImage(imageUrl: url, cacheManager: imageCache);
```

```dart
await CachedNetworkImage.evictFromCache(url); // one image
await imageCache.emptyCache();                // on sign-out
```

---

## 3. flutter_svg

```dart
SvgPicture.asset(
  'assets/icons/calendar.svg',
  width: 24,
  height: 24,
  colorFilter: ColorFilter.mode(
    Theme.of(context).colorScheme.primary,
    BlendMode.srcIn,
  ),
  semanticsLabel: 'Calendar',
);
```

```dart
SvgPicture.network(
  url,
  placeholderBuilder: (context) => const CircularProgressIndicator(),
);
```

**Docs:**

- Tint with `colorFilter`. For finer control, a `ColorMapper` substitutes individual colours.
- Without `width` and `height` the placeholder is an empty box; setting them reserves the space.
- CSS inside the SVG is not fully supported, and text, filters and animations have limits.
- Export from design tools with styling as **presentation attributes**, not inline CSS, and with images embedded.
- Errors are logged to the console in debug mode and nothing is drawn.

### Precompiling

SVG files can be compiled at build time so the device does not parse XML:

```bash
dart run vector_graphics_compiler -i assets/foo.svg -o assets/foo.svg.vec
```

```dart
import 'package:vector_graphics/vector_graphics.dart';

const SvgPicture(AssetBytesLoader('assets/foo.svg.vec'));
```

**Recommendation:**

- Keep icons single-colour and tint them from the theme, so light and dark mode need one file.
- Set `semanticsLabel` on meaningful images. For purely decorative ones wrap in `ExcludeSemantics`.
- Run new SVG files through an optimiser such as SVGO, and open them in the app once. A file that uses unsupported features renders wrong without throwing.
- Reference assets through constants (`AppIcons.calendar`), not string literals in widgets.
- Precompile only when profiling shows SVG parsing on a hot path, such as a long list of distinct icons. It adds a build step.
- Do not embed raster images inside SVG files; ship them as PNG or WebP instead.

---

## 4. Review checklist

- [ ] Network images go through one shared widget with placeholder and error states.
- [ ] Every network image has explicit dimensions or an aspect ratio.
- [ ] Thumbnails set `memCacheWidth` or `memCacheHeight`.
- [ ] Image cache cleared on sign-out when images are user-specific.
- [ ] SVG assets are tinted with `colorFilter`, not duplicated per colour.
- [ ] Each new SVG was checked visually in the app.
- [ ] Asset paths are constants.
