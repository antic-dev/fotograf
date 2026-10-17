import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../api/api.dart';
import '../api/models.dart';
import '../ui/common.dart';
import '../ui/theme.dart';
import '../web/browser.dart';
import 'auth.dart';
import 'widgets.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, this.driveResult});
  final String? driveResult;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  Settings? _s;
  Object? _error;
  final _studio = TextEditingController();
  final _watermark = TextEditingController();
  final _printer = TextEditingController();
  final _sizes = TextEditingController();
  final _finishes = TextEditingController();
  bool _saving = false;
  List<Map<String, dynamic>>? _audit;

  @override
  void initState() {
    super.initState();
    _load();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      switch (widget.driveResult) {
        case 'povezan':
          showMessage(context, 'Google Drive je uspešno povezan.');
        case 'greska':
          showMessage(context, 'Povezivanje nije uspelo. Prijavite se nalogom ${AdminAuth.instance.email} i dozvolite pristup.', error: true);
        case 'otkazano':
          showMessage(context, 'Povezivanje je otkazano.', error: true);
      }
    });
  }

  @override
  void dispose() {
    for (final c in [_studio, _watermark, _printer, _sizes, _finishes]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final d = await Api.instance.get('/api/admin/settings');
      final s = Settings.fromJson(d as Map<String, dynamic>);
      if (!mounted) return;
      setState(() {
        _s = s;
        _studio.text = s.studioName;
        _watermark.text = s.watermarkText;
        _printer.text = s.printerEmail;
        _sizes.text = s.defaultSizes.join(', ');
        _finishes.text = s.defaultFinishes.join(', ');
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  List<String> _split(String s) => s.split(',').map((x) => x.trim()).where((x) => x.isNotEmpty).toList();

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await Api.instance.put('/api/admin/settings', {
        'studioName': _studio.text.trim(),
        'watermarkText': _watermark.text.trim(),
        'printerEmail': _printer.text.trim(),
        'defaultSizes': _split(_sizes.text),
        'defaultFinishes': _split(_finishes.text),
      });
      AdminAuth.instance.studioName = _studio.text.trim();
      if (mounted) showMessage(context, 'Podešavanja su sačuvana.');
      await _load();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _disconnect() async {
    final ok = await confirm(
      context,
      title: 'Isključiti Google Drive?',
      message: 'Fotografije ostaju na vašem Drive-u, ali klijenti neće moći da ih vide dok ponovo ne povežete nalog.',
      confirmLabel: 'Isključi',
      danger: true,
    );
    if (!ok) return;
    try {
      await Api.instance.post('/api/admin/drive/disconnect');
      await _load();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _revokeAll() async {
    final ok = await confirm(
      context,
      title: 'Odjaviti sve uređaje?',
      message: 'Bićete odjavljeni svuda, uključujući i ovaj uređaj.',
      confirmLabel: 'Odjavi sve',
      danger: true,
    );
    if (!ok) return;
    try {
      await Api.instance.post('/api/admin/sessions/revoke-all');
    } catch (_) {}
    await AdminAuth.instance.logout();
    if (mounted) context.go('/admin/prijava');
  }

  Future<void> _loadAudit() async {
    try {
      final list = await Api.instance.get('/api/admin/audit') as List;
      if (mounted) setState(() => _audit = list.cast<Map<String, dynamic>>());
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _s;
    final t = Theme.of(context).textTheme;
    if (s == null) return Scaffold(body: _error != null ? ErrorView(error: _error!, onRetry: _load) : const LoadingView());

    Widget section(String title, String? subtitle, List<Widget> children) => Card(
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(title, style: t.titleLarge),
              if (subtitle != null) ...[const SizedBox(height: 4), Text(subtitle, style: t.bodyMedium?.copyWith(color: AppColors.inkSoft))],
              const SizedBox(height: 18),
              ...children,
            ]),
          ),
        );

    return Scaffold(
      body: ListView(padding: const EdgeInsets.only(bottom: 140), children: [
        Centered(
          maxWidth: 820,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const PageHeader(title: 'Podešavanja'),
            section(
              'Google Drive',
              'Svaki projekat dobija svoj folder u „Fotograf” na vašem Drive-u.',
              [
                if (s.driveConnected)
                  Row(children: [
                    const Icon(Icons.check_circle_rounded, color: AppColors.emerald),
                    const SizedBox(width: 10),
                    Expanded(child: Text('Povezano: ${s.driveEmail ?? ''}', style: t.titleSmall)),
                    TextButton(onPressed: _disconnect, child: const Text('Isključi')),
                  ])
                else
                  const DriveConnectBanner(),
                if (s.driveConnected) ...[
                  const SizedBox(height: 8),
                  Text('Aplikacija ima pristup samo fajlovima koje je sama napravila (dozvola „drive.file”).', style: t.bodySmall),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      onPressed: () => navigateTo('/api/admin/drive/connect'),
                      icon: const Icon(Icons.sync_rounded),
                      label: const Text('Poveži ponovo'),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 16),
            section('Studio', 'Prikazuje se klijentima i u žigu.', [
              TextField(controller: _studio, maxLength: 80, decoration: const InputDecoration(labelText: 'Naziv studija', counterText: '')),
              const SizedBox(height: 14),
              TextField(
                controller: _watermark,
                maxLength: 40,
                decoration: const InputDecoration(labelText: 'Tekst vodenog žiga', helperText: 'Prazno = naziv studija. Žig je uvek uključen za klijente.', counterText: ''),
              ),
            ]),
            const SizedBox(height: 16),
            section('Štamparija', null, [
              TextField(
                controller: _printer,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'Mejl štamparije', prefixIcon: Icon(Icons.alternate_email_rounded)),
              ),
              const SizedBox(height: 8),
              Text(
                s.smtpEnabled
                    ? 'Slanje mejla direktno iz aplikacije je uključeno.'
                    : 'Mejl se otvara u vašoj mejl aplikaciji. Za slanje jednim dodirom podesite SMTP (vidi README).',
                style: t.bodySmall,
              ),
              const SizedBox(height: 14),
              TextField(controller: _sizes, decoration: const InputDecoration(labelText: 'Podrazumevane veličine (zarezom)', hintText: '10x15, 13x18, 20x30')),
              const SizedBox(height: 14),
              TextField(controller: _finishes, decoration: const InputDecoration(labelText: 'Podrazumevani papir (zarezom)', hintText: 'Sjajni, Mat')),
            ]),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Sačuvaj podešavanja'),
            ),
            const SizedBox(height: 28),
            section('Bezbednost', 'Administrator: ${s.adminEmail} · aktivnih sesija: ${s.activeSessions}', [
              Wrap(spacing: 10, runSpacing: 10, children: [
                OutlinedButton.icon(
                  onPressed: () async {
                    await AdminAuth.instance.logout();
                    if (context.mounted) context.go('/admin/prijava');
                  },
                  icon: const Icon(Icons.logout_rounded),
                  label: const Text('Odjavi se'),
                ),
                OutlinedButton.icon(onPressed: _revokeAll, icon: const Icon(Icons.devices_other_rounded), label: const Text('Odjavi sve uređaje')),
                OutlinedButton.icon(onPressed: _loadAudit, icon: const Icon(Icons.history_rounded), label: const Text('Dnevnik aktivnosti')),
              ]),
              if (_audit != null) ...[
                const SizedBox(height: 16),
                for (final a in _audit!.take(100))
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      SizedBox(width: 130, child: Text(formatDateTimeMs(a['ts'] as int), style: t.bodySmall)),
                      Expanded(
                        child: Text('${_auditLabel(a['action'] as String)}${(a['detail'] as String).isEmpty ? '' : ' · ${a['detail']}'}', style: t.bodyMedium),
                      ),
                      Text(a['ip'] as String, style: t.bodySmall?.copyWith(color: AppColors.inkFaint)),
                    ]),
                  ),
              ],
            ]),
          ]),
        ),
      ]),
    );
  }
}

String _auditLabel(String action) => switch (action) {
      'login' => 'Prijava',
      'login_failed' => '⚠ Neuspela prijava',
      'login_denied' => '⚠ Odbijen nalog',
      'project_created' => 'Novi projekat',
      'project_updated' => 'Izmenjen projekat',
      'project_deleted' => 'Obrisan projekat',
      'project_link_rotated' => 'Novi link projekta',
      'photos_deleted' => 'Obrisane fotografije',
      'order_submitted' => 'Klijent poslao izbor',
      'order_status' => 'Status porudžbine',
      'order_deleted' => 'Obrisana porudžbina',
      'print_link_created' => 'Link za štampariju',
      'print_link_revoked' => 'Opozvan link štamparije',
      'print_link_sent' => 'Mejl štampariji',
      'print_zip' => 'Štamparija preuzela ZIP',
      'drive_connected' => 'Povezan Drive',
      'drive_disconnected' => 'Isključen Drive',
      'drive_connect_failed' => '⚠ Neuspelo povezivanje Drive-a',
      'settings_updated' => 'Izmenjena podešavanja',
      'sessions_revoked' => 'Odjavljeni svi uređaji',
      _ => action,
    };
