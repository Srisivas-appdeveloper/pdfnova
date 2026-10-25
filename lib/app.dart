import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/app_motion.dart';
import 'features/splash/splash_screen.dart';
import 'services/storage_service.dart';

class PdfNovaApp extends StatelessWidget {
  const PdfNovaApp({super.key});

  @override
  Widget build(BuildContext context) {
    final storage = StorageService.instance;
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: storage.themeMode,
      builder: (context, mode, _) => MaterialApp(
        title: 'PDF Nova',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: mode,
        // Switching theme cross-fades every colour token (NovaColors.lerp).
        themeAnimationDuration: NovaMotion.page,
        themeAnimationCurve: NovaMotion.emphasized,
        // Screens without an AppBar (home, splash) still get status/nav bar
        // icons that match the current theme.
        builder: (context, child) {
          final dark = Theme.of(context).brightness == Brightness.dark;
          return AnnotatedRegion<SystemUiOverlayStyle>(
            value: (dark
                    ? SystemUiOverlayStyle.light
                    : SystemUiOverlayStyle.dark)
                .copyWith(
              statusBarColor: Colors.transparent,
              systemNavigationBarColor:
                  Theme.of(context).scaffoldBackgroundColor,
              systemNavigationBarIconBrightness:
                  dark ? Brightness.light : Brightness.dark,
            ),
            child: child!,
          );
        },
        home: const SplashScreen(),
      ),
    );
  }
}
