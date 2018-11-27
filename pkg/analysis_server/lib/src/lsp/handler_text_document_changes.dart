// Copyright (c) 2018, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:analysis_server/lsp_protocol/protocol_generated.dart';
import 'package:analysis_server/src/lsp/handlers/handlers.dart';
import 'package:analysis_server/src/lsp/lsp_analysis_server.dart';
import 'package:analysis_server/src/lsp/mapping.dart';
import 'package:analysis_server/src/lsp/source_edits.dart';

class TextDocumentChangeHandler
    extends MessageHandler<DidChangeTextDocumentParams, void> {
  TextDocumentChangeHandler(LspAnalysisServer server) : super(server);
  Method get handlesMessage => Method.textDocument_didChange;

  @override
  DidChangeTextDocumentParams convertParams(Map<String, dynamic> json) =>
      DidChangeTextDocumentParams.fromJson(json);

  void handle(DidChangeTextDocumentParams params) {
    final path = pathOf(params.textDocument);
    final oldContents = server.fileContentOverlay[path];
    // TODO(dantup): Should we be tracking the version?

    // Visual Studio has been seen to skip didOpen notifications for files that
    // were already open when the LSP server initialized, so handle this with
    // a specific message to make it clear what's happened.
    if (oldContents == null) {
      throw new ResponseError(
        ErrorCodes.InvalidParams,
        'Unable to edit document because the file was not previously opened: $path',
        null,
      );
    }
    final newContents = applyEdits(oldContents, params.contentChanges);

    server.updateOverlay(path, newContents);
  }
}

class TextDocumentCloseHandler
    extends MessageHandler<DidCloseTextDocumentParams, void> {
  TextDocumentCloseHandler(LspAnalysisServer server) : super(server);
  Method get handlesMessage => Method.textDocument_didClose;

  @override
  DidCloseTextDocumentParams convertParams(Map<String, dynamic> json) =>
      DidCloseTextDocumentParams.fromJson(json);

  void handle(DidCloseTextDocumentParams params) {
    final path = pathOf(params.textDocument);
    server.updateOverlay(path, null);
  }
}

class TextDocumentOpenHandler
    extends MessageHandler<DidOpenTextDocumentParams, void> {
  TextDocumentOpenHandler(LspAnalysisServer server) : super(server);
  Method get handlesMessage => Method.textDocument_didOpen;

  @override
  DidOpenTextDocumentParams convertParams(Map<String, dynamic> json) =>
      DidOpenTextDocumentParams.fromJson(json);

  void handle(DidOpenTextDocumentParams params) {
    final doc = params.textDocument;
    final path = Uri.parse(doc.uri).toFilePath();
    // TODO(dantup): Keep track of versions, so that when we compute fixes etc.
    // we can send them back versions so the client can drop them if the document
    // has been modified.

    server.updateOverlay(path, doc.text);

    // If the file did not exist, and is "overlay only", it still should be
    // analyzed. Add it to driver to which it should have been added.
    server.contextManager.getDriverFor(path)?.addFile(path);
  }
}