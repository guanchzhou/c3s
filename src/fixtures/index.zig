/// Test fixtures and dummy data for c3s
///
/// This module provides testing data for view components and development.
/// Use these fixtures when --debug flag is enabled or in tests.
pub const k8s_data = @import("k8s_data.zig");
pub const pods_data = @import("pods_data.zig");

// Re-export commonly used types
pub const K8sData = k8s_data.K8sData;
pub const PodInfo = pods_data.PodInfo;
