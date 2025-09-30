// Main module exports for testing
pub const Terminal = @import("core/terminal.zig").Terminal;
pub const Color = @import("core/terminal.zig").Color;
pub const Header = @import("ui/header.zig").Header;
pub const Footer = @import("ui/footer.zig").Footer;
pub const PodsView = @import("view/pods_view.zig").PodsView;
pub const ThemesView = @import("view/themes_view.zig").ThemesView;
pub const HelpView = @import("view/help_view.zig").HelpView;
pub const App = @import("app.zig").App;
pub const Config = @import("model/config.zig");
pub const Logger = @import("core/logger.zig");
pub const version = @import("model/version.zig");
pub const theme_loader = @import("model/theme_loader.zig");
