import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../domain/sport.dart';
import '../features/activity/activity_screen.dart';
import '../features/coach/coach_screen.dart';
import '../features/log/log_screen.dart';
import '../features/profile/profile_screen.dart';
import '../features/recovery/night_screen.dart';
import '../features/recovery/nights_screen.dart';
import '../features/recovery/recovery_screen.dart';
import '../features/recovery/trends_screen.dart';
import '../features/sports/sport_screen.dart';
import '../features/sports/sports_screen.dart';
import '../features/today/today_screen.dart';
import 'shell.dart';

/// Branch order is fixed: Training 0–2, Coach 3 (shared), Recovery 4–6.
abstract final class Tabs {
  static const today = 0, log = 1, sports = 2, coach = 3, recovery = 4, nights = 5, trends = 6;
}

GoRoute _tab(String path, Widget screen) => GoRoute(path: path, builder: (_, _) => screen);

final appRouter = GoRouter(
  initialLocation: '/today',
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (context, state, shell) => AppShell(shell: shell),
      branches: [
        StatefulShellBranch(routes: [_tab('/today', const TodayScreen())]),
        StatefulShellBranch(routes: [_tab('/log', const LogScreen())]),
        StatefulShellBranch(routes: [_tab('/sports', const SportsScreen())]),
        StatefulShellBranch(routes: [_tab('/coach', const CoachScreen())]),
        StatefulShellBranch(routes: [_tab('/recovery', const RecoveryScreen())]),
        StatefulShellBranch(routes: [_tab('/nights', const NightsScreen())]),
        StatefulShellBranch(routes: [_tab('/trends', const TrendsScreen())]),
      ],
    ),
    // Details sit above the shell so the nav bar gets out of the way.
    GoRoute(
      path: '/activity/:id',
      builder: (_, state) => ActivityScreen(id: int.parse(state.pathParameters['id']!)),
    ),
    GoRoute(
      path: '/sport/:name',
      builder: (_, state) => SportScreen(sport: Sport.byName(state.pathParameters['name']!) ?? Sport.run),
    ),
    GoRoute(
      path: '/sleep/:date',
      builder: (_, state) => NightScreen(date: DateTime.parse(state.pathParameters['date']!)),
    ),
    GoRoute(path: '/profile', builder: (_, _) => const ProfileScreen()),
  ],
);

/// Opens an activity from anywhere.
void openActivity(BuildContext context, int id) => context.push('/activity/$id');

/// Opens one sport's page from anywhere.
void openSport(BuildContext context, Sport sport) => context.push('/sport/${sport.name}');

/// Opens one night. [date] is the morning of waking up.
void openNight(BuildContext context, DateTime date) {
  final d = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  context.push('/sleep/$d');
}
