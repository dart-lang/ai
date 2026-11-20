// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import '../models/skill_manifest.dart';
import 'skill_scanner.dart';

/// One source's version of a skill name.
class SkillCopy {
  final String sourceUri;

  /// Whether the agent's manifest records this copy with `isInstalled: false`.
  final bool isSkipped;

  final String? path;

  const SkillCopy(this.sourceUri, {required this.isSkipped, this.path});

  bool get isFromPackage => sourceUri.startsWith('package:');
}

/// A skill name that both a package and a git repo ship, as a run sees it for
/// one agent.
///
/// The copies that are not skipped are candidates. With more than one
/// candidate the collision is a conflict, and the skill stays as it is until
/// someone chooses a copy.
class SkillCollision {
  final String skillName;

  /// One copy per source, package copies first.
  final List<SkillCopy> copies;

  const SkillCollision(this.skillName, this.copies);

  List<SkillCopy> get candidates => [
    for (final copy in copies)
      if (!copy.isSkipped) copy,
  ];

  bool get isConflict => candidates.length > 1;

  /// The copies that a run leaves exactly as they are.
  List<SkillCopy> get heldCopies => [
    for (final copy in copies)
      if (isConflict || copy.isSkipped) copy,
  ];
}

/// Finds the skill names in [skills] that both a package and a git repo ship
/// for [agentName].
///
/// A run limited to [runSourceUris] also sees the copies that [manifest]
/// records as installed under other sources, so that it does not install its
/// own copy over them.
List<SkillCollision> findCollisions({
  required List<ScannedSkill> skills,
  required SkillManifest manifest,
  required String agentName,
  required Set<String> runSourceUris,
}) {
  final entries = manifest.sourceUrisForAgent(agentName);
  final copiesByName = <String, Map<String, SkillCopy>>{};
  for (final skill in skills) {
    final copies = copiesByName.putIfAbsent(skill.skillName, () => {});
    copies[skill.sourceUri] ??= SkillCopy(
      skill.sourceUri,
      isSkipped: _isSkipped(entries[skill.sourceUri], skill.skillName),
      path: skill.path,
    );
  }
  for (final MapEntry(key: sourceUri, value: entry) in entries.entries) {
    if (runSourceUris.isEmpty || runSourceUris.contains(sourceUri)) continue;
    for (final skill in entry.skills) {
      if (!skill.isInstalled) continue;
      copiesByName[skill.name]?[sourceUri] = SkillCopy(
        sourceUri,
        isSkipped: false,
        path: skill.path,
      );
    }
  }
  return [
    for (final MapEntry(key: skillName, value: copies) in copiesByName.entries)
      if (copies.values.any((c) => c.isFromPackage) &&
          copies.values.any((c) => !c.isFromPackage))
        SkillCollision(skillName, [
          ...copies.values.where((c) => c.isFromPackage),
          ...copies.values.where((c) => !c.isFromPackage),
        ]),
  ];
}

bool _isSkipped(SkillsEntry? entry, String skillName) =>
    entry?.skills.any((s) => s.name == skillName && !s.isInstalled) ?? false;

/// Returns [manifest] with the copy from [sourceUri] chosen for [collision]
/// and [agentName]: every other candidate is recorded as skipped.
SkillManifest withChosenCopy(
  SkillManifest manifest, {
  required String agentName,
  required SkillCollision collision,
  required String sourceUri,
}) {
  var updated = manifest;
  for (final copy in collision.candidates) {
    if (copy.sourceUri == sourceUri) continue;
    updated = _withSkippedEntry(updated, agentName, copy, collision.skillName);
  }
  return updated;
}

/// Returns [manifest] with [copy] recorded as skipped for [agentName], in place
/// of the entry that its source has for [skillName].
SkillManifest _withSkippedEntry(
  SkillManifest manifest,
  String agentName,
  SkillCopy copy,
  String skillName,
) {
  final entries = manifest.sourceUrisForAgent(agentName)[copy.sourceUri];
  final skipped = InstalledSkillEntry(
    name: skillName,
    installedAt: DateTime.now().toUtc(),
    isInstalled: false,
    path: copy.path,
  );
  return manifest.withSourceUri(
    agentName,
    copy.sourceUri,
    SkillsEntry(
      skills: [
        for (final other in entries?.skills ?? const <InstalledSkillEntry>[])
          if (other.name != skillName) other,
        skipped,
      ],
    ),
  );
}
