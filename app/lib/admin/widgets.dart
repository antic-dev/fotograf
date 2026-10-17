import 'package:flutter/material.dart';

import '../api/models.dart';
import '../ui/common.dart';
import '../ui/theme.dart';
import '../web/browser.dart';

String adminThumb(String photoId) => '/api/admin/photos/$photoId/thumb';
String adminPreview(String photoId) => '/api/admin/photos/$photoId/preview';
String adminOriginal(String photoId) => '/api/admin/photos/$photoId/original';

class PageHeader extends StatelessWidget {
  const PageHeader({super.key, required this.title, this.subtitle, this.actions = const []});
  final String title;
  final String? subtitle;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final phone = isPhone(context);
    return Padding(
      padding: EdgeInsets.only(top: phone ? 20 : 40, bottom: 20),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.end,
        spacing: 16,
        runSpacing: 14,
        children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(title, style: phone ? t.headlineLarge : t.displaySmall),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(subtitle!, style: t.bodyLarge?.copyWith(color: AppColors.inkSoft)),
            ],
          ]),
          if (actions.isNotEmpty) Wrap(spacing: 10, runSpacing: 10, children: actions),
        ],
      ),
    );
  }
}

class StatCard extends StatelessWidget {
  const StatCard({super.key, required this.label, required this.value, required this.icon, this.highlight = false, this.onTap});
  final String label;
  final String value;
  final IconData icon;
  final bool highlight;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final fg = highlight ? Colors.white : AppColors.ink;
    return Material(
      color: highlight ? AppColors.emerald : AppColors.paper,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: highlight ? null : Border.all(color: AppColors.line),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(icon, color: highlight ? Colors.white : AppColors.gold),
              const Spacer(),
              if (onTap != null) Icon(Icons.arrow_forward_rounded, size: 18, color: fg.withValues(alpha: 0.5)),
            ]),
            const SizedBox(height: 14),
            Text(value, style: t.displaySmall?.copyWith(fontFamily: bodyFont, fontWeight: FontWeight.w800, color: fg)),
            const SizedBox(height: 2),
            Text(label, style: t.bodyMedium?.copyWith(color: fg.withValues(alpha: 0.75), fontWeight: FontWeight.w500)),
          ]),
        ),
      ),
    );
  }
}

class OrderCard extends StatelessWidget {
  const OrderCard({super.key, required this.order, this.onTap, this.selected, this.onSelect});
  final AdminOrder order;
  final VoidCallback? onTap;
  final bool? selected;
  final ValueChanged<bool>? onSelect;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final o = order;
    final phone = isPhone(context);
    return Material(
      color: selected == true ? AppColors.emeraldSoft : AppColors.paper,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: selected == true ? AppColors.emerald : AppColors.line, width: selected == true ? 2 : 1),
          ),
          child: Row(children: [
            if (selected != null)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Checkbox(value: selected, onChanged: (v) => onSelect?.call(v ?? false)),
              ),
            SizedBox(
              width: phone ? 64 : 132,
              height: 64,
              child: Row(children: [
                for (final id in o.previewPhotoIds.take(phone ? 1 : 2)) ...[
                  Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(10), child: NetImage(adminThumb(id)))),
                  const SizedBox(width: 4),
                ],
                if (o.previewPhotoIds.isEmpty) const Expanded(child: Icon(Icons.image_outlined, color: AppColors.inkFaint)),
              ]),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(o.displayName, style: t.titleMedium, overflow: TextOverflow.ellipsis),
                Text(o.projectTitle, style: t.bodyMedium?.copyWith(color: AppColors.inkSoft), overflow: TextOverflow.ellipsis),
                const SizedBox(height: 6),
                Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  orderStatusPill(o.status),
                  Text('${photosLabel(o.photoCount)} · ${copiesLabel(o.copies)}', style: t.bodySmall),
                  Text(timeAgo(o.submittedAt ?? o.updatedAt), style: t.bodySmall?.copyWith(color: AppColors.inkFaint)),
                ]),
              ]),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.inkFaint),
          ]),
        ),
      ),
    );
  }
}

class DriveConnectBanner extends StatelessWidget {
  const DriveConnectBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(color: AppColors.amberSoft, borderRadius: BorderRadius.circular(20)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.add_to_drive_rounded, color: AppColors.amber, size: 30),
          const SizedBox(width: 12),
          Expanded(child: Text('Povežite Google Drive', style: t.titleLarge)),
        ]),
        const SizedBox(height: 8),
        Text(
          'Fotografije se čuvaju na vašem Google Drive-u (folder „Fotograf”, poseban podfolder za svaki projekat). '
          'Aplikacija vidi samo fajlove koje sama napravi — ostatak vašeg Drive-a joj je nedostupan.',
          style: t.bodyLarge,
        ),
        const SizedBox(height: 14),
        FilledButton.icon(
          onPressed: () => navigateTo('/api/admin/drive/connect'),
          icon: const Icon(Icons.link_rounded),
          label: const Text('Poveži Google Drive'),
        ),
      ]),
    );
  }
}
