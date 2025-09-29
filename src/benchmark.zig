const std = @import("std");

pub fn main() !void {
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;
    
    try stdout.print("Running benchmarks...\n", .{});

    // Example benchmark
    const iterations = 1000000;
    const start_time = std.time.nanoTimestamp();
    
    var sum: u64 = 0;
    for (0..iterations) |i| {
        sum += i;
    }
    
    const end_time = std.time.nanoTimestamp();
    const duration = end_time - start_time;
    
    try stdout.print("Sum: {}\n", .{sum});
    try stdout.print("Duration: {} ns\n", .{duration});
    try stdout.print("Average per iteration: {} ns\n", .{@divTrunc(duration, iterations)});
    try stdout.flush();
}
