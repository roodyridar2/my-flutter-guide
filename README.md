# my-flutter-guide

A Claude skill, and the guides behind it, for building Flutter apps one consistent way.

The stack it covers: Riverpod 3 with code generation, go_router with typed routes, Dio, Freezed and json_serializable, secure storage and shared preferences, Flutter's built-in localization, Firebase, plus forms, animations, adaptive layout and the hand-off from the native splash screen to a Flutter one.

Each guide was written from the package's own documentation on 2026-10-04. It separates what the documentation states from what is this project's recommendation, and ends with a review checklist.

## What is in this repository

| Path | What it is |
|---|---|
| [`docs/`](docs/) | The 17 guides and a new-project setup checklist. This is the source of truth. |
| [`skills/my-flutter-guide/`](skills/my-flutter-guide/) | The skill: `SKILL.md` (core rules and which guide to open for which task) and `references/` (a copy of `docs/`). |
| [`dist/my-flutter-guide.skill`](dist/my-flutter-guide.skill) | The skill as one installable file. |
| [`scripts/build_skill.py`](scripts/build_skill.py) | Copies `docs/` into the skill and rebuilds the installable file. |

## Install the skill

**Claude Code, all projects on your machine.** Copy the skill folder into your personal skills folder:

```bash
cp -R skills/my-flutter-guide ~/.claude/skills/
```

**Claude Code, one project only.** Copy it into that project so it travels with the repository:

```bash
mkdir -p /path/to/your/app/.claude/skills && cp -R skills/my-flutter-guide /path/to/your/app/.claude/skills/
```

**Claude app.** Add `dist/my-flutter-guide.skill` through the Skills settings.

**Skills CLI.** The repository uses the usual `skills/<name>/SKILL.md` layout, so this should work once the repository is on GitHub. It has not been tested yet:

```bash
npx skills add https://github.com/roodyridar2/my-flutter-guide --skill my-flutter-guide
```

## Use it

Type the command, then say what you want:

```text
/my-flutter-guide set up a new project called shop_app
/my-flutter-guide add a products feature with a list and a details screen
/my-flutter-guide add a login form that calls POST /auth/login
/my-flutter-guide review lib/ui/features/orders
/my-flutter-guide what is the recommended way to do pull to refresh?
```

Claude should also pick the skill up by itself when you ask for Flutter work in plain words.

When the skill is active, Claude:

1. reads the project's `pubspec.yaml` to see which packages and versions are in use,
2. opens only the guides the task needs,
3. writes the code following the core rules,
4. checks the result against each guide's checklist, and runs format, analyze and tests when it can,
5. reports what it did, anything that departs from the guides, and what it could not verify.

## The guides

| Guide | Covers |
|---|---|
| [architecture](docs/architecture-guide.md) | Layers, folder layout, adding a feature end to end |
| [riverpod](docs/riverpod-guide.md) | Providers, Notifiers, async state, `AsyncValue.guard`, retry, testing |
| [go-router](docs/go-router-guide.md) | Routes, redirects, tabs, deep links, typed routes |
| [dio](docs/dio-guide.md) | HTTP client, interceptors, token refresh, error mapping |
| [models-codegen](docs/models-codegen-guide.md) | Freezed, json_serializable, build_runner |
| [storage](docs/storage-guide.md) | Secure storage and shared preferences |
| [localization](docs/localization-guide.md) | ARB files, generated localizations, dates and numbers |
| [quality](docs/quality-guide.md) | Lints, logging, unit, widget and integration tests |
| [images](docs/images-guide.md) | Network images and SVG |
| [platform](docs/platform-guide.md) | Opening links, permissions, app version |
| [app-icon-splash](docs/app-icon-splash-guide.md) | App icon and a static native splash |
| [splash-handoff](docs/splash-handoff-guide.md) | A seamless hand-off from the native splash to an animated Flutter splash |
| [layout](docs/layout-guide.md) | Adaptive layout and common layout errors |
| [forms](docs/forms-guide.md) | Forms, validation, server-side errors |
| [animations](docs/animations-guide.md) | Choosing an animation approach, motion tokens, reduce-motion |
| [firebase](docs/firebase-guide.md) | Setup, Crashlytics, Cloud Messaging |
| [plugin-practices](docs/plugin-practices-guide.md) | Theming, accessibility, security, test conventions, quality gate |
| [project-setup](docs/project-setup.md) | The order of work for a new project |

## Change the rules

Edit the guides in `docs/`, or the core rules in `skills/my-flutter-guide/SKILL.md`. Then rebuild and reinstall:

```bash
python3 scripts/build_skill.py
```

```bash
cp -R skills/my-flutter-guide ~/.claude/skills/
```

The script needs only the Python standard library. Do not edit `skills/my-flutter-guide/references/` by hand; the script overwrites it from `docs/`.

## Test results

A quick test on 2026-10-04: three tasks, each run once with the skill and once without, then graded against fixed checks by a separate grader that read the output.

| Task | With the skill | Without |
|---|---|---|
| Products feature: list with paging, pull to refresh, details screen | 14 of 14 | 8 of 14 |
| Login form with server-side field errors | 11 of 12 | 8 of 12 |
| Review of two deliberately flawed files | 12 of 12 | 12 of 12 |

How to read this:

- The checks are this project's own rules, so the run without the skill fails some by design. On the products task, three of its six failures are one layering decision counted three ways.
- The review task did not separate the two runs. Its checks only test whether a topic is mentioned.
- One login check failed in both runs for the same reason and is ambiguous.
- Nothing was compiled or run. The with-skill outputs depend on code generation and more packages. Only the with-skill runs wrote tests.
- With the skill, runs took about 49% longer and used about 22% more tokens.
- There was one run per configuration, so run-to-run variation is unknown.

## Limits to know about

- **The guides have a date.** They describe the package versions current on 2026-10-04, named at the top of each guide. The skill tells Claude to check the project's real versions and not to copy version numbers from the guides.
- **The code samples were not compiled.** They are patterns. Let the analyzer have the last word.
- **It is one team's choice of stack.** On a project with another state manager, the layering, data, navigation, UI and testing rules still apply; the Riverpod specifics do not.

## Sources

The guides are based on the official documentation of each package and of Flutter, Dart, Android and Firebase. Some practices were taken, paraphrased and adapted, from these agent skills, after checking them against that documentation:

- [flutter/agent-plugins](https://github.com/flutter/agent-plugins), the official Dart and Flutter plugin
- [VeryGoodOpenSource/vgv-ai-flutter-plugin](https://github.com/VeryGoodOpenSource/vgv-ai-flutter-plugin)
- [firebase/agent-skills](https://github.com/firebase/agent-skills)
- [dhruvanbhalara/skills](https://github.com/dhruvanbhalara/skills)

Each guide lists the pages it was written from.
