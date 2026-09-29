import 'package:flutter/cupertino.dart';

final class KeyboardUtil {
  KeyboardUtil._();

  /// Drops the keyboard **and** clears the focused child the enclosing route
  /// would otherwise restore.
  ///
  /// Unfocuses the primary node, not the scope. `FocusNode.unfocus` works
  /// relative to the node's `enclosingScope`, so calling it on
  /// `FocusScope.of(context)` — the route's own scope — clears the focused
  /// children of the scope *around* the route while the route's own list keeps
  /// holding the field. The keyboard hides, and then `ModalRoute` puts it
  /// straight back the next time the screen is returned to. Unfocusing the
  /// focused node makes the route's scope the enclosing one, so it is that
  /// list which gets cleared.
  ///
  /// [context] is no longer read; it is kept so the dozens of existing call
  /// sites do not have to change.
  static void hideKeyboard(BuildContext context) {
    FocusManager.instance.primaryFocus?.unfocus();
  }

  static void shiftFocus(
    BuildContext context,
    FocusNode? currentFocus,
    FocusNode? nextFocus,
  ) {
    currentFocus?.unfocus();
    if (nextFocus != null) {
      FocusScope.of(context).requestFocus(nextFocus);
    }
  }
}
