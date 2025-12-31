//! Liquid filters implementation
//! Each filter transforms a value based on its arguments

const std = @import("std");
const Allocator = std.mem.Allocator;
const Value = @import("value.zig").Value;

pub const FilterError = error{
    OutOfMemory,
    InvalidArgument,
    TypeError,
};

/// Apply a named filter to a value with optional arguments
pub fn apply(
    allocator: Allocator,
    filter_name: []const u8,
    value: Value,
    args: []const Value,
) FilterError!Value {
    // Route to specific filter implementations
    if (std.mem.eql(u8, filter_name, "upcase")) {
        return filterUpcase(allocator, value);
    } else if (std.mem.eql(u8, filter_name, "downcase")) {
        return filterDowncase(allocator, value);
    } else if (std.mem.eql(u8, filter_name, "capitalize")) {
        return filterCapitalize(allocator, value);
    } else if (std.mem.eql(u8, filter_name, "reverse")) {
        return filterReverse(allocator, value);
    } else if (std.mem.eql(u8, filter_name, "size")) {
        return filterSize(allocator, value);
    } else if (std.mem.eql(u8, filter_name, "join")) {
        const sep = if (args.len > 0) args[0] else Value.initString(" ");
        return filterJoin(allocator, value, sep);
    } else if (std.mem.eql(u8, filter_name, "split")) {
        if (args.len == 0) return FilterError.InvalidArgument;
        return filterSplit(allocator, value, args[0]);
    } else if (std.mem.eql(u8, filter_name, "strip")) {
        return filterStrip(allocator, value);
    } else if (std.mem.eql(u8, filter_name, "lstrip")) {
        return filterLstrip(allocator, value);
    } else if (std.mem.eql(u8, filter_name, "rstrip")) {
        return filterRstrip(allocator, value);
    } else if (std.mem.eql(u8, filter_name, "plus")) {
        if (args.len == 0) return FilterError.InvalidArgument;
        return filterPlus(value, args[0]);
    } else if (std.mem.eql(u8, filter_name, "minus")) {
        if (args.len == 0) return FilterError.InvalidArgument;
        return filterMinus(value, args[0]);
    } else if (std.mem.eql(u8, filter_name, "times")) {
        if (args.len == 0) return FilterError.InvalidArgument;
        return filterTimes(value, args[0]);
    } else if (std.mem.eql(u8, filter_name, "divided_by")) {
        if (args.len == 0) return FilterError.InvalidArgument;
        return filterDividedBy(value, args[0]);
    } else if (std.mem.eql(u8, filter_name, "modulo")) {
        if (args.len == 0) return FilterError.InvalidArgument;
        return filterModulo(value, args[0]);
    } else if (std.mem.eql(u8, filter_name, "ceil")) {
        return filterCeil(value);
    } else if (std.mem.eql(u8, filter_name, "floor")) {
        return filterFloor(value);
    } else if (std.mem.eql(u8, filter_name, "round")) {
        const places = if (args.len > 0) args[0] else Value.initInt(0);
        return filterRound(value, places);
    } else if (std.mem.eql(u8, filter_name, "abs")) {
        return filterAbs(value);
    } else if (std.mem.eql(u8, filter_name, "default")) {
        if (args.len == 0) return FilterError.InvalidArgument;
        return filterDefault(value, args[0]);
    } else if (std.mem.eql(u8, filter_name, "first")) {
        return filterFirst(allocator, value);
    } else if (std.mem.eql(u8, filter_name, "last")) {
        return filterLast(allocator, value);
    } else if (std.mem.eql(u8, filter_name, "map")) {
        if (args.len == 0) return FilterError.InvalidArgument;
        return filterMap(allocator, value, args[0]);
    } else if (std.mem.eql(u8, filter_name, "where")) {
        if (args.len == 0) return FilterError.InvalidArgument;
        return filterWhere(allocator, value, args[0], if (args.len > 1) args[1] else Value.initBool(true));
    } else if (std.mem.eql(u8, filter_name, "sort")) {
        return filterSort(allocator, value);
    } else if (std.mem.eql(u8, filter_name, "uniq")) {
        return filterUniq(allocator, value);
    } else if (std.mem.eql(u8, filter_name, "compact")) {
        return filterCompact(allocator, value);
    } else if (std.mem.eql(u8, filter_name, "escape") or std.mem.eql(u8, filter_name, "escape_once")) {
        return filterEscape(allocator, value);
    } else if (std.mem.eql(u8, filter_name, "json")) {
        return filterJson(allocator, value);
    } else if (std.mem.eql(u8, filter_name, "truncate")) {
        const length = if (args.len > 0) args[0].toInt() orelse 50 else 50;
        const ellipsis = if (args.len > 1) args[1].toString() else "...";
        return filterTruncate(allocator, value, length, ellipsis);
    } else if (std.mem.eql(u8, filter_name, "truncatewords")) {
        const words = if (args.len > 0) args[0].toInt() orelse 15 else 15;
        const ellipsis = if (args.len > 1) args[1].toString() else "...";
        return filterTruncateWords(allocator, value, words, ellipsis);
    } else if (std.mem.eql(u8, filter_name, "strip_html")) {
        return filterStripHtml(allocator, value);
    } else if (std.mem.eql(u8, filter_name, "append")) {
        if (args.len == 0) return FilterError.InvalidArgument;
        return filterAppend(allocator, value, args[0]);
    } else if (std.mem.eql(u8, filter_name, "prepend")) {
        if (args.len == 0) return FilterError.InvalidArgument;
        return filterPrepend(allocator, value, args[0]);
    } else if (std.mem.eql(u8, filter_name, "date")) {
        const format = if (args.len > 0) args[0].toString() else "%Y-%m-%d";
        return filterDate(allocator, value, format);
    } else if (std.mem.eql(u8, filter_name, "sum")) {
        return filterSum(value);
    } else if (std.mem.eql(u8, filter_name, "at_least")) {
        if (args.len == 0) return FilterError.InvalidArgument;
        return filterAtLeast(value, args[0]);
    } else if (std.mem.eql(u8, filter_name, "at_most")) {
        if (args.len == 0) return FilterError.InvalidArgument;
        return filterAtMost(value, args[0]);
    } else if (std.mem.eql(u8, filter_name, "replace")) {
        if (args.len < 2) return FilterError.InvalidArgument;
        return filterReplace(allocator, value, args[0], args[1]);
    } else if (std.mem.eql(u8, filter_name, "replace_first")) {
        if (args.len < 2) return FilterError.InvalidArgument;
        return filterReplaceFirst(allocator, value, args[0], args[1]);
    } else if (std.mem.eql(u8, filter_name, "remove")) {
        if (args.len == 0) return FilterError.InvalidArgument;
        return filterRemove(allocator, value, args[0]);
    } else if (std.mem.eql(u8, filter_name, "remove_first")) {
        if (args.len == 0) return FilterError.InvalidArgument;
        return filterRemoveFirst(allocator, value, args[0]);
    } else if (std.mem.eql(u8, filter_name, "newline_to_br") or std.mem.eql(u8, filter_name, "nl2br")) {
        return filterNewlineToBr(allocator, value);
    } else if (std.mem.eql(u8, filter_name, "strip_newlines")) {
        return filterStripNewlines(allocator, value);
    } else if (std.mem.eql(u8, filter_name, "url_encode")) {
        return filterUrlEncode(allocator, value);
    } else if (std.mem.eql(u8, filter_name, "url_decode")) {
        return filterUrlDecode(allocator, value);
    } else if (std.mem.eql(u8, filter_name, "slice")) {
        const start = if (args.len > 0) args[0].toInt() orelse 0 else 0;
        const length = if (args.len > 1) args[1].toInt() else null;
        return filterSlice(allocator, value, start, length);
    } else if (std.mem.eql(u8, filter_name, "concat")) {
        if (args.len == 0) return FilterError.InvalidArgument;
        return filterConcat(allocator, value, args[0]);
    } else if (std.mem.eql(u8, filter_name, "sort_natural")) {
        return filterSortNatural(allocator, value);
    }
    // Shopify-specific filters (mocked for benchmarking)
    else if (std.mem.eql(u8, filter_name, "t")) {
        // Translation filter - return key as-is (or first arg if provided)
        return value;
    } else if (std.mem.eql(u8, filter_name, "asset_url")) {
        // Return /assets/{value}
        return filterAssetUrl(allocator, value);
    } else if (std.mem.eql(u8, filter_name, "image_url")) {
        // Return value with image CDN params
        return filterImageUrl(allocator, value, args);
    } else if (std.mem.eql(u8, filter_name, "stylesheet_tag")) {
        return filterStylesheetTag(allocator, value);
    } else if (std.mem.eql(u8, filter_name, "script_tag")) {
        return filterScriptTag(allocator, value);
    } else if (std.mem.eql(u8, filter_name, "money") or std.mem.eql(u8, filter_name, "money_with_currency") or std.mem.eql(u8, filter_name, "money_without_currency")) {
        return filterMoney(allocator, value);
    } else if (std.mem.eql(u8, filter_name, "inline_asset_content")) {
        // Mock - return placeholder content
        return Value.initString("/* inline asset content */");
    } else if (std.mem.eql(u8, filter_name, "placeholder_svg_tag")) {
        return Value.initString("<svg></svg>");
    } else if (std.mem.eql(u8, filter_name, "font_face") or std.mem.eql(u8, filter_name, "font_url")) {
        return value;
    } else if (std.mem.eql(u8, filter_name, "time_tag")) {
        return filterTimeTag(allocator, value);
    } else if (std.mem.eql(u8, filter_name, "format_address")) {
        return value;
    } else if (std.mem.eql(u8, filter_name, "shopify_asset_url")) {
        return filterShopifyAssetUrl(allocator, value);
    } else if (std.mem.eql(u8, filter_name, "link_to")) {
        if (args.len == 0) return value;
        return filterLinkTo(allocator, value, args[0]);
    } else if (std.mem.eql(u8, filter_name, "img_tag") or std.mem.eql(u8, filter_name, "image_tag")) {
        return filterImgTag(allocator, value);
    } else if (std.mem.eql(u8, filter_name, "media_tag")) {
        return value;
    } else if (std.mem.eql(u8, filter_name, "structured_data")) {
        return Value.initString("");
    } else if (std.mem.eql(u8, filter_name, "line_items_for") or std.mem.eql(u8, filter_name, "item_count_for_variant")) {
        return Value.initInt(0);
    } else if (std.mem.eql(u8, filter_name, "payment_terms") or std.mem.eql(u8, filter_name, "payment_button") or std.mem.eql(u8, filter_name, "payment_type_svg_tag")) {
        return Value.initString("");
    } else if (std.mem.eql(u8, filter_name, "login_button")) {
        return Value.initString("<button>Login</button>");
    } else if (std.mem.eql(u8, filter_name, "avatar")) {
        return Value.initString("<img src=\"/avatar.png\" />");
    } else if (std.mem.eql(u8, filter_name, "format_code")) {
        return value;
    } else if (std.mem.eql(u8, filter_name, "default_errors")) {
        return value;
    } else if (std.mem.eql(u8, filter_name, "unit_price_with_measurement")) {
        return value;
    } else {
        // Unknown filter - return value unchanged
        return value;
    }
}

// Specific filter implementations

fn filterUpcase(allocator: Allocator, value: Value) FilterError!Value {
    const str = switch (value) {
        .string => |s| s,
        else => value.toDisplayString(allocator) catch |e| return if (e == std.mem.Allocator.Error.OutOfMemory) FilterError.OutOfMemory else FilterError.TypeError,
    };

    const result = std.ascii.allocUpperString(allocator, str) catch return FilterError.OutOfMemory;
    return Value.initString(result);
}

fn filterDowncase(allocator: Allocator, value: Value) FilterError!Value {
    const str = switch (value) {
        .string => |s| s,
        else => value.toDisplayString(allocator) catch |e| return if (e == std.mem.Allocator.Error.OutOfMemory) FilterError.OutOfMemory else FilterError.TypeError,
    };

    const result = std.ascii.allocLowerString(allocator, str) catch return FilterError.OutOfMemory;
    return Value.initString(result);
}

fn filterCapitalize(allocator: Allocator, value: Value) FilterError!Value {
    const str = switch (value) {
        .string => |s| s,
        else => value.toDisplayString(allocator) catch |e| return if (e == std.mem.Allocator.Error.OutOfMemory) FilterError.OutOfMemory else FilterError.TypeError,
    };

    if (str.len == 0) return Value.initString("");

    var result = allocator.alloc(u8, str.len) catch return FilterError.OutOfMemory;
    result[0] = std.ascii.toUpper(str[0]);
    if (str.len > 1) {
        @memcpy(result[1..], str[1..]);
    }
    return Value.initString(result);
}

fn filterReverse(allocator: Allocator, value: Value) FilterError!Value {
    return switch (value) {
        .string => |s| {
            var result = allocator.alloc(u8, s.len) catch return FilterError.OutOfMemory;
            var i: usize = 0;
            while (i < s.len) : (i += 1) {
                result[s.len - 1 - i] = s[i];
            }
            return Value.initString(result);
        },
        .array => |arr| {
            const new_arr = allocator.alloc(Value, arr.len) catch return FilterError.OutOfMemory;
            var i: usize = 0;
            while (i < arr.len) : (i += 1) {
                new_arr[arr.len - 1 - i] = arr[i];
            }
            return Value.initArray(new_arr);
        },
        else => FilterError.TypeError,
    };
}

fn filterSize(allocator: Allocator, value: Value) FilterError!Value {
    _ = allocator;
    return switch (value) {
        .string => |s| Value.initInt(@intCast(s.len)),
        .array => |arr| Value.initInt(@intCast(arr.len)),
        .object => |obj| Value.initInt(@intCast(obj.count())),
        else => Value.initInt(0),
    };
}

fn filterJoin(allocator: Allocator, value: Value, sep: Value) FilterError!Value {
    const arr = switch (value) {
        .array => |a| a,
        else => return FilterError.TypeError,
    };

    const sep_str = switch (sep) {
        .string => |s| s,
        else => sep.toDisplayString(allocator) catch return FilterError.OutOfMemory,
    };

    var result: std.ArrayList(u8) = .empty;
    defer result.deinit(allocator);

    for (arr, 0..) |item, i| {
        if (i > 0) {
            try result.appendSlice(allocator, sep_str);
        }
        const item_str = item.toDisplayString(allocator) catch return FilterError.OutOfMemory;
        try result.appendSlice(allocator, item_str);
    }

    return Value.initString(result.toOwnedSlice(allocator) catch return FilterError.OutOfMemory);
}

fn filterSplit(allocator: Allocator, value: Value, sep: Value) FilterError!Value {
    const str = switch (value) {
        .string => |s| s,
        else => return FilterError.TypeError,
    };

    const sep_str = switch (sep) {
        .string => |s| s,
        else => return FilterError.TypeError,
    };

    var parts: std.ArrayList(Value) = .empty;
    var iter = std.mem.splitSequence(u8, str, sep_str);
    while (iter.next()) |part| {
        try parts.append(allocator, Value.initString(part));
    }

    return Value.initArray(parts.items);
}

fn filterStrip(allocator: Allocator, value: Value) FilterError!Value {
     _ = allocator;
     const str = switch (value) {
         .string => |s| s,
         else => return FilterError.TypeError,
     };

    const trimmed = std.mem.trim(u8, str, " \t\n\r");
    return Value.initString(trimmed);
}

fn filterLstrip(allocator: Allocator, value: Value) FilterError!Value {
    _ = allocator;
    const str = switch (value) {
        .string => |s| s,
        else => return FilterError.TypeError,
    };

    const trimmed = std.mem.trimLeft(u8, str, " \t\n\r");
    return Value.initString(trimmed);
}

fn filterRstrip(allocator: Allocator, value: Value) FilterError!Value {
    _ = allocator;
    const str = switch (value) {
        .string => |s| s,
        else => return FilterError.TypeError,
    };

    const trimmed = std.mem.trimRight(u8, str, " \t\n\r");
    return Value.initString(trimmed);
}

fn filterPlus(lhs: Value, rhs: Value) FilterError!Value {
    return switch (lhs) {
        .integer => |l| switch (rhs) {
            .integer => |r| Value.initInt(l + r),
            .float => |r| Value.initFloat(@as(f64, @floatFromInt(l)) + r),
            else => FilterError.TypeError,
        },
        .float => |l| switch (rhs) {
            .integer => |r| Value.initFloat(l + @as(f64, @floatFromInt(r))),
            .float => |r| Value.initFloat(l + r),
            else => FilterError.TypeError,
        },
        .string => |l| switch (rhs) {
            .string => |r| Value.initString(std.fmt.comptimePrint("{s}{s}", .{ l, r })),
            else => FilterError.TypeError,
        },
        else => FilterError.TypeError,
    };
}

fn filterMinus(lhs: Value, rhs: Value) FilterError!Value {
    return switch (lhs) {
        .integer => |l| switch (rhs) {
            .integer => |r| Value.initInt(l - r),
            .float => |r| Value.initFloat(@as(f64, @floatFromInt(l)) - r),
            else => FilterError.TypeError,
        },
        .float => |l| switch (rhs) {
            .integer => |r| Value.initFloat(l - @as(f64, @floatFromInt(r))),
            .float => |r| Value.initFloat(l - r),
            else => FilterError.TypeError,
        },
        else => FilterError.TypeError,
    };
}

fn filterTimes(lhs: Value, rhs: Value) FilterError!Value {
    return switch (lhs) {
        .integer => |l| switch (rhs) {
            .integer => |r| Value.initInt(l * r),
            .float => |r| Value.initFloat(@as(f64, @floatFromInt(l)) * r),
            else => FilterError.TypeError,
        },
        .float => |l| switch (rhs) {
            .integer => |r| Value.initFloat(l * @as(f64, @floatFromInt(r))),
            .float => |r| Value.initFloat(l * r),
            else => FilterError.TypeError,
        },
        else => FilterError.TypeError,
    };
}

fn filterDividedBy(lhs: Value, rhs: Value) FilterError!Value {
    return switch (lhs) {
        .integer => |l| switch (rhs) {
            .integer => |r| if (r == 0) FilterError.InvalidArgument else Value.initInt(@divFloor(l, r)),
            .float => |r| if (r == 0) FilterError.InvalidArgument else Value.initFloat(@as(f64, @floatFromInt(l)) / r),
            else => FilterError.TypeError,
        },
        .float => |l| switch (rhs) {
            .integer => |r| if (r == 0) FilterError.InvalidArgument else Value.initFloat(l / @as(f64, @floatFromInt(r))),
            .float => |r| if (r == 0) FilterError.InvalidArgument else Value.initFloat(l / r),
            else => FilterError.TypeError,
        },
        else => FilterError.TypeError,
    };
}

fn filterModulo(lhs: Value, rhs: Value) FilterError!Value {
    return switch (lhs) {
        .integer => |l| switch (rhs) {
            .integer => |r| if (r == 0) FilterError.InvalidArgument else Value.initInt(@mod(l, r)),
            else => FilterError.TypeError,
        },
        else => FilterError.TypeError,
    };
}

fn filterCeil(value: Value) FilterError!Value {
    return switch (value) {
        .float => |f| Value.initInt(@intFromFloat(@ceil(f))),
        .integer => |i| Value.initInt(i),
        else => FilterError.TypeError,
    };
}

fn filterFloor(value: Value) FilterError!Value {
    return switch (value) {
        .float => |f| Value.initInt(@intFromFloat(@floor(f))),
        .integer => |i| Value.initInt(i),
        else => FilterError.TypeError,
    };
}

fn filterRound(value: Value, places: Value) FilterError!Value {
    const digits = switch (places) {
        .integer => |i| @max(0, i),
        else => 0,
    };

    return switch (value) {
        .float => |f| {
            if (digits == 0) {
                return Value.initInt(@intFromFloat(@round(f)));
            }
            const multiplier = std.math.pow(f64, 10, @floatFromInt(digits));
            const rounded = @round(f * multiplier) / multiplier;
            return Value.initFloat(rounded);
        },
        .integer => |i| Value.initInt(i),
        else => FilterError.TypeError,
    };
}

fn filterAbs(value: Value) FilterError!Value {
    return switch (value) {
        .integer => |i| Value.initInt(@abs(i)),
        .float => |f| Value.initFloat(@abs(f)),
        else => FilterError.TypeError,
    };
}

fn filterDefault(value: Value, default: Value) FilterError!Value {
    return switch (value) {
        .nil, .blank, .empty => default,
        else => value,
    };
}

fn filterFirst(allocator: Allocator, value: Value) FilterError!Value {
    _ = allocator;
    return switch (value) {
        .array => |arr| if (arr.len > 0) arr[0] else Value.initNil(),
        else => FilterError.TypeError,
    };
}

fn filterLast(allocator: Allocator, value: Value) FilterError!Value {
    _ = allocator;
    return switch (value) {
        .array => |arr| if (arr.len > 0) arr[arr.len - 1] else Value.initNil(),
        else => FilterError.TypeError,
    };
}

fn filterMap(allocator: Allocator, value: Value, key: Value) FilterError!Value {
    const arr = switch (value) {
        .array => |a| a,
        else => return FilterError.TypeError,
    };

    const key_str = switch (key) {
        .string => |s| s,
        else => return FilterError.TypeError,
    };

    var result: std.ArrayList(Value) = .empty;
    for (arr) |item| {
        if (item.get(key_str)) |val| {
            try result.append(allocator, val);
        }
    }

    return Value.initArray(result.items);
}

fn filterWhere(allocator: Allocator, value: Value, key: Value, filter_val: Value) FilterError!Value {
    const arr = switch (value) {
        .array => |a| a,
        else => return FilterError.TypeError,
    };

    const key_str = switch (key) {
        .string => |s| s,
        else => return FilterError.TypeError,
    };

    var result: std.ArrayList(Value) = .empty;
    for (arr) |item| {
        if (item.get(key_str)) |val| {
            if (val.isTruthy() and filter_val.isTruthy()) {
                try result.append(allocator, item);
            }
        }
    }

    return Value.initArray(result.items);
}

fn filterSort(allocator: Allocator, value: Value) FilterError!Value {
    const arr = switch (value) {
        .array => |a| a,
        else => return FilterError.TypeError,
    };

    const sorted = try allocator.alloc(Value, arr.len);
    @memcpy(sorted, arr);

    std.sort.insertion(Value, sorted, {}, struct {
        fn lessThan(_: void, a: Value, b: Value) bool {
            return a.compare(b) == .less;
        }
    }.lessThan);

    return Value.initArray(sorted);
}

fn filterUniq(allocator: Allocator, value: Value) FilterError!Value {
    const arr = switch (value) {
        .array => |a| a,
        else => return FilterError.TypeError,
    };

    var unique: std.ArrayList(Value) = .empty;
    for (arr) |item| {
        var found = false;
        for (unique.items) |existing| {
            if (item.compare(existing) == .equal) {
                found = true;
                break;
            }
        }
        if (!found) {
            try unique.append(allocator, item);
        }
    }

    return Value.initArray(unique.items);
}

fn filterCompact(allocator: Allocator, value: Value) FilterError!Value {
    const arr = switch (value) {
        .array => |a| a,
        else => return FilterError.TypeError,
    };

    var compacted: std.ArrayList(Value) = .empty;
    for (arr) |item| {
        if (!item.isNil()) {
            try compacted.append(allocator, item);
        }
    }

    return Value.initArray(compacted.items);
}

fn filterEscape(allocator: Allocator, value: Value) FilterError!Value {
    const str = switch (value) {
        .string => |s| s,
        else => value.toDisplayString(allocator) catch return FilterError.OutOfMemory,
    };

    var result: std.ArrayList(u8) = .empty;
    for (str) |c| {
        switch (c) {
            '&' => result.appendSlice(allocator, "&amp;") catch return FilterError.OutOfMemory,
            '<' => result.appendSlice(allocator, "&lt;") catch return FilterError.OutOfMemory,
            '>' => result.appendSlice(allocator, "&gt;") catch return FilterError.OutOfMemory,
            '"' => result.appendSlice(allocator, "&quot;") catch return FilterError.OutOfMemory,
            '\'' => result.appendSlice(allocator, "&#39;") catch return FilterError.OutOfMemory,
            else => result.append(allocator, c) catch return FilterError.OutOfMemory,
        }
    }
    return Value.initString(result.items);
}

fn filterJson(allocator: Allocator, value: Value) FilterError!Value {
    const result = value.toJsonString(allocator) catch return FilterError.OutOfMemory;
    return Value.initString(result);
}

fn filterTruncate(allocator: Allocator, value: Value, length: i64, ellipsis: []const u8) FilterError!Value {
    const str = switch (value) {
        .string => |s| s,
        else => value.toDisplayString(allocator) catch return FilterError.OutOfMemory,
    };

    const len: usize = @intCast(@max(0, length));
    if (str.len <= len) return Value.initString(str);

    const ellipsis_len = ellipsis.len;
    if (len <= ellipsis_len) {
        return Value.initString(ellipsis);
    }

    const result = allocator.alloc(u8, len) catch return FilterError.OutOfMemory;
    @memcpy(result[0 .. len - ellipsis_len], str[0 .. len - ellipsis_len]);
    @memcpy(result[len - ellipsis_len ..], ellipsis);
    return Value.initString(result);
}

fn filterTruncateWords(allocator: Allocator, value: Value, word_count: i64, ellipsis: []const u8) FilterError!Value {
    const str = switch (value) {
        .string => |s| s,
        else => value.toDisplayString(allocator) catch return FilterError.OutOfMemory,
    };

    const count: usize = @intCast(@max(0, word_count));
    var words_found: usize = 0;
    var end_pos: usize = 0;
    var in_word = false;

    for (str, 0..) |c, i| {
        const is_space = c == ' ' or c == '\t' or c == '\n' or c == '\r';
        if (in_word and is_space) {
            words_found += 1;
            if (words_found >= count) {
                end_pos = i;
                break;
            }
        }
        in_word = !is_space;
        end_pos = i + 1;
    }

    // Count final word if we ended in one
    if (in_word and words_found < count) {
        words_found += 1;
    }

    if (words_found <= count and end_pos == str.len) {
        return Value.initString(str);
    }

    const result = allocator.alloc(u8, end_pos + ellipsis.len) catch return FilterError.OutOfMemory;
    @memcpy(result[0..end_pos], str[0..end_pos]);
    @memcpy(result[end_pos..], ellipsis);
    return Value.initString(result);
}

fn filterStripHtml(allocator: Allocator, value: Value) FilterError!Value {
    const str = switch (value) {
        .string => |s| s,
        else => value.toDisplayString(allocator) catch return FilterError.OutOfMemory,
    };

    var result: std.ArrayList(u8) = .empty;
    var in_tag = false;

    for (str) |c| {
        if (c == '<') {
            in_tag = true;
        } else if (c == '>') {
            in_tag = false;
        } else if (!in_tag) {
            result.append(allocator, c) catch return FilterError.OutOfMemory;
        }
    }
    return Value.initString(result.items);
}

fn filterAppend(allocator: Allocator, value: Value, suffix: Value) FilterError!Value {
    const str = switch (value) {
        .string => |s| s,
        else => value.toDisplayString(allocator) catch return FilterError.OutOfMemory,
    };
    const suffix_str = switch (suffix) {
        .string => |s| s,
        else => suffix.toDisplayString(allocator) catch return FilterError.OutOfMemory,
    };

    const result = allocator.alloc(u8, str.len + suffix_str.len) catch return FilterError.OutOfMemory;
    @memcpy(result[0..str.len], str);
    @memcpy(result[str.len..], suffix_str);
    return Value.initString(result);
}

fn filterPrepend(allocator: Allocator, value: Value, prefix: Value) FilterError!Value {
    const str = switch (value) {
        .string => |s| s,
        else => value.toDisplayString(allocator) catch return FilterError.OutOfMemory,
    };
    const prefix_str = switch (prefix) {
        .string => |s| s,
        else => prefix.toDisplayString(allocator) catch return FilterError.OutOfMemory,
    };

    const result = allocator.alloc(u8, prefix_str.len + str.len) catch return FilterError.OutOfMemory;
    @memcpy(result[0..prefix_str.len], prefix_str);
    @memcpy(result[prefix_str.len..], str);
    return Value.initString(result);
}

fn filterDate(allocator: Allocator, value: Value, format: []const u8) FilterError!Value {
    _ = format;
    // Simple date filter - for now just return the string representation
    // Full implementation would parse dates and format them
    const str = switch (value) {
        .string => |s| s,
        else => value.toDisplayString(allocator) catch return FilterError.OutOfMemory,
    };
    return Value.initString(str);
}

fn filterSum(value: Value) FilterError!Value {
    const arr = switch (value) {
        .array => |a| a,
        else => return FilterError.TypeError,
    };

    var sum: f64 = 0;
    for (arr) |item| {
        sum += item.toFloat() orelse 0;
    }
    return Value.initFloat(sum);
}

fn filterAtLeast(value: Value, min: Value) FilterError!Value {
    const val = value.toFloat() orelse return FilterError.TypeError;
    const min_val = min.toFloat() orelse return FilterError.TypeError;
    return if (val < min_val) Value.initFloat(min_val) else value;
}

fn filterAtMost(value: Value, max: Value) FilterError!Value {
    const val = value.toFloat() orelse return FilterError.TypeError;
    const max_val = max.toFloat() orelse return FilterError.TypeError;
    return if (val > max_val) Value.initFloat(max_val) else value;
}

fn filterReplace(allocator: Allocator, value: Value, search: Value, replacement: Value) FilterError!Value {
    const str = switch (value) {
        .string => |s| s,
        else => value.toDisplayString(allocator) catch return FilterError.OutOfMemory,
    };
    const search_str = switch (search) {
        .string => |s| s,
        else => search.toDisplayString(allocator) catch return FilterError.OutOfMemory,
    };
    const replace_str = switch (replacement) {
        .string => |s| s,
        else => replacement.toDisplayString(allocator) catch return FilterError.OutOfMemory,
    };

    if (search_str.len == 0) return Value.initString(str);

    var result: std.ArrayList(u8) = .empty;
    var i: usize = 0;
    while (i < str.len) {
        if (i + search_str.len <= str.len and std.mem.eql(u8, str[i .. i + search_str.len], search_str)) {
            result.appendSlice(allocator, replace_str) catch return FilterError.OutOfMemory;
            i += search_str.len;
        } else {
            result.append(allocator, str[i]) catch return FilterError.OutOfMemory;
            i += 1;
        }
    }
    return Value.initString(result.items);
}

fn filterReplaceFirst(allocator: Allocator, value: Value, search: Value, replacement: Value) FilterError!Value {
    const str = switch (value) {
        .string => |s| s,
        else => value.toDisplayString(allocator) catch return FilterError.OutOfMemory,
    };
    const search_str = switch (search) {
        .string => |s| s,
        else => search.toDisplayString(allocator) catch return FilterError.OutOfMemory,
    };
    const replace_str = switch (replacement) {
        .string => |s| s,
        else => replacement.toDisplayString(allocator) catch return FilterError.OutOfMemory,
    };

    if (search_str.len == 0) return Value.initString(str);

    if (std.mem.indexOf(u8, str, search_str)) |pos| {
        const new_len = str.len - search_str.len + replace_str.len;
        const result = allocator.alloc(u8, new_len) catch return FilterError.OutOfMemory;
        @memcpy(result[0..pos], str[0..pos]);
        @memcpy(result[pos .. pos + replace_str.len], replace_str);
        @memcpy(result[pos + replace_str.len ..], str[pos + search_str.len ..]);
        return Value.initString(result);
    }
    return Value.initString(str);
}

fn filterRemove(allocator: Allocator, value: Value, search: Value) FilterError!Value {
    return filterReplace(allocator, value, search, Value.initString(""));
}

fn filterRemoveFirst(allocator: Allocator, value: Value, search: Value) FilterError!Value {
    return filterReplaceFirst(allocator, value, search, Value.initString(""));
}

fn filterNewlineToBr(allocator: Allocator, value: Value) FilterError!Value {
    const str = switch (value) {
        .string => |s| s,
        else => value.toDisplayString(allocator) catch return FilterError.OutOfMemory,
    };

    var result: std.ArrayList(u8) = .empty;
    for (str) |c| {
        if (c == '\n') {
            result.appendSlice(allocator, "<br />\n") catch return FilterError.OutOfMemory;
        } else {
            result.append(allocator, c) catch return FilterError.OutOfMemory;
        }
    }
    return Value.initString(result.items);
}

fn filterStripNewlines(allocator: Allocator, value: Value) FilterError!Value {
    const str = switch (value) {
        .string => |s| s,
        else => value.toDisplayString(allocator) catch return FilterError.OutOfMemory,
    };

    var result: std.ArrayList(u8) = .empty;
    for (str) |c| {
        if (c != '\n' and c != '\r') {
            result.append(allocator, c) catch return FilterError.OutOfMemory;
        }
    }
    return Value.initString(result.items);
}

fn filterUrlEncode(allocator: Allocator, value: Value) FilterError!Value {
    const str = switch (value) {
        .string => |s| s,
        else => value.toDisplayString(allocator) catch return FilterError.OutOfMemory,
    };

    var result: std.ArrayList(u8) = .empty;
    for (str) |c| {
        if (std.ascii.isAlphanumeric(c) or c == '-' or c == '_' or c == '.' or c == '~') {
            result.append(allocator, c) catch return FilterError.OutOfMemory;
        } else if (c == ' ') {
            result.append(allocator, '+') catch return FilterError.OutOfMemory;
        } else {
            result.append(allocator, '%') catch return FilterError.OutOfMemory;
            const hex = "0123456789ABCDEF";
            result.append(allocator, hex[c >> 4]) catch return FilterError.OutOfMemory;
            result.append(allocator, hex[c & 0x0F]) catch return FilterError.OutOfMemory;
        }
    }
    return Value.initString(result.items);
}

fn filterUrlDecode(allocator: Allocator, value: Value) FilterError!Value {
    const str = switch (value) {
        .string => |s| s,
        else => value.toDisplayString(allocator) catch return FilterError.OutOfMemory,
    };

    var result: std.ArrayList(u8) = .empty;
    var i: usize = 0;
    while (i < str.len) {
        if (str[i] == '%' and i + 2 < str.len) {
            const hi = std.fmt.charToDigit(str[i + 1], 16) catch {
                result.append(allocator, str[i]) catch return FilterError.OutOfMemory;
                i += 1;
                continue;
            };
            const lo = std.fmt.charToDigit(str[i + 2], 16) catch {
                result.append(allocator, str[i]) catch return FilterError.OutOfMemory;
                i += 1;
                continue;
            };
            result.append(allocator, (hi << 4) | lo) catch return FilterError.OutOfMemory;
            i += 3;
        } else if (str[i] == '+') {
            result.append(allocator, ' ') catch return FilterError.OutOfMemory;
            i += 1;
        } else {
            result.append(allocator, str[i]) catch return FilterError.OutOfMemory;
            i += 1;
        }
    }
    return Value.initString(result.items);
}

fn filterSlice(allocator: Allocator, value: Value, start: i64, length: ?i64) FilterError!Value {
    return switch (value) {
        .string => |s| {
            const len = s.len;
            const actual_start: usize = if (start < 0)
                @intCast(@max(0, @as(i64, @intCast(len)) + start))
            else
                @intCast(@min(@as(i64, @intCast(len)), start));

            const actual_len = if (length) |l|
                @as(usize, @intCast(@max(0, @min(@as(i64, @intCast(len - actual_start)), l))))
            else
                1; // Default to single character

            if (actual_start >= len) return Value.initString("");
            const result = allocator.dupe(u8, s[actual_start..][0..actual_len]) catch return FilterError.OutOfMemory;
            return Value.initString(result);
        },
        .array => |arr| {
            const len = arr.len;
            const actual_start: usize = if (start < 0)
                @intCast(@max(0, @as(i64, @intCast(len)) + start))
            else
                @intCast(@min(@as(i64, @intCast(len)), start));

            const actual_len = if (length) |l|
                @as(usize, @intCast(@max(0, @min(@as(i64, @intCast(len - actual_start)), l))))
            else
                1;

            if (actual_start >= len) return Value.initArray(&[_]Value{});
            const result = allocator.dupe(Value, arr[actual_start..][0..actual_len]) catch return FilterError.OutOfMemory;
            return Value.initArray(result);
        },
        else => FilterError.TypeError,
    };
}

fn filterConcat(allocator: Allocator, value: Value, other: Value) FilterError!Value {
    const arr1 = switch (value) {
        .array => |a| a,
        else => return FilterError.TypeError,
    };
    const arr2 = switch (other) {
        .array => |a| a,
        else => return FilterError.TypeError,
    };

    const result = allocator.alloc(Value, arr1.len + arr2.len) catch return FilterError.OutOfMemory;
    @memcpy(result[0..arr1.len], arr1);
    @memcpy(result[arr1.len..], arr2);
    return Value.initArray(result);
}

fn filterSortNatural(allocator: Allocator, value: Value) FilterError!Value {
    const arr = switch (value) {
        .array => |a| a,
        else => return FilterError.TypeError,
    };

    const sorted = allocator.dupe(Value, arr) catch return FilterError.OutOfMemory;
    std.mem.sort(Value, sorted, allocator, struct {
        fn lessThan(alloc: Allocator, a: Value, b: Value) bool {
            const a_str = switch (a) {
                .string => |s| s,
                else => a.toDisplayString(alloc) catch return false,
            };
            const b_str = switch (b) {
                .string => |s| s,
                else => b.toDisplayString(alloc) catch return false,
            };
            return std.ascii.lessThanIgnoreCase(a_str, b_str);
        }
    }.lessThan);
    return Value.initArray(sorted);
}

// Shopify-specific filter implementations (mocked for benchmarking)

fn filterAssetUrl(allocator: Allocator, value: Value) FilterError!Value {
    const str = switch (value) {
        .string => |s| s,
        else => value.toDisplayString(allocator) catch return FilterError.OutOfMemory,
    };
    const result = std.fmt.allocPrint(allocator, "/assets/{s}", .{str}) catch return FilterError.OutOfMemory;
    return Value.initString(result);
}

fn filterImageUrl(allocator: Allocator, value: Value, args: []const Value) FilterError!Value {
    const str = switch (value) {
        .string => |s| s,
        else => value.toDisplayString(allocator) catch return FilterError.OutOfMemory,
    };
    // Get width param if provided
    const width = if (args.len > 0) args[0].toInt() orelse 100 else 100;
    const result = std.fmt.allocPrint(allocator, "{s}?width={d}", .{ str, width }) catch return FilterError.OutOfMemory;
    return Value.initString(result);
}

fn filterStylesheetTag(allocator: Allocator, value: Value) FilterError!Value {
    const str = switch (value) {
        .string => |s| s,
        else => value.toDisplayString(allocator) catch return FilterError.OutOfMemory,
    };
    const result = std.fmt.allocPrint(allocator, "<link rel=\"stylesheet\" href=\"{s}\" />", .{str}) catch return FilterError.OutOfMemory;
    return Value.initString(result);
}

fn filterScriptTag(allocator: Allocator, value: Value) FilterError!Value {
    const str = switch (value) {
        .string => |s| s,
        else => value.toDisplayString(allocator) catch return FilterError.OutOfMemory,
    };
    const result = std.fmt.allocPrint(allocator, "<script src=\"{s}\"></script>", .{str}) catch return FilterError.OutOfMemory;
    return Value.initString(result);
}

fn filterMoney(allocator: Allocator, value: Value) FilterError!Value {
    // Format cents as dollars
    const cents = value.toInt() orelse 0;
    const dollars = @divFloor(cents, 100);
    const remainder = @mod(cents, 100);
    const result = std.fmt.allocPrint(allocator, "${d}.{d:0>2}", .{ dollars, @abs(remainder) }) catch return FilterError.OutOfMemory;
    return Value.initString(result);
}

fn filterTimeTag(allocator: Allocator, value: Value) FilterError!Value {
    const str = switch (value) {
        .string => |s| s,
        else => value.toDisplayString(allocator) catch return FilterError.OutOfMemory,
    };
    const result = std.fmt.allocPrint(allocator, "<time datetime=\"{s}\">{s}</time>", .{ str, str }) catch return FilterError.OutOfMemory;
    return Value.initString(result);
}

fn filterShopifyAssetUrl(allocator: Allocator, value: Value) FilterError!Value {
    const str = switch (value) {
        .string => |s| s,
        else => value.toDisplayString(allocator) catch return FilterError.OutOfMemory,
    };
    const result = std.fmt.allocPrint(allocator, "//cdn.shopify.com/s/{s}", .{str}) catch return FilterError.OutOfMemory;
    return Value.initString(result);
}

fn filterLinkTo(allocator: Allocator, value: Value, url: Value) FilterError!Value {
    const text = switch (value) {
        .string => |s| s,
        else => value.toDisplayString(allocator) catch return FilterError.OutOfMemory,
    };
    const href = switch (url) {
        .string => |s| s,
        else => url.toDisplayString(allocator) catch return FilterError.OutOfMemory,
    };
    const result = std.fmt.allocPrint(allocator, "<a href=\"{s}\">{s}</a>", .{ href, text }) catch return FilterError.OutOfMemory;
    return Value.initString(result);
}

fn filterImgTag(allocator: Allocator, value: Value) FilterError!Value {
    const str = switch (value) {
        .string => |s| s,
        else => value.toDisplayString(allocator) catch return FilterError.OutOfMemory,
    };
    const result = std.fmt.allocPrint(allocator, "<img src=\"{s}\" />", .{str}) catch return FilterError.OutOfMemory;
    return Value.initString(result);
}
