const std = @import("std");

const String = @import("string.zig").String;

pub const Token = struct {
    token_type: TokenType,
    lexeme: String,
    line: u32,
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

    token_error,
    token_eof,
};

const Self = @This();

start: usize,
line: u32,

iterator: std.unicode.Utf8Iterator,

pub fn init(source: []const u8) Self {
    const view = std.unicode.Utf8View.init(source) catch @panic("Failed to create Utf8View");
    return Self{
        .start = 0,
        .line = 1,
        .iterator = view.iterator(),
    };
}

pub fn scanToken(self: *Self) ?Token {
    self.skipWhitespace();
    self.start = self.iterator.i;

    const c = self.advance() orelse return null;
    if (isAlpha(c)) return self.identifier();

    return self.errorToken("Unexpected character.");
}

fn advance(self: *Self) ?u8 {
    const slice = self.iterator.nextCodepointSlice() orelse return null;
    if (slice.len > 1) return null;
    return slice[0];
}

fn skipWhitespace(self: *Self) void {
    while (self.peek()) |c| {
        switch (c) {
            ' ', '\r', '\t' => self.iterator.i += 1,
            '\n' => {
                self.line += 1;
                self.iterator.i += 1;
            },
            else => return,
        }
    }
}

fn identifier(self: *Self) Token {
    while (self.peek()) |c| {
        if (!isAlpha(c) and !isDigit(c)) break;
        _ = self.advance();
    }
    return self.makeToken(.token_identifier);
}

fn isAtEnd(self: *Self) bool {
    return self.iterator.i >= self.iterator.bytes.len;
}

fn peek(self: *Self) ?u8 {
    const slice = self.iterator.peek(1);
    if (slice.len != 1) return null;
    return slice[0];
}

fn peekNext(self: *Self) ?u8 {
    const slice = self.iterator.peek(2);
    if (slice.len != 2) return null;
    return slice[1];
}

fn makeToken(self: *Self, token_type: TokenType) Token {
    return self.token(token_type, self.iterator.bytes[self.start..self.iterator.i]);
}

fn errorToken(self: *Self, message: []const u8) Token {
    return self.token(.token_error, message);
}

fn token(self: *Self, token_type: TokenType, lexeme: []const u8) Token {
    return .{
        .token_type = token_type,
        .lexeme = .{
            .ptr = lexeme.ptr,
            .len = lexeme.len,
        },
        .line = self.line,
    };
}

fn isAlpha(c: u8) bool {
    return switch (c) {
        'a'...'z', 'A'...'Z', '_' => true,
        else => false,
    };
}

fn isDigit(c: u8) bool {
    return c >= '0' and c <= '9';
}
