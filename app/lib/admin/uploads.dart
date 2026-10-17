import 'dart:async';

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

import '../ui/common.dart';
import '../ui/theme.dart';
import '../web/browser.dart';
import 'refresh.dart';

enum UploadStatus { queued, uploading, done, failed }

class UploadTask {
  UploadTask(this.file, this.projectId, this.projectTitle);

  final web.File file;
  final String projectId;
  final String projectTitle;
  double progress = 0;
  UploadStatus status = UploadStatus.queued;
  String? error;
  UploadHandle? handle;

  String get name => file.name;
  int get size => file.size;
}

/// Red za otpremanje originala. Radi u pozadini dok se krećete kroz
/// aplikaciju; neuspele fotografije se mogu ponovo poslati jednim dodirom.
/// Originali se šalju netaknuti — bez ikakvog smanjivanja ili kompresije.
class UploadManager extends ChangeNotifier {
  UploadManager._();

  static final UploadManager instance = UploadManager._();

  /// Dve paralelne fotografije — najbolje za sporiji internet.
  static const concurrency = 2;

  final List<UploadTask> tasks = [];
  final _uploaded = StreamController<String>.broadcast();
  final _guard = LeaveGuard();
  Timer? _throttle;
  Timer? _autoClear;

  /// Emituje ID projekta svaki put kada se fotografija uspešno otpremi.
  Stream<String> get uploaded => _uploaded.stream;

  int get total => tasks.length;
  int get done => tasks.where((t) => t.status == UploadStatus.done).length;
  int get failed => tasks.where((t) => t.status == UploadStatus.failed).length;
  int get active => tasks.where((t) => t.status == UploadStatus.uploading).length;
  bool get busy => tasks.any((t) => t.status == UploadStatus.queued || t.status == UploadStatus.uploading);

  double get overall {
    final totalBytes = tasks.fold<int>(0, (a, t) => a + t.size);
    if (totalBytes == 0) return 0;
    final sent = tasks.fold<double>(0, (a, t) => a + t.size * (t.status == UploadStatus.done ? 1 : t.progress));
    return sent / totalBytes;
  }

  /// Vraća poruku o preskočenim fajlovima (npr. HEIC), ili null.
  String? add(String projectId, String projectTitle, List<web.File> files) {
    var skipped = 0;
    for (final f in files) {
      if (!isImageFile(f) || f.name.toLowerCase().endsWith('.heic')) {
        skipped++;
        continue;
      }
      tasks.add(UploadTask(f, projectId, projectTitle));
    }
    _pump();
    notifyListeners();
    return skipped == 0 ? null : 'Preskočeno: ${photosLabel(skipped)} (podržani su JPG, PNG, WebP i TIFF).';
  }

  void _pump() {
    while (active < concurrency) {
      final next = tasks.where((t) => t.status == UploadStatus.queued).firstOrNull;
      if (next == null) break;
      _start(next);
    }
    busy ? _guard.enable() : _guard.disable();
  }

  void _start(UploadTask t) {
    t
      ..status = UploadStatus.uploading
      ..progress = 0
      ..error = null;
    final url = '/api/admin/projects/${t.projectId}/photos?name=${Uri.encodeQueryComponent(t.name)}';
    t.handle = uploadFile(url, t.file, (p) {
      t.progress = p;
      _notifySoon();
    });
    t.handle!.done.then((_) {
      t
        ..status = UploadStatus.done
        ..progress = 1;
      _uploaded.add(t.projectId);
      AdminRefresh.instance.changed();
    }, onError: (Object e) {
      t
        ..status = UploadStatus.failed
        ..error = e.toString();
    }).whenComplete(() {
      t.handle = null;
      _pump();
      _scheduleAutoClear();
      notifyListeners();
    });
  }

  /// Kada sve uspešno završi, panel se sam skloni da ne prekriva dugmad.
  /// Ako nešto nije uspelo, ostaje dok ne pritisnete "Ponovi" ili ×.
  void _scheduleAutoClear() {
    _autoClear?.cancel();
    if (busy || failed > 0 || tasks.isEmpty) return;
    _autoClear = Timer(const Duration(seconds: 5), () {
      if (!busy && failed == 0) clear();
    });
  }

  void _notifySoon() {
    if (_throttle?.isActive ?? false) return;
    _throttle = Timer(const Duration(milliseconds: 120), notifyListeners);
  }

  void retryFailed() {
    for (final t in tasks.where((t) => t.status == UploadStatus.failed)) {
      t.status = UploadStatus.queued;
    }
    _pump();
    notifyListeners();
  }

  void cancelAll() {
    for (final t in tasks.where((t) => t.status == UploadStatus.queued || t.status == UploadStatus.uploading).toList()) {
      t.handle?.cancel();
      t.status = UploadStatus.failed;
      t.error = 'Otkazano';
    }
    _pump();
    notifyListeners();
  }

  void clear() {
    tasks.removeWhere((t) => t.status == UploadStatus.done || t.status == UploadStatus.failed);
    _pump();
    notifyListeners();
  }
}

/// Plutajući panel sa napretkom otpremanja (vidljiv na svim admin stranicama).
class UploadPanel extends StatefulWidget {
  const UploadPanel({super.key});

  @override
  State<UploadPanel> createState() => _UploadPanelState();
}

class _UploadPanelState extends State<UploadPanel> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final m = UploadManager.instance;
    return ListenableBuilder(
      listenable: m,
      builder: (context, _) {
        if (m.tasks.isEmpty) return const SizedBox.shrink();
        final t = Theme.of(context).textTheme;
        final finished = !m.busy;
        final title = finished
            ? (m.failed > 0 ? 'Otpremljeno ${m.done} od ${m.total} · ${m.failed} nije uspelo' : 'Otpremljeno: ${photosLabel(m.done)}')
            : 'Otpremam ${m.done + m.active} od ${m.total}  ·  ${(m.overall * 100).round()}%';
        return Material(
          elevation: 10,
          shadowColor: Colors.black38,
          color: AppColors.ink,
          borderRadius: BorderRadius.circular(20),
          clipBehavior: Clip.antiAlias,
          child: SizedBox(
            width: 400,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              InkWell(
                onTap: () => setState(() => _expanded = !_expanded),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 14, 8, 14),
                  child: Row(children: [
                    Icon(
                      finished ? (m.failed > 0 ? Icons.error_outline_rounded : Icons.cloud_done_rounded) : Icons.cloud_upload_rounded,
                      color: finished && m.failed == 0 ? const Color(0xFF8FE3BF) : Colors.white,
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Text(title, style: t.titleSmall?.copyWith(color: Colors.white))),
                    if (m.failed > 0 && finished)
                      TextButton(
                        style: TextButton.styleFrom(foregroundColor: const Color(0xFF8FE3BF)),
                        onPressed: m.retryFailed,
                        child: const Text('Ponovi'),
                      ),
                    IconButton(
                      color: Colors.white70,
                      onPressed: finished ? m.clear : () => setState(() => _expanded = !_expanded),
                      icon: Icon(finished ? Icons.close_rounded : (_expanded ? Icons.expand_more_rounded : Icons.expand_less_rounded)),
                    ),
                  ]),
                ),
              ),
              if (!finished)
                LinearProgressIndicator(value: m.overall, minHeight: 4, backgroundColor: Colors.white12, color: const Color(0xFF8FE3BF)),
              if (_expanded)
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 320),
                  child: ListView.builder(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    itemCount: m.tasks.length,
                    itemBuilder: (context, i) {
                      final task = m.tasks[m.tasks.length - 1 - i];
                      return ListTile(
                        dense: true,
                        leading: switch (task.status) {
                          UploadStatus.done => const Icon(Icons.check_circle_rounded, color: Color(0xFF8FE3BF)),
                          UploadStatus.failed => const Icon(Icons.error_rounded, color: Color(0xFFFFB4AB)),
                          UploadStatus.uploading => SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(value: task.progress, strokeWidth: 3, color: Colors.white, backgroundColor: Colors.white12),
                            ),
                          UploadStatus.queued => const Icon(Icons.schedule_rounded, color: Colors.white38),
                        },
                        title: Text(task.name, style: const TextStyle(color: Colors.white), overflow: TextOverflow.ellipsis),
                        subtitle: Text(
                          task.error ?? '${formatBytes(task.size)} · ${task.projectTitle}',
                          style: TextStyle(color: task.error != null ? const Color(0xFFFFB4AB) : Colors.white54),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                    },
                  ),
                ),
              if (_expanded && m.busy)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: TextButton(
                    style: TextButton.styleFrom(foregroundColor: Colors.white70),
                    onPressed: m.cancelAll,
                    child: const Text('Otkaži preostale'),
                  ),
                ),
            ]),
          ),
        );
      },
    );
  }
}
