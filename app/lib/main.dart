import 'dart:js_interop';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:web/web.dart' as web;

import 'router.dart';
import 'ui/theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  usePathUrlStrategy();
  _protectImages();
  runApp(const FotografApp());
}

/// Otežava čuvanje fotografija: nema kontekst menija ("Sačuvaj sliku"),
/// slike se ne mogu prevući na radnu površinu, a štampa stranice je prazna.
/// Fotografije se ionako crtaju na canvas, a ne kao <img> elementi.
void _protectImages() {
  BrowserContextMenu.disableContextMenu();
  web.document.addEventListener('contextmenu', ((web.Event e) => e.preventDefault()).toJS);
  web.document.addEventListener('dragstart', ((web.Event e) => e.preventDefault()).toJS);
}

class FotografApp extends StatefulWidget {
  const FotografApp({super.key});

  @override
  State<FotografApp> createState() => _FotografAppState();
}

class _FotografAppState extends State<FotografApp> {
  final _router = buildRouter();

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Fotograf',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      routerConfig: _router,
      locale: const Locale.fromSubtags(languageCode: 'sr', scriptCode: 'Latn'),
      supportedLocales: const [Locale.fromSubtags(languageCode: 'sr', scriptCode: 'Latn'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      builder: (context, child) {
        // Poštuje veća slova na telefonu, ali ne dozvoljava da raspored pukne.
        final mq = MediaQuery.of(context);
        return MediaQuery(
          data: mq.copyWith(textScaler: mq.textScaler.clamp(minScaleFactor: 1, maxScaleFactor: 1.35)),
          child: child!,
        );
      },
    );
  }
}
