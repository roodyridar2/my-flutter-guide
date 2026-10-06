# Dependencies — recommended approach

Covers adding, upgrading and locking packages with pub, and what to do when version solving fails.

Sources, read 2026-10-06:

- The skill `dart-resolve-package-conflicts` from the official Dart and Flutter plugin ([flutter/agent-plugins](https://github.com/flutter/agent-plugins)), installed copy 1.0.5.
- dart.dev, used to check it: [package dependencies](https://dart.dev/tools/pub/dependencies), [pub outdated](https://dart.dev/tools/pub/cmd/pub-outdated), [pub upgrade](https://dart.dev/tools/pub/cmd/pub-upgrade), [what not to commit](https://dart.dev/tools/pub/private-files) and [retracting a package version](https://dart.dev/tools/pub/publishing).

Version documented: Flutter 3.47.2 with Dart 3.13.2. Every command and flag below was run on it.

**Skill** and **Docs** mark what those sources say (paraphrased). **Adapted** marks my additions for this project.

---

## 1. Verdict

The skill is accurate and agrees with dart.dev. It is written for a plain Dart package, so three things are missing for a Flutter app, and one of its steps has a better form:

- The commands are `flutter pub …` here, not `dart pub …`. The flags are the same.
- The Flutter SDK chooses some versions itself (section 3). No constraint in `pubspec.yaml` moves those.
- This stack's code generators share dependencies and have to move together (section 4).
- For a locked version that must change, the skill edits `pubspec.lock` by hand. `flutter pub upgrade <package>` does the same without hand-editing a generated file (section 5).

---

## 2. Constraints and the lockfile

**Docs:**

- Use caret constraints (`^1.2.3`): any version from that one up to the next breaking one.
- `pubspec.lock` records the exact version of every package, including the ones your packages depend on. For an app, commit it. Then a change to any version shows up in review.
- `pub get` keeps to the lockfile. `pub upgrade` ignores it and writes a new one.
- For `dev_dependencies`, set the lower bound to the version in use.

**Adapted:**

- Add packages with `flutter pub add`, which writes a caret constraint for the current version. Do not copy version numbers from these guides or from memory.
- Do not write `any`, with one exception: `intl`, which the Flutter documentation tells you to add that way so that it follows `flutter_localizations` ([project-setup.md](project-setup.md), step 2).
- A package pinned to an exact version or held back on purpose gets a comment on that line saying why.

---

## 3. Seeing what is behind

```bash
flutter pub outdated
```

**Docs.** The columns:

| Column | Meaning |
|---|---|
| Current | The version in `pubspec.lock`. |
| Upgradable | The newest version the constraints in `pubspec.yaml` allow. `pub upgrade` goes here. |
| Resolvable | The newest version that works with every other package, if the constraints were lifted. |
| Latest | The newest version published, without prereleases. |

A gap between Upgradable and Resolvable means a constraint in your `pubspec.yaml` is the limit. A gap between Resolvable and Latest means another package is. To find which one:

```bash
flutter pub deps --style=compact
```

**Adapted:** some packages will always show as behind, and that is normal. The Flutter SDK pins a few itself (`material_color_utilities` and `test_api` on 3.47.2). They move only when Flutter is upgraded. Leave them alone.

---

## 4. Upgrading

**Skill and Docs.** Within the current constraints:

```bash
flutter pub upgrade
```

```bash
flutter pub upgrade --tighten
```

The second form also raises the lower bounds in `pubspec.yaml` to the versions just resolved, so the file says what the app is tested against.

Across a breaking version, name the package. Pub rewrites its constraint to the Resolvable version:

```bash
flutter pub upgrade --major-versions go_router
```

Add `--dry-run` to any of these to see what would change first.

**Adapted:**

- Read the changelog before a major upgrade, and upgrade one package or one family per pull request. When something breaks, the cause is then obvious.
- The families in this stack move together:
  - **The generators:** `build_runner`, `riverpod_generator`, `freezed`, `json_serializable` and `go_router_builder` all depend on `analyzer` and `build`. One of them lagging holds the others back. Each also moves with its annotation package.
  - **Riverpod:** `flutter_riverpod`, `riverpod_annotation`, `riverpod_generator`, `riverpod_lint`.
  - **Firebase:** all the `firebase_*` plugins.
- After any upgrade, in this order: regenerate, apply automated fixes, analyze, test.

```bash
dart run build_runner build -d
```

```bash
dart fix --apply
```

```bash
flutter analyze
```

```bash
flutter test
```

`dart fix` is what migrates calls to APIs the new version deprecated; see [quality-guide.md](quality-guide.md), section 1.

- Upgrading Flutter itself is a separate, single-purpose pull request ([plugin-practices-guide.md](plugin-practices-guide.md), section 11).

---

## 5. When version solving fails

Read the message first. It names the two requirements that cannot both hold:

```text
Because my_app depends on flutter_localizations from sdk which depends on
intl ^0.20.3, intl ^0.20.3 is required.
So, because my_app depends on intl ^0.18.0, version solving failed.
```

Here the app's own constraint on `intl` is the one to change.

**Adapted.** The usual causes on this stack:

| The message says | Cause | Fix |
|---|---|---|
| `… from sdk which depends on …` | Flutter requires a version your constraint excludes. | Change your constraint to match, or upgrade Flutter. |
| Two generators disagree about `analyzer`, `build` or `source_gen` | One generator is older than the rest. | Upgrade the whole family in one command (section 4). |
| `… requires SDK version >=…` | The package needs a newer Dart than the one installed. | Upgrade Flutter, or take the last version of the package that supports this SDK. |
| Two `firebase_*` plugins disagree | They come from different releases. | Upgrade all of them together. |

Try the remedies in this order and stop at the first that works:

1. Upgrade only the package in the way. The others stay locked unless they have to move.

```bash
flutter pub upgrade <package>
```

2. Let the packages it depends on move as well.

```bash
flutter pub upgrade --unlock-transitive <package>
```

3. Change the constraint in `pubspec.yaml` to the version in the Resolvable column, then run `flutter pub upgrade <package>` again.
4. As a last resort, a `dependency_overrides` entry. It forces a version that some package said it does not support, and the docs call that a risk. Put the reason and a link to the upstream issue in a comment on the entry, and delete it when the fix is released.

**Never delete `pubspec.lock` to make an error go away.** (Skill.) That upgrades every package at once. Whatever breaks next can no longer be traced to one change.

**Docs**, a retracted version. An author can withdraw a version after you have locked it. The app keeps working from the lockfile, but move off it. When a newer version exists:

```bash
flutter pub upgrade <package>
```

When the newest good version is older than the locked one:

```bash
flutter pub downgrade <package>
```

```bash
flutter pub upgrade <package>
```

---

## 6. CI and releases

**Docs:** in CI, fetch with the lockfile enforced. The command fails if `pubspec.lock` does not exactly satisfy `pubspec.yaml`, or if a downloaded package's content hash differs from the recorded one.

```bash
flutter pub get --enforce-lockfile
```

**Adapted:**

- That makes "it resolved differently on CI" impossible, and catches a `pubspec.yaml` edit committed without its lockfile.
- Before a release, scan the lockfile for known vulnerabilities and check licences: [plugin-practices-guide.md](plugin-practices-guide.md), sections 4 and 11.

---

## 7. Review checklist

- [ ] Constraints use caret syntax. Any exact pin or held-back package has a comment saying why.
- [ ] `pubspec.lock` is committed, and changes to it arrive with the `pubspec.yaml` change that caused them.
- [ ] CI runs `flutter pub get --enforce-lockfile`.
- [ ] A major upgrade covers one package or one family, in its own pull request.
- [ ] After an upgrade the generator, `dart fix`, analyze and the tests were run.
- [ ] No `dependency_overrides` without a reason and a link beside it.
- [ ] Nobody deleted `pubspec.lock` to get past a conflict.
