// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library;

import 'package:checks/checks.dart';
import 'package:checks/context.dart';
import 'package:dart_mcp/api.dart';

part 'completions.dart';
part 'elicitation.dart';
part 'icons.dart';
part 'initialization.dart';
part 'logging.dart';
part 'prompts.dart';
part 'resources.dart';
part 'roots.dart';
part 'sampling.dart';
part 'tools.dart';

extension BaseMetadataChecks<T extends BaseMetadata> on Subject<T> {
  Subject<String> get name => has((x) => x.name, 'name');
  Subject<String?> get title => has((x) => x.title, 'title');
}

extension AnnotatedChecks<T extends Annotated> on Subject<T> {
  Subject<Annotations?> get annotations =>
      has((x) => x.annotations, 'annotations');
}

extension AnnotationsChecks on Subject<Annotations> {
  Subject<List<Role>?> get audience => has((x) => x.audience, 'audience');
  Subject<DateTime?> get lastModified =>
      has((x) => x.lastModified, 'lastModified');
  Subject<double?> get priority => has((x) => x.priority, 'priority');
}

extension WithMetadataChecks<T extends WithMetadata> on Subject<T> {
  Subject<Meta?> get meta => has((x) => x.meta, 'meta');
}

extension RequestChecks<T extends Request> on Subject<T> {
  Subject<MetaWithProgressToken?> get meta => has((x) => x.meta, 'meta');
}

extension NotificationChecks<T extends Notification> on Subject<T> {
  Subject<Meta?> get meta => has((x) => x.meta, 'meta');
}

extension ResultChecks<T extends Result> on Subject<T> {
  Subject<Meta?> get meta => has((x) => x.meta, 'meta');
}

extension CancelledNotificationChecks on Subject<CancelledNotification> {
  Subject<RequestId?> get requestId => has((x) => x.requestId, 'requestId');
  Subject<String?> get reason => has((x) => x.reason, 'reason');
}

extension ProgressNotificationChecks on Subject<ProgressNotification> {
  Subject<ProgressToken> get progressToken =>
      has((x) => x.progressToken, 'progressToken');
  Subject<num> get progress => has((x) => x.progress, 'progress');
  Subject<num?> get total => has((x) => x.total, 'total');
  Subject<String?> get message => has((x) => x.message, 'message');
}

extension PaginatedRequestChecks<T extends PaginatedRequest> on Subject<T> {
  Subject<Cursor?> get cursor => has((x) => x.cursor, 'cursor');
}

extension PaginatedResultChecks<T extends PaginatedResult> on Subject<T> {
  Subject<Cursor?> get nextCursor => has((x) => x.nextCursor, 'nextCursor');
}

extension ContentChecks on Subject<Content> {
  Subject<String> get type => has((x) => x.type, 'type');
  Subject<bool> get isText => has((x) => x.isText, 'isText');
  Subject<bool> get isImage => has((x) => x.isImage, 'isImage');
  Subject<bool> get isAudio => has((x) => x.isAudio, 'isAudio');
  Subject<bool> get isEmbeddedResource =>
      has((x) => x.isEmbeddedResource, 'isEmbeddedResource');

  Subject<TextContent> get asText {
    return context.nest(() => ['as TextContent'], (actual) {
      if (actual.isText) {
        return Extracted.value(actual as TextContent);
      }
      return Extracted.rejection(
        which: ['is not a TextContent (type is ${actual.type})'],
      );
    });
  }

  Subject<ImageContent> get asImage {
    return context.nest(() => ['as ImageContent'], (actual) {
      if (actual.isImage) {
        return Extracted.value(actual as ImageContent);
      }
      return Extracted.rejection(
        which: ['is not an ImageContent (type is ${actual.type})'],
      );
    });
  }

  Subject<AudioContent> get asAudio {
    return context.nest(() => ['as AudioContent'], (actual) {
      if (actual.isAudio) {
        return Extracted.value(actual as AudioContent);
      }
      return Extracted.rejection(
        which: ['is not an AudioContent (type is ${actual.type})'],
      );
    });
  }

  Subject<EmbeddedResource> get asEmbeddedResource {
    return context.nest(() => ['as EmbeddedResource'], (actual) {
      if (actual.isEmbeddedResource) {
        return Extracted.value(actual as EmbeddedResource);
      }
      return Extracted.rejection(
        which: ['is not an EmbeddedResource (type is ${actual.type})'],
      );
    });
  }
}

extension TextContentChecks on Subject<TextContent> {
  Subject<String> get text => has((x) => x.text, 'text');
}

extension ImageContentChecks on Subject<ImageContent> {
  Subject<String> get data => has((x) => x.data, 'data');
  Subject<String> get mimeType => has((x) => x.mimeType, 'mimeType');
}

extension AudioContentChecks on Subject<AudioContent> {
  Subject<String> get data => has((x) => x.data, 'data');
  Subject<String> get mimeType => has((x) => x.mimeType, 'mimeType');
}

extension EmbeddedResourceChecks on Subject<EmbeddedResource> {
  Subject<ResourceContents> get resource => has((x) => x.resource, 'resource');
}

extension ResourceLinkChecks on Subject<ResourceLink> {
  Subject<String?> get description => has((x) => x.description, 'description');
  Subject<String> get uri => has((x) => x.uri, 'uri');
  Subject<String?> get mimeType => has((x) => x.mimeType, 'mimeType');
  Subject<int?> get size => has((x) => x.size, 'size');
  Subject<List<String>?> get icons => has((x) => x.icons, 'icons');
}
