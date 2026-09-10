const std = @import("std");
const h = @import("data_plane_gate_harness.zig");

const record_exports = [_][]const u8{
    "PodRecord",                     "NodeRecord",                           "NamespaceRecord",                      "ServiceRecord",                      "EndpointRecord",
    "EndpointSliceRecord",           "ConfigMapRecord",                      "SecretRecord",                         "ServiceAccountRecord",               "ResourceQuotaRecord",
    "LimitRangeRecord",              "DeploymentRecord",                     "StatefulSetRecord",                    "DaemonSetRecord",                    "ReplicaSetRecord",
    "JobRecord",                     "CronJobRecord",                        "HPARecord",                            "PDBRecord",                          "IngressRecord",
    "IngressClassRecord",            "NetworkPolicyRecord",                  "IPAddressRecord",                      "ServiceCIDRRecord",                  "PVRecord",
    "PVCRecord",                     "StorageClassRecord",                   "VolumeAttributesClassRecord",          "CSIDriverRecord",                    "GatewayClassRecord",
    "GatewayRecord",                 "HTTPRouteRecord",                      "GRPCRouteRecord",                      "ReferenceGrantRecord",               "TCPRouteRecord",
    "TLSRouteRecord",                "UDPRouteRecord",                       "BackendTLSPolicyRecord",               "ListenerSetRecord",                  "RoleRecord",
    "RoleBindingRecord",             "ClusterRoleRecord",                    "ClusterRoleBindingRecord",             "ValidatingAdmissionPolicyRecord",    "ValidatingAdmissionPolicyBindingRecord",
    "MutatingAdmissionPolicyRecord", "MutatingAdmissionPolicyBindingRecord", "ValidatingWebhookConfigurationRecord", "MutatingWebhookConfigurationRecord", "ResourceClaimRecord",
    "DeviceClassRecord",             "PriorityClassRecord",                  "RuntimeClassRecord",                   "LeaseRecord",                        "CSRRecord",
    "StorageVersionMigrationRecord", "EventRecord",
};

test "Gate 9 every compact record enforces UID and ownership" {
    try std.testing.expectEqual(@as(usize, 57), record_exports.len);
    try h.expectUnique(&record_exports);
    inline for (record_exports) |name| {
        try std.testing.expect(@hasDecl(h.c3s, name));
    }
    try h.c3s.k8s_resource_subscription.runTask14RecordContractGate();
    try h.c3s.k8s_resource_projection.runTask14UidReplacementGate();
    try h.c3s.k8s_resource_subscription.runTask14MalformedListGate();
    try h.c3s.k8s_resource_subscription.runTask14MalformedWatchGate();
    try h.c3s.runTask14MalformedProductionGate();
    try h.c3s.runTask14MalformedWatchProductionGate();
}

test "every production record constructor preserves metadata labels" {
    try h.c3s.k8s_resource_key.auditMetadataConstructors(&record_exports);
}

test "PDB IntOrString production sort orders integers numerically" {
    try h.c3s.k8s_resource_subscription.runTask14PdbHeaderSortGate();
}
