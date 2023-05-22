const std = @import("std");

const utils_mod = @import("./utils.zig");

const String = @import("string.zig").String;

const Position = struct {
    line: u32,
    character: u32,
};

const Range = struct {
    start: Position,
    end: Position,
};

pub const Token = struct {
    token_type: TokenType,
    lexeme: String,
    error_message: String,
    range: Range,
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
};

const Self = @This();

start: usize,
start_line: u32,
start_character: u32,
end_line: u32,
end_character: u32,
prev_token: Token,

iterator: std.unicode.Utf8Iterator,

pub fn init(source: []const u8) Self {
    const view = std.unicode.Utf8View.init(source) catch @panic("Failed to create Utf8View");
    return Self{
        .start = 0,
        .start_line = 0,
        .start_character = 0,
        .end_line = 0,
        .end_character = 0,
        .prev_token = .{
            .token_type = .token_whitespace,
            .lexeme = undefined,
            .error_message = undefined,
            .range = undefined,
        },
        .iterator = view.iterator(),
    };
}

pub fn scanToken(self: *Self) ?Token {
    self.start = self.iterator.i;
    self.start_line = self.end_line;
    self.start_character = self.end_character;

    const c = self.advance() orelse return null;
    if (isWhitespace(c)) return self.whitespace(c);

    if (c == '/') {
        if (self.start_character == 0) {
            const next = self.peek();
            if (next == 0 or next == '\n' or next == '\r') return self.blockComment(c);
            return self.comment();
        }

        if (self.prev_token.token_type == .token_whitespace) return self.comment();
    }

    if (c == '\\' and self.start_character == 0) {
        const next = self.peek();
        if (next == 0 or next == '\n' or next == '\r') return self.trailingComment();
        return self.system();
    }

    if (isIdentifierAlpha(c)) return self.identifier();
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
    if (slice[0] == '\n') {
        self.end_line += 1;
        self.end_character = 0;
    } else {
        self.end_character += 1;
    }
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
    while (c != 0 and c != '\n' and c != '\r') : (c = self.peek()) _ = self.advance();
    return self.makeToken(.token_comment);
}

fn blockComment(self: *Self, c: u8) Token {
    var prev = c;
    var next = self.peek();
    while (next != 0) : (next = self.peek()) {
        if (next == '\\' and prev == '\n') {
            const p = self.peekNext();
            if (p == '\n' or p == '\r') {
                _ = self.advance();
                break;
            }
        }

        _ = self.advance();
        prev = next;
    }
    return self.comment();
}

fn trailingComment(self: *Self) Token {
    var c = self.peek();
    while (c != 0) : (c = self.peek()) {
        _ = self.advance();
    }
    return self.makeToken(.token_comment);
}

fn whitespace(self: *Self, c: u8) Token {
    if (c == '\n') return self.makeToken(.token_whitespace);

    while (true) {
        switch (self.peek()) {
            ' ', '\r', '\t' => _ = self.advance(),
            '\n' => {
                _ = self.advance();
                return self.makeToken(.token_whitespace);
            },
            else => break,
        }
    }
    return self.makeToken(.token_whitespace);
}

fn system(self: *Self) Token {
    var c = self.peek();
    while (c != 0 and c != '\n') : (c = self.peek()) _ = self.advance();
    return self.makeToken(.token_system);
}

fn identifier(self: *Self) Token {
    while (isAlpha(self.peek()) or isDigit(self.peek())) _ = self.advance();
    const slice = self.getSlice();
    if (slice.len == 1 and slice[0] == '.') return self.makeToken(.token_dot);
    return self.makeToken(if (isKeyword(slice)) .token_keyword else .token_identifier);
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
    var c = self.peek();
    while (c != 0 and c != '"') : (c = self.peek()) {
        if (c == '\\') _ = self.advance();
        _ = self.advance();
    }

    if (self.isAtEnd()) return self.errorToken("Unterminated string.");

    _ = self.advance();
    return self.makeToken(.token_string);
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

fn getSlice(self: *Self) []const u8 {
    return self.iterator.bytes[self.start..self.iterator.i];
}

fn makeToken(self: *Self, token_type: TokenType) Token {
    return self.token(token_type, self.getSlice(), "");
}

fn errorToken(self: *Self, message: []const u8) Token {
    return self.token(.token_error, self.getSlice(), message);
}

fn token(self: *Self, token_type: TokenType, lexeme: []const u8, error_message: []const u8) Token {
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
        .range = .{
            .start = .{
                .line = self.start_line,
                .character = self.start_character,
            },
            .end = .{
                .line = self.end_line,
                .character = self.end_character,
            },
        },
    };
    return self.prev_token;
}

fn isKeyword(slice: []const u8) bool {
    if (slice.len <= 1) return false;

    return switch (slice[0]) {
        'a' => switch (slice[1]) {
            'b' => slice.len == 3 and slice[2] == 's',
            'c' => std.mem.eql(u8, "os", slice[2..]),
            'j' => slice.len == 2 or switch (slice[2]) {
                '0' => slice.len == 3,
                'f' => slice.len == 3 or (slice.len == 4 and slice[3] == '0'),
                else => false,
            },
            'l' => slice.len == 3 and slice[2] == 'l',
            'n' => slice.len == 3 and (slice[2] == 'd' or slice[2] == 'y'),
            's' => slice.len > 2 and switch (slice[2]) {
                'c' => slice.len == 3,
                'i' => slice.len == 4 and slice[3] == 'n',
                'o' => slice.len == 4 and slice[3] == 'f',
                else => false,
            },
            't' => slice.len > 2 and switch (slice[2]) {
                'a' => slice.len == 4 and slice[3] == 'n',
                't' => slice.len == 4 and slice[3] == 'r',
                else => false,
            },
            'v' => slice.len > 2 and switch (slice[2]) {
                'g' => slice.len == 3 or (slice.len == 4 and slice[3] == 's'),
                else => false,
            },
            else => false,
        },
        'b' => slice.len > 2 and switch (slice[1]) {
            'i' => switch (slice[2]) {
                'n' => slice.len == 3 or (slice.len == 4 and slice[3] == 'r'),
                else => false,
            },
            else => false,
        },
        'c' => switch (slice[1]) {
            'e' => std.mem.eql(u8, "iling", slice[2..]),
            'o' => slice.len > 2 and switch (slice[2]) {
                'l' => slice.len == 4 and slice[3] == 's',
                'r' => slice.len == 3,
                's' => slice.len == 3,
                'u' => std.mem.eql(u8, "nt", slice[3..]),
                'v' => slice.len == 3,
                else => false,
            },
            'r' => std.mem.eql(u8, "oss", slice[2..]),
            's' => slice.len == 3 and slice[2] == 'v',
            'u' => slice.len == 3 and slice[2] == 't',
            else => false,
        },
        'd' => switch (slice[1]) {
            'e' => slice.len > 2 and switch (slice[2]) {
                'l' => slice.len == 6 and switch (slice[3]) {
                    'e' => std.mem.eql(u8, "te", slice[4..]),
                    't' => std.mem.eql(u8, "as", slice[4..]),
                    else => false,
                },
                's' => slice.len == 4 and slice[3] == 'c',
                'v' => slice.len == 3,
                else => false,
            },
            'i' => slice.len > 2 and switch (slice[2]) {
                'f' => std.mem.eql(u8, "fer", slice[3..]),
                's' => std.mem.eql(u8, "tinct", slice[3..]),
                'v' => slice.len == 3,
                else => false,
            },
            'o' => slice.len == 2,
            's' => std.mem.eql(u8, "ave", slice[2..]),
            else => false,
        },
        'e' => switch (slice[1]) {
            'a' => std.mem.eql(u8, "ch", slice[2..]),
            'j' => slice.len == 2,
            'm' => slice.len == 3 and slice[2] == 'a',
            'n' => std.mem.eql(u8, "list", slice[2..]),
            'v' => std.mem.eql(u8, "al", slice[2..]),
            'x' => slice.len > 2 and switch (slice[2]) {
                'c' => std.mem.eql(u8, "ept", slice[3..]),
                'e' => slice.len == 4 and slice[3] == 'c',
                'i' => slice.len == 4 and slice[3] == 't',
                'p' => slice.len == 3,
                else => false,
            },
            else => false,
        },
        'f' => switch (slice[1]) {
            'b' => slice.len == 3 and slice[2] == 'y',
            'i' => slice.len == 5 and switch (slice[2]) {
                'l' => std.mem.eql(u8, "ls", slice[3..]),
                'r' => std.mem.eql(u8, "st", slice[3..]),
                else => false,
            },
            'k' => std.mem.eql(u8, "eys", slice[2..]),
            'l' => slice.len > 2 and switch (slice[2]) {
                'i' => slice.len == 4 and slice[3] == 'p',
                'o' => std.mem.eql(u8, "or", slice[3..]),
                else => false,
            },
            else => false,
        },
        'g' => switch (slice[1]) {
            'e' => slice.len > 2 and switch (slice[2]) {
                't' => slice.len == 3 or std.mem.eql(u8, "env", slice[3..]),
                else => false,
            },
            'r' => std.mem.eql(u8, "oup", slice[2..]),
            't' => std.mem.eql(u8, "ime", slice[2..]),
            else => false,
        },
        'h' => switch (slice[1]) {
            'c' => slice.len == 6 and switch (slice[2]) {
                'l' => std.mem.eql(u8, "ose", slice[3..]),
                'o' => std.mem.eql(u8, "unt", slice[3..]),
                else => false,
            },
            'd' => std.mem.eql(u8, "el", slice[2..]),
            'o' => std.mem.eql(u8, "pen", slice[2..]),
            's' => std.mem.eql(u8, "ym", slice[2..]),
            else => false,
        },
        'i' => switch (slice[1]) {
            'a' => std.mem.eql(u8, "sc", slice[2..]),
            'd' => std.mem.eql(u8, "esc", slice[2..]),
            'f' => slice.len == 2,
            'j' => slice.len == 2 or (slice.len == 3 and slice[2] == 'f'),
            'n' => slice.len == 2 or switch (slice[2]) {
                's' => std.mem.eql(u8, "ert", slice[3..]),
                't' => std.mem.eql(u8, "er", slice[3..]),
                'v' => slice.len == 3,
                else => false,
            },
            else => false,
        },
        'k' => switch (slice[1]) {
            'e' => slice.len > 2 and switch (slice[2]) {
                'y' => slice.len == 3 or (slice.len == 4 and slice[3] == 's'),
                else => false,
            },
            else => false,
        },
        'l' => switch (slice[1]) {
            'a' => std.mem.eql(u8, "st", slice[2..]),
            'i' => std.mem.eql(u8, "ke", slice[2..]),
            'j' => slice.len == 2 or (slice.len == 3 and slice[2] == 'f'),
            'o' => slice.len > 2 and switch (slice[2]) {
                'a' => slice.len == 4 and slice[3] == 'd',
                'g' => slice.len == 3,
                'w' => std.mem.eql(u8, "er", slice[3..]),
                else => false,
            },
            's' => slice.len == 3 and slice[2] == 'q',
            't' => slice.len == 5 and switch (slice[2]) {
                'i' => std.mem.eql(u8, "me", slice[3..]),
                'r' => std.mem.eql(u8, "im", slice[3..]),
                else => false,
            },
            else => false,
        },
        'm' => switch (slice[1]) {
            'a' => slice.len > 2 and switch (slice[2]) {
                'v' => slice.len == 4 and slice[3] == 'g',
                'x' => slice.len == 3 or (slice.len == 4 and slice[3] == 's'),
                else => false,
            },
            'c' => std.mem.eql(u8, "ount", slice[2..]),
            'd' => slice.len > 2 and switch (slice[2]) {
                '5' => slice.len == 3,
                'e' => slice.len == 4 and slice[3] == 'v',
                else => false,
            },
            'e' => slice.len > 2 and switch (slice[2]) {
                'd' => slice.len == 3,
                't' => slice.len == 4 and slice[3] == 'a',
                else => false,
            },
            'i' => slice.len > 2 and switch (slice[2]) {
                'n' => slice.len == 3 or (slice.len == 4 and slice[3] == 's'),
                else => false,
            },
            'm' => slice.len > 2 and switch (slice[2]) {
                'a' => slice.len == 4 and slice[3] == 'x',
                'i' => slice.len == 4 and slice[3] == 'n',
                'u' => slice.len == 3,
                else => false,
            },
            'o' => slice.len == 3 and slice[2] == 'd',
            's' => std.mem.eql(u8, "um", slice[2..]),
            else => false,
        },
        'n' => switch (slice[1]) {
            'e' => slice.len > 2 and switch (slice[2]) {
                'g' => slice.len == 3,
                'x' => slice.len == 4 and slice[3] == 't',
                else => false,
            },
            'o' => slice.len == 3 and slice[2] == 't',
            'u' => std.mem.eql(u8, "ll", slice[2..]),
            else => false,
        },
        'o' => switch (slice[1]) {
            'r' => slice.len == 2,
            'v' => std.mem.eql(u8, "er", slice[2..]),
            else => false,
        },
        'p' => switch (slice[1]) {
            'a' => std.mem.eql(u8, "rse", slice[2..]),
            'e' => std.mem.eql(u8, "ach", slice[2..]),
            'j' => slice.len == 2,
            'r' => slice.len > 2 and switch (slice[2]) {
                'd' => slice.len == 3 or (slice.len == 4 and slice[3] == 's'),
                'e' => slice.len == 4 and slice[3] == 'v',
                'i' => std.mem.eql(u8, "or", slice[3..]),
                else => false,
            },
            else => false,
        },
        'r' => switch (slice[1]) {
            'a' => slice.len > 2 and switch (slice[2]) {
                'n' => slice.len == 4 and (slice[3] == 'd' or slice[3] == 'k'),
                't' => std.mem.eql(u8, "ios", slice[3..]),
                'z' => slice.len == 4 and slice[3] == 'e',
                else => false,
            },
            'e' => slice.len > 2 and switch (slice[2]) {
                'a' => slice.len == 5 and switch (slice[3]) {
                    'd' => slice[4] == '0' or slice[4] == '1',
                    else => false,
                },
                'c' => std.mem.eql(u8, "iprocal", slice[3..]),
                'v' => slice.len > 4 and switch (slice[3]) {
                    'a' => slice.len == 5 and slice[4] == 'l',
                    'e' => std.mem.eql(u8, "rse", slice[4..]),
                    else => false,
                },
                else => false,
            },
            'l' => std.mem.eql(u8, "oad", slice[2..]),
            'o' => std.mem.eql(u8, "tate", slice[2..]),
            's' => std.mem.eql(u8, "ave", slice[2..]),
            't' => std.mem.eql(u8, "rim", slice[2..]),
            else => false,
        },
        's' => switch (slice[1]) {
            'a' => std.mem.eql(u8, "ve", slice[2..]),
            'c' => slice.len > 2 and switch (slice[2]) {
                'a' => slice.len == 4 and slice[3] == 'n',
                'o' => slice.len == 4 and slice[3] == 'v',
                else => false,
            },
            'd' => std.mem.eql(u8, "ev", slice[2..]),
            'e' => slice.len > 2 and switch (slice[2]) {
                'l' => std.mem.eql(u8, "ect", slice[3..]),
                't' => slice.len == 3 or std.mem.eql(u8, "env", slice[3..]),
                else => false,
            },
            'h' => std.mem.eql(u8, "ow", slice[2..]),
            'i' => slice.len > 2 and switch (slice[2]) {
                'g' => std.mem.eql(u8, "num", slice[3..]),
                'n' => slice.len == 3,
                else => false,
            },
            'q' => std.mem.eql(u8, "rt", slice[2..]),
            's' => slice.len == 2 or (slice.len == 3 and slice[2] == 'r'),
            't' => std.mem.eql(u8, "ring", slice[2..]),
            'u' => slice.len > 2 and switch (slice[2]) {
                'b' => std.mem.eql(u8, "list", slice[3..]),
                'm' => slice.len == 3 or (slice.len == 4 and slice[3] == 's'),
                else => false,
            },
            'v' => slice.len == 2 or std.mem.eql(u8, "ar", slice[2..]),
            'y' => std.mem.eql(u8, "stem", slice[2..]),
            else => false,
        },
        't' => switch (slice[1]) {
            'a' => slice.len > 2 and switch (slice[2]) {
                'b' => std.mem.eql(u8, "les", slice[3..]),
                'n' => slice.len == 3,
                else => false,
            },
            'i' => slice.len == 3 and slice[2] == 'l',
            'r' => std.mem.eql(u8, "im", slice[2..]),
            'y' => std.mem.eql(u8, "pe", slice[2..]),
            else => false,
        },
        'u' => switch (slice[1]) {
            'j' => slice.len == 2 or (slice.len == 3 and slice[2] == 'f'),
            'n' => slice.len > 2 and switch (slice[2]) {
                'g' => std.mem.eql(u8, "roup", slice[3..]),
                'i' => std.mem.eql(u8, "on", slice[3..]),
                else => false,
            },
            'p' => slice.len > 2 and switch (slice[2]) {
                'd' => std.mem.eql(u8, "ate", slice[3..]),
                'p' => std.mem.eql(u8, "er", slice[3..]),
                's' => std.mem.eql(u8, "ert", slice[3..]),
                else => false,
            },
            else => false,
        },
        'v' => switch (slice[1]) {
            'a' => slice.len > 2 and switch (slice[2]) {
                'l' => std.mem.eql(u8, "ue", slice[3..]),
                'r' => slice.len == 3,
                else => false,
            },
            'i' => slice.len > 2 and switch (slice[2]) {
                'e' => slice.len > 3 and switch (slice[3]) {
                    'w' => slice.len == 4 or (slice.len == 5 and slice[4] == 's'),
                    else => false,
                },
                else => false,
            },
            's' => slice.len == 2,
            else => false,
        },
        'w' => switch (slice[1]) {
            'a' => std.mem.eql(u8, "vg", slice[2..]),
            'h' => slice.len > 2 and switch (slice[2]) {
                'e' => std.mem.eql(u8, "re", slice[3..]),
                'i' => std.mem.eql(u8, "le", slice[3..]),
                else => false,
            },
            'i' => std.mem.eql(u8, "thin", slice[2..]),
            'j' => slice.len == 2 or (slice.len == 3 and slice[2] == '1'),
            's' => std.mem.eql(u8, "um", slice[2..]),
            else => false,
        },
        'x' => switch (slice[1]) {
            'a' => std.mem.eql(u8, "sc", slice[2..]),
            'b' => std.mem.eql(u8, "ar", slice[2..]),
            'c' => slice.len > 3 and switch (slice[2]) {
                'o' => switch (slice[3]) {
                    'l' => slice.len == 4 or (slice.len == 5 and slice[4] == 's'),
                    else => false,
                },
                else => false,
            },
            'd' => std.mem.eql(u8, "esc", slice[2..]),
            'e' => std.mem.eql(u8, "xp", slice[2..]),
            'g' => std.mem.eql(u8, "roup", slice[2..]),
            'k' => std.mem.eql(u8, "ey", slice[2..]),
            'l' => std.mem.eql(u8, "og", slice[2..]),
            'p' => std.mem.eql(u8, "rev", slice[2..]),
            'r' => std.mem.eql(u8, "ank", slice[2..]),
            else => false,
        },
        else => false,
    };
}

fn isWhitespace(c: u8) bool {
    return switch (c) {
        ' ', '\r', '\t', '\n' => true,
        else => false,
    };
}

fn isIdentifierAlpha(c: u8) bool {
    return switch (c) {
        'a'...'z', 'A'...'Z', '.' => true,
        else => false,
    };
}

fn isAlpha(c: u8) bool {
    return switch (c) {
        'a'...'z', 'A'...'Z', '.', '_' => true,
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
