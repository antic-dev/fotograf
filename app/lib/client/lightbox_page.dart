import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/models.dart';
import '../ui/common.dart';
import '../ui/theme.dart';
import 'client_controller.dart';

/// Prikaz jedne fotografije preko celog ekrana. Prevlačenje levo/desno menja
/// fotografiju, a veliko dugme na dnu je izbor. Dugme "Nazad" u pregledaču
/// (ili na Android telefonu) zatvara prikaz.
class LightboxPage extends StatefulWidget {
  const LightboxPage({super.key, required this.photoId});
  final String photoId;

  @override
  State<LightboxPage> createState() => _LightboxPageState();
}

class _LightboxPageState extends State<LightboxPage> {
  PageController? _pages;
  int _index = 0;
  bool _zoomed = false;
  bool _showHint = true;
  final _focus = FocusNode();
  Timer? _hintTimer;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_pages == null) {
      final c = Scope.read<ClientController>(context);
      _index = c.indexOf(widget.photoId).clamp(0, c.photos.length - 1);
      _pages = PageController(initialPage: _index);
      _hintTimer = Timer(const Duration(seconds: 4), () {
        if (mounted) setState(() => _showHint = false);
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => _precache(c));
    }
  }

  @override
  void dispose() {
    _pages?.dispose();
    _focus.dispose();
    _hintTimer?.cancel();
    super.dispose();
  }

  void _precache(ClientController c) {
    for (final i in [_index - 1, _index + 1, _index + 2]) {
      if (i >= 0 && i < c.photos.length) {
        precacheImage(appImage(c.previewUrl(c.photos[i].id)), context);
      }
    }
  }

  void _go(int delta) {
    final c = Scope.read<ClientController>(context);
    final next = _index + delta;
    if (next < 0 || next >= c.photos.length) return;
    _pages!.animateToPage(next, duration: const Duration(milliseconds: 280), curve: Curves.easeOutCubic);
  }

  void _toggle(ClientController c, Photo photo) {
    final msg = c.toggle(photo.id);
    if (msg != null) {
      showMessage(context, msg, error: true);
    } else {
      HapticFeedback.selectionClick();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = Scope.of<ClientController>(context);
    if (c.photos.isEmpty) return const Scaffold(body: SizedBox());
    final photo = c.photos[_index.clamp(0, c.photos.length - 1)];
    final selected = c.isSelected(photo.id);
    final t = Theme.of(context).textTheme;
    final wide = MediaQuery.sizeOf(context).width > 760;

    return KeyboardListener(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: (e) {
        if (e is! KeyDownEvent) return;
        if (e.logicalKey == LogicalKeyboardKey.arrowRight) _go(1);
        if (e.logicalKey == LogicalKeyboardKey.arrowLeft) _go(-1);
        if (e.logicalKey == LogicalKeyboardKey.escape) Navigator.of(context).maybePop();
        if (e.logicalKey == LogicalKeyboardKey.space || e.logicalKey == LogicalKeyboardKey.enter) _toggle(c, photo);
      },
      child: Scaffold(
        backgroundColor: AppColors.night,
        body: Stack(children: [
          PageView.builder(
            controller: _pages,
            physics: _zoomed ? const NeverScrollableScrollPhysics() : const PageScrollPhysics(),
            itemCount: c.photos.length,
            onPageChanged: (i) {
              setState(() {
                _index = i;
                _showHint = false;
              });
              _precache(c);
            },
            itemBuilder: (context, i) => _ZoomablePhoto(
              key: ValueKey(c.photos[i].id),
              photo: c.photos[i],
              controller: c,
              onZoomChanged: (z) {
                if (z != _zoomed) setState(() => _zoomed = z);
              },
            ),
          ),

          // Gornja traka
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xAA000000), Color(0x00000000)]),
              ),
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 6, 16, 18),
                  child: Row(children: [
                    TextButton.icon(
                      style: TextButton.styleFrom(foregroundColor: Colors.white, textStyle: t.titleMedium),
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const Icon(Icons.close_rounded, size: 28),
                      label: const Text('Zatvori'),
                    ),
                    const Spacer(),
                    Text(
                      'Fotografija ${_index + 1} od ${c.photos.length}',
                      style: t.titleMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.w500),
                    ),
                  ]),
                ),
              ),
            ),
          ),

          // Strelice na većim ekranima
          if (wide) ...[
            Align(alignment: Alignment.centerLeft, child: _Arrow(icon: Icons.chevron_left_rounded, onTap: _index > 0 ? () => _go(-1) : null)),
            Align(alignment: Alignment.centerRight, child: _Arrow(icon: Icons.chevron_right_rounded, onTap: _index < c.photos.length - 1 ? () => _go(1) : null)),
          ],

          // Savet za prevlačenje
          if (!wide)
            Positioned(
              left: 0,
              right: 0,
              bottom: 150,
              child: IgnorePointer(
                child: AnimatedOpacity(
                  opacity: _showHint && c.photos.length > 1 ? 1 : 0,
                  duration: const Duration(milliseconds: 400),
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                      decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(99)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.swipe_rounded, color: Colors.white),
                        const SizedBox(width: 10),
                        Text('Prevucite prstom za sledeću', style: t.bodyLarge?.copyWith(color: Colors.white)),
                      ]),
                    ),
                  ),
                ),
              ),
            ),

          // Donja traka sa velikim dugmetom za izbor
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: [Color(0xCC000000), Color(0x00000000)]),
              ),
              child: SafeArea(
                top: false,
                child: Centered(
                  maxWidth: 560,
                  padding: const EdgeInsets.fromLTRB(16, 28, 16, 16),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    if (c.canEdit)
                      SizedBox(
                        width: double.infinity,
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 180),
                          child: selected
                              ? FilledButton.icon(
                                  key: const ValueKey('sel'),
                                  onPressed: () => _toggle(c, photo),
                                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(64), backgroundColor: AppColors.emerald),
                                  icon: const Icon(Icons.check_circle_rounded, size: 28),
                                  label: const Text('Izabrana  ·  dodirnite da poništite'),
                                )
                              : FilledButton.icon(
                                  key: const ValueKey('unsel'),
                                  onPressed: () => _toggle(c, photo),
                                  style: FilledButton.styleFrom(
                                    minimumSize: const Size.fromHeight(64),
                                    backgroundColor: Colors.white,
                                    foregroundColor: AppColors.ink,
                                  ),
                                  icon: const Icon(Icons.radio_button_unchecked_rounded, size: 28),
                                  label: const Text('Izaberi ovu fotografiju'),
                                ),
                        ),
                      )
                    else if (selected)
                      const Pill('Izabrana', icon: Icons.check_circle_rounded, color: Colors.white, background: AppColors.emerald),
                    const SizedBox(height: 10),
                    Text(
                      c.canEdit ? 'Ukupno izabrano: ${c.selectedCount}${c.project?.maxPhotos != null ? ' od ${c.project!.maxPhotos}' : ''}' : photo.name,
                      style: t.bodyLarge?.copyWith(color: Colors.white70),
                    ),
                  ]),
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

class _ZoomablePhoto extends StatefulWidget {
  const _ZoomablePhoto({super.key, required this.photo, required this.controller, required this.onZoomChanged});
  final Photo photo;
  final ClientController controller;
  final ValueChanged<bool> onZoomChanged;

  @override
  State<_ZoomablePhoto> createState() => _ZoomablePhotoState();
}

class _ZoomablePhotoState extends State<_ZoomablePhoto> {
  final _transform = TransformationController();

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return GestureDetector(
      onDoubleTap: () {
        final zoomed = _transform.value.getMaxScaleOnAxis() > 1.01;
        _transform.value = zoomed ? Matrix4.identity() : (Matrix4.identity()..scaleByDouble(2, 2, 1, 1));
        widget.onZoomChanged(!zoomed);
      },
      child: InteractiveViewer(
        transformationController: _transform,
        minScale: 1,
        maxScale: 2.5,
        onInteractionEnd: (_) => widget.onZoomChanged(_transform.value.getMaxScaleOnAxis() > 1.01),
        child: Center(
          child: AspectRatio(
            aspectRatio: widget.photo.aspect,
            child: Hero(
              tag: 'photo-${widget.photo.id}',
              child: Stack(fit: StackFit.expand, children: [
                // Sličica je već u kešu — prikazuje se odmah dok stiže veći pregled.
                Image(image: appImage(c.thumbUrl(widget.photo.id)), fit: BoxFit.contain, gaplessPlayback: true),
                Image(
                  image: appImage(c.previewUrl(widget.photo.id)),
                  fit: BoxFit.contain,
                  gaplessPlayback: true,
                  frameBuilder: (context, child, frame, sync) => AnimatedOpacity(
                    opacity: frame == null && !sync ? 0 : 1,
                    duration: const Duration(milliseconds: 250),
                    child: child,
                  ),
                  errorBuilder: (_, _, _) => const SizedBox(),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _Arrow extends StatelessWidget {
  const _Arrow({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(16),
        child: IconButton.filled(
          style: IconButton.styleFrom(
            backgroundColor: Colors.white.withValues(alpha: 0.14),
            foregroundColor: Colors.white,
            disabledBackgroundColor: Colors.transparent,
            minimumSize: const Size(60, 60),
          ),
          iconSize: 36,
          onPressed: onTap,
          icon: Icon(icon),
        ),
      );
}
