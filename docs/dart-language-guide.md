# Dart language — recommended approach

Covers `switch` and patterns, records, primary constructors, exceptions and doc comments: the language habits the other guides rely on.

Sources, read 2026-10-06:

- The skills `dart-use-pattern-matching`, `dart-use-primary-constructors`, `dart-write-documentation` and `dart-fix-runtime-errors` from the official Dart and Flutter plugin ([flutter/agent-plugins](https://github.com/flutter/agent-plugins)), installed copy 1.0.5.
- dart.dev, used to check the skills: [branches](https://dart.dev/language/branches), [pattern types](https://dart.dev/language/pattern-types), [primary constructors](https://dart.dev/language/primary-constructors), [Effective Dart: usage](https://dart.dev/effective-dart/usage) and [Effective Dart: documentation](https://dart.dev/effective-dart/documentation).

Version documented: Dart 3.13.2, the one that ships with Flutter 3.47.2.

**Skill** and **Docs** mark what those sources say (paraphrased). **Adapted** marks my additions for this project. Unlike most of the guides, the samples here passed `flutter analyze` on that version, and the map-pattern behaviour in section 3 was confirmed with a test.

---

## 1. Verdict

| Skill | Is it best practice? |
|---|---|
| `dart-use-pattern-matching` | Yes, and the most useful of the four. Its list of patterns to avoid (section 4) is the part most code gets wrong. Adopted. |
| `dart-use-primary-constructors` | Accurate for Dart 3.13: every form it shows compiled. It is a syntax reference and says nothing about when to use the feature; section 6 adds that. |
| `dart-write-documentation` | A faithful short version of Effective Dart. It is written for published packages. An app needs fewer doc comments (section 8). |
| `dart-fix-runtime-errors` | Mostly general type and null-safety advice that the analyzer already enforces. Its three points on exceptions are kept (section 7). |

---

## 2. `switch`: which form, and the wildcard rule

**Docs:**

- A switch **expression** produces a value. Each arm is `pattern => expression`, arms are separated by commas, and it can stand anywhere an expression can except at the start of a statement.
- A switch **statement** runs statements. A non-empty case does not fall through, so no `break` is needed. An empty case falls through to the next one.
- `if`-`case` matches a single pattern. For several patterns use `switch`.
- A guard (`when condition`) is checked after the pattern matches. If it is false, matching goes on to the next case.
- The compiler checks that every possible value is handled. Enums and sealed types are fully known, so they need no default. A `default` case or a `_` arm makes any switch exhaustive.

```dart
IconData iconFor(OrderStatus status) => switch (status) {
  OrderStatus.pending => Icons.schedule,
  OrderStatus.shipped => Icons.local_shipping,
  OrderStatus.delivered => Icons.check_circle,
  OrderStatus.unknown => Icons.help_outline,
};
```

**Adapted.** That last point decides when a wildcard is allowed:

- **A type this app owns** (a Freezed union, an app enum): no `_` and no `default`. When someone adds a case, every switch that has to handle it stops compiling. A wildcard would hide the new case in all of them. `AppException` is consumed this way in [models-codegen-guide.md](models-codegen-guide.md), section 4.
- **A type a package owns** (`DioExceptionType`, for example): keep the `_`, so a package upgrade that adds a value cannot break the build. See [dio-guide.md](dio-guide.md), section 4.
- `AsyncValue` has its own switch, with the value matched first: [riverpod-guide.md](riverpod-guide.md).

---

## 3. Patterns worth using

| Situation | Use |
|---|---|
| A value from a sealed union or an enum | A switch expression with object patterns: `ServerError(:final message?) => message` |
| Several cases handled the same way | Logical-or: `Cancelled() \|\| UnknownError() => …` |
| A table of ranges | Relational patterns: `>= 80 => …` |
| A nullable field, which does not promote | A null-check pattern: `if (name case final name?)` |
| Two or three values back from a private helper | A record, destructured where it is called (section 5) |
| Untyped data at the edge of the app | A map pattern in a switch, with a `_` arm |

```dart
Color colorForScore(int score, ColorScheme scheme) => switch (score) {
  >= 80 => scheme.primary,
  >= 50 => scheme.tertiary,
  _ => scheme.error,
};
```

**Docs:** a map pattern matches the keys it lists and ignores the rest of the map. Both sides of a logical-or pattern must bind the same variables.

**Verified on Dart 3.13.2:**

- In a `switch` or an `if`-`case`, a map pattern does not match when a listed key is missing. That holds even when the subpattern is nullable: `{'note': final String? note}` fails on a map with no `note` key and matches on `'note': null`.
- In a declaration (`final {'id': id} = data;`) a missing key throws a `StateError`.

```dart
// A push notification payload: there is no model for it.
String? locationFor(Map<String, Object?> data) => switch (data) {
  {'type': 'order', 'id': final String id} => '/orders/$id',
  {'type': 'chat', 'thread_id': final String id} => '/chats/$id',
  _ => null,
};

// Required keys go in the pattern. An optional key is read from the map.
({String id, String? note})? orderFrom(Map<String, Object?> data) {
  if (data case {'type': 'order', 'id': final String id}) {
    return (id: id, note: data['note'] as String?);
  }
  return null;
}
```

**Adapted:**

- Typed JSON stays with `json_serializable`. Map patterns are for the few places that have no model: a push payload, deep-link parameters, an error body.
- Never destructure outside data with a map pattern in a declaration. A missing key is then a crash, not a failed match.
- The paths above are literal to keep the sample short. Real code builds them from the typed routes in [go-router-guide.md](go-router-guide.md).

---

## 4. Patterns to avoid

**Skill.** A pattern should make the code shorter or safer. When it does neither, the older form is the better one.

| Instead of | Write | Why |
|---|---|---|
| `if (x case final String s)` to promote one local variable | `if (x is String)` | The variable promotes by itself. The pattern only adds a second name for it. |
| A `null => null` arm beside `final String s => s` | One arm: `final String? s => s` | Same result with one case. |
| `if (raw case final Map<String, dynamic> m) use(m);` in a loop over data that must be valid | `if (raw is! Map<String, dynamic>) throw FormatException(…);` | The `if`-`case` skips a bad item without a trace. |
| `switch (flag) { true => a, false => b }` | `flag ? a : b` | A two-way choice is what the conditional operator is for. |
| A `switch` with one case and an empty default | `if (x is T)` | One case is not a table. |
| `final User(:name) = user;` to read one property | `user.name` | Nothing was destructured. |
| `if (code case >= 200 && < 300)` on its own | `if (code >= 200 && code < 300)` | Relational patterns earn their place in a multi-arm switch. |

**Adapted:** the third row is the pattern form of a core rule. A failure is thrown, never swallowed; skipping a malformed item is returning `null` for a failure under another name.

---

## 5. Records

```dart
({int done, int total}) _progress(List<Task> tasks) =>
    (done: tasks.where((task) => task.isDone).length, total: tasks.length);

double fraction(List<Task> tasks) {
  final (:done, :total) = _progress(tasks);
  return total == 0 ? 0 : done / total;
}
```

**Adapted:**

- A record fits a private helper that returns two or three values, and a grouping that lives inside one function.
- Anything that crosses a layer is a named Freezed class: a repository's return value, a provider's state, an argument to a route. The name documents it, and the class can later grow `copyWith`, JSON and a doc comment. A record can do none of that.
- Use named fields once there are more than two, or two of the same type. `(int, int)` says nothing about which is which.

---

## 6. Primary constructors

**Docs:**

- They need language version 3.13, that is `sdk: ^3.13.0` or newer under `environment` in `pubspec.yaml`.
- A parameter list after the class name declares the constructor. A parameter marked `final` or `var` also declares the field. A parameter with neither is only a parameter, usable in field initialisers.
- `const` goes before the class name. An empty body can be written as `;`.
- Checks and extra initialisation go in the body, after `this :`.
- A class with a primary constructor can have no other constructor that initialises the object itself. Every other one redirects to it. Constructors in the body can be written `new name(…)` and `factory name(…)`, without repeating the class name.
- A private named parameter is public where it is called: `{required final int _amount}` is called with `amount:`.
- Enums and extension types take them too.

```dart
// Before
class EventRepository {
  EventRepository(this._api);
  final ApiClient _api;

  Future<Event> getEvent(int id) => _api.fetchEvent(id);
}

// After
class EventRepository(final ApiClient _api) {
  Future<Event> getEvent(int id) => _api.fetchEvent(id);
}
```

```dart
class const EventTile({
  super.key,
  required final Event event,
  final VoidCallback? onTap,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) =>
      ListTile(title: Text(event.title), onTap: onTap);
}

class Range(final int start, final int end) {
  this : assert(start <= end);

  final int length = end - start;

  new empty() : this(0, 0);
}
```

**Docs, and it breaks existing code:** from language version 3.13, `final` and `var` on a parameter mean "declare a field", so they are allowed only in a primary constructor. `void f(final int x)` and a body constructor `A(final int x)` no longer compile (`extraneous_modifier`). Remove the modifier when a project moves to 3.13. Freezed 4 made the same change to its factory parameters ([models-codegen-guide.md](models-codegen-guide.md), section 8).

**Adapted:**

- **Where they fit:** plain classes whose constructor only stores its arguments. Here that means repositories and services that take their dependencies, small value classes, and widgets.
- **Where they do not:** models stay Freezed, because a primary constructor gives fields but not `==`, `copyWith` or JSON ([models-codegen-guide.md](models-codegen-guide.md), section 8). Notifiers have no constructor to shorten. A constructor that does real work reads better written out.
- **Classes a code generator reads** (`@JsonSerializable`, `@TypedGoRoute` and the like): check that generator's changelog before using one. Freezed 4 supports them; the others were not checked for this guide.
- **It is a style, not a fix.** Follow the file you are in. Do not convert existing classes inside a feature change; a conversion is its own pull request, like a lint upgrade ([plugin-practices-guide.md](plugin-practices-guide.md), section 11).
- On an older language version none of this compiles. Write ordinary constructors and say so.

---

## 7. Exceptions

**Docs (Effective Dart):**

- Catch with an `on` clause. A bare `catch` also catches the bugs.
- An `Error` (`TypeError`, `StateError`, `ArgumentError`, …) is a programming mistake. Do not catch it; fix it. An `Exception` is a failure at run time.
- If a bare `catch` is unavoidable, do something with what it caught: log it, show it or rethrow it.
- Rethrow with `rethrow`. `throw e` replaces the stack trace with the current line.
- Avoid a `late` variable when the code needs to ask whether it was set. Make it nullable and check for `null`.

**Skill:** the lint `avoid_catching_errors` reports a catch of an `Error` type. It is not in `flutter_lints`; switch it on under `linter: rules:`.

**Adapted:**

- This stack converts exceptions in one place. `guardDio` catches `DioException` and throws an `AppException`, keeping the stack trace with `Error.throwWithStackTrace` ([dio-guide.md](dio-guide.md), section 4). Above it nothing catches: the `AppException` travels up to the `AsyncValue`.
- The exception is a Notifier method that must put its state back, such as load-more clearing `isLoadingMore` ([riverpod-guide.md](riverpod-guide.md)). A bare `catch` is acceptable there because leaving the flag set is worse. It still records the failure, in the state and in the log.
- `!` and `late` are not fixes for an analyzer error. Each one moves a compile-time error to run time.

---

## 8. Doc comments

**Docs (Effective Dart):**

- `///`, never `/** … */`. Write sentences: a capital letter and a full stop.
- The first paragraph is one sentence that summarises, with a blank `///` line after it.
- Do not repeat what the name and signature already say.
- A method that acts starts with a third-person verb ("Starts…"). A value starts with a noun phrase. A boolean starts with "Whether".
- Parameters, return values and exceptions are described in prose, with the name in square brackets. No `@param` or `@return` tags.
- The comment goes above annotations, not between them and the declaration.
- For a getter and setter pair, document one of them.

**Skill, verified:** to link a name the file does not import, add a doc import above the `library;` line instead of a real import. With the lint `comment_references` on, the analyzer reports a `[name]` that does not resolve.

```dart
/// @docImport 'package:dio/dio.dart';
library;

/// Loads events from the API.
///
/// Every method throws an [AppException] when the request fails, mapped
/// from the [DioException] underneath. None returns `null` for a failure.
class EventRepository(final ApiClient _api) {
  /// The events that start on [day], soonest first.
  ///
  /// Throws a [RequestTimeout] when the server does not answer in time.
  Future<List<Event>> fetchForDay(DateTime day) => _api.fetchEvents(day);
}
```

**Adapted:**

- An app is not a published package. Do not turn on `public_member_api_docs`: a comment on every widget and field is noise, and noise trains people to skip comments.
- Document what the name and signature cannot say: which `AppException` a repository method throws, why a provider is kept alive, a parameter's unit or range, anything that would surprise the next reader.
- A comment says why. What the code does is the job of the names.
- Turn on `comment_references`, so a rename does not leave dead links behind.

---

## 9. Review checklist

- [ ] A switch over a type this app owns has no `_` and no `default`. A switch over a package's type keeps one.
- [ ] A switch that produces a value is a switch expression.
- [ ] Map patterns on outside data are in a `switch` or `if`-`case` with a fallback, never in a declaration.
- [ ] Optional keys are read from the map, not listed in the pattern.
- [ ] No pattern from section 4: no alias for a promotable variable, no single-case or boolean switch, no `if`-`case` that silently skips bad data.
- [ ] Records stay inside a file. Values that cross a layer are named classes.
- [ ] Primary constructors only where the language version is 3.13 or newer, only on plain classes, and not introduced as a side effect of another change.
- [ ] No `final` or `var` on ordinary parameters.
- [ ] Catches name a type with `on`. No catch of an `Error`. `rethrow`, not `throw e`.
- [ ] Doc comments explain failures and reasons, start with a one-sentence summary, and use `[name]` links that resolve.
