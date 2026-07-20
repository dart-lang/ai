// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

part of 'api.dart';

extension ListResourcesRequestChecks on Subject<ListResourcesRequest> {}

extension ListResourcesResultChecks on Subject<ListResourcesResult> {
  Subject<List<Resource>> get resources => has((x) => x.resources, 'resources');
}

extension ListResourceTemplatesRequestChecks
    on Subject<ListResourceTemplatesRequest> {}

extension ListResourceTemplatesResultChecks
    on Subject<ListResourceTemplatesResult> {
  Subject<List<ResourceTemplate>> get resourceTemplates =>
      has((x) => x.resourceTemplates, 'resourceTemplates');
}

extension ReadResourceRequestChecks on Subject<ReadResourceRequest> {
  Subject<String> get uri => has((x) => x.uri, 'uri');
}

extension ReadResourceResultChecks on Subject<ReadResourceResult> {
  Subject<List<ResourceContents>> get contents =>
      has((x) => x.contents, 'contents');
}

extension ResourceListChangedNotificationChecks
    on Subject<ResourceListChangedNotification> {}

extension SubscribeRequestChecks on Subject<SubscribeRequest> {
  Subject<String> get uri => has((x) => x.uri, 'uri');
}

extension UnsubscribeRequestChecks on Subject<UnsubscribeRequest> {
  Subject<String> get uri => has((x) => x.uri, 'uri');
}

extension ResourceUpdatedNotificationChecks
    on Subject<ResourceUpdatedNotification> {
  Subject<String> get uri => has((x) => x.uri, 'uri');
}

extension ResourceChecks on Subject<Resource> {
  Subject<String> get uri => has((x) => x.uri, 'uri');
  Subject<String?> get description => has((x) => x.description, 'description');
  Subject<String?> get mimeType => has((x) => x.mimeType, 'mimeType');
  Subject<int?> get size => has((x) => x.size, 'size');
  Subject<List<Icon>?> get icons => has((x) => x.icons, 'icons');
}

extension ResourceTemplateChecks on Subject<ResourceTemplate> {
  Subject<String> get uriTemplate => has((x) => x.uriTemplate, 'uriTemplate');
  Subject<String?> get description => has((x) => x.description, 'description');
  Subject<String?> get mimeType => has((x) => x.mimeType, 'mimeType');
  Subject<List<Icon>?> get icons => has((x) => x.icons, 'icons');
}

extension ResourceContentsChecks<T extends ResourceContents> on Subject<T> {
  Subject<String> get uri => has((x) => x.uri, 'uri');
  Subject<String?> get mimeType => has((x) => x.mimeType, 'mimeType');
  Subject<bool> get isText => has((x) => x.isText, 'isText');
  Subject<bool> get isBlob => has((x) => x.isBlob, 'isBlob');

  Subject<TextResourceContents> get asText {
    return context.nest(() => ['as TextResourceContents'], (resource) {
      if (resource.isText) {
        return Extracted.value(resource as TextResourceContents);
      }
      return Extracted.rejection(which: ['is not a TextResourceContents']);
    });
  }

  Subject<BlobResourceContents> get asBlob {
    return context.nest(() => ['as BlobResourceContents'], (resource) {
      if (resource.isBlob) {
        return Extracted.value(resource as BlobResourceContents);
      }
      return Extracted.rejection(which: ['is not a BlobResourceContents']);
    });
  }
}

extension TextResourceContentsChecks on Subject<TextResourceContents> {
  Subject<String> get text => has((x) => x.text, 'text');
}

extension BlobResourceContentsChecks on Subject<BlobResourceContents> {
  Subject<String> get blob => has((x) => x.blob, 'blob');
}
