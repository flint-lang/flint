//! Small purpose-built TOML parser whose job is to parse the 'flint.toml' file
const std = @import("std");

const Self = @This();

var toml: ?Self = null;

config: Config,
deps: []const Dep,

pub const Config = struct {
    indentation: ?u32 = null,

    comptime {
        for (std.meta.fieldTypes(Config)) |field| {
            std.debug.assert(@typeInfo(field) == .optional);
        }
    }
};

pub const Dep = struct {
    name: []const u8,
    kind: []const u8,
    src: Src,

    pub const Src = union(enum) {
        // NOTE: This value is only intended to be used during parsing, after parsing no value should be 'none', at all
        none: void,
        path: []const u8,
        link: Link,

        pub const Link = struct {
            url: []const u8 = "",
            tag: []const u8 = "",
            hash: []const u8 = "",
        };
    };
};

pub fn get(io: std.Io, arena: std.mem.Allocator) !Self {
    if (toml) |t| {
        return t;
    }

    const src: []const u8 = std.Io.Dir.cwd().readFileAlloc(io, "flint.toml", arena, .unlimited) catch |err| switch (err) {
        error.FileNotFound => {
            var cwd_buffer: [std.fs.max_path_bytes]u8 = @splat(0);
            const path_len = try std.Io.Dir.cwd().realPath(io, &cwd_buffer);
            std.log.warn("'{s}/flint.toml' file not found", .{cwd_buffer[0..path_len]});
            std.log.warn("Please run 'flint init' to init a new Flint project or change your working directory", .{});
            return error.MissingTomlFile;
        },
        else => return err,
    };

    const res = try Token.tokenize(arena, src);
    std.debug.print("====== TOKENS BEGIN ======\n", .{});
    const wl = std.math.log(usize, 10, res.positions[res.positions.len - 1].line) + 1;
    var wc: usize = 1;
    for (res.positions) |pos| {
        wc = @max(wc, std.math.log(usize, 10, pos.col) + 1);
    }
    for (res.tokens, res.positions) |token, pos| {
        switch (token) {
            .identifier => |value| std.debug.print("{[line]d: >[wl]}:{[col]d: <[wc]} | .identifier | {[val]s}\n", .{
                .line = pos.line,
                .wl = wl,
                .col = pos.col,
                .wc = wc,
                .val = value,
            }),
            .string => |value| std.debug.print("{[line]d: >[wl]}:{[col]d: <[wc]} | .string     | {[val]q}\n", .{
                .line = pos.line,
                .wl = wl,
                .col = pos.col,
                .wc = wc,
                .val = value,
            }),
            .number => |value| std.debug.print("{[line]d: >[wl]}:{[col]d: <[wc]} | .number     | {[val]d}\n", .{
                .line = pos.line,
                .wl = wl,
                .col = pos.col,
                .wc = wc,
                .val = value,
            }),
            .bool => |value| std.debug.print("{[line]d: >[wl]}:{[col]d: <[wc]} | .bool       | {[val]}\n", .{
                .line = pos.line,
                .wl = wl,
                .col = pos.col,
                .wc = wc,
                .val = value,
            }),
            .l_bracket => std.debug.print("{[line]d: >[wl]}:{[col]d: <[wc]} | .l_bracket  | [\n", .{
                .line = pos.line,
                .wl = wl,
                .col = pos.col,
                .wc = wc,
            }),
            .r_bracket => std.debug.print("{[line]d: >[wl]}:{[col]d: <[wc]} | .r_bracket  | ]\n", .{
                .line = pos.line,
                .wl = wl,
                .col = pos.col,
                .wc = wc,
            }),
            .equals => std.debug.print("{[line]d: >[wl]}:{[col]d: <[wc]} | .equals     | =\n", .{
                .line = pos.line,
                .wl = wl,
                .col = pos.col,
                .wc = wc,
            }),
        }
    }
    std.debug.print("======= TOKENS END =======\n", .{});

    const TagOrField = union(enum) {
        tag: []const u8,
        field: struct {
            name: []const u8,
            value: union(enum) {
                string: []const u8,
                number: i64,
                bool: bool,

                const This = @This();

                pub fn expect(self: This, tag: std.meta.Tag(This), field_name: []const u8) !void {
                    if (self != tag) {
                        std.log.err("Expected value of type '{s}' for field '{s}', but got '{s}'", .{
                            @tagName(tag),
                            field_name,
                            @tagName(self),
                        });
                        return error.IncorrectTypeOfField;
                    }
                }
            },
        },
    };

    var line_list: std.ArrayList(TagOrField) = .empty;
    var i: usize = 0;
    while (i < res.tokens.len) {
        switch (res.tokens[i]) {
            .l_bracket => {
                // A new tag begins: [ident]
                if (i + 1 >= res.tokens.len) {
                    std.log.err("Unexpected end of file, expected identifier", .{});
                    return error.UnexpectedEOF;
                }
                if (res.tokens[i + 1] != .identifier) {
                    std.log.err("Unexpected token: {s}, expected identifier", .{@tagName(res.tokens[i + 1])});
                    return error.MalformedTomlFile;
                }
                if (i + 2 >= res.tokens.len) {
                    std.log.err("Unexpected end of file, expected ']'", .{});
                    return error.UnexpectedEOF;
                }
                if (res.tokens[i + 2] != .r_bracket) {
                    std.log.err("Unexpected token: {s}, expected ']'", .{@tagName(res.tokens[i + 2])});
                    return error.MalformedTomlFile;
                }
                try line_list.append(arena, .{ .tag = res.tokens[i + 1].identifier });
                i += 3;
            },
            .identifier => |name| {
                // A field begins: ident = value
                if (i + 1 >= res.tokens.len) {
                    std.log.err("Unexpected end of file, expected '='", .{});
                    return error.UnexpectedEOF;
                }
                if (res.tokens[i + 1] != .equals) {
                    std.log.err("Unexpected token: {s}, expected '='", .{@tagName(res.tokens[i + 1])});
                    return error.MalformedTomlFile;
                }
                if (i + 2 >= res.tokens.len) {
                    std.log.err("Unexpected end of file, expected value", .{});
                    return error.UnexpectedEOF;
                }
                try line_list.append(arena, .{
                    .field = .{
                        .name = name,
                        .value = switch (res.tokens[i + 2]) {
                            .string => |value| .{ .string = value },
                            .number => |value| .{ .number = value },
                            .bool => |value| .{ .bool = value },
                            else => {
                                std.log.err("Unexpected token: {s}, expected value", .{@tagName(res.tokens[i + 2])});
                                return error.MalformedTomlFile;
                            },
                        },
                    },
                });
                i += 3;
            },
            else => {
                std.log.err("Unexpected token: {s}, expected '[' or identifier", .{@tagName(res.tokens[i])});
                return error.MalformedTomlFile;
            },
        }
    }
    std.debug.print("\n====== LINES BEGIN ======\n", .{});
    for (line_list.items) |line| {
        switch (line) {
            .tag => |tag| std.debug.print("[{s}]\n", .{tag}),
            .field => |field| switch (field.value) {
                .string => |value| std.debug.print("{s} = {q}\n", .{ field.name, value }),
                .number => |value| std.debug.print("{s} = {d}\n", .{ field.name, value }),
                .bool => |value| std.debug.print("{s} = {}\n", .{ field.name, value }),
            },
        }
    }
    std.debug.print("======= LINES END =======\n", .{});

    var config: Config = .{};
    var config_parsed: bool = false;
    var deps_list: std.ArrayList(Dep) = .empty;

    var current_dep: Dep = .{
        .name = "",
        .kind = "",
        .src = .none,
    };
    var current_dep_parsed: struct {
        name_parsed: bool = false,
        kind_parsed: bool = false,
        src_parsed: ?union(enum) {
            // If the union is 'path' then this means that it has been parsed
            path: void,
            link: struct {
                url_parsed: bool = false,
                tag_parsed: bool = false,
                hash_parsed: bool = false,
            },
        } = null,

        const This = @This();

        pub fn check(self: This, tag: []const u8) !void {
            if (self.name_parsed) {
                if (!self.kind_parsed) {
                    std.log.err("Missing required field 'kind' in dependency {s}", .{tag});
                    return error.MissingFieldKind;
                }
                if (self.src_parsed) |src_parsed| {
                    switch (src_parsed) {
                        .path => {},
                        .link => |link| {
                            if (!link.url_parsed) {
                                std.log.err("Missing required field 'url' in dependency {s}", .{tag});
                                return error.MissingFieldUrl;
                            }
                            if (!link.tag_parsed) {
                                std.log.err("Missing required field 'tag' in dependency {s}", .{tag});
                                return error.MissingFieldTag;
                            }
                            if (!link.hash_parsed) {
                                std.log.err("Missing required field 'hash' in dependency {s}", .{tag});
                                return error.MissingFieldHash;
                            }
                        },
                    }
                } else {
                    std.log.err("Missing path or url source", .{});
                    return error.MissingPathOrUrlSource;
                }
            }
        }
    } = .{};

    i = 0;
    while (i < line_list.items.len) {
        switch (line_list.items[i]) {
            .tag => |tag| {
                if (current_dep_parsed.name_parsed) {
                    try current_dep_parsed.check(current_dep.name);
                    try deps_list.append(arena, current_dep);
                }
                if (std.mem.eql(u8, tag, "config")) {
                    // The 'config' section is handled differently
                    if (config_parsed) {
                        std.log.err("Duplicate 'config' section found", .{});
                        return error.ConfigDuplicateSection;
                    }
                    // Skip the '[config]' tag line to look at the fields
                    i += 1;
                    while (i < line_list.items.len and line_list.items[i] == .field) {
                        const field = line_list.items[i].field;
                        if (std.mem.eql(u8, field.name, "indentation")) {
                            if (config.indentation != null) {
                                std.log.err("Duplicate field 'indentation' found in in 'config' section", .{});
                                return error.ConfigDuplicateFieldIn;
                            }
                            try field.value.expect(.number, "indentation");
                            if (field.value.number < 1) {
                                std.log.err("Value of field 'indentation' has a minimum settable value of '1'", .{});
                                return error.ConfigIndentationTooSmall;
                            }
                            if (field.value.number > std.math.maxInt(u32)) {
                                std.log.err("Value of field 'indentation' has a maximum settable value of '{d}'", .{std.math.maxInt(u32)});
                                return error.ConfigIndentationTooLarge;
                            }
                            config.indentation = @intCast(field.value.number);
                        } else {
                            std.log.err("Unrecognized 'config' field: {s}", .{field.name});
                            std.debug.print("       Available fields are:\n", .{});
                            inline for (comptime std.meta.fieldNames(Config), comptime std.meta.fieldTypes(Config)) |field_name, field_type| {
                                std.debug.print("       - {s}: ", .{field_name});
                                switch (@typeInfo(@typeInfo(field_type).optional.child)) {
                                    .array => std.debug.print("string\n", .{}),
                                    .int => std.debug.print("number\n", .{}),
                                    .bool => std.debug.print("bool\n", .{}),
                                    else => unreachable,
                                }
                            }
                            return error.ConfigUnrecognizedField;
                        }
                        i += 1;
                    }
                    config_parsed = true;
                    continue;
                }

                // Reset the current dep parsed for the next dependency
                current_dep_parsed = .{};
                current_dep_parsed.name_parsed = true;
                current_dep.name = tag;
                i += 1;
            },
            .field => |field| {
                if (!current_dep_parsed.name_parsed) {
                    std.log.err("Field '{s}' is not part of any section", .{field.name});
                    return error.FieldNotPartOfAnySection;
                }
                if (std.mem.eql(u8, field.name, "kind")) {
                    try field.value.expect(.string, "kind");
                    if (current_dep_parsed.kind_parsed) {
                        std.log.err("Duplicate field 'kind' in dependency '{s}'", .{current_dep.name});
                        return error.DependencyDuplicateField;
                    }
                    current_dep_parsed.kind_parsed = true;
                    current_dep.kind = field.value.string;
                } else if (std.mem.eql(u8, field.name, "path")) {
                    try field.value.expect(.string, "path");
                    if (current_dep_parsed.src_parsed != null and current_dep_parsed.src_parsed.? == .link) {
                        std.log.err("Field 'path' in dependency '{s}' is not allowed to coexist with url-based fields 'url', 'tag' and 'hash'", .{
                            current_dep.name,
                        });
                        return error.DependencyPathWithUrl;
                    }
                    current_dep_parsed.src_parsed = .path;
                    current_dep.src = .{ .path = field.value.string };
                } else if (std.mem.eql(u8, field.name, "url")) {
                    try field.value.expect(.string, "url");
                    if (current_dep_parsed.src_parsed != null and current_dep_parsed.src_parsed.? == .path) {
                        std.log.err("Field 'url' in dependency '{s}' is not allowed to coexist with the 'path' field. Choose one", .{
                            current_dep.name,
                        });
                        return error.DependencyUrlWithPath;
                    }
                    if (current_dep_parsed.src_parsed == null) {
                        current_dep_parsed.src_parsed = .{ .link = .{} };
                    }
                    if (current_dep_parsed.src_parsed.?.link.url_parsed) {
                        std.log.err("Duplicate field 'url' in dependency '{s}'", .{current_dep.name});
                        return error.DependencyDuplicateField;
                    }
                    current_dep_parsed.src_parsed.?.link.url_parsed = true;
                    if (current_dep.src == .none) {
                        current_dep.src = .{ .link = .{} };
                    }
                    current_dep.src.link.url = field.value.string;
                } else if (std.mem.eql(u8, field.name, "tag")) {
                    try field.value.expect(.string, "tag");
                    if (current_dep_parsed.src_parsed != null and current_dep_parsed.src_parsed.? == .path) {
                        std.log.err("Field 'tag' in dependency '{s}' is not allowed to coexist with the 'path' field. Choose one", .{
                            current_dep.name,
                        });
                        return error.DependencyUrlWithPath;
                    }
                    if (current_dep_parsed.src_parsed == null) {
                        current_dep_parsed.src_parsed = .{ .link = .{} };
                    }
                    if (current_dep_parsed.src_parsed.?.link.tag_parsed) {
                        std.log.err("Duplicate field 'tag' in dependency '{s}'", .{current_dep.name});
                        return error.DependencyDuplicateField;
                    }
                    current_dep_parsed.src_parsed.?.link.tag_parsed = true;
                    if (current_dep.src == .none) {
                        current_dep.src = .{ .link = .{} };
                    }
                    current_dep.src.link.tag = field.value.string;
                } else if (std.mem.eql(u8, field.name, "hash")) {
                    try field.value.expect(.string, "hash");
                    if (current_dep_parsed.src_parsed != null and current_dep_parsed.src_parsed.? == .path) {
                        std.log.err("Field 'hash' in dependency '{s}' is not allowed to coexist with the 'path' field. Choose one", .{
                            current_dep.name,
                        });
                        return error.DependencyUrlWithPath;
                    }
                    if (current_dep_parsed.src_parsed == null) {
                        current_dep_parsed.src_parsed = .{ .link = .{} };
                    }
                    if (current_dep_parsed.src_parsed.?.link.hash_parsed) {
                        std.log.err("Duplicate field 'hash' in dependency '{s}'", .{current_dep.name});
                        return error.DependencyDuplicateField;
                    }
                    current_dep_parsed.src_parsed.?.link.hash_parsed = true;
                    if (current_dep.src == .none) {
                        current_dep.src = .{ .link = .{} };
                    }
                    current_dep.src.link.hash = field.value.string;
                } else {
                    std.log.err("Unrecognized field in dependency '{s}': {s}", .{ current_dep.name, field.name });
                    return error.DependencyUnrecognizedField;
                }
                i += 1;
            },
        }
    }
    if (current_dep_parsed.name_parsed) {
        try current_dep_parsed.check(current_dep.name);
        try deps_list.append(arena, current_dep);
    }

    std.debug.print("\n======= DEPS BEGIN =======\n", .{});
    if (config_parsed) {
        std.debug.print("[config]\n", .{});
        if (config.indentation) |indentation| {
            std.debug.print("indentation = {d}\n", .{indentation});
        }
        std.debug.print("\n", .{});
    }
    for (deps_list.items, 0..) |dep, j| {
        if (j > 0) {
            std.debug.print("\n", .{});
        }
        std.debug.print(
            \\[{s}]
            \\kind = {q}
            \\
        , .{
            dep.name,
            dep.kind,
        });
        switch (dep.src) {
            .none => unreachable,
            .path => |path| std.debug.print("path = {q}\n", .{path}),
            .link => |link| std.debug.print(
                \\url = {q}
                \\tag = {q}
                \\hash = {q}
                \\
            , .{
                link.url,
                link.tag,
                link.hash,
            }),
        }
    }
    std.debug.print("======== DEPS END ========\n", .{});

    toml = .{
        .config = config,
        .deps = deps_list.items,
    };
    return toml.?;
}

const Pos = struct {
    line: usize,
    col: usize,
};

const Token = union(enum) {
    identifier: []const u8,
    string: []const u8,
    number: i64,
    bool: bool,
    l_bracket: void,
    r_bracket: void,
    equals: void,

    pub fn tokenize(arena: std.mem.Allocator, src: []const u8) !struct {
        tokens: []const Token,
        positions: []const Pos,
    } {
        var tokens: std.ArrayList(Token) = .empty;
        var positions: std.ArrayList(Pos) = .empty;

        var line: usize = 1;
        var col: usize = 1;
        var i: usize = 0;
        while (i < src.len) : (i += 1) {
            const next: ?Token = switch (src[i]) {
                '\n' => blk: {
                    line += 1;
                    col = 1;
                    break :blk null;
                },
                // Skip whitespace
                ' ', '\t', '\r', std.ascii.control_code.vt, std.ascii.control_code.ff => null,
                '#' => blk: {
                    // Skip comments until end of line
                    while (i + 1 < src.len and src[i + 1] != '\n') {
                        i += 1;
                        col += 1;
                    }
                    break :blk null;
                },
                '_', 'A'...'Z', 'a'...'z' => blk: {
                    const start = i;
                    while (i + 1 < src.len and (std.ascii.isAlphabetic(src[i + 1]) or src[i + 1] == '_')) {
                        i += 1;
                        col += 1;
                    }
                    const identifier = src[start..(i + 1)];
                    if (identifier.len == 1 and identifier[0] == '_') {
                        std.log.err("An identifier can not only contain a single '_'", .{});
                        return error.MalformedIdentifier;
                    }
                    if (std.mem.eql(u8, identifier, "true")) {
                        break :blk .{ .bool = true };
                    } else if (std.mem.eql(u8, identifier, "false")) {
                        break :blk .{ .bool = false };
                    }
                    break :blk .{ .identifier = identifier };
                },
                '"' => blk: {
                    i += 1; // Skip "
                    const start = i;
                    while (i < src.len and src[i] != '"') {
                        i += 1;
                        col += 1;
                    }
                    break :blk .{
                        .string = src[start..i],
                    };
                },
                '-', '0'...'9' => blk: {
                    const start = i;
                    const is_negative: bool = src[i] == '-';
                    if (is_negative) {
                        i += 1;
                        col += 1;
                    }
                    while (i < src.len and std.ascii.isDigit(src[i])) {
                        i += 1;
                        col += 1;
                    }
                    if (is_negative and start + 1 == i) {
                        std.log.err("Dangling '-' sign in toml file at {d}:{d}", .{ line, col });
                        return error.DanglingMinusSign;
                    }
                    break :blk .{
                        .number = try std.fmt.parseInt(i64, src[start..i], 10),
                    };
                },
                '[' => .l_bracket,
                ']' => .r_bracket,
                '=' => .equals,
                else => {
                    std.log.err("Unrecognized token in toml file: '{c}' at {d}:{d}", .{ src[i], line, col });
                    return error.UnrecognizedToken;
                },
            };
            if (next) |tok| {
                try tokens.append(arena, tok);
                try positions.append(arena, .{ .col = col, .line = line });
            }
            col += 1;
        }

        return .{
            .tokens = tokens.items,
            .positions = positions.items,
        };
    }
};
