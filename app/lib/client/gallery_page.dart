import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../api/models.dart';
import '../ui/common.dart';
import '../ui/justified_grid.dart';
import '../ui/theme.dart';
import 'client_controller.dart';
import 'help_sheet.dart';

class GalleryPage extends StatelessWidget {
  const GalleryPage({super.key});

  @override
  Widget build(BuildContext context) {
    final c = Scope.of<ClientController>(context);
    final p = c.project!;
    final photos = c.visiblePhotos;
    final phone = isPhone(context);
    final size = MediaQuery.sizeOf(context);
    final heroHeight = math.min(size.height * (phone ? 0.56 : 0.72), 640.0);

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: p.coverPhotoId == null ? null : heroHeight,
            backgroundColor: AppColors.ivory,
            foregroundColor: AppColors.ink,
            automaticallyImplyLeading: false,
            flexibleSpace: p.coverPhotoId == null ? null : _Hero(controller: c),
            title: p.coverPhotoId == null ? Text(p.title) : _CollapsedTitle(title: p.title),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: _HelpButton(onLight: true),
              ),
            ],
          ),
          if (p.coverPhotoId == null) SliverToBoxAdapter(child: _PlainHeader(controller: c)),
          SliverToBoxAdapter(
            child: Centered(
              maxWidth: 1400,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const SizedBox(height: 16),
                _StatusBanner(controller: c),
                // Uputstvo ostaje na mestu i posle prvog izbora — da se stranica ne pomera ispod prsta.
                if (c.canEdit) ...[const _HowTo(), const SizedBox(height: 16)],
                if (p.message.isNotEmpty) ...[_Message(text: p.message, studio: c.studioName), const SizedBox(height: 16)],
                _FilterBar(controller: c),
                const SizedBox(height: 12),
              ]),
            ),
          ),
          if (photos.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(top: 40),
                child: EmptyState(
                  icon: c.onlySelected ? Icons.check_circle_outline_rounded : Icons.photo_library_outlined,
                  title: c.onlySelected ? 'Još niste ništa izabrali' : 'Fotografije uskoro stižu',
                  message: c.onlySelected
                      ? 'Vratite se na sve fotografije i dodirnite krug na onima koje želite.'
                      : 'Fotograf još nije dodao fotografije. Pogledajte ponovo malo kasnije.',
                  action: c.onlySelected
                      ? OutlinedButton(onPressed: () => c.setOnlySelected(false), child: const Text('Prikaži sve fotografije'))
                      : null,
                ),
              ),
            )
          else
            SliverPadding(
              padding: EdgeInsets.symmetric(horizontal: phone ? 6 : math.max(16, (size.width - 1400) / 2 + 16)),
              sliver: SliverJustifiedGrid(
                aspects: [for (final ph in photos) ph.aspect],
                gap: phone ? 4 : 8,
                itemBuilder: (context, i) => _Tile(photo: photos[i], controller: c),
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 140)),
        ],
      ),
      bottomNavigationBar: _SelectionBar(controller: c),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.controller});
  final ClientController controller;

  @override
  Widget build(BuildContext context) {
    final p = controller.project!;
    final t = Theme.of(context).textTheme;
    final phone = isPhone(context);
    final date = formatIsoDate(p.eventDate);
    return FlexibleSpaceBar(
      collapseMode: CollapseMode.parallax,
      background: Stack(fit: StackFit.expand, children: [
        NetImage(controller.previewUrl(p.coverPhotoId!), background: AppColors.night),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0x66000000), Color(0x00000000), Color(0x00000000), Color(0xCC000000)],
              stops: [0, 0.25, 0.5, 1],
            ),
          ),
        ),
        SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(phone ? 22 : 48, 16, phone ? 22 : 48, phone ? 28 : 48),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                controller.studioName.toUpperCase(),
                style: t.labelLarge?.copyWith(color: Colors.white, letterSpacing: 3, fontSize: 13),
              ),
              const Spacer(),
              Text(
                p.title,
                style: (phone ? t.displaySmall : t.displayLarge)?.copyWith(color: Colors.white, shadows: const [Shadow(blurRadius: 24, color: Colors.black45)]),
              ),
              if (date != null || p.clientName.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  [if (p.clientName.isNotEmpty) p.clientName, ?date].join('  ·  '),
                  style: t.titleMedium?.copyWith(color: Colors.white.withValues(alpha: 0.92), fontWeight: FontWeight.w500),
                ),
              ],
              const SizedBox(height: 22),
              Row(children: [
                const Icon(Icons.photo_library_outlined, color: Colors.white70, size: 20),
                const SizedBox(width: 8),
                Text(photosLabel(controller.photos.length), style: t.bodyLarge?.copyWith(color: Colors.white70)),
                const Spacer(),
                const Icon(Icons.keyboard_double_arrow_down_rounded, color: Colors.white70),
              ]),
            ]),
          ),
        ),
      ]),
    );
  }
}

class _CollapsedTitle extends StatelessWidget {
  const _CollapsedTitle({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    final settings = context.dependOnInheritedWidgetOfExactType<FlexibleSpaceBarSettings>();
    var visible = true;
    if (settings != null) {
      final range = settings.maxExtent - settings.minExtent;
      visible = range <= 0 || (settings.currentExtent - settings.minExtent) / range < 0.02;
    }
    return AnimatedOpacity(
      opacity: visible ? 1 : 0,
      duration: const Duration(milliseconds: 180),
      child: Text(title, overflow: TextOverflow.ellipsis),
    );
  }
}

class _PlainHeader extends StatelessWidget {
  const _PlainHeader({required this.controller});
  final ClientController controller;

  @override
  Widget build(BuildContext context) {
    final p = controller.project!;
    final t = Theme.of(context).textTheme;
    final date = formatIsoDate(p.eventDate);
    return Centered(
      maxWidth: 1400,
      child: Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(controller.studioName.toUpperCase(), style: t.labelLarge?.copyWith(color: AppColors.gold, letterSpacing: 3, fontSize: 13)),
          const SizedBox(height: 8),
          if (date != null || p.clientName.isNotEmpty)
            Text([if (p.clientName.isNotEmpty) p.clientName, ?date].join('  ·  '), style: t.titleMedium?.copyWith(color: AppColors.inkSoft)),
        ]),
      ),
    );
  }
}

class _HelpButton extends StatelessWidget {
  const _HelpButton({required this.onLight});
  final bool onLight;

  @override
  Widget build(BuildContext context) {
    return FilledButton.tonalIcon(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 44),
        backgroundColor: Colors.white.withValues(alpha: 0.92),
        foregroundColor: AppColors.ink,
        padding: const EdgeInsets.symmetric(horizontal: 14),
      ),
      onPressed: () => showHelpSheet(context),
      icon: const Icon(Icons.help_outline_rounded, size: 22),
      label: const Text('Pomoć'),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.controller});
  final ClientController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final p = c.project!;
    final t = Theme.of(context).textTheme;

    Widget banner({required IconData icon, required Color color, required Color bg, required String title, String? text, Widget? action}) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(icon, color: color, size: 30),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: t.titleMedium?.copyWith(color: color, fontWeight: FontWeight.w700)),
                  if (text != null) ...[const SizedBox(height: 4), Text(text, style: t.bodyLarge?.copyWith(color: AppColors.ink))],
                ]),
              ),
            ]),
            if (action != null) ...[const SizedBox(height: 14), action],
          ]),
        ),
      );
    }

    if (c.submitted) {
      return banner(
        icon: Icons.check_circle_rounded,
        color: AppColors.emeraldDark,
        bg: AppColors.emeraldSoft,
        title: c.status == 'submitted' ? 'Vaš izbor je poslat fotografu. Hvala!' : 'Vaše fotografije su poslate na štampu.',
        text: c.status == 'submitted'
            ? 'Izabrali ste ${photosLabel(c.selectedCount)}. Izabrane su označene zelenom kvačicom.'
            : 'Izbor više ne može da se menja. Za izmene pozovite fotografa.',
        action: c.status == 'submitted' && p.canSelect
            ? OutlinedButton.icon(
                onPressed: () async {
                  try {
                    await c.reopen();
                    if (context.mounted) showMessage(context, 'Sada možete da menjate izbor.');
                  } catch (e) {
                    if (context.mounted) showError(context, e);
                  }
                },
                icon: const Icon(Icons.edit_rounded),
                label: const Text('Želim da izmenim izbor'),
              )
            : null,
      );
    }
    if (!p.canSelect) {
      return banner(
        icon: Icons.visibility_rounded,
        color: AppColors.amber,
        bg: AppColors.amberSoft,
        title: 'Izbor fotografija je završen',
        text: 'Fotografije možete i dalje da gledate.',
      );
    }
    final parts = <String>[
      if (p.maxPhotos != null) 'Možete izabrati do ${photosLabel(p.maxPhotos!)}.',
      if (p.deadline != null) 'Izbor je moguć do ${formatDateMs(p.deadline!)}',
    ];
    if (parts.isEmpty) return const SizedBox.shrink();
    return banner(
      icon: Icons.info_outline_rounded,
      color: AppColors.inkSoft,
      bg: AppColors.sand,
      title: parts.join(' '),
    );
  }
}

class _HowTo extends StatelessWidget {
  const _HowTo();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    Widget step(int n, String text, Widget icon) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(children: [
            Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: const BoxDecoration(color: AppColors.emerald, shape: BoxShape.circle),
              child: Text('$n', style: t.titleMedium?.copyWith(color: Colors.white)),
            ),
            const SizedBox(width: 14),
            Expanded(child: Text(text, style: t.bodyLarge?.copyWith(fontWeight: FontWeight.w500))),
            const SizedBox(width: 8),
            icon,
          ]),
        );
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Kako da izaberete fotografije?', style: t.headlineSmall),
          const SizedBox(height: 10),
          step(1, 'Dodirnite krug na fotografiji koju želite da odštampate.', const _MiniCircle(selected: false)),
          step(2, 'Krug postaje zelen sa kvačicom — fotografija je izabrana.', const _MiniCircle(selected: true)),
          step(3, 'Kada završite, pritisnite zeleno dugme „Dalje” na dnu ekrana.', const Icon(Icons.arrow_forward_rounded, color: AppColors.emerald)),
          const SizedBox(height: 6),
          Text('Dodirom na samu fotografiju vidite je u punoj veličini.', style: t.bodyMedium?.copyWith(color: AppColors.inkSoft)),
        ]),
      ),
    );
  }
}

class _MiniCircle extends StatelessWidget {
  const _MiniCircle({required this.selected});
  final bool selected;

  @override
  Widget build(BuildContext context) => Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: selected ? AppColors.emerald : AppColors.inkFaint.withValues(alpha: 0.35),
          border: Border.all(color: selected ? AppColors.emerald : AppColors.inkSoft, width: 2.5),
        ),
        child: selected ? const Icon(Icons.check_rounded, color: Colors.white, size: 20) : null,
      );
}

class _Message extends StatelessWidget {
  const _Message({required this.text, required this.studio});
  final String text;
  final String studio;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      decoration: BoxDecoration(
        color: AppColors.paper,
        borderRadius: BorderRadius.circular(20),
        border: const Border(left: BorderSide(color: AppColors.gold, width: 4)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Poruka od fotografa', style: t.titleSmall?.copyWith(color: AppColors.gold)),
        const SizedBox(height: 6),
        Text(text, style: t.bodyLarge?.copyWith(fontFamily: displayFont, fontSize: 18, fontStyle: FontStyle.normal)),
        if (studio.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text('— $studio', style: t.bodyMedium?.copyWith(color: AppColors.inkSoft)),
        ],
      ]),
    );
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({required this.controller});
  final ClientController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Row(children: [
      Expanded(
        child: SegmentedButton<bool>(
          showSelectedIcon: false,
          style: SegmentedButton.styleFrom(
            minimumSize: const Size(0, 50),
            selectedBackgroundColor: AppColors.ink,
            selectedForegroundColor: Colors.white,
            side: const BorderSide(color: AppColors.line, width: 1.5),
            textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
          ),
          segments: [
            ButtonSegment(value: false, label: Text('Sve (${c.photos.length})')),
            ButtonSegment(value: true, label: Text('Izabrane (${c.selectedCount})')),
          ],
          selected: {c.onlySelected},
          onSelectionChanged: (s) => c.setOnlySelected(s.first),
        ),
      ),
    ]);
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.photo, required this.controller});
  final Photo photo;
  final ClientController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final selected = c.isSelected(photo.id);
    final number = c.indexOf(photo.id) + 1;
    return Semantics(
      button: true,
      selected: selected,
      label: 'Fotografija $number${selected ? ', izabrana' : ''}',
      child: GestureDetector(
        onTap: () => context.push('/g/${c.token}/foto/${photo.id}'),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: EdgeInsets.all(selected ? 5 : 0),
          decoration: BoxDecoration(
            color: selected ? AppColors.emerald : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(selected ? 4 : 6),
            child: Stack(fit: StackFit.expand, children: [
              Hero(tag: 'photo-${photo.id}', child: NetImage(c.thumbUrl(photo.id))),
              if (selected && c.item(photo.id)!.quantity > 1)
                Positioned(
                  left: 6,
                  bottom: 6,
                  child: Pill('${c.item(photo.id)!.quantity} kom', color: Colors.white, background: AppColors.emerald),
                ),
              if (c.canEdit || selected)
                Positioned(
                  top: 0,
                  right: 0,
                  child: _SelectCircle(
                    selected: selected,
                    enabled: c.canEdit,
                    onTap: () {
                      final msg = c.toggle(photo.id);
                      if (msg != null) showMessage(context, msg, error: true);
                    },
                  ),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _SelectCircle extends StatelessWidget {
  const _SelectCircle({required this.selected, required this.enabled, required this.onTap});
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: enabled ? onTap : null,
      child: SizedBox(
        width: 52,
        height: 52,
        child: Center(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: selected ? AppColors.emerald : Colors.black.withValues(alpha: 0.28),
              border: Border.all(color: Colors.white, width: 2.5),
              boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 6)],
            ),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 160),
              transitionBuilder: (child, a) => ScaleTransition(scale: a, child: child),
              child: selected
                  ? const Icon(Icons.check_rounded, key: ValueKey(1), color: Colors.white, size: 22)
                  : const SizedBox(key: ValueKey(0)),
            ),
          ),
        ),
      ),
    );
  }
}

class _SelectionBar extends StatelessWidget {
  const _SelectionBar({required this.controller});
  final ClientController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final t = Theme.of(context).textTheme;
    final max = c.project!.maxPhotos;
    final has = c.selectedCount > 0;
    if (!c.canEdit && !has) return const SizedBox.shrink();
    return Material(
      color: AppColors.paper,
      elevation: 12,
      shadowColor: Colors.black26,
      child: SafeArea(
        top: false,
        child: Centered(
          maxWidth: 900,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(children: [
            Expanded(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(c.submitted ? 'Poslato' : 'Izabrano', style: t.bodyMedium?.copyWith(color: AppColors.inkSoft)),
                Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    transitionBuilder: (child, a) => ScaleTransition(scale: a, child: child),
                    child: Text('${c.selectedCount}', key: ValueKey(c.selectedCount), style: t.headlineMedium?.copyWith(fontFamily: bodyFont, fontWeight: FontWeight.w800)),
                  ),
                  if (max != null) Text('  od $max', style: t.titleMedium?.copyWith(color: AppColors.inkSoft)),
                  const SizedBox(width: 8),
                  if (c.saving)
                    const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                  else if (has && c.canEdit)
                    const Icon(Icons.cloud_done_outlined, size: 18, color: AppColors.emerald),
                ]),
              ]),
            ),
            const SizedBox(width: 12),
            if (c.canEdit)
              FilledButton(
                onPressed: has
                    ? () => context.push('/g/${c.token}/izbor')
                    : () => showMessage(context, 'Prvo izaberite fotografije — dodirnite krug na slici.'),
                style: FilledButton.styleFrom(
                  backgroundColor: has ? AppColors.emerald : AppColors.inkFaint,
                  minimumSize: const Size(150, 60),
                  textStyle: t.titleMedium?.copyWith(fontWeight: FontWeight.w700, fontSize: 19),
                ),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [Text('Dalje'), SizedBox(width: 8), Icon(Icons.arrow_forward_rounded)]),
              )
            else
              OutlinedButton(onPressed: () => context.push('/g/${c.token}/izbor'), child: const Text('Pogledaj izbor')),
          ]),
        ),
      ),
    );
  }
}
