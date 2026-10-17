import 'dart:async';
import 'dart:io';

import 'package:fotograf_server/fotograf_server.dart';
import 'package:shelf/shelf_io.dart' as io;

Future<void> main() async {
  final Config config;
  try {
    config = Config.fromEnvironment();
  } on StateError catch (e) {
    stderr.writeln('Greška u podešavanjima: ${e.message}');
    exit(78);
  } on FormatException catch (e) {
    stderr.writeln('Greška u podešavanjima (neispravna vrednost): ${e.message}');
    exit(78);
  }

  final db = Db.open(config.dataDir);
  final services = Services(
    config: config,
    db: db,
    drive: DriveStore(config: config, db: db, box: SecretBox(config.secretKey)),
    cache: MediaCache(config.dataDir),
    idVerifier: GoogleIdTokenVerifier(clientId: config.googleClientId),
    mailer: Mailer(config),
  );

  await services.initAdminAccount();
  if (!services.adminAccountSet) {
    stderr.writeln('UPOZORENJE: prijava nije podešena — postavite ADMIN_EMAIL i ADMIN_PASSWORD.');
  }
  if (!config.googleConfigured) {
    stdout.writeln('Napomena: GOOGLE_CLIENT_ID/GOOGLE_CLIENT_SECRET nisu podešeni — Google Drive se ne može povezati.');
  }

  final server = await io.serve(buildHandler(services), config.host, config.port, poweredByHeader: null);
  // Uklanja zastarela podrazumevana zaglavlja (x-xss-protection...) — naša su stroža.
  server.defaultResponseHeaders.clear();
  // Kompresiju radi Caddy (samo za tekst); slike i ZIP-ovi su već kompresovani.
  server.autoCompress = false;
  server.idleTimeout = const Duration(seconds: 120);
  stdout.writeln('Fotograf radi na http://${config.host}:${config.port}  (javni URL: ${config.publicUrl})');

  // Keš sličica ne sme da napuni disk servera.
  Future<void> trimCache() => services.cache.trim(config.cacheMaxBytes).catchError((Object e) {
        stderr.writeln('Čišćenje keša nije uspelo: $e');
      });
  unawaited(trimCache());
  final trimTimer = Timer.periodic(const Duration(hours: 1), (_) => trimCache());

  late final StreamSubscription<ProcessSignal> sigint;
  Future<void> shutdown(ProcessSignal _) async {
    stdout.writeln('Gašenje...');
    trimTimer.cancel();
    await sigint.cancel();
    await server.close();
    db.close();
    exit(0);
  }

  sigint = ProcessSignal.sigint.watch().listen(shutdown);
  if (!Platform.isWindows) ProcessSignal.sigterm.watch().listen(shutdown);
}
