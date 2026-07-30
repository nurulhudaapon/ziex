const std = @import("std");

pub fn containsIgnoreCase(haystack: []const u8, needle: []const u8) bool {
    if (needle.len > haystack.len) return false;
    var i: usize = 0;
    while (i <= haystack.len - needle.len) : (i += 1) {
        var match = true;
        for (0..needle.len) |j| {
            if (std.ascii.toLower(haystack[i + j]) != std.ascii.toLower(needle[j])) {
                match = false;
                break;
            }
        }
        if (match) return true;
    }
    return false;
}
