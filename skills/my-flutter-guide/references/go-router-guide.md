# go_router — recommended approach for this project

**Contents:** 1. Before adopting · 2. Decisions to make once · 3. Setup · 4. Route tree · 5. Navigating · 6. Redirects and guards · 7. Named routes · 8. Typed routes (`go_router_builder`) · 9. Errors · 10. Transitions · 11. Platform concerns · 12. Using it with Riverpod · 13. Review checklist · 14. Breaking changes since 14, for upgrades · Pages read

Source: [pub.dev/documentation/go_router/latest](https://pub.dev/documentation/go_router/latest/), read 2026-10-04.
Version documented there: `go_router 18.0.2`. Companion generator: `go_router_builder 4.5.0`.

Throughout, **Docs** marks what the documentation states and **Recommendation** marks my reading of it for a new project.

---

## 1. Before adopting

- **Status (Docs):** "This package is considered feature-complete. The Flutter team's primary focus will be on addressing bug fixes and ensuring stability." Expect fixes, not new features.
- **SDK floor:** 18.0.0 requires Flutter 3.44 / Dart 3.12. 17.3.0 and later require Flutter 3.38 / Dart 3.10. If the project's Flutter is older than 3.44, pin `^17.x`.
- **18.0.0 is a breaking release:** the changelog entry is "Migrates to material_ui and cupertino_ui packages". I could not read the linked [v18 migration guide](https://flutter.dev/go/go-router-v18-breaking-changes) (it is a Google Doc that did not render for me), so read it before choosing 18 over 17.

## 2. Decisions to make once

| Decision | Recommendation | What the docs say |
|---|---|---|
| Default navigation call | `context.go(...)`. Use `push` only when you need a result back or a screen that is not a destination in its own right. | `go` replaces the stack with the one configured for that location. "Imperative navigation is known to cause issues with the browser history." |
| How routes are referenced | Typed routes with `go_router_builder` if the project already runs `build_runner`; otherwise named routes. Avoid raw path strings scattered through widgets. | Typed routes move missing/mistyped parameters to compile time. |
| Bottom nav / tabs | `StatefulShellRoute.indexedStack`. | One `Navigator` per branch, so each tab keeps its own stack. |
| Auth gating | Top-level `redirect` + `refreshListenable` (section 6). | The pattern in the Redirection topic and the official example. |
| Passing data | Path and query parameters. Avoid `extra`. | `$extra` "defeats dynamic and deep linking (including the browser back button) and is still not recommended when targeting Flutter web." |
| Error screen | One of `onException` or `errorBuilder`, not both. | `onException` supersedes the builders. |

---

## 3. Setup

```yaml
dependencies:
  go_router: ^18.0.2

dev_dependencies:          # only for typed routes
  build_runner: ^2.6.0
  go_router_builder: ^4.5.0
```

```dart
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(routerConfig: router);
  }
}
```

Create the `GoRouter` once (top-level `final`, or a keep-alive provider, see section 12). Never construct it inside a `build` method; a new instance discards the navigation stack.

---

## 4. Route tree

```dart
final _rootKey = GlobalKey<NavigatorState>(debugLabel: 'root');

final router = GoRouter(
  navigatorKey: _rootKey,
  initialLocation: '/home',
  debugLogDiagnostics: kDebugMode,
  redirect: guard,                 // section 6
  refreshListenable: authState,    // section 6
  errorBuilder: (context, state) => NotFoundScreen(error: state.error),
  routes: [
    GoRoute(path: '/', redirect: (_, _) => '/home'),
    GoRoute(
      path: '/login',
      builder: (context, state) =>
          LoginScreen(from: state.uri.queryParameters['from']),
    ),
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) =>
          AppShell(navigationShell: navigationShell),
      branches: [
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/home',
              builder: (context, state) => const HomeScreen(),
              routes: [
                GoRoute(
                  path: 'items/:itemId',
                  builder: (context, state) =>
                      ItemScreen(id: state.pathParameters['itemId']!),
                ),
              ],
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/settings',
              builder: (context, state) => const SettingsScreen(),
            ),
          ],
        ),
      ],
    ),
  ],
);
```

Points from the docs:

- The route list must contain a route matching `/`.
- Child routes stack on top of their parent, which is what gives a working back button after a deep link. Model the hierarchy the user should be able to go "up" through.
- Path parameters: `state.pathParameters['itemId']`. Query parameters: `state.uri.queryParameters['filter']`. Both are strings; parse in the builder, or let typed routes do it.
- URLs are case-sensitive since 15.0.0 (`caseSensitive` defaults to `true`).
- `initialLocation` is used only when the app is not launched by a deep link.
- `debugLogDiagnostics: true` prints the route table and each navigation.

### Shell with tabs

```dart
class AppShell extends StatelessWidget {
  const AppShell({required this.navigationShell, super.key});
  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: navigationShell.currentIndex,
        onTap: (index) => navigationShell.goBranch(index),
        items: const [/* ... */],
      ),
    );
  }
}
```

- To switch from the bottom bar to a side rail on wide windows, see [layout-guide.md](layout-guide.md), section 5.
- With `StatefulShellRoute` the routes live on the branches, not on the shell.
- `StatefulShellBranch(preload: true)` builds a branch's first screen before it is visited; default is `false`.
- To show a child route above the shell (full-screen detail, modal flow), give it `parentNavigatorKey: _rootKey`.
- Use plain `ShellRoute` only when the tabs do not need to keep their own stacks.
- Since 17.0.0, navigation inside a shell notifies the root `GoRouter.observers` by default; `notifyRootObserver: false` opts a shell out. Relevant if an analytics observer starts double-counting.

---

## 5. Navigating

| Need | Call |
|---|---|
| Go to a destination | `context.go('/home/items/42')` |
| With query parameters | `context.go(Uri(path: '/users', queryParameters: {'filter': 'abc'}).toString())` |
| By name | `context.goNamed('item', pathParameters: {'itemId': '42'})` |
| Get a result back | `final ok = await context.push<bool>('/confirm');` then `context.pop(true)` |
| Switch tab | `navigationShell.goBranch(index)` |
| Real `<a>` link on web | `Link` widget from `url_launcher` |

- `go` is the default because the resulting stack is derived from the URL, so it is the same whether the user tapped, deep-linked or reloaded.
- On web, pushed routes are not reflected in the address bar by default. `GoRouter.optionURLReflectsImperativeAPIs = true` changes that, but the docs "strongly suggest against" it.
- `Navigator.of(context).push(...)` still works for screens that should not be deep-linkable (pickers, one-off dialogs).
- `Router.neglect(context, () => context.go(...))` skips a browser history entry for one navigation; `routerNeglect: true` does it app-wide.
- If `extra` is used anyway, register an `extraCodec` so it survives browser history and state restoration.

---

## 6. Redirects and guards

The documented pattern, taken from the official redirection example:

```dart
String? guard(BuildContext context, GoRouterState state) {
  final loggedIn = authState.loggedIn;
  final loggingIn = state.matchedLocation == '/login';

  if (!loggedIn) {
    if (loggingIn) return null;
    return Uri(
      path: '/login',
      queryParameters: {'from': state.uri.toString()},
    ).toString();
  }
  if (loggingIn) return state.uri.queryParameters['from'] ?? '/home';
  return null; // no redirect
}

final router = GoRouter(
  redirect: guard,
  refreshListenable: authState, // a Listenable; router re-runs redirect when it notifies
  routes: [/* ... */],
);
```

- Return `null` (or the same path) to continue.
- **Top-level** `redirect` on `GoRouter` runs before every navigation. **Route-level** `redirect` on a `GoRoute` runs when that route is about to be shown; use it for aliases and per-section rules (`GoRoute(path: '/old', redirect: (_, _) => '/home')`).
- `redirectLimit` defaults to 5; exceeding it shows the error screen. A guard that can loop is the usual cause.
- `refreshListenable` is what makes login and logout navigate on their own. Screens should change auth state and let the router react; they should not call `context.go('/home')` after login.

**Recommendation:** keep the guard synchronous and free of side effects. It runs often, and an async guard delays every navigation.

### `onEnter`

Added in 16.3.0. Signature:

```dart
FutureOr<OnEnterResult> onEnter(
  BuildContext context,
  GoRouterState currentState,
  GoRouterState nextState,
  GoRouter goRouter,
)
```

It returns `const Allow()`, `const Block.stop()` or `Block.then(() => goRouter.go('/login'))`. Order per the API reference: `onEnter` → "legacy top-level `redirect`" → route-level `redirect`.

**Recommendation:** use `onEnter` when navigation must be *cancelled* rather than sent elsewhere, for example a deep link that should trigger an action and leave the user where they are, or a rule that needs both the current and the next state. Keep auth on `redirect` + `refreshListenable` for now: it is the pattern the topic guide documents, and `onEnter` needed several fixes through 17.x (lost stack on block, lost `Block.then` callbacks on refresh). The API reference calling top-level redirect "legacy" signals where the package is heading, so keep the auth rule in one function that would be easy to move.

To confirm leaving a screen with unsaved changes, use `GoRoute.onExit`.

---

## 7. Named routes

```dart
GoRoute(name: 'song', path: 'songs/:songId', builder: /* ... */);

context.goNamed('song', pathParameters: {'songId': '123'});
final location = context.namedLocation('song', pathParameters: {'songId': '123'});
```

Names must be unique. Keep them in one constants file. Inside a redirect, return `context.namedLocation(...)`.

---

## 8. Typed routes (`go_router_builder`)

```dart
import 'package:go_router/go_router.dart';

part 'routes.g.dart';

@TypedGoRoute<HomeRoute>(
  path: '/',
  routes: [TypedGoRoute<ItemRoute>(path: 'items/:itemId')],
)
class HomeRoute extends GoRouteData with $HomeRoute {
  const HomeRoute();

  @override
  Widget build(BuildContext context, GoRouterState state) => const HomeScreen();
}

class ItemRoute extends GoRouteData with $ItemRoute {
  const ItemRoute({required this.itemId, this.tab = ItemTab.details});
  final int itemId;      // in the path -> path parameter, parsed to int
  final ItemTab tab;     // not in the path -> query parameter with a default

  @override
  Widget build(BuildContext context, GoRouterState state) =>
      ItemScreen(id: itemId, tab: tab);
}

final router = GoRouter(routes: $appRoutes);
```

```bash
dart run build_runner build
```

```dart
const ItemRoute(itemId: 42).go(context);
final ok = await const ConfirmRoute().push<bool>(context);
final path = const HomeRoute().location; // use in redirects
```

- Constructor parameters named in the path are path parameters; all others are query parameters. A query parameter equal to its default is left out of the URL.
- `int`, enums and extension types are converted automatically.
- Override `redirect` on the route class for route-level redirects, and `buildPage` instead of `build` for custom pages and transitions.
- Shells: `TypedShellRoute` / `ShellRouteData`, `TypedStatefulShellRoute`. Navigator keys are static fields named `$navigatorKey` (shell) and `$parentNavigatorKey` (route).
- The builder warns when two routes resolve to the same URL. Set `duplicate_route_paths: error` in `build.yaml` to fail the build instead.
- The mixin is `$HomeRoute` with builder 4.x. The go_router topic page still shows the 3.x form `_$HomeRoute`; follow whatever the generated file declares.

---

## 9. Errors

**Docs:** `GoError` and `AssertionError` mean the router is misconfigured; fix the code, do not catch them. `GoException` means a request could not be handled, typically an unknown URL, and is what the callbacks below receive.

```dart
GoRouter(
  errorBuilder: (context, state) => NotFoundScreen(error: state.error),
  // or, to redirect instead of showing a page:
  // onException: (context, state, router) => router.go('/not-found'),
);
```

Always provide one. Otherwise a mistyped URL on web shows the package's default error screen.

---

## 10. Transitions

```dart
GoRoute(
  path: '/details',
  pageBuilder: (context, state) => CustomTransitionPage(
    key: state.pageKey,
    child: const DetailsScreen(),
    transitionsBuilder: (context, animation, secondaryAnimation, child) =>
        FadeTransition(
          opacity: CurveTween(curve: Curves.easeInOut).animate(animation),
          child: child,
        ),
  ),
);
```

Use `builder` unless a route needs a non-default page. With `builder`, go_router picks the page type from the surrounding app (`MaterialPage`, `CupertinoPage`).

---

## 11. Platform concerns

- **Web:** hash URLs are the default; path URLs need the URL strategy set as described in Flutter's docs, plus a server that rewrites unknown paths to `index.html`.
- **Deep links:** go_router shows whatever route matches the incoming path. The Android and iOS setup (intent filters, associated domains) is in Flutter's deep-linking docs, not in go_router. Because any URL can arrive from outside, every route must be able to build from its parameters alone, and the guard must cover it.
- **State restoration:** supported. Set `restorationScopeId` on both `GoRouter` and `MaterialApp.router`. Routes using `pageBuilder` need a `restorationId` on the page. `ShellRoute` and `StatefulShellRoute` need a `restorationScopeId`, a `pageBuilder` returning a page with a `restorationId`, and a `restorationScopeId` on each branch. This restores after the OS kills the app in the background; it is unrelated to tabs keeping their stacks.
- **Routes that change at runtime** (feature flags, roles): `GoRouter.routingConfig` with a `ValueNotifier<RoutingConfig>`; assigning a new value makes the router re-parse the current location.

---

## 12. Using it with Riverpod

Neither documentation covers this; what follows is my recommendation. See [riverpod-guide.md](riverpod-guide.md) for the Riverpod side.

```dart
final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier<int>(0);
  ref.listen(authProvider, (_, _) => refresh.value++);

  final router = GoRouter(
    refreshListenable: refresh,
    redirect: (context, state) {
      final auth = ref.read(authProvider);
      if (auth.isLoading) return null;
      final loggedIn = auth.value != null;
      final loggingIn = state.matchedLocation == '/login';
      if (!loggedIn) return loggingIn ? null : '/login';
      if (loggingIn) return '/home';
      return null;
    },
    routes: [/* ... */],
  );

  ref.onDispose(() {
    router.dispose();
    refresh.dispose();
  });
  return router;
});

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(routerConfig: ref.watch(routerProvider));
  }
}
```

- Inside `routerProvider`, use `ref.listen` and `ref.read`, never `ref.watch(authProvider)`. Watching would rebuild the provider, create a new `GoRouter` and wipe the navigation stack on every auth change.
- The router provider must be kept alive. Hand-written providers are by default; with code generation use `@Riverpod(keepAlive: true)`.
- Route parameters are the input to family providers: `/items/:itemId` → `ref.watch(itemProvider(itemId))`. This is the replacement for a "selected item" provider, which Riverpod's DO/DON'T page advises against.
- Navigation as a reaction to state belongs in `ref.listen` inside a widget's `build`, or in the redirect. Notifiers should not hold a `BuildContext` or call the router.

---

## 13. Review checklist

- [ ] One `GoRouter` instance, created outside `build`.
- [ ] A route matches `/`; an `errorBuilder` or `onException` is set.
- [ ] Detail screens are child routes of their list, so deep links have a back stack.
- [ ] `context.go` by default; each `push` has a reason.
- [ ] No `extra` for anything a URL should be able to reproduce.
- [ ] Guard is synchronous, returns `null` when nothing changes, and cannot loop.
- [ ] Auth changes navigate through `refreshListenable`, not through `context.go` in screens.
- [ ] Tabs use `StatefulShellRoute.indexedStack`; full-screen children set `parentNavigatorKey`.
- [ ] No raw path strings in widgets: typed routes or named routes only.
- [ ] `debugLogDiagnostics` is on in debug builds only.

---

## 14. Breaking changes since 14, for upgrades

| Version | Change |
|---|---|
| 18.0.0 | Migrates to `material_ui` / `cupertino_ui` packages. Minimum Flutter 3.44 / Dart 3.12. |
| 17.0.0 | Shell route navigation notifies root observers by default (`notifyRootObserver` added). |
| 16.3.0 | Top-level `onEnter` added (not breaking). |
| 16.0.0 | Case-sensitivity fix: `/Home` and `/home` are distinct. `GoRouteData` defines `.location`, `.go`, `.push`, `.pushReplacement`, `.replace`; needs `go_router_builder` ≥ 3.0.0. |
| 15.0.0 | URLs are case-sensitive; `caseSensitive` parameter added, default `true`. |
| 14.0.0 | `GoRouteData.onExit` takes `(BuildContext context, GoRouterState state)`. |

---

## Pages read

[Package index](https://pub.dev/documentation/go_router/latest/) ·
[Get started](https://pub.dev/documentation/go_router/latest/topics/Get%20started-topic.html) ·
[Upgrading](https://pub.dev/documentation/go_router/latest/topics/Upgrading-topic.html) ·
[Configuration](https://pub.dev/documentation/go_router/latest/topics/Configuration-topic.html) ·
[Navigation](https://pub.dev/documentation/go_router/latest/topics/Navigation-topic.html) ·
[Redirection](https://pub.dev/documentation/go_router/latest/topics/Redirection-topic.html) ·
[Web](https://pub.dev/documentation/go_router/latest/topics/Web-topic.html) ·
[Deep linking](https://pub.dev/documentation/go_router/latest/topics/Deep%20linking-topic.html) ·
[Transition animations](https://pub.dev/documentation/go_router/latest/topics/Transition%20animations-topic.html) ·
[Type-safe routes](https://pub.dev/documentation/go_router/latest/topics/Type-safe%20routes-topic.html) ·
[Named routes](https://pub.dev/documentation/go_router/latest/topics/Named%20routes-topic.html) ·
[Error handling](https://pub.dev/documentation/go_router/latest/topics/Error%20handling-topic.html) ·
[State restoration](https://pub.dev/documentation/go_router/latest/topics/State%20restoration-topic.html) ·
[GoRouter class](https://pub.dev/documentation/go_router/latest/go_router/GoRouter-class.html) ·
[OnEnter](https://pub.dev/documentation/go_router/latest/go_router/OnEnter.html) ·
[Block](https://pub.dev/documentation/go_router/latest/go_router/Block-class.html) ·
[StatefulShellRoute](https://pub.dev/documentation/go_router/latest/go_router/StatefulShellRoute-class.html) ·
[Changelog](https://pub.dev/packages/go_router/changelog) ·
[go_router_builder README](https://pub.dev/packages/go_router_builder) ·
official examples [`redirection.dart`](https://github.com/flutter/packages/blob/main/packages/go_router/example/lib/redirection.dart) and [`top_level_on_enter.dart`](https://github.com/flutter/packages/blob/main/packages/go_router/example/lib/top_level_on_enter.dart)
