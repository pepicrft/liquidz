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
