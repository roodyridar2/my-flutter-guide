# Forms — recommended approach

Sources, read 2026-10-04:

- **Skill `flutter-building-forms`** from [flutter/agent-plugins](https://github.com/flutter/agent-plugins). It was removed from that repository on 2026-04-21, in a commit that replaced the whole skill set; I read its last version (dated 2026-03-12) from the repository history. The current repository no longer contains it.
- [Build a form with validation](https://docs.flutter.dev/cookbook/forms/validation) on docs.flutter.dev, used to check the skill.
- Flutter API reference for [`AutovalidateMode`](https://api.flutter.dev/flutter/widgets/AutovalidateMode.html) and [`FormField.forceErrorText`](https://api.flutter.dev/flutter/widgets/FormField/forceErrorText.html).

**Skill** and **Docs** mark what the sources say (paraphrased). **Adapted** marks my additions for this stack. Code samples have not been compiled.

---

## 1. Verdict

The skill is retired upstream, but it is the official cookbook recipe almost step for step, so it is still correct. It stops at basic validation. Submitting, server errors, keyboard behaviour and autofill are not in it; those parts below are mine.

---

## 2. Structure

**Skill and Docs:**

- A form is a `Form` widget inside a `StatefulWidget`.
- Create `final _formKey = GlobalKey<FormState>();` as a field of the `State` class and pass it to `Form(key: …)`. Never create it in `build`: a new key on every rebuild is expensive and throws away the form's state.
- A deeply nested widget can reach the form with `Form.of(context)` instead of receiving the key.

---

## 3. Validation

**Skill and Docs:**

- Fields are `TextFormField`s. Each has a `validator` that returns an error message when the input is wrong and `null` when it is fine.
- `_formKey.currentState!.validate()` runs every validator, shows the messages under the fields, and returns `true` only when all passed.

```dart
TextFormField(
  validator: (value) {
    if (value == null || value.isEmpty) return 'Please enter some text';
    return null;
  },
);

FilledButton(
  onPressed: () {
    if (_formKey.currentState!.validate()) {
      // submit
    }
  },
  child: const Text('Submit'),
);
```

**API reference**, when validation runs by itself:

| `AutovalidateMode` | Validates |
|---|---|
| `disabled` | Only when `validate()` is called. |
| `always` | All the time, even before the user types. |
| `onUserInteraction` | After each change the user makes. |
| `onUnfocus` | When the field loses focus. |
| `onUserInteractionIfError` | After a change, but only for a field already showing an error. |

**Adapted:**

- Start with `disabled`. After the first failed submit, switch the form to `onUserInteraction`, so errors clear as the user fixes them and nobody is told off before they have typed anything.
- Validators are small named functions (`validateEmail`, `validateRequired`) that return a **translated** message. Keep them in one file and unit-test them.
- Client-side validation is for the user's convenience. The server validates again.

---

## 4. Server-side errors

**API reference:** `forceErrorText` puts a field into the error state with the given message. While it is set the validator is not called, and it takes priority over `InputDecoration.errorText`. It exists for errors that come back from the server.

**Adapted:**

```dart
TextFormField(
  controller: _email,
  forceErrorText: _serverErrors['email'],
  onChanged: (_) => setState(() => _serverErrors.remove('email')),
);
```

Map the backend's error codes to translated messages ([plugin-practices-guide.md](plugin-practices-guide.md), section 7). Clear a field's server error as soon as the user edits that field.

---

## 5. Submitting with Riverpod

**Adapted.**

- What the user is typing is local widget state: controllers and the form key. It does not go into a provider ([riverpod-guide.md](riverpod-guide.md), section 7).
- Submitting is an action. It goes through an action controller, which gives the loading and error state.
- The button is disabled while the action runs. This also prevents a double submit.
- Failures that are not tied to one field are shown through `ref.listen`.

```dart
class LoginForm extends ConsumerStatefulWidget {
  const LoginForm({super.key});

  @override
  ConsumerState<LoginForm> createState() => _LoginFormState();
}

class _LoginFormState extends ConsumerState<LoginForm> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  var _autovalidate = AutovalidateMode.disabled;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      setState(() => _autovalidate = AutovalidateMode.onUserInteraction);
      return;
    }
    await ref
        .read(loginControllerProvider.notifier)
        .login(_email.text.trim(), _password.text);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final login = ref.watch(loginControllerProvider);

    ref.listen(loginControllerProvider, (_, next) {
      if (next case AsyncError(:final error)) showError(context, error);
    });

    return Form(
      key: _formKey,
      autovalidateMode: _autovalidate,
      child: AutofillGroup(
        child: Column(
          children: [
            TextFormField(
              controller: _email,
              decoration: InputDecoration(labelText: l10n.emailLabel),
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.email],
              validator: (value) => validateEmail(value, l10n),
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              controller: _password,
              decoration: InputDecoration(labelText: l10n.passwordLabel),
              obscureText: true,
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.password],
              validator: (value) => validateRequired(value, l10n),
              onFieldSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: AppSpacing.lg),
            FilledButton(
              onPressed: login.isLoading ? null : _submit,
              child: Text(l10n.signIn),
            ),
          ],
        ),
      ),
    );
  }
}

String? validateRequired(String? value, AppLocalizations l10n) {
  if (value == null || value.trim().isEmpty) return l10n.fieldRequired;
  return null;
}
```

`loginControllerProvider` is the action controller from the Riverpod guide.

---

## 6. Field details

**Adapted.**

- **Keyboard:** set `keyboardType` to match the content (email, number, phone) and `textInputAction` so the keyboard's action key moves to the next field, then submits on the last one.
- **Autofill:** set `autofillHints` on personal-data fields and wrap them in an `AutofillGroup`. Password managers depend on it, and it is an accessibility requirement ([plugin-practices-guide.md](plugin-practices-guide.md), section 6).
- **Labels:** use `labelText`, not only a hint. A hint disappears when typing starts, and screen readers need the label.
- **Formatting:** restrict or shape input with `inputFormatters`, such as digits only. Do not rewrite the text from `onChanged`.
- **Controllers:** dispose every `TextEditingController` and `FocusNode` the widget creates.
- **Small screens:** put the form in a scroll view so the keyboard does not cover fields or cause an overflow ([layout-guide.md](layout-guide.md), section 10).
- **Styling:** borders, padding and error colours come from `InputDecorationTheme`, not from each field.

---

## 7. Not adopted

- The Very Good Ventures plugin requires the `formz` package for validation. `Form` with validator functions covers the same need without another dependency.
- The skill's sample shows a snackbar straight from the button handler on success. Here the outcome comes from the action controller.

---

## 8. Review checklist

- [ ] The form key is a field of the `State`, not created in `build`.
- [ ] Every validator returns `null` on success and a translated message on failure.
- [ ] Validation starts on submit and becomes live after the first failure.
- [ ] Field values and controllers are local state; submit goes through an action controller.
- [ ] The submit button is disabled while submitting.
- [ ] Server errors appear on the field they belong to and clear on edit.
- [ ] Keyboard type, input action and autofill hints are set on every field.
- [ ] Controllers and focus nodes are disposed.
- [ ] The form scrolls when the keyboard is open.
