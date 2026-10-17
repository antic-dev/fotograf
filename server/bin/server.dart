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

  final server = await io.serve(buildHandler(services), config.host, config.port, poweredByHeader: null);
  // Uklanja zastarela podrazumevana zaglavlja (x-xss-protection...) — naša su stroža.
  server.defaultResponseHeaders.clear();
  server.autoCompress = true;
  server.idleTimeout = const Duration(seconds: 120);
  stdout.writeln('Fotograf radi na http://${config.host}:${config.port}  (javni URL: ${config.publicUrl})');
  stdout.writeln('Administrator: ${config.adminEmail}');

  late final StreamSubscription<ProcessSignal> sigint;
  Future<void> shutdown(ProcessSignal _) async {
    stdout.writeln('Gašenje...');
    await sigint.cancel();
    await server.close();
    db.close();
    exit(0);
  }

  sigint = ProcessSignal.sigint.watch().listen(shutdown);
  if (!Platform.isWindows) ProcessSignal.sigterm.watch().listen(shutdown);
}
