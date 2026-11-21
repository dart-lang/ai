// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import '../agent/agent.dart';
import '../models/skill_manifest.dart';
import 'skill_scanner.dart';

/// A skipped copy has a manifest entry with `isInstalled: false`.
enum CopyState { installed, skipped, unrecorded }

/// One source's version of a skill name.
class SkillCopy {
  final String sourceUri;
  final CopyState state;

  /// The scanned skill, or `null` for a copy that a run limited to other
  /// sources knows only from the manifest.
  final ScannedSkill? skill;

  const SkillCopy(this.sourceUri, this.state, [this.skill]);

  bool get isFromPackage => sourceUri.startsWith('package:');
}

/// A skill name that both a package and a git repo ship, as a run sees it for
/// one agent.
///
/// The copies that are not skipped are candidates. With more than one
/// candidate the collision is a conflict, and the skill stays as it is until
/// someone chooses a copy.
class SkillCollision {
  final Agent agent;
  final String skillName;

  /// One copy per source, package copies first.
  final List<SkillCopy> copies;

  const SkillCollision(this.agent, this.skillName, this.copies);

  List<SkillCopy> get candidates => [
    for (final copy in copies)
      if (copy.state != CopyState.skipped) copy,
  ];

  bool get isConflict => candidates.length > 1;

  /// The scanned skills that a run leaves exactly as they are.
  List<ScannedSkill> get heldSkills => [
    for (final copy in copies)
      if (isConflict || copy.state == CopyState.skipped) ?copy.skill,
  ];

  ScannedSkill? skillFrom(String sourceUri) =>
      copies.where((copy) => copy.sourceUri == sourceUri).firstOrNull?.skill;

  SkillCopy? get soleInstalledCopy =>
      copies.where((copy) => copy.state == CopyState.installed).singleOrNull;
}

/// Finds the skill names in [skills] that both a package and a git repo ship,
/// for each of [agents].
///
/// A run limited to [runSourceUris] also sees the copies that [manifest]
/// records as installed under other sources, so that it does not install its
/// own copy over them.
List<SkillCollision> findCollisions({
  required List<ScannedSkill> skills,
  required SkillManifest manifest,
  required List<Agent> agents,
  required Set<String> runSourceUris,
}) {
  final collisions = <SkillCollision>[];
  for (final agent in agents) {
    final entries = manifest.sourceUrisForAgent(agent.cliName);
    final copiesByName = <String, Map<String, SkillCopy>>{};
    for (final skill in skills) {
      final copies = copiesByName.putIfAbsent(skill.skillName, () => {});
      copies[skill.sourceUri] ??= SkillCopy(
        skill.sourceUri,
        _stateOf(entries[skill.sourceUri], skill.skillName),
        skill,
      );
    }
    for (final MapEntry(key: sourceUri, value: entry) in entries.entries) {
      final isSourceOfThisRun =
          runSourceUris.isEmpty || runSourceUris.contains(sourceUri);
      if (isSourceOfThisRun) continue;
      for (final skill in entry.skills) {
        if (!skill.isInstalled) continue;
        copiesByName[skill.name]?[sourceUri] = SkillCopy(
          sourceUri,
          CopyState.installed,
        );
      }
    }
    for (final MapEntry(key: skillName, value: copies)
        in copiesByName.entries) {
      final packageCopies = copies.values.where((copy) => copy.isFromPackage);
      final gitCopies = copies.values.where((copy) => !copy.isFromPackage);
      if (packageCopies.isEmpty || gitCopies.isEmpty) continue;
      collisions.add(
        SkillCollision(agent, skillName, [...packageCopies, ...gitCopies]),
      );
    }
  }
  return collisions;
}

CopyState _stateOf(SkillsEntry? entry, String skillName) =>
    switch (entry?.skills.where((s) => s.name == skillName).firstOrNull) {
      null => CopyState.unrecorded,
      InstalledSkillEntry(isInstalled: true) => CopyState.installed,
      _ => CopyState.skipped,
    };

/// Returns [manifest] with each choice in [chosenSkills] recorded once its
/// copy is installed: every other candidate of the collision is then skipped.
SkillManifest withInstalledChoices(
  SkillManifest manifest,
  Map<SkillCollision, ScannedSkill> chosenSkills,
) {
  var updated = manifest;
  for (final MapEntry(key: collision, value: chosen) in chosenSkills.entries) {
    final agentName = collision.agent.cliName;
    final chosenEntry = updated.sourceUrisForAgent(agentName)[chosen.sourceUri];
    if (_stateOf(chosenEntry, chosen.skillName) != CopyState.installed) {
      continue;
    }
    for (final copy in collision.candidates) {
      if (copy.sourceUri == chosen.sourceUri) continue;
      final entry = updated.sourceUrisForAgent(agentName)[copy.sourceUri];
      updated = updated.withSourceUri(
        agentName,
        copy.sourceUri,
        SkillsEntry(
          skills: [
            for (final other in entry?.skills ?? const <InstalledSkillEntry>[])
              if (other.name != collision.skillName) other,
            InstalledSkillEntry(
              name: collision.skillName,
              installedAt: DateTime.now().toUtc(),
              isInstalled: false,
            ),
          ],
        ),
      );
    }
  }
  return updated;
}
