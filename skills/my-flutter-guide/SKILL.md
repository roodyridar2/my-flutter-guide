---
name: my-flutter-guide
description: House rules and reference guides for building Flutter apps on this stack - Riverpod 3 with code generation, go_router with typed routes, Dio, Freezed and json_serializable, secure storage, gen-l10n, Firebase, forms, animations, adaptive layout, widget previews and the native-to-Flutter splash hand-off. Use this skill whenever the user asks to set up a Flutter project, add or change a feature, screen, provider or Notifier, model, repository, API call, route, form, animation, theme, test, widget preview or splash screen, wants to upgrade packages or fix a pub version conflict, wants Flutter or Dart code reviewed, fixed or refactored, or asks what the recommended way to do something in Flutter or Dart is, even when they do not mention the guide. Also use it when the user types /my-flutter-guide.
---

# My Flutter Guide

One team's agreed way to build Flutter apps. The detail lives in `references/`: twenty guides, each written from the documentation of the package or tool it covers (seventeen on 2026-10-04, three on 2026-10-06) and each ending in a review checklist. This file is the map: how to approach a task, the rules that apply to all of them, and which guide to open for which job.

## How to work

1. **Look at the project first.** Read `pubspec.yaml`, and `pubspec.lock` if it exists. Note which packages of this stack are in use and at which major versions, whether `build_runner` is present, and how the code is already organised. The guides describe specific versions (named at the top of each), and APIs differ between majors. An existing project's conventions also outrank the guide's layout: where they differ, say so instead of restructuring unasked.
2. **Open the guides for the task** (table below) and read the relevant sections before writing code. Do not work from memory of these libraries. Several defaults changed recently, and the guides record what the current documentation says, including which common patterns it now advises against.
3. **Write the code** following the core rules below and the guides.
4. **Check the result against the checklist** at the end of each guide you used. When a Flutter SDK and the project are available, run `dart format`, `flutter analyze` and the tests. If you could not run them, say so plainly.
5. **Report briefly:** what you did, anything that departs from the guides and why, and what you did not verify.

With no project yet (a design question, or code written from scratch), assume the full stack with code generation.

## Core rules

These hold for every task. Each one exists because the opposite is a mistake that keeps turning up in real code. The guides give the full reasoning.

**Layers** (`architecture-guide.md`)
- View → view model (a Riverpod Notifier) → repository → service. State travels back up as immutable objects. A widget never touches Dio, storage or Firebase.
- Data and domain code is grouped by type and shared (`lib/data/services`, `lib/data/repositories`, `lib/domain/models`). UI is grouped by feature (`lib/ui/features/<feature>/view_models` and `views`). A feature folder never imports another feature folder, because the day two screens need the same data that import becomes a tangle.
- Only the `ApiClient` service uses the `Dio` client. Repositories receive their services through the constructor.

**State** (`riverpod-guide.md`)
- `build` is the read: it returns the value or throws. Never assign `state`, call `AsyncValue.guard` or read `state` inside `build`, and never start a load from a widget's `initState`. Riverpod already turns `build` into loading, data and error; doing it by hand hides the error from it.
- Data for one item is a family provider keyed by the item's id. No "current item" or "selected item" provider: a single slot is overwritten as soon as two screens are open.
- Screen data is auto-dispose. Keep-alive is only for app-wide singletons: Dio, `ApiClient`, repositories, the session, the router.
- `ref.watch` in `build`. `ref.read` in callbacks and Notifier methods. Snackbars, dialogs and navigation that react to state go in `ref.listen`.
- After every `await`, check `ref.mounted` in a Notifier and `context.mounted` in a widget before going on.
- Writes are Notifier methods. Replace the whole state with `AsyncValue.guard` only for a reload with new inputs or for an action controller. Load-more, add, edit, delete and toggle use `try`/`catch` and leave the existing data in place when they fail.
- What the user is typing or has selected on one screen is widget state, not a provider.
- Render `AsyncValue` with a `switch` that matches the value first, so data stays visible during a refresh.

**Data and errors** (`dio-guide.md`, `models-codegen-guide.md`, `storage-guide.md`)
- Services and repositories return the value or throw a typed `AppException`. They never return `null` for a failure: that throws away why it failed and the UI can only say "something went wrong".
- Models are immutable Freezed classes. An enum that comes from the server has an `unknown` fallback.
- Tokens go in secure storage. Settings go in shared preferences through the newer API. Neither holds lists of data.

**Navigation** (`go-router-guide.md`)
- `context.go` by default. `push` only when a result is needed back.
- Typed routes when the project runs `build_runner`, named routes otherwise. No raw path strings in widgets. Pass ids in the path, not objects in `extra`.
- Signing in or out changes the session state, and the router's redirect reacts through `refreshListenable`. A screen does not navigate after login.
- Inside the router provider use `ref.listen` and `ref.read`, never `ref.watch` on the session: watching rebuilds the router and wipes the navigation stack.

**UI** (`plugin-practices-guide.md`, `layout-guide.md`, `localization-guide.md`)
- No user-visible literal strings: everything goes through the generated localizations.
- No hard-coded colours, font sizes or spacing in widgets: use the theme and the spacing scale.
- Decide layout by available width, never by device type or orientation.
- Images and icon buttons have labels, touch targets are at least 48 dp, and animations respect reduce-motion.

**Tests** (`quality-guide.md`)
- Test the real Notifier with a mocked or fake repository. Override repositories, not Notifiers.
- `ProviderContainer.test()` with retry turned off, private mocks, `setUp` inside groups.

**Language and packages** (`dart-language-guide.md`, `dependencies-guide.md`)
- A `switch` over a type this app owns (a Freezed union, an app enum) has no `_` and no `default`, so that adding a case stops every switch that must handle it from compiling. Over a package's type, keep the `_`.
- Primary constructors need Dart 3.13, suit plain classes only (models stay Freezed), and are never introduced as a side effect of another change.
- Never delete `pubspec.lock` to get past a version conflict: that upgrades everything at once. Upgrade the one package in the way.

## Which guide to open

All paths are under `references/`.

| Working on | Read |
|---|---|
| Starting a new project | `project-setup.md`, then the guides it points to |
| Layers, folders, adding a feature end to end | `architecture-guide.md` |
| Providers, Notifiers, async state, `AsyncValue.guard`, retry | `riverpod-guide.md` |
| Routes, redirects, tabs, deep links, typed routes | `go-router-guide.md` |
| HTTP calls, interceptors, token refresh, error mapping | `dio-guide.md` |
| Models, JSON, Freezed, `build_runner` | `models-codegen-guide.md` |
| Tokens, settings, anything kept on the device | `storage-guide.md` |
| Translations, ARB files, dates and numbers, right-to-left | `localization-guide.md` |
| Lints, `dart fix`, coverage, logging, unit, widget and integration tests, CI | `quality-guide.md` |
| `switch` and patterns, records, primary constructors, exceptions, doc comments | `dart-language-guide.md` |
| Upgrading packages, `pubspec.lock`, a pub version conflict | `dependencies-guide.md` |
| Widget previews (`@Preview`) | `widget-previews-guide.md` |
| Network images, SVG | `images-guide.md` |
| Opening links, permissions, app version | `platform-guide.md` |
| App icon, static native splash | `app-icon-splash-guide.md` |
| A splash that animates on from the native one | `splash-handoff-guide.md` |
| Adapting to screen size, overflow and constraint errors | `layout-guide.md` |
| Forms and validation | `forms-guide.md` |
| Animations and page transitions | `animations-guide.md` |
| Firebase setup, Crashlytics, push notifications | `firebase-guide.md` |
| Theming, accessibility, security, test conventions, quality gate, what was taken from which plugin | `plugin-practices-guide.md` |

Guides longer than 300 lines start with a contents line. Read the sections you need, not the whole file.

## Common jobs

**Set up a new project.** Follow `project-setup.md` in order. Add packages with `flutter pub add` so that pub resolves current versions; do not copy version numbers out of the guides.

**Add a feature.** Follow the order in `architecture-guide.md`, section 7: domain model, endpoint in `ApiClient`, repository, Notifier, view, generated providers, tests. Read `riverpod-guide.md` sections 3 and 7 for the Notifier, and the routing, forms or layout guide when the feature involves them.

**Review code.** Work out which guides the code touches and go through each one's checklist against it. Report findings most serious first. For each: the file and line, what is wrong, which rule it breaks and why that matters, and the fix, with corrected code where that helps. Connect the findings to the symptoms the user described. Do not rewrite the code unless asked.

**Upgrade packages, or fix a version conflict.** Follow `dependencies-guide.md`: read the solver's message, upgrade the one package or family it names, then regenerate, run `dart fix`, analyze and test. An SDK upgrade or a major version is its own change.

**Answer a "what is the recommended way" question.** Answer from the guide. Each guide marks what the package documentation states and what is this team's recommendation; keep that distinction in the answer and name the guide.

## When the guides and the project disagree

- **Newer package versions than the guide names:** check that package's current documentation or changelog before using the API in question, and tell the user the guide is out of date on that point.
- **Older versions:** the Riverpod guide is written for 3.x and the go_router guide for 18. On older majors some APIs do not exist (`ref.mounted`, automatic retry) or behave differently (`AsyncValue.value` rethrows on Riverpod 2). Adapt, and say so.
- **No `build_runner`:** write providers by hand and use named routes. Both styles are shown in the guides.
- **A different state manager (Bloc, Provider, GetX):** the layering, data, navigation, UI and testing rules still apply. The Riverpod specifics do not; say that instead of mixing two state managers.
- **Most of the guides' code samples were not compiled.** Treat them as patterns and let the analyzer have the last word. The guides that were checked on a real SDK say so at the top, with the version.
