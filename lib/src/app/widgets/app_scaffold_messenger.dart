import 'package:material_ui/material_ui.dart';

const appSnackBarDuration = Duration(seconds: 2);

/// Applies the app-wide SnackBar duration without requiring every call site to
/// repeat the same value.
class OronBoxScaffoldMessenger extends ScaffoldMessenger {
  const OronBoxScaffoldMessenger({super.key, required super.child});

  @override
  ScaffoldMessengerState createState() => _OronBoxScaffoldMessengerState();
}

class _OronBoxScaffoldMessengerState extends ScaffoldMessengerState {
  @override
  ScaffoldFeatureController<SnackBar, SnackBarClosedReason> showSnackBar(
    SnackBar snackBar, {
    AnimationStyle? snackBarAnimationStyle,
  }) {
    final duration = snackBar.duration > appSnackBarDuration
        ? appSnackBarDuration
        : snackBar.duration;
    return super.showSnackBar(
      SnackBar(
        key: snackBar.key,
        content: snackBar.content,
        backgroundColor: snackBar.backgroundColor,
        elevation: snackBar.elevation,
        margin: snackBar.margin,
        padding: snackBar.padding,
        width: snackBar.width,
        shape: snackBar.shape,
        hitTestBehavior: snackBar.hitTestBehavior,
        behavior: snackBar.behavior,
        action: snackBar.action,
        actionOverflowThreshold: snackBar.actionOverflowThreshold,
        showCloseIcon: snackBar.showCloseIcon,
        closeIconColor: snackBar.closeIconColor,
        duration: duration,
        persist: snackBar.persist,
        animation: snackBar.animation,
        onVisible: snackBar.onVisible,
        dismissDirection: snackBar.dismissDirection,
        clipBehavior: snackBar.clipBehavior,
      ),
      snackBarAnimationStyle: snackBarAnimationStyle,
    );
  }
}
