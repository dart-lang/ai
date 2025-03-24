// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Interfaces are based on https://github.com/modelcontextprotocol/specification/blob/main/schema/2024-11-05/schema.json
//
// TODO: Finish porting the commented out typescript types to dart extension
//       types.
// TODO: Autogenerate this from schema files
library;

import 'package:json_rpc_2/json_rpc_2.dart';

const protocolVersion = '2024-11-0';

/// A progress token, used to associate progress notifications with the original
/// request.
extension type ProgressToken( /*String|int*/ Object _) {}

/// An opaque token used to represent a cursor for pagination.
extension type Cursor(String _) {}

/// Generic metadata passed with most requests, can be anything.
extension type Meta.fromMap(Map<String, Object?> _value) {}

/// A "mixin"-like extension type for any extension type that contains a
/// [ProgressToken] at the key "progressToken".
///
/// Should be "mixed in" by implementing this type from other extension types.
extension type WithProgressToken.fromMap(Map<String, Object?> _value) {
  ProgressToken? get progressToken => _value['progressToken'] as ProgressToken?;
}

/// A [Meta] object with a known progress token key.
///
/// Has arbitrary other keys.
extension type MetaWithProgressToken.fromMap(Map<String, Object?> _value)
    implements Meta, WithProgressToken {}

/// Base interface for all request types.
///
/// Should not be constructed directly, and has no public constructor.
extension type Request._fromMap(Map<String, Object?> _value) {
  /// If specified, the caller is requesting out-of-band progress notifications
  /// for this request (as represented by notifications/progress). The value of
  /// this parameter is an opaque token that will be attached to any subsequent
  /// notifications. The receiver is not obligated to provide these
  /// notifications.
  MetaWithProgressToken? get meta => _value['_meta'] as MetaWithProgressToken?;
}

/// Base interface for all notifications.
extension type Notification(Map<String, Object?> _value) implements Request {
  /// This parameter name is reserved by MCP to allow clients and servers to
  /// attach additional metadata to their notifications.
  Meta? get meta => _value['_meta'] as Meta?;
}

/// Base interface for all responses to requests.
extension type Result(Map<String, Object?> _value) {
  Meta? get meta => _value['_meta'] as Meta?;
}

/// A response that indicates success but carries no data.
extension type EmptyResult.fromMap(Map<String, Object?> _) implements Result {
  factory EmptyResult() => EmptyResult.fromMap(const {});
}

/// This notification can be sent by either side to indicate that it is
/// cancelling a previously-issued request.
///
///  The request SHOULD still be in-flight, but due to communication latency, it
/// is always possible that this notification MAY arrive after the request has
/// already finished.
///
///  This notification indicates that the result will be unused, so any
///  associated processing SHOULD cease.
///
///  A client MUST NOT attempt to cancel its `initialize` request.
extension type CancelledNotification.fromMap(Map<String, Object?> _value)
    implements Notification {
  static const methodName = 'notifications/cancelled';

  factory CancelledNotification({
    required RequestId requestId,
    String? reason,
    Meta? meta,
  }) {
    return CancelledNotification.fromMap({
      'requestId': requestId,
      if (reason != null) 'reason': reason,
      if (meta != null) '_meta': meta,
    });
  }

  /// The ID of the request to cancel.
  ///
  /// This MUST correspond to the ID of a request previously issued in the same
  /// direction.
  RequestId? get requestId => _value['requestId'] as RequestId?;

  /// An optional string describing the reason for the cancellation. This MAY be
  /// logged or presented to the user.
  String? get reason => _value['reason'] as String?;
}

/// An opaque request ID.
extension type RequestId( /*String|int*/ Parameter _) {}

/// This request is sent from the client to the server when it first connects,
/// asking it to begin initialization.
extension type InitializeRequest._fromMap(Map<String, Object?> _value)
    implements Request {
  static const methodName = 'initialize';

  factory InitializeRequest({
    required String protocolVersion,
    required ClientCapabilities capabilities,
    required ClientImplementation clientInfo,
    Meta? meta,
  }) => InitializeRequest._fromMap({
    'protocolVersion': protocolVersion,
    'capabilities': capabilities,
    'clientInfo': clientInfo,
    if (meta != null) 'meta': meta,
  });

  /// The latest version of the Model Context Protocol that the client supports.
  /// The client MAY decide to support older versions as well.
  String get protocolVersion => _value['protocolVersion'] as String;
  ClientCapabilities get capabilities =>
      _value['capabilities'] as ClientCapabilities;
  ClientImplementation get clientInfo =>
      _value['clientInfo'] as ClientImplementation;
}

/// After receiving an initialize request from the client, the server sends
/// this response.
extension type InitializeResult.fromMap(Map<String, Object?> _value)
    implements Result {
  factory InitializeResult({
    required String protocolVersion,
    required ServerCapabilities serverCapabilities,
    required ServerImplementation serverInfo,
    String? instructions,
  }) => InitializeResult.fromMap({
    'protocolVersion': protocolVersion,
    'capabilities': serverCapabilities,
    'serverInfo': serverInfo,
    'instructions': instructions,
  });

  /// The version of the Model Context Protocol that the server wants to use.
  /// This may not match the version that the client requested. If the client
  /// cannot support this version, it MUST disconnect.
  String get protocolVersion => _value['protocolVersion'] as String;

  ServerCapabilities get capabilities =>
      _value['capabilities'] as ServerCapabilities;

  ServerImplementation get serverInfo =>
      _value['serverInfo'] as ServerImplementation;

  /// Instructions describing how to use the server and its features.
  ///
  /// This can be used by clients to improve the LLM's understanding of
  /// available tools, resources, etc. It can be thought of like a "hint" to the
  /// model. For example, this information MAY be added to the system prompt.
  String? get instructions => _value['instructions'] as String?;
}

/// This notification is sent from the client to the server after initialization
/// has finished.
extension type InitializedNotification.fromMap(Map<String, Object?> _value)
    implements Notification {
  static const methodName = 'notifications/initialized';

  factory InitializedNotification({Meta? meta}) =>
      InitializedNotification.fromMap({if (meta != null) '_meta': meta});
}

/// Capabilities a client may support. Known capabilities are defined here, in
/// this schema, but this is not a closed set: any client can define its own,
/// additional capabilities.
extension type ClientCapabilities.fromMap(Map<String, Object?> _value) {
  factory ClientCapabilities({
    Map<String, Object?>? experimental,
    RootsCapabilities? roots,
    Map<String, Object?>? sampling,
  }) => ClientCapabilities.fromMap({
    if (experimental != null) 'experimental': experimental,
    if (roots != null) 'roots': roots,
    if (sampling != null) 'sampling': sampling,
  });

  /// Experimental, non-standard capabilities that the client supports.
  Parameter? get experimental => _value['experimental'] as Parameter?;

  /// Present if the client supports any capabilities regarding roots.
  RootsCapabilities? get roots => _value['roots'] as RootsCapabilities?;

  /// Present if the client supports sampling from an LLM.
  Map<String, Object?>? get sampling =>
      (_value['sampling'] as Map?)?.cast<String, Object?>();
}

/// Whether the client supports notifications for changes to the roots list.
extension type RootsCapabilities.fromMap(Map<String, Object?> _value) {
  /// Present if the client supports listing roots.
  bool? get listChanged => _value['listChanged'] as bool?;
}

/// Capabilities that a server may support. Known capabilities are defined here,
/// in this schema, but this is not a closed set: any server can define its own,
/// additional capabilities.
extension type ServerCapabilities.fromMap(Map<String, Object?> _value) {
  factory ServerCapabilities({
    Map<String, Object?>? experimental,
    Map<String, Object?>? logging,
    Prompts? prompts,
    Resources? resources,
    Tools? tools,
  }) => ServerCapabilities.fromMap({
    if (experimental != null) 'experimental': experimental,
    if (logging != null) 'logging': logging,
    if (prompts != null) 'prompts': prompts,
    if (resources != null) 'resources': resources,
    if (tools != null) 'tools': tools,
  });

  /// Experimental, non-standard capabilities that the server supports.
  Map<String, Object?>? get experimental =>
      (_value['experimental'] as Map?)?.cast<String, Object?>();

  /// Present if the server supports sending log messages to the client.
  Map<String, Object?>? get logging =>
      (_value['logging'] as Map?)?.cast<String, Object?>();

  /// Present if the server offers any prompt templates.
  Prompts? get prompts => _value['prompts'] as Prompts?;

  /// Whether this server supports subscribing to resource updates.
  Resources? get resources => _value['resources'] as Resources?;

  /// Present if the server offers any tools to call.
  Tools? get tools => _value['tools'] as Tools?;

  /// Sets [tools] if it is null, otherwise throws.
  ///
  // TODO: Add more setters for other types?
  set tools(Tools? value) {
    assert(tools == null);
    _value['tools'] = value;
  }
}

/// Prompts parameter for [ServerCapabilities].
extension type Prompts.fromMap(Map<String, Object?> _value) {
  factory Prompts({bool? listChanged}) =>
      Prompts.fromMap({if (listChanged != null) 'listChanged': listChanged});

  /// Whether this server supports notifications for changes to the prompt list.
  bool? get listChanged => _value['listChanged'] as bool?;
}

/// Resources parameter for [ServerCapabilities].
extension type Resources.fromMap(Map<String, Object?> _value) {
  factory Resources({bool? listChanged, bool? subscribe}) => Resources.fromMap({
    if (listChanged != null) 'listChanged': listChanged,
    if (subscribe != null) 'subscribe': subscribe,
  });

  /// Whether this server supports notifications for changes to the resource
  /// list.
  bool? get listChanged => _value['listChanged'] as bool?;

  /// Present if the server offers any resources to read.
  bool? get subscribe => _value['subscribe'] as bool?;
}

/// Tools parameter for [ServerCapabilities].
extension type Tools.fromMap(Map<String, Object?> _value) {
  factory Tools({bool? listChanged}) =>
      Tools.fromMap({if (listChanged != null) 'listChanged': listChanged});

  /// Whether this server supports notifications for changes to the tool list.
  bool? get listChanged => _value['listChanged'] as bool?;

  /// Sets whether [listChanged] is supported.
  set listChanged(bool? value) {
    assert(listChanged == null);
    _value['listChanged'] = value;
  }
}

/// Describes the name and version of an MCP implementation.
extension type ClientImplementation.fromMap(Map<String, Object?> _value) {
  factory ClientImplementation({
    required String name,
    required String version,
  }) => ClientImplementation.fromMap({'name': name, 'version': version});

  String get name => _value['name'] as String;
  String get version => _value['version'] as String;
}

/// Describes the name and version of an MCP implementation.
extension type ServerImplementation.fromMap(Map<String, Object?> _value) {
  factory ServerImplementation({
    required String name,
    required String version,
  }) => ServerImplementation.fromMap({'name': name, 'version': version});

  String get name => _value['name'] as String;
  String get version => _value['version'] as String;
}

// /* Ping */
// /**
//  * A ping, issued by either the server or the client, to check that the other
//  * party is still alive. The receiver must promptly respond, or else may be
//  * disconnected.
//  */
// export interface PingRequest extends Request {
//   method: "ping";
// }

// /* Progress notifications */
// /**
//  * An out-of-band notification used to inform the receiver of a progress
//  * update for a long-running request.
//  */
// export interface ProgressNotification extends Notification {
//   method: "notifications/progress";
//   params: {
//     /**
//      * The progress token which was given in the initial request, used to
//      * associate this notification with the request that is proceeding.
//      */
//     progressToken: ProgressToken;
//     /**
//      * The progress thus far. This should increase every time progress is
//      * made, even if the total is unknown.
//      *
//      * @TJS-type number
//      */
//     progress: number;
//     /**
//      * Total number of items to process (or total progress required), if
//      * known.
//      *
//      * @TJS-type number
//      */
//     total?: number;
//   };
// }

/// A "mixin"-like extension type for any request that contains a [Cursor] at
/// the key "cursor".
///
/// Should be "mixed in" by implementing this type from other extension types.
///
/// This type is not intended to be constructed directly and thus has no public
/// constructor.
extension type PaginatedRequest._fromMap(Map<String, Object?> _value)
    implements Request {
  /// An opaque token representing the current pagination position.
  /// If provided, the server should return results starting after this cursor.
  Cursor? get cursor => _value['cursor'] as Cursor?;
}

/// A "mixin"-like extension type for any result type that contains a [Cursor]
/// at the key "cursor".
///
/// Should be "mixed in" by implementing this type from other extension types.
///
/// This type is not intended to be constructed directly and thus has no public
/// constructor.
extension type PaginatedResult._fromMap(Map<String, Object?> _value)
    implements Result {
  Cursor? get cursor => _value['cursor'] as Cursor?;
}

// /* Resources */
// /**
//  * Sent from the client to request a list of resources the server has.
//  */
// export interface ListResourcesRequest extends PaginatedRequest {
//   method: "resources/list";
// }

// /**
//  * The server's response to a resources/list request from the client.
//  */
// export interface ListResourcesResult extends PaginatedResult {
//   resources: Resource[];
// }

// /**
//  * Sent from the client to request a list of resource templates the server
//  * has.
//  */
// export interface ListResourceTemplatesRequest extends PaginatedRequest {
//   method: "resources/templates/list";
// }

// /**
//  * The server's response to a resources/templates/list request from the client.
//  */
// export interface ListResourceTemplatesResult extends PaginatedResult {
//   resourceTemplates: ResourceTemplate[];
// }

// /**
//  * Sent from the client to the server, to read a specific resource URI.
//  */
// export interface ReadResourceRequest extends Request {
//   method: "resources/read";
//   params: {
//     /**
//      * The URI of the resource to read. The URI can use any protocol; it is
//      * up to the server how to interpret it.
//      *
//      * @format uri
//      */
//     uri: string;
//   };
// }

// /**
//  * The server's response to a resources/read request from the client.
//  */
// export interface ReadResourceResult extends Result {
//   contents: (TextResourceContents | BlobResourceContents)[];
// }

// /**
//  * An optional notification from the server to the client, informing it that
//  * the list of resources it can read from has changed. This may be issued by
//  * servers without any previous subscription from the client.
//  */
// export interface ResourceListChangedNotification extends Notification {
//   method: "notifications/resources/list_changed";
// }

// /**
//  * Sent from the client to request resources/updated notifications from the
//  * server whenever a particular resource changes.
//  */
// export interface SubscribeRequest extends Request {
//   method: "resources/subscribe";
//   params: {
//     /**
//      * The URI of the resource to subscribe to. The URI can use any protocol;
//      * it is up to the server how to interpret it.
//      *
//      * @format uri
//      */
//     uri: string;
//   };
// }

// /**
//  * Sent from the client to request cancellation of resources/updated
//  * notifications from the server. This should follow a previous
//  * resources/subscribe request.
//  */
// export interface UnsubscribeRequest extends Request {
//   method: "resources/unsubscribe";
//   params: {
//     /**
//      * The URI of the resource to unsubscribe from.
//      *
//      * @format uri
//      */
//     uri: string;
//   };
// }

// /**
//  * A notification from the server to the client, informing it that a resource
//  * has changed and may need to be read again. This should only be sent if the
//  * client previously sent a resources/subscribe request.
//  */
// export interface ResourceUpdatedNotification extends Notification {
//   method: "notifications/resources/updated";
//   params: {
//     /**
//      * The URI of the resource that has been updated. This might be a
//      * sub-resource of the one that the client actually subscribed to.
//      *
//      * @format uri
//      */
//     uri: string;
//   };
// }

// /**
//  * A known resource that the server is capable of reading.
//  */
// export interface Resource extends Annotated {
//   /**
//    * The URI of this resource.
//    *
//    * @format uri
//    */
//   uri: string;

//   /**
//    * A human-readable name for this resource.
//    *
//    * This can be used by clients to populate UI elements.
//    */
//   name: string;

//   /**
//    * A description of what this resource represents.
//    *
//    * This can be used by clients to improve the LLM's understanding of
//    * available resources. It can be thought of like a "hint" to the model.
//    */
//   description?: string;

//   /**
//    * The MIME type of this resource, if known.
//    */
//   mimeType?: string;

//   /**
//    * The size of the raw resource content, in bytes (i.e., before base64
//    * encoding or any tokenization), if known.
//    *
//    * This can be used by Hosts to display file sizes and estimate context
//    * window usage.
//    */
//   size?: number;
// }

// /**
//  * A template description for resources available on the server.
//  */
// export interface ResourceTemplate extends Annotated {
//   /**
//    * A URI template (according to RFC 6570) that can be used to construct
//    * resource URIs.
//    *
//    * @format uri-template
//    */
//   uriTemplate: string;

//   /**
//    * A human-readable name for the type of resource this template refers to.
//    *
//    * This can be used by clients to populate UI elements.
//    */
//   name: string;

//   /**
//    * A description of what this template is for.
//    *
//    * This can be used by clients to improve the LLM's understanding of
//    * available resources. It can be thought of like a "hint" to the model.
//    */
//   description?: string;

//   /**
//    * The MIME type for all resources that match this template. This should
//    * only be included if all resources matching this template have the same
//    * type.
//    */
//   mimeType?: string;
// }

// /* Prompts */
// /**
//  * Sent from the client to request a list of prompts and prompt templates the
//  * server has.
//  */
// export interface ListPromptsRequest extends PaginatedRequest {
//   method: "prompts/list";
// }

// /**
//  * The server's response to a prompts/list request from the client.
//  */
// export interface ListPromptsResult extends PaginatedResult {
//   prompts: Prompt[];
// }

// /**
//  * Used by the client to get a prompt provided by the server.
//  */
// export interface GetPromptRequest extends Request {
//   method: "prompts/get";
//   params: {
//     /**
//      * The name of the prompt or prompt template.
//      */
//     name: string;
//     /**
//      * Arguments to use for templating the prompt.
//      */
//     arguments?: { [key: string]: string };
//   };
// }

// /**
//  * The server's response to a prompts/get request from the client.
//  */
// export interface GetPromptResult extends Result {
//   /**
//    * An optional description for the prompt.
//    */
//   description?: string;
//   messages: PromptMessage[];
// }

// /**
//  * A prompt or prompt template that the server offers.
//  */
// export interface Prompt {
//   /**
//    * The name of the prompt or prompt template.
//    */
//   name: string;
//   /**
//    * An optional description of what this prompt provides
//    */
//   description?: string;
//   /**
//    * A list of arguments to use for templating the prompt.
//    */
//   arguments?: PromptArgument[];
// }

// /**
//  * Describes an argument that a prompt can accept.
//  */
// export interface PromptArgument {
//   /**
//    * The name of the argument.
//    */
//   name: string;
//   /**
//    * A human-readable description of the argument.
//    */
//   description?: string;
//   /**
//    * Whether this argument must be provided.
//    */
//   required?: boolean;
// }

// /**
//  * The sender or recipient of messages and data in a conversation.
//  */
// export type Role = "user" | "assistant";

// /**
//  * Describes a message returned as part of a prompt.
//  *
//  * This is similar to `SamplingMessage`, but also supports the embedding of
//  * resources from the MCP server.
//  */
// export interface PromptMessage {
//   role: Role;
//   content: TextContent | ImageContent | EmbeddedResource;
// }

// /**
//  * An optional notification from the server to the client, informing it that
//  * the list of prompts it offers has changed. This may be issued by servers
//  * without any previous subscription from the client.
//  */
// export interface PromptListChangedNotification extends Notification {
//   method: "notifications/prompts/list_changed";
// }

/// Sent from the client to request a list of tools the server has.
extension type ListToolsRequest.fromMap(Map<String, Object?> _value)
    implements PaginatedRequest {
  static const methodName = 'tools/list';

  factory ListToolsRequest({Cursor? cursor, Meta? meta}) =>
      ListToolsRequest.fromMap({
        if (cursor != null) 'cursor': cursor,
        if (meta != null) '_meta': meta,
      });
}

/// The server's response to a tools/list request from the client.
extension type ListToolsResult.fromMap(Map<String, Object?> _value)
    implements PaginatedResult {
  factory ListToolsResult({
    required List<Tool> tools,
    Cursor? cursor,
    Meta? meta,
  }) => ListToolsResult.fromMap({
    'tools': tools,
    if (cursor != null) 'cursor': cursor,
    if (meta != null) '_meta': meta,
  });

  List<Tool> get tools => (_value['tools'] as List).cast<Tool>();
}

/// The server's response to a tool call.
///
/// Any errors that originate from the tool SHOULD be reported inside the result
/// object, with `isError` set to true, _not_ as an MCP protocol-level error
/// response. Otherwise, the LLM would not be able to see that an error occurred
/// and self-correct.
///
/// However, any errors in _finding_ the tool, an error indicating that the
/// server does not support tool calls, or any other exceptional conditions,
/// should be reported as an MCP error response.
extension type CallToolResult.fromMap(Map<String, Object?> _value)
    implements Result {
  factory CallToolResult({
    Meta? meta,
    required List<UnionType> content,
    bool? isError,
  }) => CallToolResult.fromMap({
    'content': content,
    if (isError != null) 'isError': isError,
    if (meta != null) '_meta': meta,
  });

  /// The type of content, either [TextContent], [ImageContent],
  /// or [EmbeddedResource],
  List<UnionType> get content => (_value['content'] as List).cast<UnionType>();

  /// Whether the tool call ended in an error.
  ///
  /// If not set, this is assumed to be false (the call was successful).
  bool? get isError => _value['isError'] as bool?;
}

/// The response type used when something returns more than one type.
///
/// Can wrap any response type, but it must have a `type` key.
///
/// Should be used by doing a `switch` on the type, and then calling the
/// `fromMap` constructor on the appropriate type.
extension type UnionType._(Map<String, Object?> _value) {
  factory UnionType(Map<String, Object?> value) {
    assert(value.containsKey('type'));
    return UnionType._(value);
  }
}

/// Text provided to an LLM.
///
// TODO: implement `Annotated`.
extension type TextContent.fromMap(Map<String, Object?> _value)
    implements UnionType {
  static const expectedType = 'type';

  factory TextContent({required String text}) =>
      TextContent.fromMap({'text': text, 'type': expectedType});

  String get type {
    final type = _value['type'] as String;
    assert(type == expectedType);
    return type;
  }

  /// The text content.
  String get text => _value['text'] as String;
}

/// An image provided to an LLM.
///
// TODO: implement `Annotated`.
extension type ImageContent.fromMap(Map<String, Object?> _value)
    implements UnionType {
  static const expectedType = 'image';

  factory ImageContent({required String data, required String mimeType}) =>
      ImageContent.fromMap({
        'data': data,
        'mimeType': mimeType,
        'type': expectedType,
      });

  String get type {
    final type = _value['type'] as String;
    assert(type == expectedType);
    return type;
  }

  /// If the [type] is `image`, this is the base64 encoded image data.
  String get data => _value['data'] as String;

  /// If the [type] is `image`, the MIME type of the image. Different providers
  /// may support different image types.
  String get mimeType => _value['mimeType'] as String;
}

/// The contents of a resource, embedded into a prompt or tool call result.
///
/// It is up to the client how best to render embedded resources for the benefit
/// of the LLM and/or the user.
///
// TODO: implement `Annotated`.
extension type EmbeddedResource.fromMap(Map<String, Object?> _value)
    implements UnionType {
  static const expectedType = 'resource';

  factory EmbeddedResource({required UnionType resource}) =>
      EmbeddedResource.fromMap({'resource': resource, 'type': expectedType});

  String get type {
    final type = _value['resource'] as String;
    assert(type == expectedType);
    return type;
  }

  /// Either [TextResourceContents] or [BlobResourceContents].
  UnionType get resource => _value['resource'] as UnionType;

  String? get mimeType => _value['mimeType'] as String?;
}

/// Base class for the contents of a specific resource or sub-resource.
extension type ResourceContentsResult.fromMap(Map<String, Object?> _value) {
  factory ResourceContentsResult({required String uri, String? mimeType}) =>
      ResourceContentsResult.fromMap({
        'uri': uri,
        if (mimeType != null) 'mimeType': mimeType,
      });

  /// The URI of this resource.
  String get uri => _value['uri'] as String;

  /// The MIME type of this resource, if known.
  String? get mimeType => _value['mimeType'] as String?;
}

/// A [ResourceContentsResult] that contains text.
extension type TextResourceContents.fromMap(Map<String, Object?> _value)
    implements ResourceContentsResult {
  factory TextResourceContents({
    required String uri,
    required String text,
    String? mimeType,
  }) => TextResourceContents.fromMap({
    'uri': uri,
    'text': text,
    if (mimeType != null) 'mimeType': mimeType,
  });

  /// The text of the item. This must only be set if the item can actually be
  /// represented as text (not binary data).
  String get text => _value['text'] as String;
}

/// A [ResourceContentsResult] that contains binary data encoded as base64.
extension type BlobResourceContents.fromJson(Map<String, Object?> _value)
    implements ResourceContentsResult {
  factory BlobResourceContents({
    required String uri,
    required String blob,
    String? mimeType,
  }) => BlobResourceContents.fromJson({
    'uri': uri,
    'blob': blob,
    if (mimeType != null) 'mimeType': mimeType,
  });

  /// A base64-encoded string representing the binary data of the item.
  String get blob => _value['blob'] as String;
}

/// Used by the client to invoke a tool provided by the server.
extension type CallToolRequest._fromMap(Map<String, Object?> _value)
    implements Request {
  static const methodName = 'tools/call';

  factory CallToolRequest({
    required String name,
    Map<String, Object?>? arguments,
    Meta? meta,
  }) => CallToolRequest._fromMap({
    'name': name,
    if (arguments != null) 'arguments': arguments,
    if (meta != null) 'meta': meta,
  });

  /// The name of the method to invoke.
  String get name => _value['name'] as String;

  /// The arguments to pass to the method.
  Map<String, Object?>? get arguments =>
      (_value['arguments'] as Map?)?.cast<String, Object?>();
}

// /**
//  * An optional notification from the server to the client, informing it that
//  * the list of tools it offers has changed. This may be issued by servers
//  * without any previous subscription from the client.
//  */
// export interface ToolListChangedNotification extends Notification {
//   method: "notifications/tools/list_changed";
// }

/// Definition for a tool the client can call.
extension type Tool.fromMap(Map<String, Object?> _value) {
  factory Tool({
    required String name,
    String? description,
    required InputSchema inputSchema,
  }) => Tool.fromMap({
    'name': name,
    if (description != null) 'description': description,
    'inputSchema': inputSchema,
  });

  /// The name of the tool.
  String get name => _value['name'] as String;

  /// A human-readable description of the tool.
  String? get description => _value['description'] as String?;

  /// A JSON Schema object defining the expected parameters for the tool.
  InputSchema get inputSchema => _value['inputSchema'] as InputSchema;
}

/// A JSON Schema object defining the expected parameters for the tool.
extension type InputSchema.fromMap(Map<String, Object?> _value) {
  factory InputSchema({
    Map<String, Object?>? properties,
    List<String>? required,
  }) => InputSchema.fromMap({
    'type': 'object',
    if (properties != null) 'properties': properties,
    if (required != null) 'required': required,
  });

  String get type => _value['type'] as String;

  Map<String, Object?>? get properties =>
      (_value['properties'] as Map?)?.cast<String, Object?>();

  List<String>? get required => (_value['required'] as List?)?.cast<String>();
}

// /* Logging */
// /**
//  * A request from the client to the server, to enable or adjust logging.
//  */
// export interface SetLevelRequest extends Request {
//   method: "logging/setLevel";
//   params: {
//     /**
//      * The level of logging that the client wants to receive from the server.
//      * The server should send all logs at this level and higher (i.e., more
//      * severe) to the client as notifications/message.
//      */
//     level: LoggingLevel;
//   };
// }

// /**
//  * Notification of a log message passed from server to client. If no logging/setLevel request has been sent from the client, the server MAY decide which messages to send automatically.
//  */
// export interface LoggingMessageNotification extends Notification {
//   method: "notifications/message";
//   params: {
//     /**
//      * The severity of this log message.
//      */
//     level: LoggingLevel;
//     /**
//      * An optional name of the logger issuing this message.
//      */
//     logger?: string;
//     /**
//      * The data to be logged, such as a string message or an object. Any JSON
//      * serializable type is allowed here.
//      */
//     data: unknown;
//   };
// }

// /**
//  * The severity of a log message.
//  *
//  * These map to syslog message severities, as specified in RFC-5424:
//  * https://datatracker.ietf.org/doc/html/rfc5424#section-6.2.1
//  */
// export type LoggingLevel =
//   | "debug"
//   | "info"
//   | "notice"
//   | "warning"
//   | "error"
//   | "critical"
//   | "alert"
//   | "emergency";

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

// /**
//  * Identifies a prompt.
//  */
// export interface PromptReference {
//   type: "ref/prompt";
//   /**
//    * The name of the prompt or prompt template
//    */
//   name: string;
// }

// /* Roots */
// /**
//  * Sent from the server to request a list of root URIs from the client. Roots
//  * allow servers to ask for specific directories or files to operate on. A
//  * common example for roots is providing a set of repositories or directories
//  * a server should operate on.
//  *
//  * This request is typically used when the server needs to understand the
//  * file system structure or access specific locations that the client has
//  * permission to read from.
//  */
// export interface ListRootsRequest extends Request {
//   method: "roots/list";
// }

// /**
//  * The client's response to a roots/list request from the server.
//  * This result contains an array of Root objects, each representing a root
//  * directory or file that the server can operate on.
//  */
// export interface ListRootsResult extends Result {
//   roots: Root[];
// }

// /**
//  * Represents a root directory or file that the server can operate on.
//  */
// export interface Root {
//   /**
//    * The URI identifying the root. This *must* start with file:// for now.
//    * This restriction may be relaxed in future versions of the protocol to
//    * allow other URI schemes.
//    *
//    * @format uri
//    */
//   uri: string;
//   /**
//    * An optional name for the root. This can be used to provide a
//    * human-readable identifier for the root, which may be useful for display
//    * purposes or for referencing the root in other parts of the application.
//    */
//   name?: string;
// }

// /**
//  * A notification from the client to the server, informing it that the list
//  * of roots has changed.
//  * This notification should be sent whenever the client adds, removes, or
//  * modifies any root.
//  * The server should then request an updated list of roots using the
//  * ListRootsRequest.
//  */
// export interface RootsListChangedNotification extends Notification {
//   method: "notifications/roots/list_changed";
// }

// /* Client messages */
// export type ClientRequest =
//   | PingRequest
//   | InitializeRequest
//   | CompleteRequest
//   | SetLevelRequest
//   | GetPromptRequest
//   | ListPromptsRequest
//   | ListResourcesRequest
//   | ListResourceTemplatesRequest
//   | ReadResourceRequest
//   | SubscribeRequest
//   | UnsubscribeRequest
//   | CallToolRequest
//   | ListToolsRequest;

// export type ClientNotification =
//   | CancelledNotification
//   | ProgressNotification
//   | InitializedNotification
//   | RootsListChangedNotification;

// export type ClientResult = EmptyResult | CreateMessageResult
//   | ListRootsResult;

// /* Server messages */
// export type ServerRequest =
//   | PingRequest
//   | CreateMessageRequest
//   | ListRootsRequest;

// export type ServerNotification =
//   | CancelledNotification
//   | ProgressNotification
//   | LoggingMessageNotification
//   | ResourceUpdatedNotification
//   | ResourceListChangedNotification
//   | ToolListChangedNotification
//   | PromptListChangedNotification;

// export type ServerResult =
//   | EmptyResult
//   | InitializeResult
//   | CompleteResult
//   | GetPromptResult
//   | ListPromptsResult
//   | ListResourcesResult
//   | ListResourceTemplatesResult
//   | ReadResourceResult
//   | CallToolResult
//   | ListToolsResult;
