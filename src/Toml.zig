//! Small purpose-built TOML parser whose job is to parse the 'flint.toml' file
//! The actual TOML tokenization is done by `tomlc17`, this module maps the
//! resulting document onto the schema used by the Flint toolchain and validates it.
const std = @import("std");
const toml = @import("toml");

const Self = @This();

// Flags to enable debug printing
const PRINT_DEPS = false;

var cached: ?std.StringHashMap(Entry) = null;

config: Config,
deps: []const Dep,

const Entry = struct {
    value: Self,
    result: toml.toml_result_t,
};

pub const Config = struct {
    indentation: ?u32 = null,
    main: ?[]const u8 = null,
    lib: ?[]const u8 = null,

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
            pub const TagOrRev = union(enum) {
                // NOTE: This value is only intended to be used during parsing, after parsing no value should be 'none', at all
                none: void,
                tag: []const u8,
                rev: []const u8,
            };

            url: []const u8 = "",
            tag_or_rev: TagOrRev = .none,
            sha256: []const u8 = "",
        };
    };
};

pub fn deinit() void {
    if (cached) |*map| {
        var iter = map.valueIterator();
        while (iter.next()) |entry| {
            toml.toml_free(entry.result);
        }
        map.deinit();
        cached = null;
    }
}

pub fn get(io: std.Io, arena: std.mem.Allocator, path: []const u8) !Self {
    if (cached == null) {
        cached = std.StringHashMap(Entry).init(arena);
    }
    var map = &cached.?;
    if (map.get(path)) |t| {
        return t.value;
    }

    const src: []const u8 = std.Io.Dir.cwd().readFileAlloc(io, path, arena, .unlimited) catch |err| switch (err) {
        error.FileNotFound => {
            var cwd_buffer: [std.fs.max_path_bytes]u8 = @splat(0);
            const path_len = try std.Io.Dir.cwd().realPath(io, &cwd_buffer);
            std.log.warn("'{s}/{s}' file not found", .{ cwd_buffer[0..path_len], path });
            std.log.warn("Please run 'flint init' to init a new Flint project or change your working directory", .{});
            return error.MissingTomlFile;
        },
        else => return err,
    };
    if (src.len > std.math.maxInt(c_int)) {
        return error.TomlFileTooLarge;
    }

    // `toml_parse` requires a NUL terminated buffer; `len` excludes the terminator.
    const src_z: [:0]const u8 = try arena.dupeSentinel(u8, src, 0);
    var result = toml.toml_parse(src_z.ptr, @intCast(src.len));
    errdefer toml.toml_free(result);

    if (!result.ok) {
        std.log.err("Failed to parse '{s}' file: {s}", .{ path, std.mem.sliceTo(&result.errmsg, 0) });
        return error.MalformedTomlFile;
    }

    const parsed = try parseResult(arena, result);
    try map.put(try arena.dupe(u8, path), .{
        .value = parsed,
        .result = result,
    });
    return parsed;
}

fn parseResult(arena: std.mem.Allocator, result: toml.toml_result_t) !Self {
    var config: Config = .{};
    var config_parsed: bool = false;
    var deps_list: std.ArrayList(Dep) = .empty;
    var dep_names: std.StringHashMap(void) = std.StringHashMap(void).init(arena);

    const root = result.toptab;
    if (root.type != toml.TOML_TABLE) {
        std.log.err("Expected the TOML document to start with a table", .{});
        return error.MalformedTomlFile;
    }
    const entries = root.u.tab;
    if (entries.size > 0) {
        if (entries.key == null or entries.value == null) {
            return error.MalformedTomlFile;
        }
        for (0..@intCast(entries.size)) |i| {
            const name = std.mem.span(entries.key[i]);
            const value = entries.value[i];

            if (std.mem.eql(u8, name, "config")) {
                if (config_parsed) {
                    std.log.err("Duplicate 'config' section found", .{});
                    return error.ConfigDuplicateSection;
                }
                config_parsed = true;
                if (value.type != toml.TOML_TABLE) {
                    std.log.err("Expected '[config]' to be a table, but got '{s}'", .{typeName(value.type)});
                    return error.IncorrectTypeOfField;
                }
                try parseConfig(value, &config);
                continue;
            }

            if (value.type != toml.TOML_TABLE) {
                std.log.err("Expected section '[{s}]' to be a table, but got '{s}'", .{ name, typeName(value.type) });
                return error.IncorrectTypeOfField;
            }
            if (dep_names.contains(name)) {
                std.log.err("Duplicate dependency section '[{s}]' found", .{name});
                return error.DependencyDuplicateSection;
            }
            try dep_names.put(name, {});
            try deps_list.append(arena, try parseDep(name, value));
        }
    }

    const self: Self = .{
        .config = config,
        .deps = deps_list.items,
    };

    if (PRINT_DEPS) {
        std.debug.print("\n======= DEPS BEGIN =======\n", .{});
        if (config_parsed) {
            std.debug.print("[config]\n", .{});
            if (config.indentation) |indentation| {
                std.debug.print("indentation = {d}\n", .{indentation});
            }
            if (config.main) |main| {
                std.debug.print("main = {q}\n", .{main});
            }
            if (config.lib) |lib| {
                std.debug.print("lib = {q}\n", .{lib});
            }
            std.debug.print("\n", .{});
        }
        for (self.deps, 0..) |dep, j| {
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
                .path => |p| std.debug.print("path = {q}\n", .{p}),
                .link => |link| {
                    std.debug.print("url = {q}\n", .{link.url});
                    switch (link.tag_or_rev) {
                        .none => unreachable,
                        .tag => |tag| std.debug.print("tag = {q}\n", .{tag}),
                        .rev => |rev| std.debug.print("rev = {q}\n", .{rev}),
                    }
                    std.debug.print("sha256 = {q}\n", .{link.sha256});
                },
            }
        }
        std.debug.print("======== DEPS END ========\n", .{});
    }

    return self;
}

fn parseConfig(table: toml.toml_datum_t, config: *Config) !void {
    var indentation_parsed: bool = false;
    var main_parsed: bool = false;
    var lib_parsed: bool = false;

    const fields = table.u.tab;
    if (fields.size > 0) {
        if (fields.key == null or fields.value == null) {
            return error.MalformedTomlFile;
        }
        for (0..@intCast(fields.size)) |i| {
            const name = std.mem.span(fields.key[i]);
            const value = fields.value[i];

            if (std.mem.eql(u8, name, "indentation")) {
                if (indentation_parsed) {
                    std.log.err("Duplicate field 'indentation' found in 'config' section", .{});
                    return error.ConfigDuplicateField;
                }
                indentation_parsed = true;
                try expectType(value, toml.TOML_INT64, "indentation");
                if (value.u.int64 < 1) {
                    std.log.err("Value of field 'indentation' has a minimum settable value of '1'", .{});
                    return error.ConfigIndentationTooSmall;
                }
                if (value.u.int64 > std.math.maxInt(u32)) {
                    std.log.err("Value of field 'indentation' has a maximum settable value of '{d}'", .{std.math.maxInt(u32)});
                    return error.ConfigIndentationTooLarge;
                }
                config.indentation = @intCast(value.u.int64);
            } else if (std.mem.eql(u8, name, "main")) {
                if (main_parsed) {
                    std.log.err("Duplicate field 'main' found in 'config' section", .{});
                    return error.ConfigDuplicateField;
                }
                main_parsed = true;
                try expectType(value, toml.TOML_STRING, "main");
                config.main = std.mem.span(value.u.str.ptr);
            } else if (std.mem.eql(u8, name, "lib")) {
                if (lib_parsed) {
                    std.log.err("Duplicate field 'lib' found in 'config' section", .{});
                    return error.ConfigDuplicateField;
                }
                lib_parsed = true;
                try expectType(value, toml.TOML_STRING, "lib");
                config.lib = std.mem.span(value.u.str.ptr);
            } else {
                std.log.err("Unrecognized 'config' field: {s}", .{name});
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
        }
    }
}

fn parseDep(name: []const u8, table: toml.toml_datum_t) !Dep {
    var kind_parsed: bool = false;
    var kind: []const u8 = "";

    var path_parsed: bool = false;
    var dep_path: []const u8 = "";

    var url_parsed: bool = false;
    var tag_parsed: bool = false;
    var rev_parsed: bool = false;
    var sha256_parsed: bool = false;
    var url: []const u8 = "";
    var tag_or_rev: Dep.Src.Link.TagOrRev = .none;
    var sha256: []const u8 = "";

    const fields = table.u.tab;
    if (fields.size > 0) {
        if (fields.key == null or fields.value == null) {
            return error.MalformedTomlFile;
        }
        for (0..@intCast(fields.size)) |i| {
            const field_name = std.mem.span(fields.key[i]);
            const value = fields.value[i];

            if (std.mem.eql(u8, field_name, "kind")) {
                try expectType(value, toml.TOML_STRING, "kind");
                if (kind_parsed) {
                    std.log.err("Duplicate field 'kind' in dependency '{s}'", .{name});
                    return error.DependencyDuplicateField;
                }
                kind_parsed = true;
                kind = std.mem.span(value.u.str.ptr);
            } else if (std.mem.eql(u8, field_name, "path")) {
                try expectType(value, toml.TOML_STRING, "path");
                try checkPathCoexistence(name, "path", url_parsed or tag_parsed or rev_parsed or sha256_parsed);
                if (path_parsed) {
                    std.log.err("Duplicate field 'path' in dependency '{s}'", .{name});
                    return error.DependencyDuplicateField;
                }
                path_parsed = true;
                dep_path = std.mem.span(value.u.str.ptr);
            } else if (std.mem.eql(u8, field_name, "url")) {
                try expectType(value, toml.TOML_STRING, "url");
                try checkPathCoexistence(name, "url", path_parsed);
                if (url_parsed) {
                    std.log.err("Duplicate field 'url' in dependency '{s}'", .{name});
                    return error.DependencyDuplicateField;
                }
                url_parsed = true;
                url = std.mem.span(value.u.str.ptr);
            } else if (std.mem.eql(u8, field_name, "tag")) {
                try expectType(value, toml.TOML_STRING, "tag");
                try checkPathCoexistence(name, "tag", path_parsed);
                if (tag_parsed) {
                    std.log.err("Duplicate field 'tag' in dependency '{s}'", .{name});
                    return error.DependencyDuplicateField;
                }
                if (rev_parsed) {
                    std.log.err("Field 'tag' in dependency '{s}' is not allowed to coexist with the 'rev' field. Choose one", .{name});
                    return error.DependencyTagWithRev;
                }
                tag_parsed = true;
                tag_or_rev = .{ .tag = std.mem.span(value.u.str.ptr) };
            } else if (std.mem.eql(u8, field_name, "rev")) {
                try expectType(value, toml.TOML_STRING, "rev");
                try checkPathCoexistence(name, "rev", path_parsed);
                if (rev_parsed) {
                    std.log.err("Duplicate field 'rev' in dependency '{s}'", .{name});
                    return error.DependencyDuplicateField;
                }
                if (tag_parsed) {
                    std.log.err("Field 'rev' in dependency '{s}' is not allowed to coexist with the 'tag' field. Choose one", .{name});
                    return error.DependencyTagWithRev;
                }
                rev_parsed = true;
                tag_or_rev = .{ .rev = std.mem.span(value.u.str.ptr) };
            } else if (std.mem.eql(u8, field_name, "sha256")) {
                try expectType(value, toml.TOML_STRING, "sha256");
                try checkPathCoexistence(name, "sha256", path_parsed);
                if (sha256_parsed) {
                    std.log.err("Duplicate field 'sha256' in dependency '{s}'", .{name});
                    return error.DependencyDuplicateField;
                }
                sha256_parsed = true;
                const hash = std.mem.span(value.u.str.ptr);
                if (!isValidSha256(hash)) {
                    std.log.err("Field 'sha256' in dependency '{s}' must be exactly 64 lowercase hexadecimal characters", .{name});
                    return error.InvalidSha256;
                }
                sha256 = hash;
            } else {
                std.log.err("Unrecognized field in dependency '{s}': {s}", .{ name, field_name });
                return error.DependencyUnrecognizedField;
            }
        }
    }

    if (!kind_parsed) {
        std.log.err("Missing required field 'kind' in dependency {s}", .{name});
        return error.MissingFieldKind;
    }

    var src: Dep.Src = .none;
    if (path_parsed) {
        src = .{ .path = dep_path };
    } else if (url_parsed or tag_parsed or rev_parsed or sha256_parsed) {
        if (!url_parsed) {
            std.log.err("Missing required field 'url' in dependency {s}", .{name});
            return error.MissingFieldUrl;
        }
        if (!tag_parsed and !rev_parsed) {
            std.log.err("Missing one of required fields 'tag' or 'rev' in dependency {s}", .{name});
            return error.MissingFieldTagOrRev;
        }
        if (!sha256_parsed) {
            std.log.err("Missing required field 'sha256' in dependency {s}", .{name});
            return error.MissingFieldSha256;
        }
        src = .{
            .link = .{
                .url = url,
                .tag_or_rev = tag_or_rev,
                .sha256 = sha256,
            },
        };
    } else {
        std.log.err("Missing path or url source in dependency '{s}'", .{name});
        return error.MissingPathOrUrlSource;
    }

    return .{
        .name = name,
        .kind = kind,
        .src = src,
    };
}

fn checkPathCoexistence(dep_name: []const u8, field_name: []const u8, other_present: bool) !void {
    if (other_present) {
        std.log.err("Field '{s}' in dependency '{s}' is not allowed to coexist with 'path' or url-based fields. Choose one", .{ field_name, dep_name });
        return error.DependencyPathWithUrl;
    }
}

fn isValidSha256(hash: []const u8) bool {
    if (hash.len != 64) {
        return false;
    }
    for (hash) |c| {
        const is_digit = c >= '0' and c <= '9';
        const is_lower_hex = c >= 'a' and c <= 'f';
        if (!is_digit and !is_lower_hex) {
            return false;
        }
    }
    return true;
}

fn expectType(value: toml.toml_datum_t, expected: toml.toml_type_t, field_name: []const u8) !void {
    if (value.type != expected) {
        std.log.err("Expected value of type '{s}' for field '{s}', but got '{s}'", .{
            typeName(expected),
            field_name,
            typeName(value.type),
        });
        return error.IncorrectTypeOfField;
    }
}

fn typeName(toml_type: toml.toml_type_t) []const u8 {
    return switch (toml_type) {
        toml.TOML_STRING => "string",
        toml.TOML_INT64 => "number",
        toml.TOML_FP64 => "number",
        toml.TOML_BOOLEAN => "bool",
        toml.TOML_ARRAY => "array",
        toml.TOML_TABLE => "table",
        else => "unknown",
    };
}
