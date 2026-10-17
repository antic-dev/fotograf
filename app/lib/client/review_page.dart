import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../api/models.dart';
import '../ui/common.dart';
import '../ui/theme.dart';
import 'client_controller.dart';

/// Drugi i poslednji korak: provera izbora, ime i slanje fotografu.
class ReviewPage extends StatefulWidget {
  const ReviewPage({super.key});

  @override
  State<ReviewPage> createState() => _ReviewPageState();
}

class _ReviewPageState extends State<ReviewPage> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _phone;
  late final TextEditingController _note;
  bool _sending = false;
  bool _justSent = false;

  @override
  void initState() {
    super.initState();
    final c = Scope.read<ClientController>(context);
    _name = TextEditingController(text: c.name);
    _phone = TextEditingController(text: c.phone);
    _note = TextEditingController(text: c.note);
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _note.dispose();
    super.dispose();
  }

  void _back() => context.canPop() ? context.pop() : context.go('/g/${Scope.read<ClientController>(context).token}');

  Future<void> _submit(ClientController c) async {
    if (!_form.currentState!.validate()) {
      showMessage(context, 'Upišite vaše ime pa pritisnite ponovo.', error: true);
      return;
    }
    final ok = await confirm(
      context,
      title: 'Pošalji fotografu?',
      message: 'Šaljete ${photosLabel(c.selectedCount)} (${copiesLabel(c.copies)}). Posle slanja izbor i dalje možete da menjate dok fotograf ne pošalje slike na štampu.',
      confirmLabel: 'Da, pošalji',
      cancelLabel: 'Ne još',
    );
    if (!ok || !mounted) return;
    setState(() => _sending = true);
    try {
      await c.submit(name: _name.text.trim(), phone: _phone.text.trim(), note: _note.text.trim());
      HapticFeedback.mediumImpact();
      if (mounted) setState(() => _justSent = true);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = Scope.of<ClientController>(context);
    final t = Theme.of(context).textTheme;
    final items = c.selectedPhotos;

    if (_justSent && c.submitted) return _ThankYou(controller: c, onBack: _back);

    return Scaffold(
      appBar: AppBar(
        leadingWidth: 130,
        leading: TextButton.icon(
          onPressed: _back,
          icon: const Icon(Icons.arrow_back_rounded),
          label: const Text('Nazad'),
        ),
        title: const Text('Vaš izbor'),
      ),
      body: items.isEmpty
          ? EmptyState(
              icon: Icons.photo_library_outlined,
              title: 'Još niste izabrali fotografije',
              message: 'Vratite se nazad i dodirnite krug na fotografijama koje želite.',
              action: FilledButton(onPressed: _back, child: const Text('Nazad na fotografije')),
            )
          : Form(
              key: _form,
              child: ListView(
                padding: const EdgeInsets.only(bottom: 40),
                children: [
                  Centered(
                    maxWidth: 720,
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      const SizedBox(height: 8),
                      Text(
                        c.canEdit ? 'Proverite izbor i pošaljite ga fotografu' : 'Vaš poslat izbor',
                        style: t.headlineMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        c.canEdit
                            ? 'Za svaku fotografiju možete izabrati broj primeraka${c.project!.sizes.length > 1 ? ' i veličinu' : ''}. Ako vam je svejedno, samo pređite na dno i pošaljite.'
                            : 'Ovo je izbor koji ste poslali fotografu.',
                        style: t.bodyLarge?.copyWith(color: AppColors.inkSoft),
                      ),
                      const SizedBox(height: 20),
                      for (final p in items) ...[
                        _ItemCard(controller: c, photo: p, item: c.item(p.id)!),
                        const SizedBox(height: 12),
                      ],
                      const SizedBox(height: 12),
                      _Summary(controller: c),
                      const SizedBox(height: 24),
                      if (c.canEdit) ...[
                        Text('Vaši podaci', style: t.headlineSmall),
                        const SizedBox(height: 6),
                        Text('Da bi fotograf znao čiji je izbor.', style: t.bodyLarge?.copyWith(color: AppColors.inkSoft)),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _name,
                          textCapitalization: TextCapitalization.words,
                          autofillHints: const [AutofillHints.name],
                          style: t.bodyLarge,
                          maxLength: 80,
                          decoration: const InputDecoration(labelText: 'Ime i prezime', hintText: 'npr. Ana Petrović', counterText: ''),
                          validator: (v) => (v == null || v.trim().isEmpty) ? 'Upišite vaše ime' : null,
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _phone,
                          keyboardType: TextInputType.phone,
                          autofillHints: const [AutofillHints.telephoneNumber],
                          style: t.bodyLarge,
                          maxLength: 40,
                          decoration: const InputDecoration(labelText: 'Broj telefona (nije obavezno)', counterText: ''),
                          validator: (v) {
                            final s = v?.trim() ?? '';
                            if (s.isEmpty) return null;
                            return RegExp(r'^[0-9+()/ .-]{5,40}$').hasMatch(s) ? null : 'Broj telefona nije ispravan';
                          },
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _note,
                          minLines: 2,
                          maxLines: 5,
                          maxLength: 2000,
                          style: t.bodyLarge,
                          decoration: const InputDecoration(labelText: 'Poruka fotografu (nije obavezno)', alignLabelWithHint: true, counterText: ''),
                        ),
                        const SizedBox(height: 24),
                        FilledButton.icon(
                          onPressed: _sending ? null : () => _submit(c),
                          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(64), textStyle: t.titleMedium?.copyWith(fontSize: 19, fontWeight: FontWeight.w700)),
                          icon: _sending
                              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                              : const Icon(Icons.send_rounded),
                          label: Text(_sending ? 'Šaljem...' : 'Pošalji izbor fotografu'),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Sve je sačuvano. Ako još niste sigurni, možete se vratiti kasnije i poslati.',
                          textAlign: TextAlign.center,
                          style: t.bodyMedium?.copyWith(color: AppColors.inkSoft),
                        ),
                      ] else if (c.status == 'submitted' && c.project!.canSelect)
                        OutlinedButton.icon(
                          onPressed: () async {
                            try {
                              await c.reopen();
                            } catch (e) {
                              if (context.mounted) showError(context, e);
                            }
                          },
                          icon: const Icon(Icons.edit_rounded),
                          label: const Text('Želim da izmenim izbor'),
                        ),
                    ]),
                  ),
                ],
              ),
            ),
    );
  }
}

class _ItemCard extends StatelessWidget {
  const _ItemCard({required this.controller, required this.photo, required this.item});
  final ClientController controller;
  final Photo photo;
  final OrderItem item;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final p = c.project!;
    final t = Theme.of(context).textTheme;
    final number = c.indexOf(photo.id) + 1;
    final edit = c.canEdit;

    Widget choice(String label, List<String> options, String value, void Function(String) onPick) => Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: t.bodyMedium?.copyWith(color: AppColors.inkSoft, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final o in options)
                ChoiceChip(
                  label: Text(o),
                  selected: o == value,
                  onSelected: edit ? (_) => onPick(o) : null,
                ),
            ]),
          ]),
        );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          GestureDetector(
            onTap: () => context.push('/g/${c.token}/foto/${photo.id}'),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(width: 104, height: 104, child: NetImage(c.thumbUrl(photo.id))),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text('Fotografija br. $number', style: t.titleMedium)),
                if (edit)
                  IconButton(
                    tooltip: 'Ukloni iz izbora',
                    onPressed: () => c.toggle(photo.id),
                    icon: const Icon(Icons.delete_outline_rounded, color: AppColors.danger),
                  ),
              ]),
              Text(photo.name, style: t.bodySmall, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 10),
              Text('Broj primeraka', style: t.bodyMedium?.copyWith(color: AppColors.inkSoft, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Row(children: [
                _StepButton(icon: Icons.remove_rounded, onTap: edit && item.quantity > 1 ? () => c.updateItem(photo.id, quantity: item.quantity - 1) : null),
                SizedBox(width: 56, child: Text('${item.quantity}', textAlign: TextAlign.center, style: t.headlineSmall?.copyWith(fontFamily: bodyFont, fontWeight: FontWeight.w700))),
                _StepButton(icon: Icons.add_rounded, onTap: edit && item.quantity < 99 ? () => c.updateItem(photo.id, quantity: item.quantity + 1) : null),
              ]),
              if (p.sizes.length > 1) choice('Veličina (cm)', p.sizes, item.size, (v) => c.updateItem(photo.id, size: v)),
              if (p.finishes.length > 1) choice('Papir', p.finishes, item.finish, (v) => c.updateItem(photo.id, finish: v)),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => IconButton.outlined(
        onPressed: onTap,
        iconSize: 26,
        style: IconButton.styleFrom(minimumSize: const Size(52, 52), side: const BorderSide(color: AppColors.line, width: 1.5)),
        icon: Icon(icon),
      );
}

class _Summary extends StatelessWidget {
  const _Summary({required this.controller});
  final ClientController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final t = Theme.of(context).textTheme;
    final groups = <String, int>{};
    for (final p in c.selectedPhotos) {
      final i = c.item(p.id)!;
      final key = ['${i.size} cm', if (c.project!.finishes.length > 1) i.finish].join(' · ');
      groups[key] = (groups[key] ?? 0) + i.quantity;
    }
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: AppColors.emeraldSoft, borderRadius: BorderRadius.circular(20)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Ukupno', style: t.titleMedium?.copyWith(color: AppColors.emeraldDark)),
        const SizedBox(height: 4),
        Text('${photosLabel(c.selectedCount)} · ${copiesLabel(c.copies)}', style: t.headlineSmall?.copyWith(color: AppColors.emeraldDark)),
        const SizedBox(height: 8),
        for (final e in groups.entries)
          Text('${e.key}:  ${copiesLabel(e.value)}', style: t.bodyLarge?.copyWith(color: AppColors.emeraldDark)),
      ]),
    );
  }
}

class _ThankYou extends StatelessWidget {
  const _ThankYou({required this.controller, required this.onBack});
  final ClientController controller;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final first = controller.name.split(' ').first;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: 1),
                  duration: const Duration(milliseconds: 650),
                  curve: Curves.elasticOut,
                  builder: (context, v, child) => Transform.scale(scale: v, child: child),
                  child: Container(
                    width: 120,
                    height: 120,
                    decoration: const BoxDecoration(color: AppColors.emerald, shape: BoxShape.circle),
                    child: const Icon(Icons.check_rounded, color: Colors.white, size: 72),
                  ),
                ),
                const SizedBox(height: 28),
                Text('Hvala${first.isEmpty ? '' : ', $first'}!', style: t.displaySmall, textAlign: TextAlign.center),
                const SizedBox(height: 12),
                Text(
                  'Vaš izbor (${photosLabel(controller.selectedCount)}) je poslat fotografu.',
                  style: t.titleMedium?.copyWith(fontWeight: FontWeight.w500),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                Text(
                  'Ne morate ništa više da radite. Fotograf će vas obavestiti kada slike budu spremne. Možete slobodno da zatvorite ovu stranicu.',
                  style: t.bodyLarge?.copyWith(color: AppColors.inkSoft),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                FilledButton(onPressed: onBack, style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(60)), child: const Text('Nazad na fotografije')),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
