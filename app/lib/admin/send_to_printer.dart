import 'package:flutter/material.dart';

import '../api/api.dart';
import '../api/models.dart';
import '../ui/common.dart';
import '../ui/theme.dart';
import '../web/browser.dart';

/// Pravi link za štampariju od izabranih porudžbina i odmah nudi slanje.
Future<bool> sendOrdersToPrinter(BuildContext context, List<String> orderIds, {String? label}) async {
  final link = await showDialog<PrintLink>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _CreateLinkDialog(orderIds: orderIds, label: label),
  );
  if (link == null || !context.mounted) return false;
  await showPrintLinkSheet(context, link, justCreated: true);
  return true;
}

class _CreateLinkDialog extends StatefulWidget {
  const _CreateLinkDialog({required this.orderIds, this.label});
  final List<String> orderIds;
  final String? label;

  @override
  State<_CreateLinkDialog> createState() => _CreateLinkDialogState();
}

class _CreateLinkDialogState extends State<_CreateLinkDialog> {
  int _days = 30;
  bool _busy = false;
  late final TextEditingController _label = TextEditingController(text: widget.label ?? '');

  @override
  void dispose() {
    _label.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    setState(() => _busy = true);
    try {
      final data = await Api.instance.post('/api/admin/print-links', {
        'orderIds': widget.orderIds,
        'days': _days,
        if (_label.text.trim().isNotEmpty) 'label': _label.text.trim(),
      });
      if (mounted) Navigator.pop(context, PrintLink.fromJson(data as Map<String, dynamic>));
    } catch (e) {
      if (mounted) {
        showError(context, e);
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return AlertDialog(
      title: const Text('Pošalji štampariji'),
      content: SizedBox(
        width: 460,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
            'Napraviću poseban link sa ${widget.orderIds.length == 1 ? 'ovom porudžbinom' : '${widget.orderIds.length} porudžbine'}. '
            'Štamparija preko njega preuzima originale u punoj rezoluciji direktno sa vašeg Google Drive-a — vaš internet se ne troši.',
            style: t.bodyLarge?.copyWith(color: AppColors.inkSoft),
          ),
          const SizedBox(height: 20),
          TextField(controller: _label, decoration: const InputDecoration(labelText: 'Naziv (nije obavezno)', hintText: 'npr. Venčanje Ana i Marko')),
          const SizedBox(height: 18),
          Text('Link važi', style: t.titleSmall),
          const SizedBox(height: 8),
          Wrap(spacing: 8, children: [
            for (final d in const [7, 14, 30, 60])
              ChoiceChip(label: Text('$d dana'), selected: _days == d, onSelected: (_) => setState(() => _days = d)),
          ]),
        ]),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('Odustani')),
        FilledButton.icon(
          onPressed: _busy ? null : _create,
          icon: _busy
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.link_rounded),
          label: const Text('Napravi link'),
        ),
      ],
    );
  }
}

Future<void> showPrintLinkSheet(BuildContext context, PrintLink link, {bool justCreated = false}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    builder: (context) => _PrintLinkSheet(link: link, justCreated: justCreated),
  );
}

class _PrintLinkSheet extends StatefulWidget {
  const _PrintLinkSheet({required this.link, required this.justCreated});
  final PrintLink link;
  final bool justCreated;

  @override
  State<_PrintLinkSheet> createState() => _PrintLinkSheetState();
}

class _PrintLinkSheetState extends State<_PrintLinkSheet> {
  Settings? _settings;
  late final TextEditingController _email = TextEditingController(text: widget.link.mailTo);
  bool _sending = false;
  bool _sent = false;

  @override
  void initState() {
    super.initState();
    Api.instance.get('/api/admin/settings').then((d) {
      if (!mounted) return;
      setState(() {
        _settings = Settings.fromJson(d as Map<String, dynamic>);
        if (_email.text.isEmpty) _email.text = _settings!.printerEmail;
      });
    }).catchError((_) {});
  }

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _sendSmtp() async {
    setState(() => _sending = true);
    try {
      await Api.instance.post('/api/admin/print-links/${widget.link.id}/send', {'to': _email.text.trim()});
      setState(() => _sent = true);
      if (mounted) showMessage(context, 'Mejl je poslat štampariji.');
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = widget.link;
    final t = Theme.of(context).textTheme;
    final smtp = _settings?.smtpEnabled ?? false;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(24, 0, 24, 24 + MediaQuery.viewInsetsOf(context).bottom),
        child: SingleChildScrollView(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: const BoxDecoration(color: AppColors.emeraldSoft, shape: BoxShape.circle),
                    child: const Icon(Icons.print_rounded, color: AppColors.emerald),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(widget.justCreated ? 'Link za štampariju je spreman' : l.label, style: t.titleLarge),
                      Text('${photosLabel(l.photoCount)} · ${copiesLabel(l.copies)} · važi do ${formatDateMs(l.expiresAt)}', style: t.bodyMedium?.copyWith(color: AppColors.inkSoft)),
                    ]),
                  ),
                ]),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: AppColors.sand, borderRadius: BorderRadius.circular(14)),
                  child: Row(children: [
                    const Icon(Icons.bolt_rounded, color: AppColors.gold),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Štamparija preuzima originale u punoj rezoluciji direktno sa servera. Vi ništa ne skidate i ne šaljete.',
                        style: t.bodyMedium,
                      ),
                    ),
                  ]),
                ),
                const SizedBox(height: 20),
                if (smtp) ...[
                  TextField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(labelText: 'Mejl štamparije', prefixIcon: Icon(Icons.alternate_email_rounded)),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _sending || _sent ? null : _sendSmtp,
                    icon: _sending
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : Icon(_sent ? Icons.check_rounded : Icons.send_rounded),
                    label: Text(_sent ? 'Poslato' : 'Pošalji mejl štampariji'),
                  ),
                  const SizedBox(height: 10),
                ] else ...[
                  FilledButton.icon(
                    onPressed: () => navigateTo(mailtoUrl(to: _email.text.isEmpty ? l.mailTo : _email.text, subject: l.mailSubject, body: l.mailBody)),
                    icon: const Icon(Icons.mail_outline_rounded),
                    label: const Text('Pošalji mejlom'),
                  ),
                  const SizedBox(height: 10),
                ],
                OutlinedButton.icon(
                  onPressed: () async {
                    final shared = await shareLink(title: l.mailSubject, text: l.mailBody, url: l.url);
                    if (!shared) {
                      await copyText(l.mailBody);
                      if (context.mounted) showMessage(context, 'Poruka sa linkom je kopirana — nalepite je u Viber/WhatsApp.');
                    }
                  },
                  icon: const Icon(Icons.ios_share_rounded),
                  label: const Text('Viber / WhatsApp / SMS'),
                ),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        await copyText(l.url);
                        if (context.mounted) showMessage(context, 'Link je kopiran.');
                      },
                      icon: const Icon(Icons.copy_rounded),
                      label: const Text('Kopiraj link'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => openInNewTab(l.url),
                      icon: const Icon(Icons.open_in_new_rounded),
                      label: const Text('Pogledaj'),
                    ),
                  ),
                ]),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
