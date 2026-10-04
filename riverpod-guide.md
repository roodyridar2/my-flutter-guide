# Riverpod — recommended approach for this project

Source: [riverpod.dev](https://riverpod.dev/), read 2026-10-04.
Versions documented there: `flutter_riverpod 3.4.3`, `riverpod_annotation 4.0.7`, `riverpod_generator 4.0.9`, `riverpod_lint 3.1.9`. Dart SDK `^3.7.0`.

Throughout, **Docs** marks what the documentation states and **Recommendation** marks my reading of it for a new project.

---

## 1. Decisions to make once

| Decision | Recommendation | What the docs say |
|---|---|---|
| Code generation (`@riverpod`) | Use it only if the project already runs `build_runner` (Freezed, json_serializable). Otherwise write providers by hand. Pick one style and keep the whole codebase on it. | "Only if you already use code-generation for other things." Since Dart macros were cancelled, codegen is no longer the default recommendation; it is still slower to build. |
| Hooks (`hooks_riverpod`) | Skip unless the team already uses `flutter_hooks`. | "If you are a newcomer to Riverpod, avoid using hooks." |
| Provider kinds | Only the six modern ones (section 3). | `StateProvider`, `StateNotifierProvider`, `ChangeNotifierProvider` moved to `legacy.dart` "to discourage use". |
| Widget base class | `ConsumerWidget`, or `ConsumerStatefulWidget` when local state is needed. | "If you do not have a strong opinion, we recommend using ConsumerWidget." |
| Lints | Turn on `riverpod_lint` from day one. | Several v3 rules that used to be compile errors are now lints. |
| Mutations, offline persistence | Do not build core flows on them yet. | Both are experimental: "the API may change in a breaking way without a major version bump." |

---

## 2. Setup

```yaml
# pubspec.yaml
environment:
  sdk: ^3.7.0

dependencies:
  flutter_riverpod: ^3.4.3
  # only with code generation:
  riverpod_annotation: ^4.0.7

dev_dependencies:
  # only with code generation:
  build_runner:
  riverpod_generator: ^4.0.9
```

```yaml
# analysis_options.yaml
plugins:
  riverpod_lint: 3.1.9
```

```dart
void main() {
  runApp(const ProviderScope(child: MyApp()));
}
```

**Docs:** in Flutter always use `ProviderScope`, never a raw `ProviderContainer`. With code generation, run `dart run build_runner watch`.

---

## 3. Choosing a provider

**Docs:** "Don't think in terms of 'Which provider should I pick'. Instead, think in terms of 'What do I want to return'."

| | Sync | `Future` | `Stream` |
|---|---|---|---|
| Read-only (function) | `Provider` | `FutureProvider` | `StreamProvider` |
| Modifiable (class with methods) | `NotifierProvider` | `AsyncNotifierProvider` | `StreamNotifierProvider` |

With code generation the generator picks the row and column from the function or class you write.

### Read-only data

```dart
// by hand
final userProvider =
    FutureProvider.autoDispose.family<User, String>((ref, id) async {
  return ref.watch(userRepositoryProvider).getUser(id);
});

// with code generation
@riverpod
Future<User> user(Ref ref, String id) async {
  return ref.watch(userRepositoryProvider).getUser(id);
}
```

### Modifiable state

```dart
// by hand
final todoListProvider =
    AsyncNotifierProvider.autoDispose<TodoList, List<Todo>>(TodoList.new);

class TodoList extends AsyncNotifier<List<Todo>> {
  @override
  Future<List<Todo>> build() => ref.watch(todoRepositoryProvider).fetchAll();

  Future<void> add(String title) async {
    final created = await ref.read(todoRepositoryProvider).create(title);
    if (!ref.mounted) return; // v3 throws if a disposed Ref is used
    state = AsyncData([...?state.value, created]);
  }
}

// with code generation
@riverpod
class TodoList extends _$TodoList {
  @override
  Future<List<Todo>> build() => ref.watch(todoRepositoryProvider).fetchAll();
  // same methods
}
```

Rules from the docs:

- Providers are top-level `final` variables. Never create them inside a class or function ("memory leaks and unexpected behavior").
- No logic in a Notifier constructor; `ref` is not available yet. Put it in `build`.
- A Notifier's public surface is `state` plus methods. Do not add other public properties (`avoid_public_notifier_properties` lint).
- In v3 a family Notifier written by hand takes its argument through the constructor (`FamilyNotifier` is gone).

---

## 4. Using `ref`

| Call | Where | Purpose |
|---|---|---|
| `ref.watch(p)` | `build` of widgets and providers | Subscribe and rebuild. The default. |
| `ref.read(p)` | Callbacks and Notifier methods only | One-off read, no subscription. |
| `ref.listen(p, cb)` | Inside `build` | Side effects: snackbars, dialogs, navigation. |
| `ref.listenManual(p, cb)` | `initState` and other lifecycle methods | Same as `listen`, outside `build`. |
| `ref.invalidate(p)` | Callbacks | Drop the state; recomputed on next read. |
| `ref.refresh(p)` | Callbacks | `invalidate` + `read`; use when you need the new value. |

**Docs:** "Do not use ref.read as a mean to 'optimize' your code by avoiding ref.watch." And do not call `ref.watch` inside callbacks.

After any `await` in a widget callback, check `context.mounted` before touching `ref`. Inside a provider or Notifier, check `ref.mounted`.

Business logic that needs a `Ref` belongs in a Notifier method, called as `ref.read(todoListProvider.notifier).add(...)`. Do not pass `WidgetRef` into non-UI code; the docs call that coupling an anti-pattern.

---

## 5. Rendering async state

```dart
class TodoScreen extends ConsumerWidget {
  const TodoScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final todos = ref.watch(todoListProvider);

    return RefreshIndicator(
      onRefresh: () => ref.refresh(todoListProvider.future),
      child: switch (todos) {
        AsyncValue(:final value?) => TodoListView(todos: value),
        AsyncValue(:final error?) => ErrorView(error: error),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}
```

`AsyncValue` is sealed in v3. Matching `value?` first keeps the previous data on screen during a refresh, so the full-screen spinner only shows on first load. This is the pattern from the docs' pull-to-refresh guide. If the data type is itself nullable, the `async_value_nullable_pattern` lint will flag `value?`; match `AsyncData(:final value)` there instead.

`valueOrNull` was renamed to `value` in v3.

---

## 6. Lifetime and caching

- **Docs:** with code generation providers are auto-dispose by default; opt out with `@Riverpod(keepAlive: true)`. Written by hand they are kept alive by default; opt in with `.autoDispose` / `isAutoDispose: true`.
- **Recommendation:** make everything auto-dispose except app-wide singletons (API client, auth session, router, storage). Hand-written providers need this stated explicitly, which is the main thing to watch for in review.
- **Docs:** "It is highly advised to enable Automatic disposal when using families" to avoid a leak per parameter value.
- Family parameters need stable `==`/`hashCode`: primitives, records, or classes with value equality. Never a `List` or `Map` literal (`provider_parameters` lint).
- Release resources with `ref.onDispose`. No side effects or provider writes inside it.

Keep successful responses for a while without keeping failures:

```dart
extension CacheForExtension on Ref {
  void cacheFor(Duration duration) {
    final link = keepAlive();
    final timer = Timer(duration, link.close);
    onDispose(timer.cancel);
  }
}
```

v3 also pauses listeners in widgets that are not visible (detected through `TickerMode`), and pauses providers only used by paused listeners. Do not rely on a hidden screen's `ref.listen` firing.

---

## 7. Writes, reloads and `AsyncValue.guard`

**Docs:** providers represent reads. "You should not use them for 'write' operations, such as submitting a form."

The rest of this section, up to Mutations, is **Recommendation**.

`build` is the read. It returns the value or throws, and Riverpod turns that into loading, data and error. Everything else is a method on the Notifier, called from a callback.

`AsyncValue.guard` is a `try/catch` that returns `AsyncData` on success and `AsyncError` on failure. Use it only where the outcome of an operation should *become* the state:

| Situation | What to write |
|---|---|
| First load | Nothing extra. `build` returns or throws. |
| Pull-to-refresh, "try again" | `ref.refresh(provider.future)` or `ref.invalidate(provider)` from the widget. `build` runs again. |
| Reload with new inputs held in the state (filter, search) | `state = const AsyncLoading();` then `AsyncValue.guard` |
| An action whose outcome is the state (login, submit) | The same pair, on an action controller typed `void` |
| Load more, add, edit, delete, toggle | `try/catch`. On failure leave `state` as it was. |

Never call `AsyncValue.guard`, assign `state`, or read `state` inside `build` or inside a function that `build` awaits. It repeats what Riverpod already does and hides the error from it.

### A list with a filter and paging

```dart
class EventList extends AsyncNotifier<EventsState> {
  @override
  Future<EventsState> build() => _load(const EventFilter());

  // Shared by build and applyFilter. Returns or throws; never touches `state`.
  Future<EventsState> _load(EventFilter filter) async {
    final page =
        await ref.read(eventRepositoryProvider).getEvents(filter, page: 1);
    return EventsState(
      events: page.items,
      filter: filter,
      page: 1,
      hasMore: page.hasMore,
    );
  }

  // New inputs replace the whole state: this is the case for guard.
  Future<void> applyFilter(EventFilter filter) async {
    state = const AsyncLoading();
    final next = await AsyncValue.guard(() => _load(filter));
    if (!ref.mounted) return;
    state = next;
  }

  // A failed page must not replace the list: no guard.
  Future<void> loadMore() async {
    final current = state.value;
    if (current == null || current.isLoadingMore || !current.hasMore) return;

    state = AsyncData(current.copyWith(isLoadingMore: true));
    try {
      final page = await ref
          .read(eventRepositoryProvider)
          .getEvents(current.filter, page: current.page + 1);
      if (!ref.mounted) return;
      state = AsyncData(
        current.copyWith(
          events: [...current.events, ...page.items],
          page: current.page + 1,
          hasMore: page.hasMore,
          isLoadingMore: false,
        ),
      );
    } catch (_) {
      if (!ref.mounted) return;
      state = AsyncData(
        current.copyWith(isLoadingMore: false, loadMoreFailed: true),
      );
    }
  }
}
```

Add, edit and delete follow the example in section 3: call the repository, then set `state` from its answer. If the call throws, `state` is untouched and the caller reports the error.

### An action controller

For login, submit and similar actions, the state is only the status of the action. Type it `void`; the data the action produces lives in another provider.

```dart
final loginControllerProvider =
    AsyncNotifierProvider.autoDispose<LoginController, void>(
  LoginController.new,
);

class LoginController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {} // idle

  Future<bool> login(String email, String password) async {
    state = const AsyncLoading();
    final result = await AsyncValue.guard<void>(
      () => ref.read(authRepositoryProvider).login(email, password),
    );
    if (!ref.mounted) return false;
    state = result;
    return !result.hasError;
  }
}
```

```dart
// in the screen's build
ref.listen(loginControllerProvider, (_, next) {
  if (next case AsyncError(:final error)) showError(context, error);
});
final isLoading = ref.watch(loginControllerProvider).isLoading;
```

Give each action, or each screen, its own controller. When several unrelated actions share one `state`, a loading or error from one appears on every screen watching another. For a single button that nothing else observes, local widget state is enough (the `_busy` flag pattern).

### Mutations

The documented long-term answer for action status is Mutations, which are still experimental:

```dart
import 'package:flutter_riverpod/experimental/mutation.dart';

final addTodo = Mutation<Todo>();

// in build
final addTodoState = ref.watch(addTodo); // MutationIdle / Pending / Error / Success

// in a callback
addTodo.run(ref, (tsx) async {
  return tsx.get(todoListProvider.notifier).add('Eat a cookie');
});
```

Adopt them only if the team accepts breaking changes in minor releases.

Other rules from the DO/DON'T page:

- Do not initialise a provider from a widget's `initState`. Providers initialise themselves.
- Do not keep ephemeral UI state in providers (form fields, selected item, animations, controllers). A "selected item" belongs in the route: pass the id as a path parameter and `ref.watch(itemProvider(id))`.

---

## 8. Failures and retry

**Recommendation:** let errors reach the provider. A repository method returns its value or throws; it does not catch and return `null`. Returning `null` throws away the status code and message, and every Notifier then has to invent a generic exception of its own, so the user can never be told "no connection" from "session expired".

**Docs:** v3 retries failed providers automatically: up to 10 times, exponential backoff from 200 ms to 6.4 s. `Error` subclasses and `ProviderException` are not retried.

**Recommendation:** set one app-wide policy instead of accepting the default, so that requests which cannot succeed fail fast.

```dart
Duration? appRetry(int retryCount, Object error) {
  if (retryCount >= 3) return null;
  if (error is ProviderException) return null; // a dependency failed, not us
  if (error is ApiException && error.isClientError) return null;
  return Duration(milliseconds: 200 * (1 << retryCount));
}

runApp(ProviderScope(retry: appRetry, child: const MyApp()));
```

Per provider: `retry:` on the provider constructor, or `@Riverpod(retry: appRetry)`.

When a provider fails, reading it rethrows a `ProviderException` wrapping the original error. `AsyncValue.error` and `ProviderObserver` still receive the original. So `try/catch` around provider reads must unwrap `e.exception`; pattern matching on `AsyncError` is unchanged.

---

## 9. Dependencies and startup

Expose every dependency (HTTP client, repositories, storage) as a provider and reach it through `ref`. That is what makes overrides work in tests.

For values that must exist before the first frame, the docs give an eager-initialisation widget placed directly under `ProviderScope`:

```dart
class _EagerInitialization extends ConsumerWidget {
  const _EagerInitialization({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final result = ref.watch(configProvider);
    if (result.isLoading) return const CircularProgressIndicator();
    if (result.hasError) return const Text('Oopsy!');
    return child;
  }
}
```

Descendants can then use `ref.watch(configProvider).requireValue`.

**Recommendation (not from the docs):** for plain async singletons such as `SharedPreferences`, await them in `main` and inject with `overrideWithValue`; it is simpler than threading a loading state through the app.

Logout: the docs say there is deliberately no "reset everything". Make user-scoped providers `ref.watch` the session provider so they recompute when the user changes.

Scoping (`dependencies: [...]` plus nested `ProviderScope`) is described as "highly complex and will likely be reworked". Avoid it unless there is no alternative.

---

## 10. Rebuild cost

```dart
final name = ref.watch(userProvider.select((u) => u.firstName));
final name = await ref.watch(userProvider.selectAsync((u) => u.firstName));
```

**Docs:** measure first. `select` adds a small cost per read and more code, and only helps when the unused fields change often.

---

## 11. Testing

```dart
test('loads todos', () async {
  final container = ProviderContainer.test(
    overrides: [
      todoRepositoryProvider.overrideWithValue(FakeTodoRepository()),
    ],
  );

  // listen, not read: keeps an auto-dispose provider alive during the test
  final sub = container.listen(todoListProvider, (_, _) {});
  await expectLater(container.read(todoListProvider.future), completion(hasLength(2)));
});

testWidgets('shows todos', (tester) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [todoRepositoryProvider.overrideWithValue(FakeTodoRepository())],
      child: const MyApp(),
    ),
  );
  final container = tester.container();
});
```

- `ProviderContainer.test()` disposes itself.
- **Docs:** prefer mocking what a Notifier depends on over mocking the Notifier. If you must, the mock has to extend the Notifier base class, not just implement it. `overrideWithBuild` replaces only `build` and keeps the real methods.
- **Recommendation:** pass `retry: (_, _) => null` in tests so a failing provider reports its error immediately instead of backing off.

---

## 12. Logging and error reporting

```dart
final class AppObserver extends ProviderObserver {
  @override
  void providerDidFail(
    ProviderObserverContext context,
    Object error,
    StackTrace stackTrace,
  ) {
    // forward to crash reporting; context.provider.name identifies the source
  }
}

ProviderScope(observers: [AppObserver()], child: const MyApp());
```

Generated providers get a `name` automatically; hand-written ones need `name: '...'` to be readable in logs.

---

## 13. Project layout

The Riverpod docs do not prescribe one. **Recommendation:** follow the Flutter team's layout, set out in [architecture-guide.md](architecture-guide.md). The data and domain layers are grouped by type and shared; the UI is grouped by feature.

```
lib/
  main.dart            ProviderScope, retry policy, observers
  app.dart             MaterialApp.router
  routing/             router provider and routes
  data/
    services/          Dio provider, ApiClient, storage wrappers
    repositories/      one per kind of data, each with its provider
  domain/
    models/            Freezed models
  ui/
    core/              shared widgets, theme
    features/<feature>/
      view_models/     Notifiers
      views/           screens and their widgets
```

Notifiers are the "view models" of that architecture. Services and repositories are keep-alive providers; view models are auto-dispose. A feature folder never imports another feature folder.

---

## 14. Review checklist

- [ ] Providers are top-level `final`; none created dynamically or held in fields.
- [ ] `ref.watch` in `build`, `ref.read` only in callbacks and Notifier methods.
- [ ] Every family and every per-screen provider is auto-dispose.
- [ ] No list/map literals as family arguments.
- [ ] `ref.mounted` / `context.mounted` checked after each `await`.
- [ ] No writes in provider `build`; no provider initialised from `initState`.
- [ ] `build` returns or throws: no `state =`, no `AsyncValue.guard`, no reading `state` inside it.
- [ ] `AsyncValue.guard` only where the whole state is being replaced.
- [ ] Load more, add, edit, delete and toggle keep the existing data when they fail.
- [ ] Repositories throw on failure; none return `null` for an error.
- [ ] Action controllers are typed `void`, one per action or per screen.
- [ ] Data for one item comes from a family keyed by its id, not from a shared "current item" provider.
- [ ] No ephemeral UI state in providers.
- [ ] No imports of `legacy.dart` in new code.
- [ ] A deliberate `retry` policy on `ProviderScope`.
- [ ] `riverpod_lint` enabled and clean.

---

## 15. If code is being ported from Riverpod 2

Breaking changes listed in the migration guide: automatic retry on by default; listeners in invisible widgets paused; using a disposed `Ref` throws; legacy providers moved to `legacy.dart`; all providers filter updates with `==`; `ProviderObserver` methods take a `ProviderObserverContext`; `ExampleRef` and other `Ref` subclasses replaced by plain `Ref`; `AutoDispose*` and `Family*Notifier` types removed; provider failures rethrown as `ProviderException`; `valueOrNull` renamed `value`.

---

## Pages read

[Getting started](https://riverpod.dev/docs/introduction/getting_started) ·
[What's new in 3.0](https://riverpod.dev/docs/whats_new) ·
[3.0 migration](https://riverpod.dev/docs/3.0_migration) ·
[DO/DON'T](https://riverpod.dev/docs/root/do_dont) ·
[FAQ](https://riverpod.dev/docs/root/faq) ·
[First app tutorial](https://riverpod.dev/docs/tutorials/first_app) ·
[Providers](https://riverpod.dev/docs/concepts2/providers) ·
[Consumers](https://riverpod.dev/docs/concepts2/consumers) ·
[Containers](https://riverpod.dev/docs/concepts2/containers) ·
[Refs](https://riverpod.dev/docs/concepts2/refs) ·
[Automatic disposal](https://riverpod.dev/docs/concepts2/auto_dispose) ·
[Family](https://riverpod.dev/docs/concepts2/family) ·
[Mutations](https://riverpod.dev/docs/concepts2/mutations) ·
[Offline persistence](https://riverpod.dev/docs/concepts2/offline) ·
[Retry](https://riverpod.dev/docs/concepts2/retry) ·
[Observers](https://riverpod.dev/docs/concepts2/observers) ·
[Overrides](https://riverpod.dev/docs/concepts2/overrides) ·
[Scoping](https://riverpod.dev/docs/concepts2/scoping) ·
[Code generation](https://riverpod.dev/docs/concepts/about_code_generation) ·
[Hooks](https://riverpod.dev/docs/concepts/about_hooks) ·
[Testing](https://riverpod.dev/docs/how_to/testing) ·
[select](https://riverpod.dev/docs/how_to/select) ·
[Eager initialization](https://riverpod.dev/docs/how_to/eager_initialization) ·
[Pull to refresh](https://riverpod.dev/docs/how_to/pull_to_refresh) ·
[Cancel/debounce](https://riverpod.dev/docs/how_to/cancel) ·
[riverpod_lint](https://pub.dev/packages/riverpod_lint) ·
[riverpod_generator](https://pub.dev/packages/riverpod_generator)

Routing and how it connects to Riverpod is covered in [go-router-guide.md](go-router-guide.md).
