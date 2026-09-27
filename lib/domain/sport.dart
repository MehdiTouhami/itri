import 'package:flutter/material.dart';

/// Sports we model. Mirrors the FIT `sport` / `sub_sport` values we care about.
enum Sport {
  run('Run', Icons.directions_run_rounded, hasGps: true, usesPace: true),
  ride('Ride', Icons.directions_bike_rounded, hasGps: true, usesPace: false),
  walk('Walk', Icons.directions_walk_rounded, hasGps: true, usesPace: true),
  tennis('Tennis', Icons.sports_tennis_rounded, stopStart: true),
  padel('Padel', Icons.sports_tennis_rounded, stopStart: true),
  squash('Squash', Icons.sports_tennis_rounded, stopStart: true),
  football('Football', Icons.sports_soccer_rounded, stopStart: true),
  strength('Strength', Icons.fitness_center_rounded);

  const Sport(this.label, this.icon, {this.hasGps = false, this.usesPace = false, this.stopStart = false});

  final String label;
  final IconData icon;

  /// Whether the route and distance-based charts mean anything. Court and
  /// pitch sports record GPS, but a scribble over one court isn't a route.
  final bool hasGps;

  /// Runs and walks read in min/km; rides read in km/h.
  final bool usesPace;

  /// Rallies and sprints with rests between: read as efforts and recovery,
  /// not as steady pace.
  final bool stopStart;

  static Sport? byName(String name) {
    for (final s in values) {
      if (s.name == name) return s;
    }
    return null;
  }
}
