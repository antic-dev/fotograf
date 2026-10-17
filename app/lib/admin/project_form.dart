import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/api.dart';
import '../api/models.dart';
import '../ui/common.dart';
import '../ui/theme.dart';

/// Pravljenje ili izmena projekta. Na telefonu preko celog ekrana.
Future<Project?> showProjectForm(BuildContext context, {Project? existing}) {
  final phone = isPhone(context);
  if (phone) {
    // Preko celog ekrana (i preko donjeg menija), da se forma ne izgubi pri navigaciji.
    return Navigator.of(context, rootNavigator: true).push<Project>(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => _ProjectForm(existing: existing, fullscreen: true),
    ));
  }
  return showDialog<Project>(
    context: context,
    builder: (_) => Dialog(
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620, maxHeight: 860),
        child: _ProjectForm(existing: existing, fullscreen: false),
      ),
    ),
  );
}

class _ProjectForm extends StatefulWidget {
  const _ProjectForm({this.existing, required this.fullscreen});
  final Project? existing;
  final bool fullscreen;

  @override
  State<_ProjectForm> createState() => _ProjectFormState();
}

class _ProjectFormState extends State<_ProjectForm> {
  final _form = GlobalKey<FormState>();
  late final _title = TextEditingController(text: widget.existing?.title);
  late final _client = TextEditingController(text: widget.existing?.clientName);
  late final _message = TextEditingController(text: widget.existing?.message);
  late final _max = TextEditingController(text: widget.existing?.maxPhotos?.toString());
  DateTime? _date;
  DateTime? _deadline;
  String _status = 'open';
  bool _busy = false;

  bool get _editing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final p = widget.existing;
    if (p != null) {
      _date = p.eventDate == null ? null : DateTime.tryParse(p.eventDate!);
      _deadline = p.deadline == null ? null : DateTime.fromMillisecondsSinceEpoch(p.deadline!);
      _status = p.status;
    } else {
      _date = DateTime.now();
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _client.dispose();
    _message.dispose();
    _max.dispose();
    super.dispose();
  }

  String _iso(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<DateTime?> _pick(DateTime? initial) => showDatePicker(
        context: context,
        initialDate: initial ?? DateTime.now(),
        firstDate: DateTime(2000),
        lastDate: DateTime(2100),
      );

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    final max = int.tryParse(_max.text.trim());
    final body = {
      'title': _title.text.trim(),
      'clientName': _client.text.trim(),
      'message': _message.text.trim(),
      'eventDate': _date == null ? null : _iso(_date!),
      'maxPhotos': max,
      'deadline': _deadline == null ? null : DateTime(_deadline!.year, _deadline!.month, _deadline!.day, 23, 59, 59).millisecondsSinceEpoch,
      if (_editing) 'status': _status,
    };
    try {
      final data = _editing
          ? await Api.instance.patch('/api/admin/projects/${widget.existing!.id}', body)
          : await Api.instance.post('/api/admin/projects', body);
      if (mounted) Navigator.pop(context, Project.fromJson(data as Map<String, dynamic>));
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
    final save = FilledButton(
      onPressed: _busy ? null : _save,
      child: _busy
          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
          : Text(_editing ? 'Sačuvaj' : 'Napravi projekat'),
    );

    final fields = Form(
      key: _form,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
        children: [
          TextFormField(
            controller: _title,
            autofocus: !_editing,
            textCapitalization: TextCapitalization.sentences,
            maxLength: 120,
            decoration: const InputDecoration(labelText: 'Naziv projekta *', hintText: 'npr. Venčanje Ana i Marko', counterText: ''),
            validator: (v) => (v == null || v.trim().isEmpty) ? 'Unesite naziv' : null,
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _client,
            textCapitalization: TextCapitalization.words,
            maxLength: 120,
            decoration: const InputDecoration(labelText: 'Klijent (nije obavezno)', hintText: 'npr. Porodica Petrović', counterText: ''),
          ),
          const SizedBox(height: 14),
          _DateField(
            label: 'Datum događaja',
            value: _date,
            onTap: () async {
              final d = await _pick(_date);
              if (d != null) setState(() => _date = d);
            },
            onClear: () => setState(() => _date = null),
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _message,
            minLines: 2,
            maxLines: 5,
            maxLength: 2000,
            decoration: const InputDecoration(
              labelText: 'Poruka za klijente (nije obavezno)',
              hintText: 'npr. Hvala vam na divnom danu! Izaberite do 30 fotografija za album.',
              alignLabelWithHint: true,
              counterText: '',
            ),
          ),
          const SizedBox(height: 24),
          Text('Pravila izbora', style: t.titleLarge),
          const SizedBox(height: 12),
          TextFormField(
            controller: _max,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(labelText: 'Najviše fotografija po osobi (prazno = bez ograničenja)'),
            validator: (v) {
              if (v == null || v.trim().isEmpty) return null;
              final n = int.tryParse(v);
              return n == null || n < 1 ? 'Unesite broj veći od 0' : null;
            },
          ),
          const SizedBox(height: 14),
          _DateField(
            label: 'Rok za izbor (nije obavezno)',
            value: _deadline,
            onTap: () async {
              final d = await _pick(_deadline ?? DateTime.now().add(const Duration(days: 14)));
              if (d != null) setState(() => _deadline = d);
            },
            onClear: () => setState(() => _deadline = null),
          ),
          const SizedBox(height: 20),
          if (_editing) ...[
            const SizedBox(height: 24),
            Text('Status', style: t.titleLarge),
            const SizedBox(height: 10),
            SegmentedButton<String>(
              showSelectedIcon: false,
              style: SegmentedButton.styleFrom(minimumSize: const Size(0, 52)),
              segments: const [
                ButtonSegment(value: 'open', label: Text('Otvoren'), icon: Icon(Icons.lock_open_rounded)),
                ButtonSegment(value: 'closed', label: Text('Samo pregled'), icon: Icon(Icons.visibility_rounded)),
                ButtonSegment(value: 'hidden', label: Text('Skriven'), icon: Icon(Icons.visibility_off_rounded)),
              ],
              selected: {_status},
              onSelectionChanged: (s) => setState(() => _status = s.first),
            ),
            const SizedBox(height: 8),
            Text(
              switch (_status) {
                'open' => 'Klijenti vide fotografije i mogu da biraju.',
                'closed' => 'Klijenti vide fotografije, ali ne mogu više da biraju.',
                _ => 'Link ne radi — niko ne vidi projekat.',
              },
              style: t.bodySmall,
            ),
          ],
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: AppColors.sand, borderRadius: BorderRadius.circular(14)),
            child: Row(children: [
              const Icon(Icons.water_drop_outlined, color: AppColors.gold),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Klijenti biraju samo fotografije i broj primeraka — format štampe je isti za sve (menja se u Podešavanjima). '
                  'Uvek vide fotografije sa vodenim žigom i u smanjenoj rezoluciji; originali ostaju samo na vašem Drive-u.',
                  style: t.bodyMedium,
                ),
              ),
            ]),
          ),
        ],
      ),
    );

    if (widget.fullscreen) {
      return Scaffold(
        appBar: AppBar(
          title: Text(_editing ? 'Izmena projekta' : 'Novi projekat'),
          actions: [Padding(padding: const EdgeInsets.only(right: 12), child: SizedBox(height: 44, child: save))],
        ),
        body: fields,
      );
    }
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 12, 8),
        child: Row(children: [
          Expanded(child: Text(_editing ? 'Izmena projekta' : 'Novi projekat', style: t.headlineSmall)),
          IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded)),
        ]),
      ),
      Expanded(child: fields),
      const Divider(),
      Padding(
        padding: const EdgeInsets.all(16),
        child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Odustani')),
          const SizedBox(width: 8),
          save,
        ]),
      ),
    ]);
  }
}

class _DateField extends StatelessWidget {
  const _DateField({required this.label, required this.value, required this.onTap, required this.onClear});
  final String label;
  final DateTime? value;
  final VoidCallback onTap;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: const Icon(Icons.event_rounded),
          suffixIcon: value == null ? null : IconButton(onPressed: onClear, icon: const Icon(Icons.close_rounded)),
        ),
        child: Text(value == null ? 'Nije izabrano' : formatDate(value!), style: Theme.of(context).textTheme.bodyLarge),
      ),
    );
  }
}
