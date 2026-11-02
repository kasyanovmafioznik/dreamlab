import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../data/local/prefs.dart';
import '../features/generate/screens/generate_screen.dart';
import '../features/history/screens/generation_detail_screen.dart';
import '../features/history/screens/history_screen.dart';
import '../features/settings/screens/settings_screen.dart';

/// Paths of the three bottom tabs, in order.
const tabPaths = ['/generate', '/history', '/settings'];

/// Shell: bottom navigation with three tabs; detail is a root-level route
/// pushed on top of the shell (proper back behavior on iOS).
///
/// The app reopens on the tab it was left on — a small "pick up where you
/// left off" touch that also makes the history visible right after a restart.
GoRouter createRouter({required Prefs prefs}) {
  final rootKey = GlobalKey<NavigatorState>();
  final startTab = prefs.lastTab.clamp(0, tabPaths.length - 1);

  return GoRouter(
    navigatorKey: rootKey,
    initialLocation: tabPaths[startTab],
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) => AppShell(
          navigationShell: navigationShell,
          prefs: prefs,
        ),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/generate',
                builder: (context, state) => const GenerateScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/history',
                builder: (context, state) => const HistoryScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/settings',
                builder: (context, state) => const SettingsScreen(),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/generation/:id',
        parentNavigatorKey: rootKey,
        builder: (context, state) =>
            GenerationDetailScreen(entryId: state.pathParameters['id']!),
      ),
    ],
  );
}

class AppShell extends StatelessWidget {
  const AppShell({
    super.key,
    required this.navigationShell,
    required this.prefs,
  });

  final StatefulNavigationShell navigationShell;
  final Prefs prefs;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: navigationShell.currentIndex,
        onDestinationSelected: (index) {
          prefs.lastTab = index;
          navigationShell.goBranch(
            index,
            initialLocation: index == navigationShell.currentIndex,
          );
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.auto_awesome_outlined),
            selectedIcon: Icon(Icons.auto_awesome),
            label: 'Create',
          ),
          NavigationDestination(
            icon: Icon(Icons.history_outlined),
            selectedIcon: Icon(Icons.history),
            label: 'History',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
