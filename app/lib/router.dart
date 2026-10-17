import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'admin/auth.dart';
import 'admin/dashboard_page.dart';
import 'admin/login_page.dart';
import 'admin/order_page.dart';
import 'admin/orders_page.dart';
import 'admin/print_links_page.dart';
import 'admin/project_page.dart';
import 'admin/projects_page.dart';
import 'admin/settings_page.dart';
import 'admin/shell.dart';
import 'client/client_shell.dart';
import 'client/gallery_page.dart';
import 'client/lightbox_page.dart';
import 'client/review_page.dart';
import 'print/print_page.dart';

Page<void> _fade(GoRouterState state, Widget child) => CustomTransitionPage<void>(
      key: state.pageKey,
      child: child,
      transitionDuration: const Duration(milliseconds: 220),
      transitionsBuilder: (context, a, _, child) => FadeTransition(opacity: CurvedAnimation(parent: a, curve: Curves.easeOut), child: child),
    );

GoRouter buildRouter() => GoRouter(
      refreshListenable: AdminAuth.instance,
      redirect: (context, state) async {
        final loc = state.matchedLocation;
        if (loc.startsWith('/admin') && loc != '/admin/prijava') {
          final ok = await AdminAuth.instance.check();
          if (!ok) return '/admin/prijava?next=${Uri.encodeQueryComponent(state.uri.toString())}';
        }
        if (loc == '/admin/prijava' && AdminAuth.instance.loggedIn == true) return '/admin';
        return null;
      },
      errorBuilder: (context, state) => const UnknownLinkPage(),
      routes: [
        // Početna adresa je prijava za fotografa. Klijenti dobijaju samo
        // link galerije (/g/...) i na njemu nema ničeg administratorskog.
        GoRoute(
          path: '/',
          redirect: (context, state) async => await AdminAuth.instance.check() ? '/admin' : '/admin/prijava',
        ),

        // Klijenti — samo preko tajnog linka
        ShellRoute(
          builder: (context, state, child) => ClientShell(token: state.pathParameters['token']!, child: child),
          routes: [
            GoRoute(
              path: '/g/:token',
              pageBuilder: (context, state) => _fade(state, const GalleryPage()),
              routes: [
                GoRoute(
                  path: 'foto/:photoId',
                  pageBuilder: (context, state) => CustomTransitionPage<void>(
                    key: state.pageKey,
                    opaque: false,
                    child: LightboxPage(photoId: state.pathParameters['photoId']!),
                    transitionsBuilder: (context, a, _, child) => FadeTransition(opacity: a, child: child),
                  ),
                ),
                GoRoute(path: 'izbor', builder: (context, state) => const ReviewPage()),
              ],
            ),
          ],
        ),

        // Štamparija
        GoRoute(path: '/stampa/:token', builder: (context, state) => PrintPage(token: state.pathParameters['token']!)),

        // Administrator
        GoRoute(path: '/admin/prijava', builder: (context, state) => AdminLoginPage(next: state.uri.queryParameters['next'])),
        ShellRoute(
          builder: (context, state, child) => AdminShell(location: state.matchedLocation, child: child),
          routes: [
            GoRoute(path: '/admin', pageBuilder: (context, state) => _fade(state, const DashboardPage())),
            GoRoute(
              path: '/admin/projekti',
              pageBuilder: (context, state) => _fade(state, const ProjectsPage()),
              routes: [
                GoRoute(path: ':id', pageBuilder: (context, state) => _fade(state, ProjectPage(key: ValueKey(state.pathParameters['id']), projectId: state.pathParameters['id']!))),
              ],
            ),
            GoRoute(
              path: '/admin/porudzbine',
              pageBuilder: (context, state) => _fade(
                state,
                OrdersPage(
                  key: ValueKey(state.uri.toString()),
                  status: state.uri.queryParameters['status'],
                  projectId: state.uri.queryParameters['projekat'],
                ),
              ),
              routes: [
                GoRoute(path: ':id', builder: (context, state) => OrderPage(orderId: state.pathParameters['id']!)),
              ],
            ),
            GoRoute(path: '/admin/stampa', pageBuilder: (context, state) => _fade(state, const PrintLinksPage())),
            GoRoute(
              path: '/admin/podesavanja',
              pageBuilder: (context, state) => _fade(state, SettingsPage(
                  driveResult: state.uri.queryParameters['drive'],
                  driveMessage: state.uri.queryParameters['poruka'],
                )),
            ),
          ],
        ),
      ],
    );
