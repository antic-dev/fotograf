import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../api/api.dart';
import '../api/models.dart';
import '../ui/common.dart';
import '../ui/justified_grid.dart';
import '../ui/theme.dart';
import '../web/browser.dart';
import 'project_form.dart';
import 'upload_picker.dart';
import 'uploads.dart';
import 'widgets.dart';

class ProjectPage extends StatefulWidget {
  const ProjectPage({super.key, required this.projectId});
  final String projectId;

  @override
  State<ProjectPage> createState() => _ProjectPageState();
}

class _ProjectPageState extends State<ProjectPage> {
  Project? _p;
  Object? _error;
  final Set<String> _selected = {};
  bool _selecting = false;
  bool _dragging = false;
  late final FileDropListener _drop;
  StreamSubscription<String>? _sub;
  Timer? _reloadTimer;

  @override
  void initState() {
    super.initState();
    _load();
    _drop = FileDropListener(
      onDragChange: (d) => setState(() => _dragging = d),
      onFiles: (files) {
        final p = _p;
        if (p == null) return;
        final warning = UploadManager.instance.add(p.id, p.title, files);
        showMessage(context, warning ?? 'Otpremam ${photosLabel(files.length)}.', error: warning != null);
      },
    )..attach();
    _sub = UploadManager.instance.uploaded.where((id) => id == widget.projectId).listen((_) {
      _reloadTimer ??= Timer(const Duration(milliseconds: 1200), () {
        _reloadTimer = null;
        _load();
      });
    });
  }

  @override
  void dispose() {
    _drop.detach();
    _sub?.cancel();
    _reloadTimer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final d = await Api.instance.get('/api/admin/projects/${widget.projectId}');
      if (mounted) setState(() => _p = Project.fromJson(d as Map<String, dynamic>));
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _edit() async {
    final p = await showProjectForm(context, existing: _p);
    if (p != null) {
      await _load();
      if (mounted) showMessage(context, 'Projekat je sačuvan.');
    }
  }

  Future<void> _rotateLink() async {
    final ok = await confirm(
      context,
      title: 'Napraviti novi link?',
      message: 'Stari link će odmah prestati da radi. Koristite ovo ako je link dospeo do pogrešnih ljudi.',
      confirmLabel: 'Napravi novi link',
      danger: true,
    );
    if (!ok) return;
    try {
      await Api.instance.post('/api/admin/projects/${widget.projectId}/rotate-link');
      await _load();
      if (mounted) showMessage(context, 'Novi link je napravljen. Pošaljite ga klijentu.');
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _sort(String by) async {
    try {
      await Api.instance.post('/api/admin/projects/${widget.projectId}/photos/sort', {'by': by});
      await _load();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _deleteProject() async {
    final p = _p!;
    final ok = await confirm(
      context,
      title: 'Obrisati projekat?',
      message: 'Projekat „${p.title}” i sve porudžbine biće obrisani, a folder sa ${photosLabel(p.photos.length)} premešten u Kantu na Google Drive-u (možete ga vratiti narednih 30 dana).',
      confirmLabel: 'Obriši projekat',
      danger: true,
    );
    if (!ok) return;
    try {
      await Api.instance.delete('/api/admin/projects/${p.id}');
      if (mounted) {
        showMessage(context, 'Projekat je obrisan.');
        context.go('/admin/projekti');
      }
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _deletePhotos(List<String> ids) async {
    final ok = await confirm(
      context,
      title: 'Obrisati ${photosLabel(ids.length)}?',
      message: 'Fotografije će biti uklonjene iz projekta i premeštene u Kantu na Google Drive-u.',
      confirmLabel: 'Obriši',
      danger: true,
    );
    if (!ok) return;
    try {
      await Api.instance.post('/api/admin/projects/${widget.projectId}/photos/delete', {'ids': ids});
      setState(() {
        _selected.clear();
        _selecting = false;
      });
      await _load();
      if (mounted) showMessage(context, 'Obrisano: ${photosLabel(ids.length)}.');
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _setCover(String photoId) async {
    try {
      await Api.instance.post('/api/admin/projects/${widget.projectId}/cover', {'photoId': photoId});
      await _load();
      if (mounted) showMessage(context, 'Naslovna fotografija je promenjena.');
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  void _openPhoto(Photo ph) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (ctx) => Dialog.fullscreen(
        backgroundColor: AppColors.night,
        child: Stack(children: [
          Positioned.fill(
            child: InteractiveViewer(
              maxScale: 4,
              child: Center(child: Image(image: appImage(adminPreview(ph.id)), fit: BoxFit.contain)),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(children: [
                IconButton(color: Colors.white, onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close_rounded)),
                Expanded(child: Text(ph.name, style: const TextStyle(color: Colors.white, fontSize: 16), overflow: TextOverflow.ellipsis)),
              ]),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Wrap(alignment: WrapAlignment.center, spacing: 10, runSpacing: 10, children: [
                  FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: AppColors.ink),
                    onPressed: () => download(adminOriginal(ph.id)),
                    icon: const Icon(Icons.download_rounded),
                    label: const Text('Original'),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _setCover(ph.id);
                    },
                    icon: const Icon(Icons.star_rounded),
                    label: const Text('Naslovna'),
                  ),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
                    onPressed: () {
                      Navigator.pop(ctx);
                      _deletePhotos([ph.id]);
                    },
                    icon: const Icon(Icons.delete_outline_rounded),
                    label: const Text('Obriši'),
                  ),
                ]),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = _p;
    if (p == null) {
      return Scaffold(
        appBar: AppBar(),
        body: _error != null ? ErrorView(error: _error!, onRetry: _load) : const LoadingView(),
      );
    }
    final t = Theme.of(context).textTheme;
    final phone = isPhone(context);
    final date = formatIsoDate(p.eventDate);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(onPressed: () => context.go('/admin/projekti'), icon: const Icon(Icons.arrow_back_rounded)),
        title: _selecting ? Text('Izabrano: ${_selected.length}') : null,
        actions: _selecting
            ? [
                if (_selected.length == 1)
                  TextButton.icon(onPressed: () => _setCover(_selected.first), icon: const Icon(Icons.star_outline_rounded), label: const Text('Naslovna')),
                TextButton.icon(
                  style: TextButton.styleFrom(foregroundColor: AppColors.danger),
                  onPressed: _selected.isEmpty ? null : () => _deletePhotos(_selected.toList()),
                  icon: const Icon(Icons.delete_outline_rounded),
                  label: const Text('Obriši'),
                ),
                TextButton(
                  onPressed: () => setState(() {
                    _selecting = false;
                    _selected.clear();
                  }),
                  child: const Text('Gotovo'),
                ),
                const SizedBox(width: 8),
              ]
            : [
                TextButton.icon(onPressed: _edit, icon: const Icon(Icons.edit_outlined), label: const Text('Uredi')),
                PopupMenuButton<String>(
                  tooltip: 'Još opcija',
                  onSelected: (v) => switch (v) {
                    'drive' => openInNewTab(p.driveFolderUrl!),
                    'rotate' => _rotateLink(),
                    'sort-time' => _sort('taken'),
                    'sort-name' => _sort('name'),
                    'select' => setState(() => _selecting = true),
                    'delete' => _deleteProject(),
                    _ => null,
                  },
                  itemBuilder: (_) => [
                    if (p.driveFolderUrl != null)
                      const PopupMenuItem(value: 'drive', child: ListTile(leading: Icon(Icons.add_to_drive_rounded), title: Text('Otvori folder na Drive-u'))),
                    const PopupMenuItem(value: 'select', child: ListTile(leading: Icon(Icons.checklist_rounded), title: Text('Izaberi više fotografija'))),
                    const PopupMenuItem(value: 'sort-time', child: ListTile(leading: Icon(Icons.schedule_rounded), title: Text('Poređaj po vremenu snimanja'))),
                    const PopupMenuItem(value: 'sort-name', child: ListTile(leading: Icon(Icons.sort_by_alpha_rounded), title: Text('Poređaj po imenu fajla'))),
                    const PopupMenuItem(value: 'rotate', child: ListTile(leading: Icon(Icons.link_off_rounded), title: Text('Napravi novi link'))),
                    const PopupMenuDivider(),
                    const PopupMenuItem(
                      value: 'delete',
                      child: ListTile(leading: Icon(Icons.delete_outline_rounded, color: AppColors.danger), title: Text('Obriši projekat', style: TextStyle(color: AppColors.danger))),
                    ),
                  ],
                ),
                const SizedBox(width: 8),
              ],
      ),
      body: Stack(children: [
        RefreshIndicator(
          onRefresh: _load,
          child: CustomScrollView(slivers: [
            SliverToBoxAdapter(
              child: Centered(
                maxWidth: 1400,
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  const SizedBox(height: 4),
                  Wrap(spacing: 10, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    projectStatusPill(p.status),
                    if (p.deadline != null) Pill('Rok: ${formatDateMs(p.deadline!)}', icon: Icons.event_rounded),
                    if (p.maxPhotos != null) Pill('Do ${photosLabel(p.maxPhotos!)}', icon: Icons.filter_none_rounded),
                  ]),
                  const SizedBox(height: 10),
                  Text(p.title, style: phone ? t.headlineLarge : t.displaySmall),
                  if (date != null || p.clientName.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text([?date, if (p.clientName.isNotEmpty) p.clientName].join(' · '), style: t.titleMedium?.copyWith(color: AppColors.inkSoft, fontWeight: FontWeight.w500)),
                    ),
                  const SizedBox(height: 20),
                  _ShareCard(project: p),
                  const SizedBox(height: 14),
                  if (p.newOrders > 0 || p.totalOrders > 0 || p.activeDrafts > 0) ...[
                    _OrdersStrip(project: p),
                    const SizedBox(height: 14),
                  ],
                  _UploadZone(project: p, dragging: _dragging),
                  const SizedBox(height: 24),
                  Row(children: [
                    Expanded(child: Text('Fotografije (${p.photos.length})', style: t.headlineSmall)),
                    if (p.photos.isNotEmpty && !_selecting)
                      TextButton.icon(onPressed: () => setState(() => _selecting = true), icon: const Icon(Icons.checklist_rounded), label: const Text('Izaberi')),
                  ]),
                  const SizedBox(height: 12),
                ]),
              ),
            ),
            if (p.photos.isEmpty)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: EmptyState(icon: Icons.add_photo_alternate_outlined, title: 'Još nema fotografija', message: 'Dodajte fotografije — klijenti ih vide čim se otpreme.'),
                ),
              )
            else
              SliverPadding(
                padding: EdgeInsets.symmetric(horizontal: phone ? 8 : 16),
                sliver: SliverJustifiedGrid(
                  aspects: [for (final ph in p.photos) ph.aspect],
                  gap: 6,
                  targetHeight: phone ? 130 : 190,
                  itemBuilder: (context, i) {
                    final ph = p.photos[i];
                    final sel = _selected.contains(ph.id);
                    return Semantics(
                      button: true,
                      selected: sel,
                      label: ph.name,
                      child: GestureDetector(
                      onTap: () {
                        if (_selecting) {
                          setState(() => sel ? _selected.remove(ph.id) : _selected.add(ph.id));
                        } else {
                          _openPhoto(ph);
                        }
                      },
                      onLongPress: () => setState(() {
                        _selecting = true;
                        _selected.add(ph.id);
                      }),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        padding: EdgeInsets.all(sel ? 5 : 0),
                        decoration: BoxDecoration(color: sel ? AppColors.emerald : Colors.transparent, borderRadius: BorderRadius.circular(8)),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: Stack(fit: StackFit.expand, children: [
                            NetImage(adminThumb(ph.id)),
                            if (ph.id == p.coverPhotoId)
                              const Positioned(left: 6, top: 6, child: Pill('Naslovna', icon: Icons.star_rounded, color: Colors.white, background: Color(0xCC1D1B18))),
                            if (ph.selectedBy > 0)
                              Positioned(
                                right: 6,
                                bottom: 6,
                                child: Pill('${ph.selectedBy}', icon: Icons.favorite_rounded, color: Colors.white, background: AppColors.emerald),
                              ),
                            if (_selecting)
                              Positioned(
                                right: 6,
                                top: 6,
                                child: Icon(sel ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded, color: Colors.white, size: 28, shadows: const [Shadow(blurRadius: 8)]),
                              ),
                          ]),
                        ),
                      ),
                    ));
                  },
                ),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 140)),
          ]),
        ),
        if (_dragging)
          Positioned.fill(
            child: IgnorePointer(
              child: Container(
                margin: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.emerald.withValues(alpha: 0.12),
                  border: Border.all(color: AppColors.emerald, width: 3),
                  borderRadius: BorderRadius.circular(28),
                ),
                child: Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.cloud_upload_rounded, size: 72, color: AppColors.emerald),
                    const SizedBox(height: 12),
                    Text('Pustite fotografije ovde', style: t.headlineMedium?.copyWith(color: AppColors.emeraldDark)),
                  ]),
                ),
              ),
            ),
          ),
      ]),
    );
  }
}

class _ShareCard extends StatelessWidget {
  const _ShareCard({required this.project});
  final Project project;

  String get _message =>
      'Zdravo! Vaše fotografije su spremne 📸\nOtvorite link, pogledajte ih i izaberite one koje želite da odštampate:\n${project.shareUrl}';

  void _showQr(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('QR kod za klijente'),
        content: SizedBox(
          width: 300,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              padding: const EdgeInsets.all(12),
              color: Colors.white,
              child: QrImageView(data: project.shareUrl, size: 260, eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.circle, color: AppColors.ink), dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.circle, color: AppColors.ink)),
            ),
            const SizedBox(height: 12),
            Text('Klijent skenira kamerom telefona i odmah vidi fotografije.', textAlign: TextAlign.center, style: Theme.of(ctx).textTheme.bodyMedium),
          ]),
        ),
        actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Zatvori'))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final hidden = project.status == 'hidden';
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: AppColors.ink, borderRadius: BorderRadius.circular(22)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.lock_rounded, color: AppColors.gold, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text('Tajni link za klijente', style: t.titleMedium?.copyWith(color: Colors.white))),
        ]),
        const SizedBox(height: 6),
        Text(
          hidden
              ? 'Projekat je skriven — link trenutno ne radi.'
              : 'Ko ima ovaj link vidi SAMO ovaj projekat. Bez prijave, bez lozinke.',
          style: t.bodyMedium?.copyWith(color: Colors.white70),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12)),
          child: SelectableText(project.shareUrl, maxLines: 1, style: t.bodyMedium?.copyWith(color: Colors.white, fontFamily: 'monospace')),
        ),
        const SizedBox(height: 14),
        Wrap(spacing: 10, runSpacing: 10, children: [
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: AppColors.ink, minimumSize: const Size(0, 50)),
            onPressed: () async {
              final ok = await shareLink(title: project.title, text: _message, url: project.shareUrl);
              if (!ok) {
                await copyText(_message);
                if (context.mounted) showMessage(context, 'Poruka sa linkom je kopirana — nalepite je u Viber ili WhatsApp.');
              }
            },
            icon: const Icon(Icons.send_rounded),
            label: const Text('Pošalji klijentu'),
          ),
          _DarkButton(
            icon: Icons.copy_rounded,
            label: 'Kopiraj',
            onTap: () async {
              await copyText(project.shareUrl);
              if (context.mounted) showMessage(context, 'Link je kopiran.');
            },
          ),
          _DarkButton(icon: Icons.qr_code_2_rounded, label: 'QR kod', onTap: () => _showQr(context)),
          _DarkButton(icon: Icons.visibility_outlined, label: 'Kako klijent vidi', onTap: () => openInNewTab(project.shareUrl)),
        ]),
      ]),
    );
  }
}

class _DarkButton extends StatelessWidget {
  const _DarkButton({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.white,
          side: const BorderSide(color: Colors.white24, width: 1.5),
          minimumSize: const Size(0, 50),
        ),
        onPressed: onTap,
        icon: Icon(icon),
        label: Text(label),
      );
}

class _OrdersStrip extends StatelessWidget {
  const _OrdersStrip({required this.project});
  final Project project;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final p = project;
    return Material(
      color: p.newOrders > 0 ? AppColors.emeraldSoft : AppColors.paper,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => context.go('/admin/porudzbine?projekat=${p.id}'),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(18), border: Border.all(color: p.newOrders > 0 ? AppColors.emerald : AppColors.line)),
          child: Row(children: [
            Icon(Icons.inbox_rounded, color: p.newOrders > 0 ? AppColors.emerald : AppColors.inkSoft),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                [
                  if (p.newOrders > 0) '${p.newOrders} ${p.newOrders == 1 ? 'nova porudžbina' : 'nove porudžbine'}',
                  if (p.totalOrders > 0) 'ukupno ${p.totalOrders}',
                  if (p.activeDrafts > 0) '${p.activeDrafts} trenutno bira',
                ].join(' · '),
                style: t.titleSmall,
              ),
            ),
            const Text('Pogledaj'),
            const Icon(Icons.chevron_right_rounded),
          ]),
        ),
      ),
    );
  }
}

class _UploadZone extends StatelessWidget {
  const _UploadZone({required this.project, required this.dragging});
  final Project project;
  final bool dragging;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final phone = isPhone(context);
    return Material(
      color: dragging ? AppColors.emeraldSoft : AppColors.paper,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: () => pickAndUpload(context, project.id, project.title),
        child: CustomPaint(
          painter: _DashedBorder(color: dragging ? AppColors.emerald : AppColors.line),
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: phone ? 22 : 34, horizontal: 20),
            child: Column(children: [
              const Icon(Icons.add_photo_alternate_rounded, size: 40, color: AppColors.emerald),
              const SizedBox(height: 10),
              Text(phone ? 'Dodaj fotografije' : 'Prevucite fotografije ovde ili kliknite da izaberete', style: t.titleMedium, textAlign: TextAlign.center),
              const SizedBox(height: 4),
              Text(
                'Originali idu na Google Drive u punoj rezoluciji (JPG, PNG, WebP, TIFF).',
                style: t.bodySmall,
                textAlign: TextAlign.center,
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _DashedBorder extends CustomPainter {
  _DashedBorder({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final path = Path()..addRRect(RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(22)));
    for (final m in path.computeMetrics()) {
      var d = 0.0;
      while (d < m.length) {
        canvas.drawPath(m.extractPath(d, d + 10), paint);
        d += 18;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorder old) => old.color != color;
}
