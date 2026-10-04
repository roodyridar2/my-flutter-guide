# Layout — recommended approach

Covers layouts that adapt to the available space, and the common layout errors.

Sources, read 2026-10-04:

- The skills `flutter-build-responsive-layout` and `flutter-fix-layout-issues` from the official Dart and Flutter plugin ([flutter/agent-plugins](https://github.com/flutter/agent-plugins)). Installed copy is plugin 1.0.5; both skill files are unchanged in 1.0.6.
- docs.flutter.dev, used to check the skills and for a few points they leave out: [general approach to adaptive apps](https://docs.flutter.dev/ui/adaptive-responsive/general), [adaptive best practices](https://docs.flutter.dev/ui/adaptive-responsive/best-practices), [common Flutter errors](https://docs.flutter.dev/testing/common-errors).

**Skill** and **Docs** mark what those sources say (paraphrased). **Adapted** marks my additions for this project. Code samples have not been compiled.

---

## 1. Verdict

Both skills are best practice: they are short versions of the official pages above, and I found nothing in them that disagrees with those pages. Nearly everything is adopted as it stands. No earlier guide covered layout.

---

## 2. The one rule

**Skill:** constraints go down, sizes go up, the parent sets the position.

A parent tells each child the minimum and maximum size it may be. The child picks a size inside that range. The parent then places it. Almost every layout error is a child that was given no upper limit in some direction, or a child that wants more than its limit.

---

## 3. Measuring the space

| Use | For |
|---|---|
| `MediaQuery.sizeOf(context)` | The size of the whole app window. |
| `LayoutBuilder` | The space this widget's parent gives it (`constraints.maxWidth`). |

**Skill and Docs:**

- Decide by **available width**, never by device type. There is no reliable "phone" or "tablet": the app can run in a resizable window, in split screen, or in picture-in-picture.
- Do not switch layouts on orientation (`OrientationBuilder`, `MediaQuery.orientationOf`) near the top of the tree. Orientation does not tell you how much room the window has.
- Use `MediaQuery.sizeOf(context)`, not `MediaQuery.of(context).size`. The second rebuilds the widget when anything in `MediaQuery` changes, not only the size.

**Recommendation:** use `MediaQuery.sizeOf` for decisions about the whole screen, such as which navigation to show. Use `LayoutBuilder` inside reusable widgets, so they adapt to wherever they are placed.

---

## 4. Breakpoints

**Docs:** Material's window classes put the first breakpoint at 600. Below it the window is "compact" and gets a `NavigationBar`; from 600 up it gets a `NavigationRail`.

**Adapted:** keep the numbers in one place. 840 is Material's next class ("expanded") and is my addition.

```dart
abstract final class Breakpoints {
  static const double medium = 600;
  static const double expanded = 840;
}
```

---

## 5. Abstract, measure, branch

**Docs:** three steps. Pull the data shared by both layouts out of the widgets. Measure the space. Branch on a breakpoint.

**Adapted:** the app shell from [go-router-guide.md](go-router-guide.md), switching between a bottom bar and a side rail.

```dart
class AppShell extends StatelessWidget {
  const AppShell({required this.navigationShell, super.key});
  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    // Abstract: one list feeds both kinds of navigation.
    final destinations = [
      (icon: Icons.home_outlined, label: l10n.tabHome),
      (icon: Icons.settings_outlined, label: l10n.tabSettings),
    ];
    // Measure.
    final wide = MediaQuery.sizeOf(context).width >= Breakpoints.medium;

    // Branch.
    if (!wide) {
      return Scaffold(
        body: navigationShell,
        bottomNavigationBar: NavigationBar(
          selectedIndex: navigationShell.currentIndex,
          onDestinationSelected: navigationShell.goBranch,
          destinations: [
            for (final d in destinations)
              NavigationDestination(icon: Icon(d.icon), label: d.label),
          ],
        ),
      );
    }

    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: navigationShell.currentIndex,
            onDestinationSelected: navigationShell.goBranch,
            labelType: NavigationRailLabelType.all,
            destinations: [
              for (final d in destinations)
                NavigationRailDestination(
                  icon: Icon(d.icon),
                  label: Text(d.label),
                ),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(child: navigationShell),
        ],
      ),
    );
  }
}
```

Resize the window across the breakpoint while a tab has a pushed screen, and check that the tab keeps its stack.

---

## 6. Large screens

**Skill:**

- Do not let content stretch across a wide window. Give it a maximum width and centre it:

```dart
Center(
  child: ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 800),
    child: content,
  ),
);
```

- Turn a single-column list into a grid whose column count follows the width:

```dart
GridView.builder(
  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
    maxCrossAxisExtent: 360,
    mainAxisSpacing: 16,
    crossAxisSpacing: 16,
    childAspectRatio: 3 / 2,
  ),
  itemCount: events.length,
  itemBuilder: (context, index) => EventCard(event: events[index]),
);
```

- Long or unbounded lists always use the `.builder` constructors, which build only what is visible.

---

## 7. Sharing space in a row or column

**Skill:**

| Widget | Effect |
|---|---|
| `Expanded` | The child must fill the remaining space. |
| `Flexible` | The child may take up to its share, and may be smaller. |
| `flex:` | The ratio between siblings. |

Both must be direct children of a `Row`, `Column` or `Flex`.

---

## 8. Orientation, windows and input

**Skill and Docs:**

- **Do not lock orientation.** On foldables and large screens a locked app is shown letterboxed. Android's large-screen quality tiers expect both orientations, Apple's guidance says the same, and it is an accessibility problem for users who mount their device one way.
- If a requirement really forces a lock, read the physical screen size from the `Display` API, not from `MediaQuery`. In compatibility mode `MediaQuery` does not report the larger window.
- Support mouse, trackpad and keyboard. Material widgets already handle them; custom widgets need focus and hover handling.
- Keep scroll position across rotation and resizing by giving lists a `PageStorageKey`.
- The app must keep its state when the window is resized, rotated, folded or unfolded.

---

## 9. Design habits

**Docs:**

- Break screens into small widgets. They rebuild less, can be `const`, and are easier to rearrange for another size.
- Design for what each form factor is good at. Not every feature has to exist everywhere.
- Solve touch first, then add mouse and keyboard shortcuts on top.

---

## 10. Common layout errors

**Skill and Docs.** Read the first error in the console. "RenderBox was not laid out" is a follow-on; the real cause is the error above it.

| Message | Cause | Fix |
|---|---|---|
| `A RenderFlex overflowed by … pixels` (yellow and black stripes) | A child of a `Row` or `Column` wants more room than there is. | Wrap the child in `Expanded` to make it fit, or `Flexible` to let it be smaller. |
| `Vertical viewport was given unbounded height` | A `ListView` or `GridView` directly inside a `Column`. The column offers infinite height. | Wrap the list in `Expanded`, or give it a height with `SizedBox`. |
| `An InputDecorator … cannot have an unbounded width` | A `TextField` directly inside a `Row`. | Wrap it in `Expanded` or `Flexible`, or give it a width. |
| `Incorrect use of ParentDataWidget` | `Expanded` or `Flexible` not directly under a `Row`, `Column` or `Flex`; `Positioned` not directly under a `Stack`; `TableCell` not under a `Table`. | Move it to be a direct child of the right parent. |
| `RenderBox was not laid out` | A side effect of one of the errors above. | Fix the earlier error. |
| `setState() or markNeedsBuild() called during build` | Something triggers a rebuild while the framework is building, for example showing a dialog from `build`. | Trigger it from a callback, not from `build`. |
| `The ScrollController is attached to multiple scroll views` | One controller is shared by two scrollables on screen. | Give each scrollable its own controller. |

```dart
// Unbounded height
Column(
  children: [
    const Text('Header'),
    Expanded(child: ListView(children: items)),
  ],
);

// Overflowing text
Row(
  children: [
    const Icon(Icons.info),
    Expanded(child: Text(longText)),
  ],
);
```

**Adapted:**

- With Riverpod, dialogs, snackbars and navigation that react to state go in `ref.listen`, which runs outside the build. That removes the usual cause of the "called during build" error.
- For single-line text, add `maxLines: 1` and `overflow: TextOverflow.ellipsis` inside the `Expanded`.
- A bottom overflow that appears only when the keyboard opens means the screen's content is not scrollable. Put it in a scroll view.
- Avoid `shrinkWrap: true` as the fix for a list inside a column. It works, but it lays out every item, so a long list becomes slow.

---

## 11. Testing a layout

**Adapted.** Run the same widget test at two window sizes.

```dart
testWidgets('shows the rail on a wide window', (tester) async {
  tester.view.physicalSize = const Size(1200, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpApp(const HomeScreen());

  expect(find.byType(NavigationRail), findsOneWidget);
  expect(find.byType(NavigationBar), findsNothing);
});
```

`pumpApp` is the helper in [plugin-practices-guide.md](plugin-practices-guide.md), section 2. An overflow fails a widget test, so a pass at a narrow size is also a check against overflow. Before release, also drag a desktop or web window through every width by hand.

---

## 12. Review checklist

- [ ] Layout decisions use window or parent width, never device type or orientation.
- [ ] `MediaQuery.sizeOf`, not `MediaQuery.of(context).size`.
- [ ] Breakpoints are constants in one place.
- [ ] Wide windows: content has a maximum width, or the list becomes a grid.
- [ ] Long lists use builder constructors.
- [ ] Orientation is not locked.
- [ ] Lists keep their scroll position across rotation and resize.
- [ ] No overflow stripes at the narrowest supported width or at the largest font size.
- [ ] `Expanded`, `Flexible` and `Positioned` are direct children of the right parent.
- [ ] Key screens have a widget test at a narrow and a wide size.
