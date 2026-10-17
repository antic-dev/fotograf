import 'package:mailer/mailer.dart' as mail;
import 'package:mailer/smtp_server.dart';

import 'config.dart';
import 'http_util.dart';

/// Opcionalno slanje mejla štampariji direktno sa servera (npr. Gmail SMTP
/// sa "App password"). Ako SMTP nije podešen, aplikacija otvara mejl klijent.
class Mailer {
  Mailer(this.config);

  final Config config;

  bool get enabled => config.smtpEnabled;

  Future<void> send({required String to, required String subject, required String text}) async {
    if (!enabled) throw ApiError.badRequest('Slanje mejla sa servera nije podešeno.');
    final server = SmtpServer(
      config.smtpHost!,
      port: config.smtpPort,
      username: config.smtpUser,
      password: config.smtpPassword,
      ssl: config.smtpPort == 465,
    );
    final message = mail.Message()
      ..from = mail.Address(config.smtpFrom ?? config.smtpUser!, 'Fotograf')
      ..recipients.add(to)
      ..subject = subject
      ..text = text;
    try {
      await mail.send(message, server);
    } on mail.MailerException {
      throw ApiError(502, 'Mejl nije poslat. Proverite SMTP podešavanja.');
    }
  }
}
