const std = @import("std");
const testing = std.testing;

const fd_t = std.c.fd_t;
const invalid_fd: fd_t = -1;

pub const InitError = error{
    SocketPairFailed,
    GetStatusFlagsFailed,
    SetStatusFlagsFailed,
    GetDescriptorFlagsFailed,
    SetDescriptorFlagsFailed,
};

const RawCallResult = struct {
    result: isize,
    errno_value: std.c.E,
};

const LibcSender = struct {
    fn send(
        _: *LibcSender,
        fd: fd_t,
        buffer: *const anyopaque,
        len: usize,
        _: u32,
    ) RawCallResult {
        const result = std.c.send(fd, buffer, len, std.c.MSG.NOSIGNAL);
        return .{ .result = result, .errno_value = std.c.errno(result) };
    }
};

const LibcReader = struct {
    fn read(_: *LibcReader, fd: fd_t, buffer: [*]u8, len: usize) RawCallResult {
        const result = std.c.read(fd, buffer, len);
        return .{ .result = result, .errno_value = std.c.errno(result) };
    }
};

fn getFlags(fd: fd_t, command: c_int) ?c_int {
    while (true) {
        const result = std.c.fcntl(fd, command);
        switch (std.c.errno(result)) {
            .SUCCESS => return result,
            .INTR => continue,
            else => return null,
        }
    }
}

fn setFlags(fd: fd_t, command: c_int, flags: c_int) bool {
    while (true) {
        const result = std.c.fcntl(fd, command, flags);
        switch (std.c.errno(result)) {
            .SUCCESS => return true,
            .INTR => continue,
            else => return false,
        }
    }
}

fn configureDescriptor(fd: fd_t) InitError!void {
    const status_flags = getFlags(fd, std.c.F.GETFL) orelse
        return error.GetStatusFlagsFailed;
    const nonblocking: c_int = @bitCast(std.c.O{ .NONBLOCK = true });
    if (!setFlags(fd, std.c.F.SETFL, status_flags | nonblocking))
        return error.SetStatusFlagsFailed;

    const descriptor_flags = getFlags(fd, std.c.F.GETFD) orelse
        return error.GetDescriptorFlagsFailed;
    if (!setFlags(fd, std.c.F.SETFD, descriptor_flags | @as(c_int, std.c.FD_CLOEXEC)))
        return error.SetDescriptorFlagsFailed;
}

fn closeDescriptor(fd: fd_t) void {
    _ = std.c.close(fd);
}

fn sendByteWith(fd: fd_t, sender: anytype) bool {
    const byte: u8 = 1;
    while (true) {
        const call = sender.send(fd, &byte, 1, @as(u32, std.c.MSG.NOSIGNAL));
        if (call.result == 1) return true;
        if (call.result >= 0) return false;
        switch (call.errno_value) {
            .INTR => continue,
            .AGAIN => return true,
            else => return false,
        }
    }
}

fn drainWith(self: *Wakeup, reader: anytype) void {
    var buffer: [256]u8 = undefined;
    while (true) {
        const call = reader.read(self.read_fd, &buffer, buffer.len);
        if (call.result > 0) continue;
        if (call.result == 0) {
            self.recordFailure();
            break;
        }
        switch (call.errno_value) {
            .INTR => continue,
            .AGAIN => break,
            else => {
                self.recordFailure();
                break;
            },
        }
    }
    self.pending.store(false, .release);
}

pub const Wakeup = struct {
    read_fd: fd_t,
    write_fd: fd_t,
    pending: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
    failures: std.atomic.Value(u32) = std.atomic.Value(u32).init(0),

    /// Create a nonblocking, close-on-exec AF_UNIX socketpair.
    pub fn init() InitError!Wakeup {
        var descriptors: [2]std.c.fd_t = undefined;
        while (true) {
            const result = std.c.socketpair(
                std.c.AF.UNIX,
                std.c.SOCK.STREAM,
                0,
                &descriptors,
            );
            switch (std.c.errno(result)) {
                .SUCCESS => break,
                .INTR => continue,
                else => return error.SocketPairFailed,
            }
        }
        errdefer {
            closeDescriptor(descriptors[0]);
            closeDescriptor(descriptors[1]);
        }

        try configureDescriptor(descriptors[0]);
        try configureDescriptor(descriptors[1]);

        return .{
            .read_fd = descriptors[0],
            .write_fd = descriptors[1],
        };
    }

    /// Coalesce pending notifications and make the read descriptor readable.
    pub fn notify(self: *Wakeup) void {
        if (self.write_fd == invalid_fd) return;
        if (self.pending.swap(true, .acq_rel)) return;

        var sender = LibcSender{};
        if (!sendByteWith(self.write_fd, &sender)) {
            self.recordFailure();
            self.pending.store(false, .release);
        }
    }

    /// Return the descriptor polled by the UI loop.
    pub fn readHandle(self: *const Wakeup) fd_t {
        return self.read_fd;
    }

    /// Empty readable bytes and clear the coalesced notification state.
    ///
    /// After draining and clearing its ChangeQueue, the caller must recheck
    /// whether the queue is nonempty and call `notify` again when needed.
    /// Task 5 wires that contract to close a notify-during-drain race.
    pub fn drain(self: *Wakeup) void {
        if (self.read_fd == invalid_fd) return;
        var reader = LibcReader{};
        drainWith(self, &reader);
    }

    /// Close both descriptors; repeated calls are harmless.
    pub fn deinit(self: *Wakeup) void {
        const read_fd = self.read_fd;
        const write_fd = self.write_fd;
        self.read_fd = invalid_fd;
        self.write_fd = invalid_fd;
        self.pending.store(false, .release);

        if (read_fd != invalid_fd) closeDescriptor(read_fd);
        if (write_fd != invalid_fd) closeDescriptor(write_fd);
    }

    fn recordFailure(self: *Wakeup) void {
        _ = self.failures.fetchAdd(1, .monotonic);
    }
};

fn testReadable(fd: fd_t) !bool {
    var poll_fds = [_]std.posix.pollfd{
        .{ .fd = fd, .events = std.posix.POLL.IN, .revents = 0 },
    };
    const ready = try std.posix.poll(&poll_fds, 0);
    return ready == 1 and (poll_fds[0].revents & std.posix.POLL.IN) != 0;
}

test "one thousand notifications coalesce to one readable byte" {
    var wakeup = try Wakeup.init();
    defer wakeup.deinit();

    for (0..1_000) |_| wakeup.notify();

    var bytes: [16]u8 = undefined;
    const first = std.c.read(wakeup.readHandle(), &bytes, bytes.len);
    try testing.expectEqual(@as(isize, 1), first);

    const second = std.c.read(wakeup.readHandle(), &bytes, bytes.len);
    try testing.expectEqual(@as(isize, -1), second);
    try testing.expectEqual(std.c.E.AGAIN, std.c.errno(second));
    wakeup.drain();
}

test "drain removes readability and permits another notification" {
    var wakeup = try Wakeup.init();
    defer wakeup.deinit();

    wakeup.notify();
    try testing.expect(try testReadable(wakeup.readHandle()));

    wakeup.drain();
    try testing.expect(!try testReadable(wakeup.readHandle()));

    wakeup.notify();
    try testing.expect(try testReadable(wakeup.readHandle()));
}

test "socketpair descriptors are nonblocking and close on exec" {
    var wakeup = try Wakeup.init();
    defer wakeup.deinit();

    const nonblocking: c_int = @bitCast(std.c.O{ .NONBLOCK = true });
    for ([_]fd_t{ wakeup.read_fd, wakeup.write_fd }) |fd| {
        const status_flags = std.c.fcntl(fd, std.c.F.GETFL);
        try testing.expect(status_flags >= 0);
        try testing.expect(status_flags & nonblocking != 0);

        const descriptor_flags = std.c.fcntl(fd, std.c.F.GETFD);
        try testing.expect(descriptor_flags >= 0);
        try testing.expect(descriptor_flags & std.c.FD_CLOEXEC != 0);
    }
}

test "deinit closes both descriptors and is idempotent" {
    var wakeup = try Wakeup.init();
    defer wakeup.deinit();
    const read_fd = wakeup.read_fd;
    const write_fd = wakeup.write_fd;

    wakeup.deinit();
    wakeup.deinit();

    try testing.expectEqual(@as(c_int, -1), std.c.fcntl(read_fd, std.c.F.GETFD));
    try testing.expectEqual(std.c.E.BADF, std.c.errno(-1));
    try testing.expectEqual(@as(c_int, -1), std.c.fcntl(write_fd, std.c.F.GETFD));
    try testing.expectEqual(std.c.E.BADF, std.c.errno(-1));
}

const ScriptedSender = struct {
    outcomes: []const RawCallResult,
    index: usize = 0,
    last_len: usize = 0,
    last_flags: u32 = 0,

    fn send(
        self: *ScriptedSender,
        _: fd_t,
        _: *const anyopaque,
        len: usize,
        flags: u32,
    ) RawCallResult {
        self.last_len = len;
        self.last_flags = flags;
        const outcome = self.outcomes[self.index];
        self.index += 1;
        return outcome;
    }
};

const ScriptedReader = struct {
    outcomes: []const RawCallResult,
    index: usize = 0,

    fn read(self: *ScriptedReader, _: fd_t, _: [*]u8, _: usize) RawCallResult {
        const outcome = self.outcomes[self.index];
        self.index += 1;
        return outcome;
    }
};

test "send retries EINTR and accepts EAGAIN as coalesced" {
    const interrupted = [_]RawCallResult{
        .{ .result = -1, .errno_value = .INTR },
        .{ .result = 1, .errno_value = .SUCCESS },
    };
    var retrying = ScriptedSender{ .outcomes = interrupted[0..] };
    try testing.expect(sendByteWith(0, &retrying));
    try testing.expectEqual(@as(usize, 2), retrying.index);
    try testing.expectEqual(@as(usize, 1), retrying.last_len);
    try testing.expectEqual(@as(u32, std.c.MSG.NOSIGNAL), retrying.last_flags);

    const full = [_]RawCallResult{
        .{ .result = -1, .errno_value = .AGAIN },
    };
    var coalesced = ScriptedSender{ .outcomes = full[0..] };
    try testing.expect(sendByteWith(0, &coalesced));
    try testing.expectEqual(@as(usize, 1), coalesced.index);
}

test "drain retries EINTR and stops at EAGAIN" {
    var wakeup = try Wakeup.init();
    defer wakeup.deinit();
    wakeup.pending.store(true, .release);

    const outcomes = [_]RawCallResult{
        .{ .result = -1, .errno_value = .INTR },
        .{ .result = 1, .errno_value = .SUCCESS },
        .{ .result = -1, .errno_value = .AGAIN },
    };
    var reader = ScriptedReader{ .outcomes = outcomes[0..] };
    drainWith(&wakeup, &reader);

    try testing.expectEqual(@as(usize, 3), reader.index);
    try testing.expect(!wakeup.pending.load(.acquire));
    try testing.expectEqual(@as(u32, 0), wakeup.failures.load(.acquire));
}

const NotifyDuringDrainReader = struct {
    wakeup: *Wakeup,
    calls: usize = 0,

    fn read(
        self: *NotifyDuringDrainReader,
        fd: fd_t,
        buffer: [*]u8,
        len: usize,
    ) RawCallResult {
        self.calls += 1;
        if (self.calls == 2) self.wakeup.notify();
        const result = std.c.read(fd, buffer, len);
        return .{ .result = result, .errno_value = std.c.errno(result) };
    }
};

test "caller re-notifies when work remains after notify during drain" {
    var wakeup = try Wakeup.init();
    defer wakeup.deinit();
    wakeup.notify();

    var reader = NotifyDuringDrainReader{ .wakeup = &wakeup };
    drainWith(&wakeup, &reader);
    try testing.expectEqual(@as(usize, 2), reader.calls);
    try testing.expect(!try testReadable(wakeup.readHandle()));

    const queue_still_has_work = true;
    if (queue_still_has_work) wakeup.notify();
    try testing.expect(try testReadable(wakeup.readHandle()));
}
