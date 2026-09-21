const DetailView = @import("DetailView.zig").DetailView;

/// Dedicated report surface for deterministic unhealthy-workload findings.
/// DetailView provides the shared scrolling renderer; explain mode adds
/// Enter/E/l navigation contracts.
pub const ExplainView = DetailView;
