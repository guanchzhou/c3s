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
pub const fixtures = @import("fixtures/index.zig");

// K8s module exports (from zig-klient library)
pub const klient = @import("klient");
pub const K8sClient = klient.K8sClient;
pub const k8s_types = klient.types;
pub const k8s_resources = klient.resources;
pub const k8s_retry = klient.retry;
pub const k8s_watch = klient.watch;
pub const k8s_exec_credential = klient.exec_credential;
pub const k8s_tls = klient.tls;
pub const k8s_connection_pool = klient.pool;
pub const k8s_crd = klient.crd;
pub const KubeconfigParser = klient.KubeconfigParser;
