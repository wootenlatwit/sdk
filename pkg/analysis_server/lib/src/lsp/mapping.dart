import 'dart:collection';

import 'package:analysis_server/lsp_protocol/protocol_generated.dart' as lsp;
import 'package:analysis_server/lsp_protocol/protocol_generated.dart';
import 'package:analysis_server/lsp_protocol/protocol_special.dart' as lsp;
import 'package:analysis_server/src/lsp/dartdoc.dart';
import 'package:analysis_server/src/lsp/lsp_analysis_server.dart' as lsp;
import 'package:analysis_server/src/protocol_server.dart' as server
    hide AnalysisError;
import 'package:analyzer/dart/analysis/results.dart' as server;
import 'package:analyzer/error/error.dart' as server;
import 'package:analyzer/source/line_info.dart' as server;
import 'package:analyzer/src/generated/source.dart' as server;

const languageSourceName = 'dart';

lsp.Either2<String, lsp.MarkupContent> asStringOrMarkupContent(
    List<lsp.MarkupKind> preferredFormats, String content) {
  if (content == null) {
    return null;
  }

  return preferredFormats == null
      ? new lsp.Either2<String, lsp.MarkupContent>.t1(content)
      : new lsp.Either2<String, lsp.MarkupContent>.t2(
          _asMarkup(preferredFormats, content));
}

lsp.MarkupContent _asMarkup(
    List<lsp.MarkupKind> preferredFormats, String content) {
  // It's not valid to call this function with a null format, as null formats
  // do not support MarkupContent. [asStringOrMarkupContent] is probably the
  // better choice.
  assert(preferredFormats != null);

  if (content == null) {
    return null;
  }

  if (preferredFormats.isEmpty) {
    preferredFormats.add(lsp.MarkupKind.Markdown);
  }

  final supportsMarkdown = preferredFormats.contains(lsp.MarkupKind.Markdown);
  final supportsPlain = preferredFormats.contains(lsp.MarkupKind.PlainText);
  // Since our PlainText version is actually just Markdown, only advertise it
  // as PlainText if the client explicitly supports PlainText and not Markdown.
  final format = supportsPlain && !supportsMarkdown
      ? lsp.MarkupKind.PlainText
      : lsp.MarkupKind.Markdown;

  return new lsp.MarkupContent(format, content);
}

lsp.CompletionItemKind elementKindToCompletionItemKind(
  HashSet<lsp.CompletionItemKind> clientSupportedCompletionKinds,
  server.ElementKind kind,
) {
  bool isSupported(lsp.CompletionItemKind kind) =>
      clientSupportedCompletionKinds.contains(kind);

  List<lsp.CompletionItemKind> getKindPreferences() {
    switch (kind) {
      case server.ElementKind.CLASS:
      case server.ElementKind.CLASS_TYPE_ALIAS:
        return const [lsp.CompletionItemKind.Class];
      case server.ElementKind.COMPILATION_UNIT:
        return const [lsp.CompletionItemKind.Module];
      case server.ElementKind.CONSTRUCTOR:
      case server.ElementKind.CONSTRUCTOR_INVOCATION:
        return const [lsp.CompletionItemKind.Constructor];
      case server.ElementKind.ENUM:
      case server.ElementKind.ENUM_CONSTANT:
        return const [lsp.CompletionItemKind.Enum];
      case server.ElementKind.FIELD:
        return const [lsp.CompletionItemKind.Field];
      case server.ElementKind.FILE:
        return const [lsp.CompletionItemKind.File];
      case server.ElementKind.FUNCTION:
      case server.ElementKind.FUNCTION_TYPE_ALIAS:
        return const [lsp.CompletionItemKind.Function];
      case server.ElementKind.GETTER:
        return const [lsp.CompletionItemKind.Property];
      case server.ElementKind.LABEL:
      case server.ElementKind.LIBRARY:
        return const [lsp.CompletionItemKind.Module];
      case server.ElementKind.LOCAL_VARIABLE:
        return const [lsp.CompletionItemKind.Variable];
      case server.ElementKind.METHOD:
        return const [lsp.CompletionItemKind.Method];
      case server.ElementKind.PARAMETER:
      case server.ElementKind.PREFIX:
        return const [lsp.CompletionItemKind.Variable];
      case server.ElementKind.SETTER:
        return const [lsp.CompletionItemKind.Property];
      case server.ElementKind.TOP_LEVEL_VARIABLE:
        return const [lsp.CompletionItemKind.Variable];
      case server.ElementKind.TYPE_PARAMETER:
        return const [
          lsp.CompletionItemKind.TypeParameter,
          lsp.CompletionItemKind.Variable,
        ];
      case server.ElementKind.UNIT_TEST_GROUP:
        return const [lsp.CompletionItemKind.Module];
      case server.ElementKind.UNIT_TEST_TEST:
        return const [lsp.CompletionItemKind.Method];
      default:
        return null;
    }
  }

  return getKindPreferences().firstWhere(isSupported, orElse: () => null);
}

String getCompletionDetail(
  server.CompletionSuggestion suggestion,
  lsp.CompletionItemKind completionKind,
  bool clientSupportsDeprecated,
) {
  final hasElement = suggestion.element != null;
  final hasParameters = hasElement &&
      suggestion.element.parameters != null &&
      suggestion.element.parameters.isNotEmpty;
  final hasReturnType = hasElement &&
      suggestion.element.returnType != null &&
      suggestion.element.returnType.isNotEmpty;
  final hasParameterType =
      suggestion.parameterType != null && suggestion.parameterType.isNotEmpty;

  final prefix = clientSupportsDeprecated || !suggestion.isDeprecated
      ? ''
      : '(Deprecated) ';

  if (completionKind == lsp.CompletionItemKind.Property) {
    // Setters appear as methods with one arg but they also cause getters to not
    // appear in the completion list, so displaying them as setters is misleading.
    // To avoid this, always show only the return type, whether it's a getter
    // or a setter.
    return prefix +
        (suggestion.element.kind == server.ElementKind.GETTER
            ? suggestion.element.returnType
            // Don't assume setters always have parameters
            // See https://github.com/dart-lang/sdk/issues/27747
            : suggestion.element.parameters != null &&
                    suggestion.element.parameters.isNotEmpty
                // Extract the type part from '(MyType value)`
                ? suggestion.element.parameters.substring(
                    1, suggestion.element.parameters.lastIndexOf(" "))
                : '');
  } else if (hasParameters && hasReturnType) {
    return '$prefix${suggestion.element.parameters} → ${suggestion.element.returnType}';
  } else if (hasReturnType) {
    return '$prefix${suggestion.element.returnType}';
  } else if (hasParameterType) {
    return '$prefix${suggestion.parameterType}';
  } else {
    return prefix;
  }
}

lsp.Location navigationTargetToLocation(String targetFilePath,
    server.NavigationTarget target, server.LineInfo lineInfo) {
  if (lineInfo == null) {
    return null;
  }

  return new Location(
    Uri.file(targetFilePath).toString(),
    toRange(lineInfo, target.offset, target.length),
  );
}

/// Returns the file system path for a TextDocumentIdentifier.
String pathOf(lsp.TextDocumentIdentifier doc) {
  final uri = Uri.tryParse(doc.uri);
  final isValidFileUri = (uri?.isScheme('file') ?? false);
  if (!isValidFileUri) {
    throw new ResponseError(lsp.ServerErrorCodes.InvalidFilePath,
        'URI was not a valid file:// URI', doc.uri);
  }
  try {
    return uri.toFilePath();
  } catch (e) {
    // Even if tryParse() works and file == scheme, toFilePath() can throw on
    // Windows if there are invalid characters.
    throw new ResponseError(lsp.ServerErrorCodes.InvalidFilePath,
        'File URI did not contain a valid file path', doc.uri);
  }
}

lsp.CompletionItemKind suggestionKindToCompletionItemKind(
  HashSet<lsp.CompletionItemKind> clientSupportedCompletionKinds,
  server.CompletionSuggestionKind kind,
  String label,
) {
  bool isSupported(lsp.CompletionItemKind kind) =>
      clientSupportedCompletionKinds.contains(kind);

  List<lsp.CompletionItemKind> getKindPreferences() {
    switch (kind) {
      case server.CompletionSuggestionKind.ARGUMENT_LIST:
        return const [lsp.CompletionItemKind.Variable];
      case server.CompletionSuggestionKind.IMPORT:
        // For package/relative URIs, we can send File/Folder kinds for better icons.
        if (!label.startsWith('dart:')) {
          return label.endsWith('.dart')
              ? const [
                  lsp.CompletionItemKind.File,
                  lsp.CompletionItemKind.Module,
                ]
              : const [
                  lsp.CompletionItemKind.Folder,
                  lsp.CompletionItemKind.Module,
                ];
        }
        return const [lsp.CompletionItemKind.Module];
      case server.CompletionSuggestionKind.IDENTIFIER:
        return const [lsp.CompletionItemKind.Variable];
      case server.CompletionSuggestionKind.INVOCATION:
        return const [lsp.CompletionItemKind.Method];
      case server.CompletionSuggestionKind.KEYWORD:
        return const [lsp.CompletionItemKind.Keyword];
      case server.CompletionSuggestionKind.NAMED_ARGUMENT:
        return const [lsp.CompletionItemKind.Variable];
      case server.CompletionSuggestionKind.OPTIONAL_ARGUMENT:
        return const [lsp.CompletionItemKind.Variable];
      case server.CompletionSuggestionKind.PARAMETER:
        return const [lsp.CompletionItemKind.Value];
      default:
        return null;
    }
  }

  return getKindPreferences().firstWhere(isSupported, orElse: () => null);
}

lsp.CompletionItem toCompletionItem(
  lsp.TextDocumentClientCapabilitiesCompletion completionCapabilities,
  HashSet<lsp.CompletionItemKind> supportedCompletionItemKinds,
  server.LineInfo lineInfo,
  server.CompletionSuggestion suggestion,
  int replacementOffset,
  int replacementLength,
) {
  final label = suggestion.displayText != null
      ? suggestion.displayText
      : suggestion.completion;

  final useSnippets =
      completionCapabilities?.completionItem?.snippetSupport == true;
  final useDeprecated =
      completionCapabilities?.completionItem?.deprecatedSupport == true;
  final formats = completionCapabilities?.completionItem?.documentationFormat;

  final completionKind = suggestion.element != null
      ? elementKindToCompletionItemKind(
          supportedCompletionItemKinds, suggestion.element.kind)
      : suggestionKindToCompletionItemKind(
          supportedCompletionItemKinds, suggestion.kind, label);

  return new lsp.CompletionItem(
    label,
    completionKind,
    getCompletionDetail(suggestion, completionKind, useDeprecated),
    asStringOrMarkupContent(formats, cleanDartdoc(suggestion.docComplete)),
    useDeprecated ? suggestion.isDeprecated : null,
    false, // preselect
    // Relevance is a number, highest being best. LSP does text sort so subtract
    // from a large number so that a text sort will result in the correct order.
    // 555 -> 999455
    //  10 -> 999990
    //   1 -> 999999
    (1000000 - suggestion.relevance).toString(),
    null, // filterText uses label if not set
    null, // insertText is deprecated, but also uses label if not set
    useSnippets ? lsp.InsertTextFormat.Snippet : lsp.InsertTextFormat.PlainText,
    new lsp.TextEdit(
      // TODO(dantup): If `clientSupportsSnippets == true` then we should map
      // `selection` in to a snippet (see how Dart Code does this).
      toRange(lineInfo, replacementOffset, replacementLength),
      suggestion.completion,
    ),
    [], // additionalTextEdits, used for adding imports, etc.
    [], // commitCharacters
    null, // command
    null, // data, useful for if using lazy resolve, this comes back to us
  );
}

lsp.Diagnostic toDiagnostic(
    server.LineInfo lineInfo, server.AnalysisError error,
    [server.ErrorSeverity errorSeverity]) {
  server.ErrorCode errorCode = error.errorCode;

  // Default to the error's severity if none is specified.
  errorSeverity ??= errorCode.errorSeverity;

  return new lsp.Diagnostic(
    toRange(lineInfo, error.offset, error.length),
    toDiagnosticSeverity(errorSeverity),
    errorCode.name.toLowerCase(),
    languageSourceName,
    error.message,
    null,
  );
}

lsp.DiagnosticSeverity toDiagnosticSeverity(server.ErrorSeverity severity) {
  switch (severity) {
    case server.ErrorSeverity.ERROR:
      return lsp.DiagnosticSeverity.Error;
    case server.ErrorSeverity.WARNING:
      return lsp.DiagnosticSeverity.Warning;
    case server.ErrorSeverity.INFO:
      return lsp.DiagnosticSeverity.Information;
    // Note: LSP also supports "Hint", but they won't render in things like the
    // VS Code errors list as they're apparently intended to communicate
    // non-visible diagnostics back (for example, if you wanted to grey out
    // unreachable code without producing an item in the error list).
    default:
      throw 'Unknown AnalysisErrorSeverity: $severity';
  }
}

int toOffset(server.LineInfo lineInfo, lsp.Position pos) {
  if (pos.line > lineInfo.lineCount) {
    throw new lsp.ResponseError(lsp.ServerErrorCodes.InvalidFileLineCol,
        'Invalid line number', pos.line);
  }
  // TODO(dantup): Is there any way to validate the character? We could ensure
  // it's less than the offset of the next line, but that would only work for
  // all lines except the last one.
  return lineInfo.getOffsetOfLine(pos.line) + pos.character;
}

lsp.Position toPosition(server.CharacterLocation location) {
  // LSP is zero-based, but analysis server is 1-based.
  return new lsp.Position(location.lineNumber - 1, location.columnNumber - 1);
}

lsp.Range toRange(server.LineInfo lineInfo, int offset, int length) {
  server.CharacterLocation start = lineInfo.getLocation(offset);
  server.CharacterLocation end = lineInfo.getLocation(offset + length);

  return new lsp.Range(
    toPosition(start),
    toPosition(end),
  );
}

lsp.SignatureHelp toSignatureHelp(List<lsp.MarkupKind> preferredFormats,
    server.AnalysisGetSignatureResult signature) {
  // For now, we only support returning one (though we may wish to use named
  // args. etc. to provide one for each possible "next" option when the cursor
  // is at the end ready to provide another argument).

  /// Gets the label for an individual parameter in the form
  ///     String s = 'foo'
  String getParamLabel(server.ParameterInfo p) {
    final def = p.defaultValue != null ? ' = ${p.defaultValue}' : '';
    return '${p.type} ${p.name}$def';
  }

  /// Gets the full signature label in the form
  ///     foo(String s, int i, bool a = true)
  String getSignatureLabel(server.AnalysisGetSignatureResult resp) {
    final req = signature.parameters
        .where((p) => p.kind == server.ParameterKind.REQUIRED)
        .toList();
    final opt = signature.parameters
        .where((p) => p.kind == server.ParameterKind.OPTIONAL)
        .toList();
    final named = signature.parameters
        .where((p) => p.kind == server.ParameterKind.NAMED)
        .toList();
    final params = [];
    if (req.isNotEmpty) {
      params.add(req.map(getParamLabel).join(", "));
    }
    if (opt.isNotEmpty) {
      params.add("[" + opt.map(getParamLabel).join(", ") + "]");
    }
    if (named.isNotEmpty) {
      params.add("{" + named.map(getParamLabel).join(", ") + "}");
    }
    return '${resp.name}(${params.join(", ")})';
  }

  lsp.ParameterInformation toParameterInfo(server.ParameterInfo param) {
    return new lsp.ParameterInformation(getParamLabel(param), null);
  }

  final cleanDoc = cleanDartdoc(signature.dartdoc);

  return new lsp.SignatureHelp(
    [
      new lsp.SignatureInformation(
        getSignatureLabel(signature),
        asStringOrMarkupContent(preferredFormats, cleanDoc),
        signature.parameters.map(toParameterInfo).toList(),
      ),
    ],
    0, // activeSignature
    null, // activeParameter
  );
}

lsp.Location searchResultToLocation(
    server.SearchResult result, server.LineInfo lineInfo) {
  final location = result.location;

  if (lineInfo == null) {
    return null;
  }

  return new Location(
    Uri.file(result.location.file).toString(),
    toRange(lineInfo, location.offset, location.length),
  );
}