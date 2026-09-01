const std = @import("std");
const active_context = @import("ActiveContextSession.zig");

pub const ActiveContextSession = active_context.ActiveContextSession;
pub const Generation = active_context.Generation;
pub const LeasePurpose = active_context.LeasePurpose;
pub const RequestLease = active_context.RequestLease;
pub const SessionState = active_context.SessionState;

pub const SessionView = struct {
    generation: Generation,
    state: SessionState,
};

pub const ActiveSessionSlot = struct {
    io: std.Io,
    mutex: std.Io.Mutex = .init,
    session: ?*ActiveContextSession = null,
    generation: Generation = 0,
    logical_state: SessionState = .empty,
    shared_event: *std.Io.Event,
    next_generation: Generation = 1,

    pub fn init(io: std.Io, shared_event: *std.Io.Event) ActiveSessionSlot {
        return .{ .io = io, .shared_event = shared_event };
    }

    pub fn deinit(self: *ActiveSessionSlot) void {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        std.debug.assert(self.session == null);
    }

    pub fn view(self: *ActiveSessionSlot) SessionView {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        return .{
            .generation = self.generation,
            .state = self.logical_state,
        };
    }

    pub fn reserveGeneration(self: *ActiveSessionSlot) !Generation {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        const generation = self.next_generation;
        self.next_generation = std.math.add(Generation, generation, 1) catch
            return error.GenerationExhausted;
        return generation;
    }

    pub fn acquire(
        self: *ActiveSessionSlot,
        expected_generation: ?Generation,
        purpose: LeasePurpose,
    ) !?RequestLease {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);

        const session = self.session orelse return null;
        if (expected_generation) |expected| {
            if (expected != self.generation) return error.GenerationMismatch;
        }
        return try session.acquireLocked(purpose, self.shared_event);
    }

    pub fn commit(
        self: *ActiveSessionSlot,
        replacement: *ActiveContextSession,
    ) !?*ActiveContextSession {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);

        if (replacement.shared_event != self.shared_event) {
            return error.SharedEventMismatch;
        }
        if (!replacement.isReady()) return error.SessionNotReady;
        if (self.session) |current| {
            if (current.leaseCount() != 0) return error.LeasesOutstanding;
        }

        try replacement.activateLocked();
        const previous = self.session;
        if (previous) |current| current.invalidate();
        self.session = replacement;
        self.generation = replacement.generation;
        self.logical_state = .active;
        if (replacement.generation >= self.next_generation) {
            self.next_generation = std.math.add(
                Generation,
                replacement.generation,
                1,
            ) catch std.math.maxInt(Generation);
        }
        return previous;
    }

    pub fn invalidate(
        self: *ActiveSessionSlot,
        expected_generation: ?Generation,
    ) !?*ActiveContextSession {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);

        const current = self.session orelse return null;
        if (expected_generation) |expected| {
            if (expected != self.generation) return error.GenerationMismatch;
        }
        current.invalidate();
        self.session = null;
        self.logical_state = .invalidated;
        return current;
    }
};
