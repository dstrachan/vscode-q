import { Range } from 'vscode';

export enum TokenType {
  // Punctuation.
  token_left_paren,
  token_right_paren,
  token_left_brace,
  token_right_brace,
  token_left_bracket,
  token_right_bracket,
  token_semicolon,
  token_colon,
  token_double_colon,

  // Verbs.
  token_plus,
  token_minus,
  token_star,
  token_percent,
  token_bang,
  token_ampersand,
  token_pipe,
  token_less,
  token_greater,
  token_equal,
  token_tilde,
  token_comma,
  token_caret,
  token_hash,
  token_underscore,
  token_dollar,
  token_question,
  token_at,
  token_dot,

  // Literals.
  token_bool,
  token_int,
  token_float,
  token_string,
  token_symbol,
  token_identifier,
  token_keyword,

  // Adverbs.
  token_apostrophe,
  token_apostrophe_colon,
  token_slash,
  token_slash_colon,
  token_backslash,
  token_backslash_colon,

  token_system,
  token_whitespace,
  token_comment,
  token_error,
  token_eof,
}

export type Token = {
  tokenType: string;
  lexeme: string;
  errorMessage: string;
  range: Range;
};
