# App architecture — recommended approach

The Flutter team's recommended architecture, adapted to this project's stack (Riverpod, go_router, Dio, Freezed).

Sources, read 2026-10-04:

- The skill `flutter-apply-architecture-best-practices` from the official Dart and Flutter plugin ([flutter/agent-plugins](https://github.com/flutter/agent-plugins)). Installed copy is plugin 1.0.5; the skill file is unchanged in 1.0.6.
- [Architecture recommendations](https://docs.flutter.dev/app-architecture/recommendations) on docs.flutter.dev, used to check the skill and for the strength of each recommendation.

**Skill** and **Docs** mark what those sources say (paraphrased). **Adapted** marks how I changed it for this stack. Code samples have not been compiled.

---

## 1. Verdict

The skill is best practice: it is a short version of the official architecture guide. It was worth copying, with two substitutions:

| The skill uses | This project uses | Why that is allowed |
|---|---|---|
| `ChangeNotifier` view models, `ListenableBuilder` | Riverpod Notifiers, `ConsumerWidget` | The docs rate `ChangeNotifier` as "conditional": the state-management tool is the team's choice. |
| `provider` or `get_it` for dependency injection | Riverpod providers | Same role. |

Not copied from the skill's sample code:

- Its repository caches one user and returns it for any id. A cache must be keyed by the argument.
- Its view model exposes only a loading flag, with no error state. `AsyncValue` covers loading, data and error.
- Its view model is loaded by calling a method from outside. With Riverpod the Notifier's `build` loads.

---

## 2. The layers

| Layer | Part | Job | In this stack |
|---|---|---|---|
| UI | View | Lean widget. Only UI logic: layout, animation, simple routing. | `ConsumerWidget` |
| UI | View model | Holds the screen's state, handles user actions, exposes immutable state. | Notifier or `AsyncNotifier`; a plain provider when the screen only reads |
| Domain (optional) | Use case | Logic too complex for a view model, or needed by several. | A class or a provider that combines repositories |
| Data | Repository | The single source of truth for one kind of data. Turns API results into app models; owns caching and retry. | A class with a keep-alive provider |
| Data | Service | Stateless wrapper around one external system: HTTP API, local database, platform plugin. | `ApiClient` over Dio, storage wrappers |

Dependencies run one way: view → view model → (use case) → repository → service. State travels back up as immutable objects. Rendering never mixes with business logic or data fetching.

---

## 3. The official recommendations

**Docs:** the recommendations page rates each item as strongly recommended ("Strong" below), recommended, or conditional. The right column is how this project meets it.

**Separation of concerns**

| Recommendation | Strength | In this project |
|---|---|---|
| Clearly separate data and UI layers | Strong | `lib/data` and `lib/ui`. Widgets never call Dio or storage. |
| Repository pattern in the data layer | Strong | One repository per kind of data. |
| Views and view models in the UI layer | Strong | `ConsumerWidget` plus Notifier. |
| `ChangeNotifier` and `Listenable` for updates | Conditional | Replaced by Riverpod. |
| No logic in widgets | Strong | Logic lives in Notifier methods. |
| A domain layer | Conditional | Only when a Notifier grows too complex or logic repeats. |

**Handling data**

| Recommendation | Strength | In this project |
|---|---|---|
| Unidirectional data flow | Strong | State comes down from providers; events go up as Notifier method calls. |
| Commands for user-interaction events | Recommended | Notifier methods and action controllers ([riverpod-guide.md](riverpod-guide.md), section 7). |
| Immutable data models | Strong | Freezed. |
| Generate them with `freezed` or `built_value` | Recommended | Freezed. |
| Separate API models and domain models | Conditional (large apps) | One model until the two shapes diverge. |

**App structure**

| Recommendation | Strength | In this project |
|---|---|---|
| Dependency injection | Strong | Providers, with constructor injection into repositories and services. |
| `go_router` for navigation | Recommended | Yes. |
| Standard names by role | Recommended | `ApiClient`, `EventRepository`, `EventDetailsNotifier`, `EventDetailsScreen`. |
| Abstract repository classes | Strong | See section 6. |

**Testing**

| Recommendation | Strength | In this project |
|---|---|---|
| Test the parts separately and together | Strong | Unit tests for services, repositories and Notifiers; widget tests for views. |
| Make fakes, and write code that can take them | Strong | Fakes or `mocktail` mocks at the repository boundary ([quality-guide.md](quality-guide.md), section 3). |

---

## 4. Project structure

**Skill:** a hybrid. UI code is grouped by feature. Data and domain code are grouped by type, because repositories and services are shared by many features.

**Adapted:**

```text
lib/
├── main.dart               ProviderScope, retry policy, observers
├── app.dart                MaterialApp.router, themes, localization
├── routing/                router provider and typed routes
├── l10n/                   ARB files and generated localizations
├── data/
│   ├── services/           Dio provider, ApiClient, storage wrappers
│   ├── repositories/       one per kind of data, each with its provider
│   └── models/             API models, only where they differ from domain models
├── domain/
│   ├── models/             Freezed models the UI works with
│   └── use_cases/          optional
└── ui/
    ├── core/               shared widgets, theme, spacing
    └── features/
        └── <feature>/
            ├── view_models/    Notifiers
            └── views/          screens and their widgets
```

The skill's tree has only `data`, `domain` and `ui`. `main.dart`, `app.dart`, `routing` and `l10n` are additions from the other guides.

Rules that follow from it:

- A feature folder never imports another feature folder. Everything shared is in `data`, `domain` or `ui/core`.
- `data` and `domain` never import from `ui`.
- `test/` mirrors `lib/`.

This replaces the layout I gave earlier in the Riverpod guide, which kept each feature's repositories inside the feature folder. That layout forces one feature to import another as soon as two screens need the same data.

---

## 5. One feature, end to end

**Adapted** from the skill's example.

```dart
// lib/data/services/api_client.dart
// The only class that knows HTTP: paths, parameters, status codes.
class ApiClient {
  ApiClient(this._dio);
  final Dio _dio;

  Future<Event> fetchEvent(int id) {
    return guardDio(() async {
      final res = await _dio.get<Map<String, dynamic>>('/events/$id');
      return Event.fromJson(res.data!);
    });
  }
}

@Riverpod(keepAlive: true)
ApiClient apiClient(Ref ref) => ApiClient(ref.watch(dioProvider));
```

```dart
// lib/data/repositories/event_repository.dart
// What the rest of the app talks to.
class EventRepository {
  EventRepository(this._api);
  final ApiClient _api;

  Future<Event> getEvent(int id) => _api.fetchEvent(id);
}

@Riverpod(keepAlive: true)
EventRepository eventRepository(Ref ref) =>
    EventRepository(ref.watch(apiClientProvider));
```

```dart
// lib/ui/features/event_details/view_models/event_details_notifier.dart
@riverpod
class EventDetailsNotifier extends _$EventDetailsNotifier {
  @override
  Future<Event> build(int id) {
    return ref.watch(eventRepositoryProvider).getEvent(id);
  }

  Future<void> setFavorite(bool value) async {
    // `id` is the build argument.
    final updated =
        await ref.read(eventRepositoryProvider).setFavorite(id, value);
    if (!ref.mounted) return;
    state = AsyncData(updated);
  }
}
```

```dart
// lib/ui/features/event_details/views/event_details_screen.dart
class EventDetailsScreen extends ConsumerWidget {
  const EventDetailsScreen({required this.id, super.key});
  final int id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final event = ref.watch(eventDetailsProvider(id));

    return Scaffold(
      body: switch (event) {
        AsyncValue(:final value?) => EventDetailsView(event: value),
        AsyncValue(:final error?) => ErrorView(error: error),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}
```

`guardDio` and `dioProvider` are from [dio-guide.md](dio-guide.md). The repository here only forwards the call. That is normal for a simple feature; it is the place caching, offline copies and combining sources go when they are needed.

---

## 6. Where Riverpod changes the picture

**Adapted.**

- **View model = Notifier.** One per screen, auto-dispose, keyed by the route's argument when the screen shows one item. Repositories and services are keep-alive.
- **Commands = Notifier methods.** The docs' command pattern wraps an action with its running and error state. `AsyncNotifier` methods and action controllers do that job here.
- **`Result` or exceptions.** The skill lets services return a `Result` wrapper. This project throws a typed `AppException` instead, and `AsyncValue` is the wrapper the UI sees. Use one style, not both.
- **Caching.** The skill puts the cache in the repository. With Riverpod the provider's state is already the UI's cache, and it is dropped when the screen closes. Add a repository cache only for data that must outlive screens or work offline.
- **Abstract repositories.** The docs recommend them strongly, so that development and staging can use different implementations. Declare `abstract interface class EventRepository` when a second implementation exists or is planned, such as a local one for running without a backend. Tests do not need it: any Dart class can be implemented by a fake.
- **Use cases.** Add one when logic combines repositories or is used by several view models. The lightest form is a provider that watches two repositories.
- **Two models.** Start with one Freezed model per entity. Add a separate API model in `data/models` when the response shape and what the UI needs stop matching, and convert in the repository.

---

## 7. Adding a feature

**Skill**, with the Riverpod steps substituted:

1. Define the domain model with Freezed.
2. Add the endpoint to `ApiClient`.
3. Add or extend the repository.
4. Complex logic or several repositories involved? Add a use case. Otherwise skip.
5. Write the Notifier: `build` loads, methods handle actions.
6. Write the view; it watches the Notifier's provider.
7. Run the generator. The providers are the dependency-injection step.
8. Test: the repository with a fake `ApiClient`, the Notifier with a mocked repository, the view with a widget test. Fix and re-run until green.

---

## 8. Review checklist

- [ ] Widgets contain no data access and no business logic.
- [ ] Every screen with state has a Notifier; state objects are immutable.
- [ ] Only services know Dio, storage keys or plugin APIs.
- [ ] Repositories receive their services through the constructor.
- [ ] No feature folder imports another; `data` and `domain` do not import `ui`.
- [ ] A domain layer exists only where a view model was getting too complex.
- [ ] Errors use one style across the data layer.
- [ ] A repository cache, if any, is keyed by its arguments.
- [ ] Classes are named for their role.
- [ ] Each layer has tests, and views are tested together with real Notifiers.
