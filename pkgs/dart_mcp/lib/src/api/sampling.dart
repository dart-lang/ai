// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

part of 'api.dart';

// /* Sampling */
// /**
//  * A request from the server to sample an LLM via the client. The client has
//  * full discretion over which model to select. The client should also inform
//  * the user before beginning sampling, to allow them to inspect the request
//  * (human in the loop) and decide whether to approve it.
//  */
// export interface CreateMessageRequest extends Request {
//   method: "sampling/createMessage";
//   params: {
//     messages: SamplingMessage[];
//     /**
//      * The server's preferences for which model to select. The client MAY
//      * ignore these preferences.
//      */
//     modelPreferences?: ModelPreferences;
//     /**
//      * An optional system prompt the server wants to use for sampling. The
//      * client MAY modify or omit this prompt.
//      */
//     systemPrompt?: string;
//     /**
//      * A request to include context from one or more MCP servers (including
//      * the caller), to be attached to the prompt. The client MAY ignore this
//      * request.
//      */
//     includeContext?: "none" | "thisServer" | "allServers";
//     /**
//      * @TJS-type number
//      */
//     temperature?: number;
//     /**
//      * The maximum number of tokens to sample, as requested by the server.
//      * The client MAY choose to sample fewer tokens than requested.
//      */
//     maxTokens: number;
//     stopSequences?: string[];
//     /**
//      * Optional metadata to pass through to the LLM provider. The format of
//      * this metadata is provider-specific.
//      */
//     metadata?: object;
//   };
// }

// /**
//  * The client's response to a sampling/create_message request from the
//  * server. The client should inform the user before returning the sampled
//  * message, to allow them to inspect the response (human in the loop) and
//  * decide whether to allow the server to see it.
//  */
// export interface CreateMessageResult extends Result, SamplingMessage {
//   /**
//    * The name of the model that generated the message.
//    */
//   model: string;
//   /**
//    * The reason why sampling stopped, if known.
//    */
//   stopReason?: "endTurn" | "stopSequence" | "maxTokens" | string;
// }

// /**
//  * Describes a message issued to or received from an LLM API.
//  */
// export interface SamplingMessage {
//   role: Role;
//   content: TextContent | ImageContent;
// }

// /**
//  * Base for objects that include optional annotations for the client. The
//  * client can use annotations to inform how objects are used or displayed
//  */
// export interface Annotated {
//   annotations?: {
//     /**
//      * Describes who the intended customer of this object or data is.
//      *
//      * It can include multiple entries to indicate content useful for
//      * multiple audiences (e.g., `["user", "assistant"]`).
//      */
//     audience?: Role[];

//     /**
//      * Describes how important this data is for operating the server.
//      *
//      * A value of 1 means "most important," and indicates that the data is
//      * effectively required, while 0 means "least important," and indicates
//      * that the data is entirely optional.
//      *
//      * @TJS-type number
//      * @minimum 0
//      * @maximum 1
//      */
//     priority?: number;
//   }
// }

// /**
//  * The server's preferences for model selection, requested of the client
//  * during sampling.
//  *
//  * Because LLMs can vary along multiple dimensions, choosing the "best" model
//  * is rarely straightforward.  Different models excel in different areas—some
//  * are faster but less capable, others are more capable but more expensive,
//  * and so on. This interface allows servers to express their priorities
//  * across multiple dimensions to help clients make an appropriate selection
//  * for their use case.
//  *
//  * These preferences are always advisory. The client MAY ignore them. It is
//  * also up to the client to decide how to interpret these preferences and
//  * how to balance them against other considerations.
//  */
// export interface ModelPreferences {
//   /**
//    * Optional hints to use for model selection.
//    *
//    * If multiple hints are specified, the client MUST evaluate them in order
//    * (such that the first match is taken).
//    *
//    * The client SHOULD prioritize these hints over the numeric priorities,
//    * but MAY still use the priorities to select from ambiguous matches.
//    */
//   hints?: ModelHint[];

//   /**
//    * How much to prioritize cost when selecting a model. A value of 0 means
//    * cost is not important, while a value of 1 means cost is the most
//    * important factor.
//    *
//    * @TJS-type number
//    * @minimum 0
//    * @maximum 1
//    */
//   costPriority?: number;

//   /**
//    * How much to prioritize sampling speed (latency) when selecting a model.
//    * A value of 0 means speed is not important, while a value of 1 means
//    * speed is the most important factor.
//    *
//    * @TJS-type number
//    * @minimum 0
//    * @maximum 1
//    */
//   speedPriority?: number;

//   /**
//    * How much to prioritize intelligence and capabilities when selecting a
//    * model. A value of 0 means intelligence is not important, while a value
//    * of 1 means intelligence is the most important factor.
//    *
//    * @TJS-type number
//    * @minimum 0
//    * @maximum 1
//    */
//   intelligencePriority?: number;
// }

// /**
//  * Hints to use for model selection.
//  *
//  * Keys not declared here are currently left unspecified by the spec and are
//  * up to the client to interpret.
//  */
// export interface ModelHint {
//   /**
//    * A hint for a model name.
//    *
//    * The client SHOULD treat this as a substring of a model name; for
//    * example:
//    *  - `claude-3-5-sonnet` should match `claude-3-5-sonnet-20241022`
//    *  - `sonnet` should match `claude-3-5-sonnet-20241022`,
//    *    `claude-3-sonnet-20240229`, etc.
//    *  - `claude` should match any Claude model
//    *
//    * The client MAY also map the string to a different provider's model name
//    * or a different model family, as long as it fills a similar niche; for
//    * example:
//    *  - `gemini-1.5-flash` could match `claude-3-haiku-20240307`
//    */
//   name?: string;
// }

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
