# Animations — recommended approach

Sources, read 2026-10-04:

- **Skill `flutter-animating-apps`** from [flutter/agent-plugins](https://github.com/flutter/agent-plugins). It was removed from that repository on 2026-04-21, in a commit that replaced the whole skill set; I read its last version (dated 2026-03-12) from the repository history. The registry page still lists it, but the current repository no longer contains it.
- [Animations overview](https://docs.flutter.dev/ui/animations) on docs.flutter.dev, used to check the skill.
- The animations skill of the Very Good Ventures plugin, already reviewed in [plugin-practices-guide.md](plugin-practices-guide.md).

**Skill** and **Docs** mark what the sources say (paraphrased). **Adapted** marks my additions. Code samples have not been compiled.

---

## 1. Verdict

The skill is retired upstream, but its content agrees with the current Flutter animation docs, so it is still worth using. It covers the concepts, how to choose an approach, and four workflows. It says nothing about motion tokens or reduce-motion; those come from the Very Good Ventures skill and are merged in below.

---

## 2. Choosing an approach

**Docs and Skill:**

| The animation is… | Use |
|---|---|
| More like a drawing than like code (a character, a complex illustration) | A tool such as Rive or Lottie |
| A change of size, colour, opacity or position, with no playback control | An implicit widget: `AnimatedContainer`, `AnimatedOpacity`, `AnimatedSwitcher` and their relatives |
| The same, but no ready-made widget fits | `TweenAnimationBuilder` |
| Something to play, pause, reverse or repeat, or several properties moving together | Explicit: an `AnimationController` with a built-in transition widget, or `AnimatedBuilder` / `AnimatedWidget` |
| One element travelling from one screen to another | `Hero` |
| A sequence with delays or overlaps | Staggered: one controller, several tweens, each on its own `Interval` |
| Motion that should feel physical, such as snapping back after a drag | Physics: `SpringSimulation` driven by `controller.animateWith` |
| A standard Material transition (container transform, shared axis, fade through) | The `animations` package |

Start at the top. Reach for a controller only when an implicit widget cannot do it.

---

## 3. The building blocks

**Skill:**

| Class | Role |
|---|---|
| `Animation<T>` | A value that changes over time and notifies listeners. It knows nothing about the UI. |
| `AnimationController` | Drives an animation, producing values from 0 to 1 in step with the screen refresh. Needs `vsync` and must be disposed. |
| `Tween<T>` | Maps 0–1 onto another range or type: a size, an `Offset`, a colour. |
| `Curve` | Bends the timing. Applied with `CurvedAnimation` or `CurveTween`. |

---

## 4. Implicit animations

**Skill:** replace the static widget with its animated counterpart, give it a duration and optionally a curve, and change the property in `setState`. The widget animates to the new value by itself.

**Adapted:** durations and curves come from Flutter's Material motion tokens, and the animation is skipped when the user has asked for reduced motion.

```dart
AnimatedOpacity(
  opacity: visible ? 1 : 0,
  duration: MediaQuery.disableAnimationsOf(context)
      ? Duration.zero
      : Durations.medium2,
  curve: Easing.standard,
  child: child,
);
```

---

## 5. Explicit animations

**Skill:**

1. Add `SingleTickerProviderStateMixin` to the `State` class. Use `TickerProviderStateMixin` only when it owns several controllers.
2. Create the `AnimationController` with `vsync: this` and a duration.
3. Build the animated values with tweens and curves.
4. Rebuild with a transition widget or `AnimatedBuilder`, passing the part that does not change as `child`.
5. Drive it with `forward()`, `reverse()` or `repeat()`.
6. Dispose the controller in `dispose()`.

**Adapted** example, staggered: the content scales up during the first half and fades in during the second.

```dart
class _RevealState extends State<Reveal> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: Durations.long2,
  );

  late final Animation<double> _scale = Tween<double>(begin: 0.9, end: 1)
      .animate(
        CurvedAnimation(
          parent: _controller,
          curve: const Interval(0, 0.5, curve: Easing.standard),
        ),
      );

  late final Animation<double> _opacity = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0.5, 1, curve: Easing.standard),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.value = 1; // jump to the end state
    } else if (_controller.isDismissed) {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: ScaleTransition(scale: _scale, child: widget.child),
    );
  }
}
```

---

## 6. Hero

**Skill:**

- Wrap the widget on both screens in a `Hero` with the same `tag`.
- The tag is unique on each screen and built from data, such as the item's id.
- The two widgets should look alike, or the flight looks wrong.
- Navigating to the other screen triggers it.

**Adapted:** both screens must be shown by the same navigator. With go_router that means a parent route and its child, or two routes in the same shell branch.

---

## 7. Physics

**Skill:** create the controller without a fixed duration. Take the velocity from the gesture when it ends, convert it into the units of the animated property, build a `SpringSimulation` from mass, stiffness, damping and that velocity, and run it with `controller.animateWith(simulation)`.

---

## 8. Page transitions

**Skill:** a `PageRouteBuilder` whose `transitionsBuilder` returns a transition widget such as `SlideTransition`, pushed with `Navigator`.

**Adapted:** with go_router the transition is set on the route, through `pageBuilder` and `CustomTransitionPage`. See [go-router-guide.md](go-router-guide.md), section 10. Keep one helper that builds the app's standard transition so every route uses the same motion.

---

## 9. Rules

From the Very Good Ventures skill and the docs:

- Durations and curves come from `Durations` and `Easing`, or from one `AppMotion` class. No literal milliseconds scattered through widgets.
- Every controller is disposed.
- Animate the smallest subtree that changes. Pass the static part through `child`.
- A subtree that repaints often can be wrapped in `RepaintBoundary` so it does not repaint its surroundings.
- Respect reduce-motion everywhere. It is an accessibility requirement, not a nicety.
- Animation that never ends, such as a loading spinner, makes `pumpAndSettle()` wait forever in tests. Use `pump(duration)` there.

---

## 10. Review checklist

- [ ] An implicit widget was considered before a controller.
- [ ] No hard-coded durations or curves in widgets.
- [ ] Every `AnimationController` has `vsync` and is disposed.
- [ ] Reduce-motion is honoured.
- [ ] Hero tags are unique per screen and derived from data.
- [ ] Route transitions are defined on the routes and share one helper.
- [ ] Only the changing subtree rebuilds.
