const std = @import("std");
const Http = @import("../Http.zig");
const Request = @import("Request.zig");
const Response = @import("Response.zig");
const common = @import("common.zig");
const MultiFormData = @import("MultiFormData.zig");
const ext = @import("../../server/wasm/extern.zig");

pub const HeaderEntry = struct { name: []const u8, value: []const u8 };

pub const Backend = struct {
    allocator: std.mem.Allocator,

    // --- request inputs --- //
    headers: []const HeaderEntry = &.{},
    search: []const u8 = "",
    body: []const u8 = "",
    content_type: []const u8 = "",
    cookie_header: []const u8 = "",
    route_match: ?Router.RouteMatch = null,

    // --- response accumulator --- //
    status: u16 = 200,
    resp_body: std.Io.Writer.Allocating,
    resp_headers: std.ArrayList(HeaderEntry) = .empty,

    // --- lazily-parsed form data --- //
    form: FormCache = .{},
    multi: MultiCache = .{},

    // --- websocket --- //
    upgraded: bool = false,
    upgrade_data_buf: [256]u8 = undefined,
    upgrade_data_len: usize = 0,

    const Router = @import("../Router.zig");

    pub fn init(allocator: std.mem.Allocator) Backend {
        return .{ .allocator = allocator, .resp_body = .init(allocator) };
    }

    pub fn deinit(self: *Backend) void {
        self.resp_body.deinit();
        self.resp_headers.deinit(self.allocator);
    }

    /// The abstract transport handle for this backend.
    pub fn http(self: *Backend) Http {
        return .{ .userdata = @ptrCast(self), .vtable = &vtable };
    }

    /// Build an abstract `Request` backed by this instance.
    pub fn request(self: *Backend, method: Request.Method, pathname: []const u8, url: []const u8) Request {
        return (Request.Builder{
            .url = url,
            .method = method,
            .method_str = @tagName(method),
            .pathname = pathname,
            .search = self.search,
            .arena = self.allocator,
            .cookie_header = self.cookie_header,
            .http = self.http(),
        }).build();
    }

    /// Build an abstract `Response` backed by this instance.
    pub fn response(self: *Backend) Response {
        return (Response.Builder{
            .arena = self.allocator,
            .http = self.http(),
        }).build();
    }

    /// The accumulated response body.
    pub fn written(self: *Backend) []const u8 {
        return self.resp_body.written();
    }

    /// Set the Content-Type response header (replacing any existing value).
    pub fn setContentTypeStr(self: *Backend, ct: []const u8) void {
        headerSet(self, "Content-Type", ct);
    }

    /// Upgrade data captured during a WebSocket upgrade, if any.
    pub fn upgradeData(self: *const Backend) ?[]const u8 {
        if (self.upgrade_data_len == 0) return null;
        return self.upgrade_data_buf[0..self.upgrade_data_len];
    }

    const vtable = Http.VTable{
        .reqText = &reqText,
        .reqHeaderGet = &reqHeaderGet,
        .reqHeaderHas = &reqHeaderHas,
        .reqParam = &reqParam,
        .reqQueryGet = &reqQueryGet,
        .reqQueryHas = &reqQueryHas,
        .reqFormGet = &reqFormGet,
        .reqFormHas = &reqFormHas,
        .reqMultiGet = &reqMultiGet,
        .reqMultiHas = &reqMultiHas,
        .reqMultiGetAll = &reqMultiGetAll,
        .resSetStatus = &resSetStatus,
        .resSetBody = &resSetBody,
        .resHeaderGet = &resHeaderGet,
        .resHeaderSet = &resHeaderSet,
        .resHeaderAdd = &resHeaderAdd,
        .resWriter = &resWriter,
        .resWriteChunk = &resWriteChunk,
        .resClearWriter = &resClearWriter,
        .resSetCookie = &resSetCookie,
        .wsUpgrade = &wsUpgrade,
        .wsWrite = &wsWrite,
        .wsRead = &wsRead,
        .wsClose = &wsClose,
        .wsSubscribe = &wsSubscribe,
        .wsUnsubscribe = &wsUnsubscribe,
        .wsPublish = &wsPublish,
        .wsIsSubscribed = &wsIsSubscribed,
        .wsSetPublishToSelf = &wsSetPublishToSelf,
    };

    fn self_(userdata: ?*anyopaque) *Backend {
        return @ptrCast(@alignCast(userdata.?));
    }

    // --- request: body / headers / params / query --- //

    fn reqText(userdata: ?*anyopaque) ?[]const u8 {
        const self = self_(userdata);
        if (self.body.len == 0) return null;
        return self.body;
    }

    fn reqHeaderGet(userdata: ?*anyopaque, name: []const u8) ?[]const u8 {
        for (self_(userdata).headers) |entry| {
            if (std.ascii.eqlIgnoreCase(entry.name, name)) return entry.value;
        }
        return null;
    }

    fn reqHeaderHas(userdata: ?*anyopaque, name: []const u8) bool {
        return reqHeaderGet(userdata, name) != null;
    }

    fn reqParam(userdata: ?*anyopaque, name: []const u8) ?[]const u8 {
        const m = self_(userdata).route_match orelse return null;
        return m.getParam(name);
    }

    fn reqQueryGet(userdata: ?*anyopaque, name: []const u8) ?[]const u8 {
        const search = self_(userdata).search;
        const query = if (search.len > 0 and search[0] == '?') search[1..] else search;
        var iter = std.mem.splitScalar(u8, query, '&');
        while (iter.next()) |pair| {
            if (pair.len == 0) continue;
            if (std.mem.indexOfScalar(u8, pair, '=')) |eq| {
                if (std.mem.eql(u8, pair[0..eq], name)) return pair[eq + 1 ..];
            } else {
                if (std.mem.eql(u8, pair, name)) return "";
            }
        }
        return null;
    }

    fn reqQueryHas(userdata: ?*anyopaque, name: []const u8) bool {
        return reqQueryGet(userdata, name) != null;
    }

    // --- request: form data --- //

    fn reqFormGet(userdata: ?*anyopaque, name: []const u8) ?[]const u8 {
        const self = self_(userdata);
        self.form.parse(self);
        for (self.form.keys[0..self.form.count], 0..) |key, i| {
            if (std.mem.eql(u8, key, name)) return self.form.values[i];
        }
        return null;
    }

    fn reqFormHas(userdata: ?*anyopaque, name: []const u8) bool {
        return reqFormGet(userdata, name) != null;
    }

    fn reqMultiGet(userdata: ?*anyopaque, name: []const u8) ?MultiFormData.Value {
        const self = self_(userdata);
        self.multi.parse(self);
        for (self.multi.keys[0..self.multi.count], 0..) |key, i| {
            if (std.mem.eql(u8, key, name)) return self.multi.values[i];
        }
        return null;
    }

    fn reqMultiHas(userdata: ?*anyopaque, name: []const u8) bool {
        return reqMultiGet(userdata, name) != null;
    }

    fn reqMultiGetAll(userdata: ?*anyopaque, name: []const u8, allocator: std.mem.Allocator) ?[]const MultiFormData.Value {
        const self = self_(userdata);
        self.multi.parse(self);
        var cnt: usize = 0;
        for (self.multi.keys[0..self.multi.count]) |key| {
            if (std.mem.eql(u8, key, name)) cnt += 1;
        }
        if (cnt == 0) return null;
        const result = allocator.alloc(MultiFormData.Value, cnt) catch return null;
        var idx: usize = 0;
        for (self.multi.keys[0..self.multi.count], 0..) |key, i| {
            if (std.mem.eql(u8, key, name)) {
                result[idx] = self.multi.values[i];
                idx += 1;
            }
        }
        return result;
    }

    // --- response --- //

    fn resSetStatus(userdata: ?*anyopaque, code: u16) void {
        self_(userdata).status = code;
    }

    fn resSetBody(userdata: ?*anyopaque, content: []const u8) void {
        const self = self_(userdata);
        self.resp_body.deinit();
        self.resp_body = .init(self.allocator);
        self.resp_body.writer.writeAll(content) catch {};
    }

    fn resHeaderGet(userdata: ?*anyopaque, name: []const u8) ?[]const u8 {
        for (self_(userdata).resp_headers.items) |entry| {
            if (std.ascii.eqlIgnoreCase(entry.name, name)) return entry.value;
        }
        return null;
    }

    fn resHeaderSet(userdata: ?*anyopaque, name: []const u8, value: []const u8) void {
        headerSet(self_(userdata), name, value);
    }

    fn resHeaderAdd(userdata: ?*anyopaque, name: []const u8, value: []const u8) void {
        const self = self_(userdata);
        self.resp_headers.append(self.allocator, .{ .name = name, .value = value }) catch {};
    }

    fn resWriter(userdata: ?*anyopaque) ?*std.Io.Writer {
        return &self_(userdata).resp_body.writer;
    }

    fn resWriteChunk(userdata: ?*anyopaque, data: []const u8) anyerror!void {
        try self_(userdata).resp_body.writer.writeAll(data);
    }

    fn resClearWriter(userdata: ?*anyopaque) void {
        const self = self_(userdata);
        self.resp_body.deinit();
        self.resp_body = .init(self.allocator);
    }

    fn resSetCookie(userdata: ?*anyopaque, name: []const u8, value: []const u8, opts: common.CookieOptions) anyerror!void {
        const self = self_(userdata);

        var cookie_buf = std.Io.Writer.Allocating.init(self.allocator);
        defer cookie_buf.deinit();

        try cookie_buf.writer.print("{s}={s}", .{ name, value });
        if (opts.path.len > 0) try cookie_buf.writer.print("; Path={s}", .{opts.path});
        if (opts.domain.len > 0) try cookie_buf.writer.print("; Domain={s}", .{opts.domain});
        if (opts.max_age) |max_age| try cookie_buf.writer.print("; Max-Age={d}", .{max_age});
        if (opts.secure) try cookie_buf.writer.writeAll("; Secure");
        if (opts.http_only) try cookie_buf.writer.writeAll("; HttpOnly");
        if (opts.same_site) |ss| try cookie_buf.writer.print("; SameSite={s}", .{switch (ss) {
            .lax => "Lax",
            .strict => "Strict",
            .none => "None",
        }});
        if (opts.partitioned) try cookie_buf.writer.writeAll("; Partitioned");

        const cookie_str = try self.allocator.dupe(u8, cookie_buf.written());
        try self.resp_headers.append(self.allocator, .{ .name = "Set-Cookie", .value = cookie_str });
    }

    fn headerSet(self: *Backend, name: []const u8, value: []const u8) void {
        for (self.resp_headers.items) |*entry| {
            if (std.ascii.eqlIgnoreCase(entry.name, name)) {
                entry.value = value;
                return;
            }
        }
        self.resp_headers.append(self.allocator, .{ .name = name, .value = value }) catch {};
    }

    // --- websocket --- //

    fn wsUpgrade(userdata: ?*anyopaque, data: ?[]const u8) anyerror!void {
        const self = self_(userdata);
        self.upgraded = true;
        if (data) |bytes| {
            const len = @min(bytes.len, self.upgrade_data_buf.len);
            @memcpy(self.upgrade_data_buf[0..len], bytes[0..len]);
            self.upgrade_data_len = len;
        }
        ext.ws_upgrade();
    }

    fn wsWrite(_: ?*anyopaque, data: []const u8) anyerror!void {
        ext.ws_write(data.ptr, data.len);
    }

    fn wsRead(_: ?*anyopaque) ?[]const u8 {
        return null;
    }

    fn wsClose(_: ?*anyopaque) void {
        const reason: []const u8 = "";
        ext.ws_close(1000, reason.ptr, reason.len);
    }

    fn wsSubscribe(_: ?*anyopaque, topic: []const u8) void {
        ext.ws_subscribe(topic.ptr, topic.len);
    }

    fn wsUnsubscribe(_: ?*anyopaque, topic: []const u8) void {
        ext.ws_unsubscribe(topic.ptr, topic.len);
    }

    fn wsPublish(_: ?*anyopaque, topic: []const u8, message: []const u8) usize {
        return ext.ws_publish(topic.ptr, topic.len, message.ptr, message.len);
    }

    fn wsIsSubscribed(_: ?*anyopaque, topic: []const u8) bool {
        return ext.ws_is_subscribed(topic.ptr, topic.len) != 0;
    }

    fn wsSetPublishToSelf(_: ?*anyopaque, _: bool) void {}
};

// --- application/x-www-form-urlencoded parsing --- //

const FormCache = struct {
    keys: [32][]const u8 = undefined,
    values: [32][]const u8 = undefined,
    count: usize = 0,
    parsed: bool = false,

    fn parse(self: *FormCache, b: *Backend) void {
        if (self.parsed) return;
        self.parsed = true;
        self.count = 0;

        const prefix = "application/x-www-form-urlencoded";
        const ct = b.content_type;
        const is_urlencoded = ct.len >= prefix.len and std.ascii.eqlIgnoreCase(ct[0..prefix.len], prefix);
        if (!is_urlencoded) return;

        var iter = std.mem.splitScalar(u8, b.body, '&');
        while (iter.next()) |pair| {
            if (pair.len == 0) continue;
            if (self.count >= self.keys.len) break;
            const i = self.count;
            if (std.mem.indexOfScalar(u8, pair, '=')) |eq| {
                self.keys[i] = urlDecode(b.allocator, pair[0..eq]) catch pair[0..eq];
                self.values[i] = urlDecode(b.allocator, pair[eq + 1 ..]) catch pair[eq + 1 ..];
            } else {
                self.keys[i] = urlDecode(b.allocator, pair) catch pair;
                self.values[i] = "";
            }
            self.count += 1;
        }
    }
};

// --- multipart/form-data parsing --- //

const MultiCache = struct {
    keys: [32][]const u8 = undefined,
    values: [32]MultiFormData.Value = undefined,
    count: usize = 0,
    parsed: bool = false,

    fn getBoundary(ct: []const u8) ?[]const u8 {
        const needle = "boundary=";
        const idx = std.mem.indexOf(u8, ct, needle) orelse return null;
        const rest = ct[idx + needle.len ..];
        const end = std.mem.indexOfAny(u8, rest, "; \t\r\n") orelse rest.len;
        return if (end == 0) null else rest[0..end];
    }

    fn extractParam(directive: []const u8, param: []const u8) ?[]const u8 {
        var i: usize = 0;
        while (i < directive.len) {
            while (i < directive.len and (directive[i] == ' ' or directive[i] == ';' or directive[i] == '\t')) i += 1;
            if (i >= directive.len) break;
            if (i + param.len + 1 <= directive.len and
                std.ascii.eqlIgnoreCase(directive[i .. i + param.len], param) and
                directive[i + param.len] == '=')
            {
                i += param.len + 1;
                if (i >= directive.len) return "";
                if (directive[i] == '"') {
                    i += 1;
                    const start = i;
                    while (i < directive.len and directive[i] != '"') i += 1;
                    return directive[start..i];
                } else {
                    const start = i;
                    while (i < directive.len and directive[i] != ';' and directive[i] != ' ') i += 1;
                    return directive[start..i];
                }
            }
            while (i < directive.len and directive[i] != ';') i += 1;
        }
        return null;
    }

    fn parse(self: *MultiCache, b: *Backend) void {
        if (self.parsed) return;
        self.parsed = true;
        self.count = 0;

        const boundary = getBoundary(b.content_type) orelse return;

        var delim_buf: [256]u8 = undefined;
        if (boundary.len + 2 > delim_buf.len) return;
        delim_buf[0] = '-';
        delim_buf[1] = '-';
        @memcpy(delim_buf[2 .. boundary.len + 2], boundary);
        const delim = delim_buf[0 .. boundary.len + 2];

        const mf_body = b.body;
        var pos: usize = 0;

        const first = std.mem.indexOf(u8, mf_body[pos..], delim) orelse return;
        pos += first + delim.len;
        if (pos < mf_body.len and mf_body[pos] == '\r') pos += 1;
        if (pos < mf_body.len and mf_body[pos] == '\n') pos += 1;

        while (pos < mf_body.len and self.count < self.keys.len) {
            if (pos + delim.len + 2 <= mf_body.len and
                std.mem.eql(u8, mf_body[pos .. pos + delim.len], delim) and
                mf_body[pos + delim.len] == '-') break;

            var name: ?[]const u8 = null;
            var filename: ?[]const u8 = null;

            while (pos < mf_body.len) {
                const line_end = std.mem.indexOf(u8, mf_body[pos..], "\r\n") orelse break;
                const line = mf_body[pos .. pos + line_end];
                pos += line_end + 2;
                if (line.len == 0) break;

                const cd_prefix = "content-disposition:";
                if (line.len > cd_prefix.len and std.ascii.eqlIgnoreCase(line[0..cd_prefix.len], cd_prefix)) {
                    const rest = std.mem.trimStart(u8, line[cd_prefix.len..], " \t");
                    if (extractParam(rest, "name")) |n| name = n;
                    if (extractParam(rest, "filename")) |f| filename = f;
                }
            }

            const part_end = std.mem.indexOf(u8, mf_body[pos..], delim) orelse break;
            var part_body = mf_body[pos .. pos + part_end];
            if (part_body.len >= 2 and part_body[part_body.len - 2] == '\r' and part_body[part_body.len - 1] == '\n') {
                part_body = part_body[0 .. part_body.len - 2];
            }
            pos += part_end + delim.len;
            if (pos < mf_body.len and mf_body[pos] == '\r') pos += 1;
            if (pos < mf_body.len and mf_body[pos] == '\n') pos += 1;

            if (name) |n| {
                const idx = self.count;
                self.keys[idx] = n;
                self.values[idx] = .{ .data = part_body, .filename = filename };
                self.count += 1;
            }
        }
    }
};

/// Decode a URL-encoded string (%xx and + → space). Returns allocated slice.
fn urlDecode(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    var buf = try allocator.alloc(u8, input.len);
    var out: usize = 0;
    var i: usize = 0;
    while (i < input.len) {
        if (input[i] == '+') {
            buf[out] = ' ';
            out += 1;
            i += 1;
        } else if (input[i] == '%' and i + 2 < input.len) {
            const hi = std.fmt.charToDigit(input[i + 1], 16) catch null;
            const lo = std.fmt.charToDigit(input[i + 2], 16) catch null;
            if (hi != null and lo != null) {
                buf[out] = (hi.? << 4) | lo.?;
                out += 1;
                i += 3;
            } else {
                buf[out] = input[i];
                out += 1;
                i += 1;
            }
        } else {
            buf[out] = input[i];
            out += 1;
            i += 1;
        }
    }
    return buf[0..out];
}
