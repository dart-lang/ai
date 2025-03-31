// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

part of 'api.dart';

// /* Autocomplete */
// /**
//  * A request from the client to the server, to ask for completion options.
//  */
// export interface CompleteRequest extends Request {
//   method: "completion/complete";
//   params: {
//     ref: PromptReference | ResourceReference;
//     /**
//      * The argument's information
//      */
//     argument: {
//       /**
//        * The name of the argument
//        */
//       name: string;
//       /**
//        * The value of the argument to use for completion matching.
//        */
//       value: string;
//     };
//   };
// }

// /**
//  * The server's response to a completion/complete request
//  */
// export interface CompleteResult extends Result {
//   completion: {
//     /**
//      * An array of completion values. Must not exceed 100 items.
//      */
//     values: string[];
//     /**
//      * The total number of completion options available. This can exceed the
//      * number of values actually sent in the response.
//      */
//     total?: number;
//     /**
//      * Indicates whether there are additional completion options beyond those
//      * provided in the current response, even if the exact total is unknown.
//      */
//     hasMore?: boolean;
//   };
// }

// /**
//  * A reference to a resource or resource template definition.
//  */
// export interface ResourceReference {
//   type: "ref/resource";
//   /**
//    * The URI or URI template of the resource.
//    *
//    * @format uri-template
//    */
//   uri: string;
// }

/// Identifies a prompt.
extension type PromptReference.fromMap(Map<String, Object?> _value) {
  static const expectedType = 'ref/prompt';

  factory PromptReference({required String name}) =>
      PromptReference.fromMap({'name': name, 'type': expectedType});

  /// This should always be [expectedType].
  ///
  /// This has a [type] because it exists as a part of a union type, so this
  /// distinguishes it from other types.
  String get type {
    final type = _value['type'] as String;
    assert(type == expectedType);
    return type;
  }

  /// The name of the prompt or prompt template
  String get name => _value['name'] as String;
}
