/* --------------------------------------------------------------------------------------------
 * Copyright (c) Microsoft Corporation. All rights reserved.
 * Licensed under the MIT License. See License.txt in the project root for license information.
 * ------------------------------------------------------------------------------------------ */

import * as path from 'path';
import {
  DocumentSemanticTokensProvider,
  ExtensionContext,
  languages,
  Position,
  ProviderResult,
  Range,
  SemanticTokens,
  SemanticTokensBuilder,
  SemanticTokensLegend,
  TextDocument,
  workspace,
} from 'vscode';
import {
  LanguageClient,
  LanguageClientOptions,
  ServerOptions,
  TransportKind,
} from 'vscode-languageclient/node';

import { TokenType } from './models';
import { init, parse } from './wasm';

let client: LanguageClient;

export function activate(context: ExtensionContext) {
  context.subscriptions.push(
    languages.registerDocumentSemanticTokensProvider(
      { scheme: 'file', language: 'plaintext' },
      provider,
      legend,
    ),
  );

  // The server is implemented in node
  const serverModule = context.asAbsolutePath(path.join('server', 'out', 'server.js'));

  // If the extension is launched in debug mode then the debug server options are used
  // Otherwise the run options are used
  const serverOptions: ServerOptions = {
    run: { module: serverModule, transport: TransportKind.ipc },
    debug: {
      module: serverModule,
      transport: TransportKind.ipc,
    },
  };

  // Options to control the language client
  const clientOptions: LanguageClientOptions = {
    // Register the server for plain text documents
    documentSelector: [{ scheme: 'file', language: 'plaintext' }],
    synchronize: {
      // Notify the server about file changes to '.clientrc files contained in the workspace
      fileEvents: workspace.createFileSystemWatcher('**/.clientrc'),
    },
  };

  // Create the language client and start the client.
  client = new LanguageClient(
    'languageServerExample',
    'Language Server Example',
    serverOptions,
    clientOptions,
  );

  // Start the client. This will also launch the server
  client.start();
}

export function deactivate(): Thenable<void> | undefined {
  if (!client) {
    return undefined;
  }
  return client.stop();
}

const tokenTypes = [
  'namespace',
  'parameter',
  'variable',
  'function',
  'comment',
  'string',
  'keyword',
  'number',
  'operator',
];
const tokenModifiers = [
  'declaration',
  'definition',
  'deprecated',
  'modification',
  'documentation',
  'defaultLibrary',
];
const legend = new SemanticTokensLegend(tokenTypes, tokenModifiers);

const provider: DocumentSemanticTokensProvider = {
  provideDocumentSemanticTokens(document: TextDocument): ProviderResult<SemanticTokens> {
    // analyze the document and return semantic tokens

    const tokensBuilder = new SemanticTokensBuilder(legend);
    init();
    const tokens = parse(document.getText());
    for (const token of tokens.filter(
      (x) => x.tokenType === TokenType[TokenType.token_comment],
    )) {
      if (token.range.isSingleLine) {
        tokensBuilder.push(token.range, 'comment');
      } else {
        for (let i = token.range.start.line; i <= token.range.end.line; i++) {
          const line = document.lineAt(i);
          tokensBuilder.push(
            new Range(new Position(i, 0), new Position(i, line.text.length)),
            'comment',
          );
        }
      }
      // tokensBuilder.push(
      //   token.range.start.line,
      //   token.range.start.character,
      //   token.lexeme.length,
      //   tokenTypes.indexOf('comment'),
      // );
    }
    return tokensBuilder.build();
  },
};
