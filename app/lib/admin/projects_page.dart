import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../api/api.dart';
import '../api/models.dart';
import '../ui/common.dart';
import '../ui/theme.dart';
import 'project_form.dart';
import 'refresh.dart';
import 'widgets.dart';

class ProjectsPage extends StatefulWidget {
  const ProjectsPage({super.key});

  @override
  State<ProjectsPage> createState() => _ProjectsPageState();
}

class _ProjectsPageState extends State<ProjectsPage> {
  List<Project>? _projects;
  Object? _error;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
    AdminRefresh.instance.addListener(_load);
  }

  @override
  void dispose() {
    AdminRefresh.instance.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final list = await Api.instance.get('/api/admin/projects') as List;
      if (mounted) setState(() => _projects = [for (final p in list) Project.fromJson(p as Map<String, dynamic>)]);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _create() async {
    final p = await showProjectForm(context);
    if (p != null && mounted) context.go('/admin/projekti/${p.id}');
  }

  @override
  Widget build(BuildContext context) {
    final all = _projects;
    final q = _query.toLowerCase();
    final list = all?.where((p) => q.isEmpty || p.title.toLowerCase().contains(q) || p.clientName.toLowerCase().contains(q)).toList();

    return Scaffold(
      floatingActionButton: isPhone(context)
          ? FloatingActionButton.extended(onPressed: _create, icon: const Icon(Icons.add_rounded), label: const Text('Novi projekat'))
          : null,
      body: RefreshIndicator(
        onRefresh: _load,
        child: CustomScrollView(slivers: [
          SliverToBoxAdapter(
            child: Centered(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                PageHeader(
                  title: 'Projekti',
                  subtitle: 'Svaki projekat ima svoj folder na Drive-u i svoj tajni link.',
                  actions: [
                    if (!isPhone(context))
                      FilledButton.icon(onPressed: _create, icon: const Icon(Icons.add_rounded), label: const Text('Novi projekat')),
                  ],
                ),
                if ((all?.length ?? 0) > 4) ...[
                  TextField(
                    onChanged: (v) => setState(() => _query = v),
                    decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'Pretraga projekata'),
                  ),
                  const SizedBox(height: 20),
                ],
              ]),
            ),
          ),
          if (list == null)
            SliverFillRemaining(child: _error != null ? ErrorView(error: _error!, onRetry: _load) : const LoadingView())
          else if (list.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyState(
                icon: Icons.photo_library_outlined,
                title: all!.isEmpty ? 'Još nemate projekata' : 'Nema rezultata',
                message: all.isEmpty ? 'Napravite prvi projekat, dodajte fotografije i pošaljite link klijentu.' : null,
                action: all.isEmpty ? FilledButton.icon(onPressed: _create, icon: const Icon(Icons.add_rounded), label: const Text('Novi projekat')) : null,
              ),
            )
          else
            SliverPadding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 120),
              sliver: SliverLayoutBuilder(builder: (context, c) {
                final maxW = 1200.0;
                final w = c.crossAxisExtent > maxW ? maxW : c.crossAxisExtent;
                final cols = w > 900 ? 3 : (w > 560 ? 2 : 1);
                final side = (c.crossAxisExtent - w) / 2;
                return SliverPadding(
                  padding: EdgeInsets.symmetric(horizontal: side),
                  sliver: SliverGrid.builder(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: cols,
                      mainAxisSpacing: 16,
                      crossAxisSpacing: 16,
                      mainAxisExtent: cols == 1 ? 300 : 320,
                    ),
                    itemCount: list.length,
                    itemBuilder: (context, i) => _ProjectCard(project: list[i]),
                  ),
                );
              }),
            ),
        ]),
      ),
    );
  }
}

class _ProjectCard extends StatelessWidget {
  const _ProjectCard({required this.project});
  final Project project;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final p = project;
    final date = formatIsoDate(p.eventDate);
    return Material(
      color: AppColors.paper,
      borderRadius: BorderRadius.circular(22),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.go('/admin/projekti/${p.id}'),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(
            child: Stack(fit: StackFit.expand, children: [
              if (p.coverPhotoId != null)
                NetImage(adminThumb(p.coverPhotoId!))
              else
                const ColoredBox(color: AppColors.sand, child: Icon(Icons.add_photo_alternate_outlined, size: 44, color: AppColors.inkFaint)),
              Positioned(left: 12, top: 12, child: projectStatusPill(p.status)),
              if (p.newOrders > 0)
                Positioned(
                  right: 12,
                  top: 12,
                  child: Pill('${p.newOrders} ${p.newOrders == 1 ? 'nova' : 'nove'}', color: Colors.white, background: AppColors.danger, icon: Icons.inbox_rounded),
                ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(p.title, style: t.titleLarge?.copyWith(fontFamily: displayFont, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 4),
              Text(
                [?date, if (p.clientName.isNotEmpty) p.clientName].join(' · ').ifEmpty('Bez datuma'),
                style: t.bodyMedium?.copyWith(color: AppColors.inkSoft),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
              Row(children: [
                const Icon(Icons.image_outlined, size: 17, color: AppColors.inkFaint),
                const SizedBox(width: 4),
                Text(photosLabel(p.photoCount), style: t.bodySmall),
                const SizedBox(width: 14),
                const Icon(Icons.receipt_long_outlined, size: 17, color: AppColors.inkFaint),
                const SizedBox(width: 4),
                Text('${p.totalOrders} porudž.', style: t.bodySmall),
                if (p.activeDrafts > 0) ...[
                  const SizedBox(width: 14),
                  const Icon(Icons.touch_app_outlined, size: 17, color: AppColors.inkFaint),
                  const SizedBox(width: 4),
                  Text('${p.activeDrafts} bira', style: t.bodySmall),
                ],
              ]),
            ]),
          ),
        ]),
      ),
    );
  }
}

extension on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}
