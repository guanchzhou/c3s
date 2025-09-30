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

// K8s module exports
pub const K8sClient = @import("k8s/client.zig").K8sClient;
pub const k8s_types = @import("k8s/types.zig");
pub const k8s_resources = @import("k8s/resources.zig");
pub const k8s_retry = @import("k8s/retry.zig");
pub const k8s_watch = @import("k8s/watch.zig");
pub const k8s_exec_credential = @import("k8s/exec_credential.zig");
pub const KubeconfigParser = @import("k8s/kubeconfig_json.zig").KubeconfigParser;
