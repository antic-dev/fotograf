import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../api/api.dart';
import '../api/models.dart';
import '../ui/common.dart';
import '../ui/theme.dart';
import '../web/browser.dart';
import 'project_form.dart';
import 'uploads.dart';
import 'widgets.dart';

/// Izbor fajlova i slanje u red za otpremanje za dati projekat.
void pickAndUpload(BuildContext context, String projectId, String projectTitle) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final width = MediaQuery.sizeOf(context).width;
  pickImages().then((files) {
    if (files.isEmpty) return;
    final warning = UploadManager.instance.add(projectId, projectTitle, files);
    if (messenger != null && messenger.mounted) {
      showMessageOn(
        messenger,
        width,
        warning ?? 'Otpremam ${photosLabel(files.length)} u „$projectTitle”. Možete nastaviti sa radom.',
        error: warning != null,
      );
    }
  });
}

/// "Otpremi fotografije" sa početne strane: prvo se bira projekat.
Future<void> pickProjectAndUpload(BuildContext context) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    builder: (_) => _ProjectPicker(parent: context),
  );
}

class _ProjectPicker extends StatefulWidget {
  const _ProjectPicker({required this.parent});
  final BuildContext parent;

  @override
  State<_ProjectPicker> createState() => _ProjectPickerState();
}

class _ProjectPickerState extends State<_ProjectPicker> {
  late final Future<List<Project>> _projects = () async {
    final list = await Api.instance.get('/api/admin/projects') as List;
    return [for (final p in list) Project.fromJson(p as Map<String, dynamic>)];
  }();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.8),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
            child: Text('U koji projekat otpremate?', style: t.headlineSmall),
          ),
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
            leading: Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(color: AppColors.emeraldSoft, borderRadius: BorderRadius.circular(14)),
              child: const Icon(Icons.add_rounded, color: AppColors.emerald),
            ),
            title: Text('Novi projekat', style: t.titleMedium),
            subtitle: const Text('Napravite projekat pa dodajte fotografije'),
            onTap: () async {
              final parent = widget.parent;
              Navigator.pop(context);
              final p = await showProjectForm(parent);
              if (p != null && parent.mounted) parent.go('/admin/projekti/${p.id}');
            },
          ),
          const Divider(),
          Flexible(
            child: FutureBuilder<List<Project>>(
              future: _projects,
              builder: (context, snap) {
                if (snap.hasError) return ErrorView(error: snap.error!);
                if (!snap.hasData) return const Padding(padding: EdgeInsets.all(32), child: LoadingView());
                return ListView(shrinkWrap: true, children: [
                  for (final p in snap.data!)
                    ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
                      leading: ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: SizedBox(
                          width: 56,
                          height: 56,
                          child: p.coverPhotoId == null
                              ? const ColoredBox(color: AppColors.sand, child: Icon(Icons.photo_outlined, color: AppColors.inkFaint))
                              : NetImage(adminThumb(p.coverPhotoId!)),
                        ),
                      ),
                      title: Text(p.title, style: t.titleMedium),
                      subtitle: Text([photosLabel(p.photoCount), ?formatIsoDate(p.eventDate)].join(' · ')),
                      trailing: const Icon(Icons.cloud_upload_outlined),
                      onTap: () {
                        // Izbor fajlova mora da krene odmah iz dodira (pravilo pregledača).
                        pickAndUpload(context, p.id, p.title);
                        Navigator.pop(context);
                      },
                    ),
                ]);
              },
            ),
          ),
        ]),
      ),
    );
  }
}
