import 'package:flutter/material.dart';
import '../../services/storage_service.dart';

/// Motion tokens. One family of curves everywhere so every transition in
/// the app feels like it belongs to the same hand: things arrive fast and
/// settle slowly (emphasized decelerate), and leave quickly (accelerate).
abstract class NovaMotion {
  static const quick = Duration(milliseconds: 180);
  static const medium = Duration(milliseconds: 320);
  static const page = Duration(milliseconds: 480);
  static const pageReverse = Duration(milliseconds: 360);
  static const container = Duration(milliseconds: 520);

  /// Staggered "rise into place" entrances.
  static const entranceFade = Duration(milliseconds: 420);
  static const entrance = Duration(milliseconds: 520);

  /// Launch: the splash sequence, then the hand-over to Home.
  static const splash = Duration(milliseconds: 1900);
  static const splashReduced = Duration(milliseconds: 500);
  static const handover = Duration(milliseconds: 750);

  /// The success check mark.
  static const celebrate = Duration(milliseconds: 900);

  /// Slow looping ambient motion (vault pulse, progress comet).
  static const ambient = Duration(milliseconds: 1800);

  /// Cross-fade when the background artwork changes with the theme.
  static const artSwap = Duration(milliseconds: 400);

  /// Material 3 "emphasized" — the house curve.
  static const emphasized = Cubic(0.2, 0.0, 0.0, 1.0);
  static const decelerate = Cubic(0.05, 0.7, 0.1, 1.0);
  static const accelerate = Cubic(0.3, 0.0, 0.8, 0.15);

  /// True when the system asks for less motion, or the user turned on
  /// "Reduce motion" in Settings. Transitions then become short fades.
  static bool reduced(BuildContext context) =>
      MediaQuery.maybeDisableAnimationsOf(context) == true ||
      StorageService.instance.reduceMotion.value;
}
