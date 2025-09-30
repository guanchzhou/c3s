const std = @import("std");
const yaml = @import("yaml");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const source =
        \\apiVersion: v1
        \\kind: Pod
        \\metadata:
        \\  name: nginx-pod
        \\  namespace: default
        \\spec:
        \\  containers:
        \\  - name: nginx
        \\    image: nginx:latest
        \\    ports:
        \\    - containerPort: 80
    ;

    var parsed_yaml = yaml.Yaml.load(allocator, source) catch |err| {
        std.debug.print("Failed to parse YAML: {}\n", .{err});
        return err;
    };
    defer parsed_yaml.deinit();

    std.debug.print("✅ zig-yaml (Zig 0.15.0 branch) works!\n", .{});
    std.debug.print("Parsed YAML successfully\n", .{});
    std.debug.print("Document count: {d}\n", .{parsed_yaml.docs.items.len});
}
