const std = @import("std");

const utils_mod = @import("./utils.zig");

const String = @import("string.zig").String;

pub const Token = struct {
    token_type: TokenType,
    lexeme: String,
    error_message: String,
    line: u32,
    char: u32,
};

pub const TokenType = enum(u32) {
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
    token_char,
    token_string,
    token_symbol,
    token_identifier,

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
};

const Self = @This();

start: usize,
line: u32,
char: u32,
prev_token: Token,

iterator: std.unicode.Utf8Iterator,

pub fn init(source: []const u8) Self {
    const view = std.unicode.Utf8View.init(source) catch @panic("Failed to create Utf8View");
    return Self{
        .start = 0,
        .line = 1,
        .char = 1,
        .prev_token = .{
            .token_type = .token_whitespace,
            .lexeme = undefined,
            .error_message = undefined,
            .line = undefined,
            .char = undefined,
        },
        .iterator = view.iterator(),
    };
}

pub fn scanToken(self: *Self) ?Token {
    self.start = self.iterator.i;

    const c = self.advance() orelse return null;
    if (isWhitespace(c)) return self.whitespace(c);

    if (c == '/') {
        if (self.char == 1) {
            const next = self.peek();
            if (next == 0 or next == '\n') return self.blockComment(c);
            return self.comment();
        }

        if (self.prev_token.token_type == .token_whitespace) return self.comment();
    }

    if (c == '\\' and self.char == 1) {
        const next = self.peek();
        if (next == 0 or next == '\n') return self.trailingComment();
        return self.system();
    }

    if (isAlpha(c)) return self.identifier();
    if (isDigit(c)) return self.number(c);
    if (c == '.' and isDigit(self.peek())) return self.float();
    if (c == '-') {
        const p = self.peek();
        if (p == '.' or isDigit(p)) {
            if (self.prev_token.token_type == .token_whitespace) {
                return self.negativeNumber();
            }
            return switch (self.prev_token.token_type) {
                .token_identifier,
                .token_bool,
                .token_int,
                .token_float,
                .token_char,
                .token_string,
                .token_symbol,
                .token_right_bracket,
                .token_right_paren,
                => self.makeToken(.token_minus),
                else => self.negativeNumber(),
            };
        }
    }

    return switch (c) {
        '(' => self.makeToken(.token_left_paren),
        ')' => self.makeToken(.token_right_paren),
        '{' => self.makeToken(.token_left_brace),
        '}' => self.makeToken(.token_right_brace),
        '[' => self.makeToken(.token_left_bracket),
        ']' => self.makeToken(.token_right_bracket),
        ';' => self.makeToken(.token_semicolon),
        ':' => self.makeToken(if (self.match(':')) .token_double_colon else .token_colon),
        '+' => self.makeToken(.token_plus),
        '-' => self.makeToken(.token_minus),
        '*' => self.makeToken(.token_star),
        '%' => self.makeToken(.token_percent),
        '!' => self.makeToken(.token_bang),
        '&' => self.makeToken(.token_ampersand),
        '|' => self.makeToken(.token_pipe),
        '<' => self.makeToken(.token_less),
        '>' => self.makeToken(.token_greater),
        '=' => self.makeToken(.token_equal),
        '~' => self.makeToken(.token_tilde),
        ',' => self.makeToken(.token_comma),
        '^' => self.makeToken(.token_caret),
        '#' => self.makeToken(.token_hash),
        '_' => self.makeToken(.token_underscore),
        '$' => self.makeToken(.token_dollar),
        '?' => self.makeToken(.token_question),
        '@' => self.makeToken(.token_at),
        '.' => self.makeToken(.token_dot),
        '\'' => self.makeToken(if (self.match(':')) .token_apostrophe_colon else .token_apostrophe),
        '/' => self.makeToken(if (self.match(':')) .token_slash_colon else .token_slash),
        '\\' => self.makeToken(if (self.match(':')) .token_backslash_colon else .token_backslash),
        '"' => self.string(),
        '`' => self.symbol(),
        else => self.errorToken("Unexpected character."),
    };
}

fn advance(self: *Self) ?u8 {
    const slice = self.iterator.nextCodepointSlice() orelse return null;
    if (slice.len > 1) return null;
    return slice[0];
}

fn match(self: *Self, expected: u8) bool {
    if (self.peek() == expected) {
        _ = self.advance();
        return true;
    }
    return false;
}

fn comment(self: *Self) Token {
    var c = self.peek();
    while (c != 0 and c != '\n') : (c = self.peek()) _ = self.advance();
    return self.makeNewlineToken(.token_comment);
}

fn blockComment(self: *Self, c: u8) Token {
    var prev = c;
    var next = self.peek();
    while (next != 0) : (next = self.peek()) {
        if (next == '\\' and prev == '\n') {
            _ = self.advance();
            break;
        }
        if (next == '\n') self.line += 1; // TODO: Increment after token creation

        _ = self.advance();
        prev = next;
    }
    return self.comment();
}

fn trailingComment(self: *Self) Token {
    var c = self.peek();
    while (c != 0) : (c = self.peek()) {
        if (c == '\n') self.line += 1; // TODO: Increment after token creation
        _ = self.advance();
    }
    return self.makeToken(.token_comment);
}

fn whitespace(self: *Self, c: u8) Token {
    if (c == '\n') return self.makeNewlineToken(.token_whitespace);

    while (true) {
        switch (self.peek()) {
            ' ', '\r', '\t' => _ = self.advance(),
            '\n' => return self.makeNewlineToken(.token_whitespace),
            else => break,
        }
    }
    return self.makeToken(.token_whitespace);
}

fn system(self: *Self) Token {
    var c = self.peek();
    while (c != 0 and c != '\n') : (c = self.peek()) _ = self.advance();
    return self.makeNewlineToken(.token_system);
}

fn identifier(self: *Self) Token {
    while (isAlpha(self.peek()) or isDigit(self.peek())) _ = self.advance();
    return self.makeToken(.token_identifier);
}

fn negativeNumber(self: *Self) Token {
    while (isDigit(self.peek())) _ = self.advance();

    if (self.peek() == '.') {
        _ = self.advance();
        return self.float();
    }

    const next = self.peek();
    if (next == 'W') {
        _ = self.advance();
    } else if (next == 'w') {
        _ = self.advance();
        if (self.peek() == 'f') {
            defer _ = self.advance();
            return self.makeToken(.token_float);
        }
        return self.makeToken(.token_float);
    }

    if (self.peek() == 'f') {
        defer _ = self.advance();
        return self.makeToken(.token_float);
    }

    return self.makeToken(.token_int);
}

fn number(self: *Self, c: u8) Token {
    var token_type: TokenType = if (c > '1') .token_int else .token_bool;
    while (isDigit(self.peek())) {
        if (self.peek() > '1') token_type = .token_int;
        _ = self.advance();
    }

    const next = self.peek();

    if (next == '.') {
        _ = self.advance();
        return self.float();
    }

    if (next == 'b') {
        _ = self.advance();
        return if (token_type == .token_bool) self.makeToken(.token_bool) else self.errorToken("Invalid boolean value.");
    }

    if (next == 'W' or next == 'N') {
        _ = self.advance();
    } else if (next == 'w' or next == 'n') {
        _ = self.advance();
        if (self.peek() == 'f') {
            defer _ = self.advance();
            return self.makeToken(.token_float);
        }
        return self.makeToken(.token_float);
    }

    if (self.peek() == 'f') {
        defer _ = self.advance();
        return self.makeToken(.token_float);
    }

    return self.makeToken(.token_int);
}

fn float(self: *Self) Token {
    while (isDigit(self.peek())) _ = self.advance();

    if (self.peek() == '.') {
        _ = self.advance();
        var c = self.peek();
        while (isDigit(c) or c == '.' or c == 'f') : (c = self.peek()) _ = self.advance();
        return self.errorToken("Too many decimal points.");
    }

    if (self.peek() == 'f') {
        defer _ = self.advance();
        return self.makeToken(.token_float);
    }

    return self.makeToken(.token_float);
}

fn string(self: *Self) Token {
    var len: usize = 0;
    var c = self.peek();
    while (c != 0 and c != '"') : (c = self.peek()) {
        switch (c) {
            '\n' => self.line += 1, // TODO: Increment after token creation
            '\\' => _ = self.advance(),
            else => {},
        }
        _ = self.advance();
        len += 1;
    }

    if (self.isAtEnd()) return self.errorToken("Unterminated string.");

    _ = self.advance();
    return self.makeToken(if (len == 1) .token_char else .token_string); // TODO: Do we need token_char?
}

fn symbol(self: *Self) Token {
    while (isSymbolChar(self.peek())) _ = self.advance();
    return self.makeToken(.token_symbol);
}

fn isAtEnd(self: *Self) bool {
    return self.iterator.i >= self.iterator.bytes.len;
}

fn peek(self: *Self) u8 {
    const slice = self.iterator.peek(1);
    if (slice.len != 1) return 0;
    return slice[0];
}

fn peekNext(self: *Self) u8 {
    const slice = self.iterator.peek(2);
    if (slice.len != 2) return 0;
    return slice[1];
}

fn makeNewlineToken(self: *Self, token_type: TokenType) Token {
    defer self.line += 1;
    defer self.char = 1;
    _ = self.advance();
    return self.makeToken(token_type);
}

fn makeToken(self: *Self, token_type: TokenType) Token {
    return self.token(token_type, self.iterator.bytes[self.start..self.iterator.i], "");
}

fn errorToken(self: *Self, message: []const u8) Token {
    return self.token(.token_error, self.iterator.bytes[self.start..self.iterator.i], message);
}

fn token(self: *Self, token_type: TokenType, lexeme: []const u8, error_message: []const u8) Token {
    defer self.char += lexeme.len;
    self.prev_token = .{
        .token_type = token_type,
        .lexeme = .{
            .ptr = lexeme.ptr,
            .len = lexeme.len,
        },
        .error_message = .{
            .ptr = error_message.ptr,
            .len = error_message.len,
        },
        .line = self.line,
        .char = self.char,
    };
    return self.prev_token;
}

fn isWhitespace(c: u8) bool {
    return switch (c) {
        ' ', '\r', '\t', '\n' => true,
        else => false,
    };
}

fn isAlpha(c: u8) bool {
    return switch (c) {
        'a'...'z', 'A'...'Z', '_' => true,
        else => false,
    };
}

fn isSymbolChar(c: u8) bool {
    return switch (c) {
        'a'...'z', 'A'...'Z', '0'...'9', '.', '_' => true,
        else => false,
    };
}

fn isDigit(c: u8) bool {
    return c >= '0' and c <= '9';
}
