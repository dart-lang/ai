// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

part of 'api.dart';

extension CompleteRequestChecks on Subject<CompleteRequest> {
  Subject<Reference> get ref => has((x) => x.ref, 'ref');
  Subject<CompletionArgument> get argument =>
      has((x) => x.argument, 'argument');
  Subject<CompletionContext?> get context => has((x) => x.context, 'context');
}

extension CompleteResultChecks on Subject<CompleteResult> {
  Subject<Completion> get completion => has((x) => x.completion, 'completion');
}

extension CompletionChecks on Subject<Completion> {
  Subject<List<String>> get values => has((x) => x.values, 'values');
  Subject<int?> get total => has((x) => x.total, 'total');
  Subject<bool?> get hasMore => has((x) => x.hasMore, 'hasMore');
}

extension CompletionArgumentChecks on Subject<CompletionArgument> {
  Subject<String> get name => has((x) => x.name, 'name');
  Subject<String> get value => has((x) => x.value, 'value');
}

extension CompletionContextChecks on Subject<CompletionContext> {
  Subject<Map<String, String>?> get arguments =>
      has((x) => x.arguments, 'arguments');
}

extension ReferenceChecks on Subject<Reference> {
  Subject<String> get type => has((x) => x.type, 'type');
  Subject<bool> get isPrompt => has((x) => x.isPrompt, 'isPrompt');
  Subject<bool> get isResource => has((x) => x.isResource, 'isResource');

  Subject<PromptReference> get asPrompt {
    return context.nest(() => ['as PromptReference'], (actual) {
      if (actual.isPrompt) {
        return Extracted.value(actual as PromptReference);
      }
      return Extracted.rejection(
        which: ['is not a PromptReference (type is ${actual.type})'],
      );
    });
  }

  Subject<ResourceTemplateReference> get asResource {
    return context.nest(() => ['as ResourceTemplateReference'], (actual) {
      if (actual.isResource) {
        return Extracted.value(actual as ResourceTemplateReference);
      }
      return Extracted.rejection(
        which: ['is not a ResourceTemplateReference (type is ${actual.type})'],
      );
    });
  }
}

extension ResourceTemplateReferenceChecks
    on Subject<ResourceTemplateReference> {
  Subject<String> get uri => has((x) => x.uri, 'uri');
}
