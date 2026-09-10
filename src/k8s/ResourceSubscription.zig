const std = @import("std");
const klient = @import("klient");
const clock = @import("../core/clock.zig");
const lifecycle = @import("LifecycleInbox.zig");
const list_watch = @import("ListWatch.zig");
const stream_list = @import("StreamList.zig");
const read_transport = @import("ReadTransport.zig");
const keys = @import("ResourceKey.zig");
const projection_mod = @import("ResourceProjection.zig");
const task15 = @import("../task15_diagnostics.zig");

fn task14TypedList(
    comptime namespaced: bool,
    comptime first_fields: []const u8,
    comptime second_fields: []const u8,
) []const u8 {
    const first_metadata = if (namespaced)
        "\"metadata\":{\"uid\":\"stable-uid\",\"namespace\":\"default\",\"name\":\"alpha-resource\",\"creationTimestamp\":\"2024-01-01T00:00:00Z\"}"
    else
        "\"metadata\":{\"uid\":\"stable-uid\",\"name\":\"alpha-resource\",\"creationTimestamp\":\"2024-01-01T00:00:00Z\"}";
    const second_metadata = if (namespaced)
        "\"metadata\":{\"uid\":\"other-uid\",\"namespace\":\"default\",\"name\":\"beta-resource\",\"creationTimestamp\":\"2024-02-01T00:00:00Z\"}"
    else
        "\"metadata\":{\"uid\":\"other-uid\",\"name\":\"beta-resource\",\"creationTimestamp\":\"2024-02-01T00:00:00Z\"}";
    return "{\"metadata\":{\"resourceVersion\":\"10\"},\"items\":[{" ++
        first_metadata ++ first_fields ++ "},{" ++ second_metadata ++ second_fields ++ "}]}";
}

pub fn task14TypeShapedListBody(comptime Record: type) []const u8 {
    const PodRecord = @import("PodRecord.zig");
    const NodeRecord = @import("NodeRecord.zig");
    const NamespaceRecord = @import("NamespaceRecord.zig");
    const ServiceRecord = @import("ServiceRecord.zig");
    const EndpointRecord = @import("EndpointRecord.zig");
    const EndpointSliceRecord = @import("EndpointSliceRecord.zig");
    const ConfigMapRecord = @import("ConfigMapRecord.zig");
    const SecretRecord = @import("SecretRecord.zig");
    const ServiceAccountRecord = @import("ServiceAccountRecord.zig");
    const ResourceQuotaRecord = @import("ResourceQuotaRecord.zig");
    const LimitRangeRecord = @import("LimitRangeRecord.zig");
    const DeploymentRecord = @import("DeploymentRecord.zig");
    const StatefulSetRecord = @import("StatefulSetRecord.zig");
    const DaemonSetRecord = @import("DaemonSetRecord.zig");
    const ReplicaSetRecord = @import("ReplicaSetRecord.zig");
    const JobRecord = @import("JobRecord.zig");
    const CronJobRecord = @import("CronJobRecord.zig");
    const HPARecord = @import("HPARecord.zig");
    const PDBRecord = @import("PDBRecord.zig");
    const IngressRecord = @import("IngressRecord.zig");
    const IngressClassRecord = @import("IngressClassRecord.zig");
    const NetworkPolicyRecord = @import("NetworkPolicyRecord.zig");
    const IPAddressRecord = @import("IPAddressRecord.zig");
    const ServiceCIDRRecord = @import("ServiceCIDRRecord.zig");
    const PVRecord = @import("PVRecord.zig");
    const PVCRecord = @import("PVCRecord.zig");
    const StorageClassRecord = @import("StorageClassRecord.zig");
    const VolumeAttributesClassRecord = @import("VolumeAttributesClassRecord.zig");
    const CSIDriverRecord = @import("CSIDriverRecord.zig");
    const GatewayClassRecord = @import("GatewayClassRecord.zig");
    const GatewayRecord = @import("GatewayRecord.zig");
    const HTTPRouteRecord = @import("HTTPRouteRecord.zig");
    const GRPCRouteRecord = @import("GRPCRouteRecord.zig");
    const ReferenceGrantRecord = @import("ReferenceGrantRecord.zig");
    const TCPRouteRecord = @import("TCPRouteRecord.zig");
    const TLSRouteRecord = @import("TLSRouteRecord.zig");
    const UDPRouteRecord = @import("UDPRouteRecord.zig");
    const BackendTLSPolicyRecord = @import("BackendTLSPolicyRecord.zig");
    const ListenerSetRecord = @import("ListenerSetRecord.zig");
    const RoleRecord = @import("RoleRecord.zig").RoleRecord;
    const RoleBindingRecord = @import("RoleBindingRecord.zig").RoleBindingRecord;
    const ClusterRoleRecord = @import("ClusterRoleRecord.zig").ClusterRoleRecord;
    const ClusterRoleBindingRecord = @import("ClusterRoleBindingRecord.zig").ClusterRoleBindingRecord;
    const ValidatingAdmissionPolicyRecord = @import("ValidatingAdmissionPolicyRecord.zig").ValidatingAdmissionPolicyRecord;
    const ValidatingAdmissionPolicyBindingRecord = @import("ValidatingAdmissionPolicyBindingRecord.zig").ValidatingAdmissionPolicyBindingRecord;
    const MutatingAdmissionPolicyRecord = @import("MutatingAdmissionPolicyRecord.zig").MutatingAdmissionPolicyRecord;
    const MutatingAdmissionPolicyBindingRecord = @import("MutatingAdmissionPolicyBindingRecord.zig").MutatingAdmissionPolicyBindingRecord;
    const ValidatingWebhookConfigurationRecord = @import("ValidatingWebhookConfigurationRecord.zig").ValidatingWebhookConfigurationRecord;
    const MutatingWebhookConfigurationRecord = @import("MutatingWebhookConfigurationRecord.zig").MutatingWebhookConfigurationRecord;
    const ResourceClaimRecord = @import("ResourceClaimRecord.zig");
    const DeviceClassRecord = @import("DeviceClassRecord.zig");
    const PriorityClassRecord = @import("PriorityClassRecord.zig");
    const RuntimeClassRecord = @import("RuntimeClassRecord.zig");
    const LeaseRecord = @import("LeaseRecord.zig");
    const CSRRecord = @import("CSRRecord.zig");
    const StorageVersionMigrationRecord = @import("StorageVersionMigrationRecord.zig");
    const EventRecord = @import("EventRecord.zig");

    if (Record == PodRecord) return task14TypedList(true, ",\"spec\":{\"containers\":[{\"name\":\"app\"}],\"nodeName\":\"worker-1\",\"serviceAccountName\":\"default\"},\"status\":{\"phase\":\"Running\",\"podIP\":\"10.0.0.1\",\"containerStatuses\":[{\"name\":\"app\",\"ready\":true,\"restartCount\":1}]}", ",\"spec\":{\"containers\":[{\"name\":\"app\"}],\"nodeName\":\"worker-2\",\"serviceAccountName\":\"default\"},\"status\":{\"phase\":\"Pending\",\"podIP\":\"10.0.0.2\",\"containerStatuses\":[{\"name\":\"app\",\"ready\":false,\"restartCount\":2}]}");
    if (Record == NodeRecord) return task14TypedList(false, ",\"status\":{\"conditions\":[{\"type\":\"Ready\",\"status\":\"True\"}],\"addresses\":[{\"type\":\"InternalIP\",\"address\":\"10.0.0.1\"}],\"nodeInfo\":{\"kubeletVersion\":\"v1.31.0\"}}", ",\"status\":{\"conditions\":[{\"type\":\"Ready\",\"status\":\"False\"}],\"addresses\":[{\"type\":\"InternalIP\",\"address\":\"10.0.0.2\"}],\"nodeInfo\":{\"kubeletVersion\":\"v1.31.0\"}}");
    if (Record == NamespaceRecord) return task14TypedList(false, ",\"status\":{\"phase\":\"Active\"}", ",\"status\":{\"phase\":\"Terminating\"}");
    if (Record == ServiceRecord) return task14TypedList(true, ",\"spec\":{\"type\":\"ClusterIP\",\"clusterIP\":\"10.96.0.1\",\"ports\":[{\"port\":80}]},\"status\":{\"loadBalancer\":{\"ingress\":[]}}", ",\"spec\":{\"type\":\"NodePort\",\"clusterIP\":\"10.96.0.2\",\"ports\":[{\"port\":81}]},\"status\":{\"loadBalancer\":{\"ingress\":[]}}");
    if (Record == EndpointRecord) return task14TypedList(true, ",\"subsets\":[{\"addresses\":[{\"ip\":\"10.0.0.1\"}],\"ports\":[{\"port\":80}]}]", ",\"subsets\":[{\"addresses\":[{\"ip\":\"10.0.0.2\"}],\"ports\":[{\"port\":81}]}]");
    if (Record == EndpointSliceRecord) return task14TypedList(true, ",\"addressType\":\"IPv4\",\"endpoints\":[{\"addresses\":[\"10.0.0.1\"]}],\"ports\":[{\"port\":80}]", ",\"addressType\":\"IPv6\",\"endpoints\":[{\"addresses\":[\"fd00::1\"]}],\"ports\":[{\"port\":81}]");
    if (Record == ConfigMapRecord) return task14TypedList(true, ",\"data\":{\"one\":\"1\"}", ",\"data\":{\"one\":\"1\",\"two\":\"2\"}");
    if (Record == SecretRecord) return task14TypedList(true, ",\"type\":\"Opaque\",\"data\":{\"one\":\"MQ==\"}", ",\"type\":\"kubernetes.io/tls\",\"data\":{\"tls.crt\":\"YQ==\"}");
    if (Record == ServiceAccountRecord) return task14TypedList(true, ",\"secrets\":[{\"name\":\"one\"}]", ",\"secrets\":[{\"name\":\"one\"},{\"name\":\"two\"}]");
    if (Record == ResourceQuotaRecord) return task14TypedList(true, ",\"spec\":{\"hard\":{\"pods\":\"2\"}}", ",\"spec\":{\"hard\":{\"pods\":\"4\"}}");
    if (Record == LimitRangeRecord) return task14TypedList(true, ",\"spec\":{\"limits\":[{\"type\":\"Container\",\"default\":{\"cpu\":\"100m\"}}]}", ",\"spec\":{\"limits\":[{\"type\":\"Container\",\"default\":{\"cpu\":\"200m\"}}]}");
    if (Record == DeploymentRecord or Record == StatefulSetRecord or Record == ReplicaSetRecord) return task14TypedList(true, ",\"spec\":{\"replicas\":2},\"status\":{\"replicas\":2,\"readyReplicas\":1,\"updatedReplicas\":1,\"availableReplicas\":1}", ",\"spec\":{\"replicas\":4},\"status\":{\"replicas\":4,\"readyReplicas\":2,\"updatedReplicas\":2,\"availableReplicas\":2}");
    if (Record == DaemonSetRecord) return task14TypedList(true, ",\"status\":{\"desiredNumberScheduled\":2,\"currentNumberScheduled\":1,\"numberReady\":1,\"updatedNumberScheduled\":1}", ",\"status\":{\"desiredNumberScheduled\":4,\"currentNumberScheduled\":2,\"numberReady\":2,\"updatedNumberScheduled\":2}");
    if (Record == JobRecord) return task14TypedList(true, ",\"spec\":{\"completions\":2},\"status\":{\"succeeded\":1,\"startTime\":\"2024-01-01T00:00:00Z\"}", ",\"spec\":{\"completions\":4},\"status\":{\"succeeded\":2,\"startTime\":\"2024-02-01T00:00:00Z\"}");
    if (Record == CronJobRecord) return task14TypedList(true, ",\"spec\":{\"schedule\":\"0 0 * * *\",\"suspend\":false},\"status\":{\"active\":[]}", ",\"spec\":{\"schedule\":\"1 0 * * *\",\"suspend\":true},\"status\":{\"active\":[]}");
    if (Record == HPARecord) return task14TypedList(true, ",\"spec\":{\"minReplicas\":1,\"maxReplicas\":4},\"status\":{\"currentReplicas\":2}", ",\"spec\":{\"minReplicas\":2,\"maxReplicas\":8},\"status\":{\"currentReplicas\":4}");
    if (Record == PDBRecord) return task14TypedList(true, ",\"spec\":{\"minAvailable\":2,\"maxUnavailable\":\"10%\"},\"status\":{\"disruptionsAllowed\":2}", ",\"spec\":{\"minAvailable\":10,\"maxUnavailable\":\"20%\"},\"status\":{\"disruptionsAllowed\":4}");
    if (Record == IngressRecord) return task14TypedList(true, ",\"spec\":{\"ingressClassName\":\"nginx\",\"rules\":[{\"host\":\"first.example\"}]},\"status\":{\"loadBalancer\":{\"ingress\":[{\"ip\":\"10.0.0.1\"}]}}", ",\"spec\":{\"ingressClassName\":\"nginx\",\"rules\":[{\"host\":\"second.example\"}]},\"status\":{\"loadBalancer\":{\"ingress\":[{\"ip\":\"10.0.0.2\"}]}}");
    if (Record == IngressClassRecord) return task14TypedList(false, ",\"spec\":{\"controller\":\"k8s.io/ingress-nginx\"}", ",\"spec\":{\"controller\":\"example.net/other\"}");
    if (Record == NetworkPolicyRecord) return task14TypedList(true, ",\"spec\":{\"podSelector\":{\"matchLabels\":{\"app\":\"one\"}},\"policyTypes\":[\"Ingress\"]}", ",\"spec\":{\"podSelector\":{\"matchLabels\":{\"app\":\"two\"}},\"policyTypes\":[\"Egress\"]}");
    if (Record == IPAddressRecord) return task14TypedList(false, ",\"spec\":{\"parentRef\":{\"group\":\"networking.k8s.io\",\"resource\":\"servicecidrs\",\"name\":\"first\"}}", ",\"spec\":{\"parentRef\":{\"group\":\"networking.k8s.io\",\"resource\":\"servicecidrs\",\"name\":\"second\"}}");
    if (Record == ServiceCIDRRecord) return task14TypedList(false, ",\"spec\":{\"cidrs\":[\"10.96.0.0/16\"]}", ",\"spec\":{\"cidrs\":[\"fd00::/108\"]}");
    if (Record == PVRecord) return task14TypedList(false, ",\"spec\":{\"capacity\":{\"storage\":\"1Gi\"},\"accessModes\":[\"ReadWriteOnce\"],\"persistentVolumeReclaimPolicy\":\"Retain\",\"storageClassName\":\"fast\"},\"status\":{\"phase\":\"Available\"}", ",\"spec\":{\"capacity\":{\"storage\":\"2Gi\"},\"accessModes\":[\"ReadWriteMany\"],\"persistentVolumeReclaimPolicy\":\"Delete\",\"storageClassName\":\"slow\"},\"status\":{\"phase\":\"Bound\"}");
    if (Record == PVCRecord) return task14TypedList(true, ",\"spec\":{\"accessModes\":[\"ReadWriteOnce\"],\"storageClassName\":\"fast\",\"volumeName\":\"pv-one\"},\"status\":{\"phase\":\"Bound\",\"capacity\":{\"storage\":\"1Gi\"}}", ",\"spec\":{\"accessModes\":[\"ReadWriteMany\"],\"storageClassName\":\"slow\",\"volumeName\":\"pv-two\"},\"status\":{\"phase\":\"Pending\",\"capacity\":{\"storage\":\"2Gi\"}}");
    if (Record == StorageClassRecord) return task14TypedList(false, ",\"provisioner\":\"csi.one\",\"reclaimPolicy\":\"Retain\",\"volumeBindingMode\":\"Immediate\",\"allowVolumeExpansion\":true", ",\"provisioner\":\"csi.two\",\"reclaimPolicy\":\"Delete\",\"volumeBindingMode\":\"WaitForFirstConsumer\",\"allowVolumeExpansion\":false");
    if (Record == VolumeAttributesClassRecord) return task14TypedList(false, ",\"driverName\":\"csi.one\"", ",\"driverName\":\"csi.two\"");
    if (Record == CSIDriverRecord) return task14TypedList(false, ",\"spec\":{\"attachRequired\":true,\"podInfoOnMount\":false}", ",\"spec\":{\"attachRequired\":false,\"podInfoOnMount\":true}");
    if (Record == GatewayClassRecord) return task14TypedList(false, ",\"spec\":{\"controllerName\":\"gateway.envoyproxy.io/gatewayclass-controller\"}", ",\"spec\":{\"controllerName\":\"example.net/other\"}");
    if (Record == GatewayRecord) return task14TypedList(true, ",\"spec\":{\"gatewayClassName\":\"envoy\",\"listeners\":[{\"name\":\"http\",\"protocol\":\"HTTP\",\"port\":80}]},\"status\":{\"addresses\":[{\"type\":\"IPAddress\",\"value\":\"10.0.0.1\"}]}", ",\"spec\":{\"gatewayClassName\":\"other\",\"listeners\":[{\"name\":\"https\",\"protocol\":\"HTTPS\",\"port\":443}]},\"status\":{\"addresses\":[{\"type\":\"IPAddress\",\"value\":\"10.0.0.2\"}]}");
    if (Record == HTTPRouteRecord or Record == GRPCRouteRecord) return task14TypedList(true, ",\"spec\":{\"parentRefs\":[{\"name\":\"public\"}],\"hostnames\":[\"first.example\"],\"rules\":[{\"backendRefs\":[{\"name\":\"one\",\"port\":80}]}]}", ",\"spec\":{\"parentRefs\":[{\"name\":\"private\"}],\"hostnames\":[\"second.example\"],\"rules\":[{\"backendRefs\":[{\"name\":\"two\",\"port\":81}]}]}");
    if (Record == ReferenceGrantRecord) return task14TypedList(true, ",\"spec\":{\"from\":[{\"group\":\"gateway.networking.k8s.io\",\"kind\":\"HTTPRoute\",\"namespace\":\"edge\"}],\"to\":[{\"group\":\"\",\"kind\":\"Service\",\"name\":\"one\"}]}", ",\"spec\":{\"from\":[{\"group\":\"gateway.networking.k8s.io\",\"kind\":\"GRPCRoute\",\"namespace\":\"edge\"}],\"to\":[{\"group\":\"\",\"kind\":\"Service\",\"name\":\"two\"}]}");
    if (Record == TCPRouteRecord or Record == UDPRouteRecord) return task14TypedList(true, ",\"spec\":{\"parentRefs\":[{\"name\":\"public\"}],\"rules\":[{\"backendRefs\":[{\"name\":\"one\",\"port\":9000}]}]}", ",\"spec\":{\"parentRefs\":[{\"name\":\"private\"}],\"rules\":[{\"backendRefs\":[{\"name\":\"two\",\"port\":9001}]}]}");
    if (Record == TLSRouteRecord) return task14TypedList(true, ",\"spec\":{\"parentRefs\":[{\"name\":\"public\"}],\"hostnames\":[\"first.example\"],\"rules\":[{\"backendRefs\":[{\"name\":\"one\",\"port\":443}]}]}", ",\"spec\":{\"parentRefs\":[{\"name\":\"private\"}],\"hostnames\":[\"second.example\"],\"rules\":[{\"backendRefs\":[{\"name\":\"two\",\"port\":8443}]}]}");
    if (Record == BackendTLSPolicyRecord) return task14TypedList(true, ",\"spec\":{\"targetRefs\":[{\"group\":\"\",\"kind\":\"Service\",\"name\":\"one\"}],\"validation\":{\"hostname\":\"one.example\",\"wellKnownCACertificates\":\"System\"}}", ",\"spec\":{\"targetRefs\":[{\"group\":\"\",\"kind\":\"Service\",\"name\":\"two\"}],\"validation\":{\"hostname\":\"two.example\",\"wellKnownCACertificates\":\"System\"}}");
    if (Record == ListenerSetRecord) return task14TypedList(true, ",\"spec\":{\"parentRef\":{\"name\":\"public\"},\"listeners\":[{\"name\":\"http\",\"protocol\":\"HTTP\",\"port\":80}]}", ",\"spec\":{\"parentRef\":{\"name\":\"private\"},\"listeners\":[{\"name\":\"http\",\"protocol\":\"HTTP\",\"port\":80},{\"name\":\"https\",\"protocol\":\"HTTPS\",\"port\":443}]}");
    if (Record == RoleRecord or Record == ClusterRoleRecord) return task14TypedList(Record == RoleRecord, ",\"rules\":[{\"apiGroups\":[\"\"],\"resources\":[\"pods\"],\"verbs\":[\"get\"]}]", ",\"rules\":[{\"apiGroups\":[\"\"],\"resources\":[\"services\"],\"verbs\":[\"list\",\"watch\"]}]");
    if (Record == RoleBindingRecord or Record == ClusterRoleBindingRecord) return task14TypedList(Record == RoleBindingRecord, ",\"roleRef\":{\"apiGroup\":\"rbac.authorization.k8s.io\",\"kind\":\"Role\",\"name\":\"reader\"},\"subjects\":[{\"kind\":\"ServiceAccount\",\"name\":\"one\"}]", ",\"roleRef\":{\"apiGroup\":\"rbac.authorization.k8s.io\",\"kind\":\"ClusterRole\",\"name\":\"writer\"},\"subjects\":[{\"kind\":\"User\",\"name\":\"two\"}]");
    if (Record == ValidatingAdmissionPolicyRecord or Record == MutatingAdmissionPolicyRecord) return task14TypedList(false, ",\"spec\":{\"failurePolicy\":\"Fail\",\"mutations\":[{}]}", ",\"spec\":{\"failurePolicy\":\"Ignore\",\"mutations\":[{},{}]}");
    if (Record == ValidatingAdmissionPolicyBindingRecord or Record == MutatingAdmissionPolicyBindingRecord) return task14TypedList(false, ",\"spec\":{\"policyName\":\"first-policy\"}", ",\"spec\":{\"policyName\":\"second-policy\"}");
    if (Record == ValidatingWebhookConfigurationRecord or Record == MutatingWebhookConfigurationRecord) return task14TypedList(false, ",\"webhooks\":[{\"name\":\"one.example.com\"}]", ",\"webhooks\":[{\"name\":\"one.example.com\"},{\"name\":\"two.example.com\"}]");
    if (Record == ResourceClaimRecord) return task14TypedList(true, ",\"spec\":{\"devices\":{\"requests\":[]}},\"status\":{\"allocation\":{}}", ",\"spec\":{\"devices\":{\"requests\":[]}},\"status\":{}");
    if (Record == DeviceClassRecord) return task14TypedList(false, ",\"spec\":{\"selectors\":[{}]}", ",\"spec\":{\"selectors\":[{},{}]}");
    if (Record == PriorityClassRecord) return task14TypedList(false, ",\"value\":2,\"globalDefault\":false", ",\"value\":10,\"globalDefault\":true");
    if (Record == RuntimeClassRecord) return task14TypedList(false, ",\"handler\":\"runc\"", ",\"handler\":\"kata\"");
    if (Record == LeaseRecord) return task14TypedList(true, ",\"spec\":{\"holderIdentity\":\"first-holder\"}", ",\"spec\":{\"holderIdentity\":\"second-holder\"}");
    if (Record == CSRRecord) return task14TypedList(false, ",\"spec\":{\"signerName\":\"kubernetes.io/kube-apiserver-client\",\"request\":\"YQ==\"},\"status\":{}", ",\"spec\":{\"signerName\":\"example.net/signer\",\"request\":\"Yg==\"},\"status\":{\"certificate\":\"YQ==\"}");
    if (Record == StorageVersionMigrationRecord) return task14TypedList(false, ",\"spec\":{\"resource\":{\"group\":\"\",\"version\":\"v1\",\"resource\":\"pods\"}},\"status\":{\"resourceVersion\":\"41\"}", ",\"spec\":{\"resource\":{\"group\":\"apps\",\"version\":\"v1\",\"resource\":\"deployments\"}},\"status\":{\"resourceVersion\":\"42\"}");
    if (Record == EventRecord) return task14TypedList(true, ",\"type\":\"Warning\",\"reason\":\"BackOff\",\"message\":\"restarting\",\"involvedObject\":{\"kind\":\"Pod\",\"name\":\"api\"},\"series\":{\"count\":2,\"lastObservedTime\":\"2024-01-01T00:00:00Z\"}", ",\"type\":\"Normal\",\"reason\":\"Ready\",\"message\":\"ready\",\"involvedObject\":{\"kind\":\"Pod\",\"name\":\"worker\"},\"series\":{\"count\":4,\"lastObservedTime\":\"2024-02-01T00:00:00Z\"}");
    @compileError("Task 14 LIST fixture missing record type");
}

fn task14LastPathSegment(path: []const u8) []const u8 {
    const query = std.mem.indexOfScalar(u8, path, '?') orelse path.len;
    const clipped = path[0..query];
    const slash = std.mem.lastIndexOfScalar(u8, clipped, '/') orelse return clipped;
    return clipped[slash + 1 ..];
}

pub fn task14ListBodyForPath(path: []const u8) []const u8 {
    const resource = task14LastPathSegment(path);
    const PodRecord = @import("PodRecord.zig");
    const NodeRecord = @import("NodeRecord.zig");
    const NamespaceRecord = @import("NamespaceRecord.zig");
    const ServiceRecord = @import("ServiceRecord.zig");
    const EndpointRecord = @import("EndpointRecord.zig");
    const EndpointSliceRecord = @import("EndpointSliceRecord.zig");
    const ConfigMapRecord = @import("ConfigMapRecord.zig");
    const SecretRecord = @import("SecretRecord.zig");
    const ServiceAccountRecord = @import("ServiceAccountRecord.zig");
    const ResourceQuotaRecord = @import("ResourceQuotaRecord.zig");
    const LimitRangeRecord = @import("LimitRangeRecord.zig");
    const DeploymentRecord = @import("DeploymentRecord.zig");
    const StatefulSetRecord = @import("StatefulSetRecord.zig");
    const DaemonSetRecord = @import("DaemonSetRecord.zig");
    const ReplicaSetRecord = @import("ReplicaSetRecord.zig");
    const JobRecord = @import("JobRecord.zig");
    const CronJobRecord = @import("CronJobRecord.zig");
    const HPARecord = @import("HPARecord.zig");
    const PDBRecord = @import("PDBRecord.zig");
    const IngressRecord = @import("IngressRecord.zig");
    const IngressClassRecord = @import("IngressClassRecord.zig");
    const NetworkPolicyRecord = @import("NetworkPolicyRecord.zig");
    const IPAddressRecord = @import("IPAddressRecord.zig");
    const ServiceCIDRRecord = @import("ServiceCIDRRecord.zig");
    const PVRecord = @import("PVRecord.zig");
    const PVCRecord = @import("PVCRecord.zig");
    const StorageClassRecord = @import("StorageClassRecord.zig");
    const VolumeAttributesClassRecord = @import("VolumeAttributesClassRecord.zig");
    const CSIDriverRecord = @import("CSIDriverRecord.zig");
    const GatewayClassRecord = @import("GatewayClassRecord.zig");
    const GatewayRecord = @import("GatewayRecord.zig");
    const HTTPRouteRecord = @import("HTTPRouteRecord.zig");
    const GRPCRouteRecord = @import("GRPCRouteRecord.zig");
    const ReferenceGrantRecord = @import("ReferenceGrantRecord.zig");
    const TCPRouteRecord = @import("TCPRouteRecord.zig");
    const TLSRouteRecord = @import("TLSRouteRecord.zig");
    const UDPRouteRecord = @import("UDPRouteRecord.zig");
    const BackendTLSPolicyRecord = @import("BackendTLSPolicyRecord.zig");
    const ListenerSetRecord = @import("ListenerSetRecord.zig");
    const RoleRecord = @import("RoleRecord.zig").RoleRecord;
    const RoleBindingRecord = @import("RoleBindingRecord.zig").RoleBindingRecord;
    const ClusterRoleRecord = @import("ClusterRoleRecord.zig").ClusterRoleRecord;
    const ClusterRoleBindingRecord = @import("ClusterRoleBindingRecord.zig").ClusterRoleBindingRecord;
    const ValidatingAdmissionPolicyRecord = @import("ValidatingAdmissionPolicyRecord.zig").ValidatingAdmissionPolicyRecord;
    const ValidatingAdmissionPolicyBindingRecord = @import("ValidatingAdmissionPolicyBindingRecord.zig").ValidatingAdmissionPolicyBindingRecord;
    const MutatingAdmissionPolicyRecord = @import("MutatingAdmissionPolicyRecord.zig").MutatingAdmissionPolicyRecord;
    const MutatingAdmissionPolicyBindingRecord = @import("MutatingAdmissionPolicyBindingRecord.zig").MutatingAdmissionPolicyBindingRecord;
    const ValidatingWebhookConfigurationRecord = @import("ValidatingWebhookConfigurationRecord.zig").ValidatingWebhookConfigurationRecord;
    const MutatingWebhookConfigurationRecord = @import("MutatingWebhookConfigurationRecord.zig").MutatingWebhookConfigurationRecord;
    const ResourceClaimRecord = @import("ResourceClaimRecord.zig");
    const DeviceClassRecord = @import("DeviceClassRecord.zig");
    const PriorityClassRecord = @import("PriorityClassRecord.zig");
    const RuntimeClassRecord = @import("RuntimeClassRecord.zig");
    const LeaseRecord = @import("LeaseRecord.zig");
    const CSRRecord = @import("CSRRecord.zig");
    const StorageVersionMigrationRecord = @import("StorageVersionMigrationRecord.zig");
    const EventRecord = @import("EventRecord.zig");
    const pairs = .{
        .{ "pods", PodRecord },
        .{ "nodes", NodeRecord },
        .{ "namespaces", NamespaceRecord },
        .{ "services", ServiceRecord },
        .{ "endpoints", EndpointRecord },
        .{ "endpointslices", EndpointSliceRecord },
        .{ "configmaps", ConfigMapRecord },
        .{ "secrets", SecretRecord },
        .{ "serviceaccounts", ServiceAccountRecord },
        .{ "resourcequotas", ResourceQuotaRecord },
        .{ "limitranges", LimitRangeRecord },
        .{ "deployments", DeploymentRecord },
        .{ "statefulsets", StatefulSetRecord },
        .{ "daemonsets", DaemonSetRecord },
        .{ "replicasets", ReplicaSetRecord },
        .{ "jobs", JobRecord },
        .{ "cronjobs", CronJobRecord },
        .{ "horizontalpodautoscalers", HPARecord },
        .{ "poddisruptionbudgets", PDBRecord },
        .{ "ingresses", IngressRecord },
        .{ "ingressclasses", IngressClassRecord },
        .{ "networkpolicies", NetworkPolicyRecord },
        .{ "ipaddresses", IPAddressRecord },
        .{ "servicecidrs", ServiceCIDRRecord },
        .{ "persistentvolumes", PVRecord },
        .{ "persistentvolumeclaims", PVCRecord },
        .{ "storageclasses", StorageClassRecord },
        .{ "volumeattributesclasses", VolumeAttributesClassRecord },
        .{ "csidrivers", CSIDriverRecord },
        .{ "gatewayclasses", GatewayClassRecord },
        .{ "gateways", GatewayRecord },
        .{ "httproutes", HTTPRouteRecord },
        .{ "grpcroutes", GRPCRouteRecord },
        .{ "referencegrants", ReferenceGrantRecord },
        .{ "tcproutes", TCPRouteRecord },
        .{ "tlsroutes", TLSRouteRecord },
        .{ "udproutes", UDPRouteRecord },
        .{ "backendtlspolicies", BackendTLSPolicyRecord },
        .{ "listenersets", ListenerSetRecord },
        .{ "roles", RoleRecord },
        .{ "rolebindings", RoleBindingRecord },
        .{ "clusterroles", ClusterRoleRecord },
        .{ "clusterrolebindings", ClusterRoleBindingRecord },
        .{ "validatingadmissionpolicies", ValidatingAdmissionPolicyRecord },
        .{ "validatingadmissionpolicybindings", ValidatingAdmissionPolicyBindingRecord },
        .{ "mutatingadmissionpolicies", MutatingAdmissionPolicyRecord },
        .{ "mutatingadmissionpolicybindings", MutatingAdmissionPolicyBindingRecord },
        .{ "validatingwebhookconfigurations", ValidatingWebhookConfigurationRecord },
        .{ "mutatingwebhookconfigurations", MutatingWebhookConfigurationRecord },
        .{ "resourceclaims", ResourceClaimRecord },
        .{ "deviceclasses", DeviceClassRecord },
        .{ "priorityclasses", PriorityClassRecord },
        .{ "runtimeclasses", RuntimeClassRecord },
        .{ "leases", LeaseRecord },
        .{ "certificatesigningrequests", CSRRecord },
        .{ "storageversionmigrations", StorageVersionMigrationRecord },
        .{ "events", EventRecord },
    };
    inline for (pairs) |pair| {
        if (std.mem.eql(u8, resource, pair[0])) return task14TypeShapedListBody(pair[1]);
    }
    return "{\"metadata\":{\"resourceVersion\":\"10\"},\"items\":[]}";
}

pub fn ResourceSubscription(
    comptime KlientType: type,
    comptime Record: type,
    comptime fromObject: fn (std.mem.Allocator, KlientType) anyerror!Record,
) type {
    const Projection = projection_mod.ResourceProjection(Record);

    return struct {
        const Self = @This();

        pub const Options = struct {
            context_name: []const u8 = "",
            namespace: ?[]const u8 = null,
            projection: *Projection,
            deinit_counter: ?*std.atomic.Value(usize) = null,
            retry_wait_entered: ?*std.atomic.Value(bool) = null,
            source_override: ?list_watch.Source(Record) = null,
            transport_override: ?read_transport.ReadTransport = null,
            watch_override: ?list_watch.Source(Record) = null,
            hold_watch: bool = false,
            convert_allocator: ?std.mem.Allocator = null,
            emit_allocator: ?std.mem.Allocator = null,
        };

        const Spec = struct {
            context_name: []u8,
            namespace: ?[]u8,
            projection: *Projection,
            generation: keys.Generation = 0,
            subscription_id: keys.SubscriptionId = 0,
            deinit_counter: ?*std.atomic.Value(usize),
            retry_wait_entered: ?*std.atomic.Value(bool),
            source_override: ?list_watch.Source(Record),
            transport_override: ?read_transport.ReadTransport,
            watch_override: ?list_watch.Source(Record),
            hold_watch: bool,
            convert_allocator: ?std.mem.Allocator,
            emit_allocator: ?std.mem.Allocator,

            fn bind(raw: ?*anyopaque, generation: keys.Generation, subscription_id: keys.SubscriptionId) void {
                const self: *Spec = @ptrCast(@alignCast(raw.?));
                self.generation = generation;
                self.subscription_id = subscription_id;
            }

            fn run(raw: ?*anyopaque, control: *lifecycle.ChildControl, io: std.Io) anyerror!void {
                const self: *Spec = @ptrCast(@alignCast(raw.?));
                var lease = &(control.lease orelse return error.MissingLease);
                const client = try lease.client();
                var sink_state = SinkState{
                    .allocator = control.allocator,
                    .emit_allocator = self.emit_allocator,
                    .control = control,
                    .projection = self.projection,
                };
                if (self.source_override) |source| {
                    try self.runDriver(
                        control,
                        source,
                        &sink_state,
                        .{ .context = self, .wait_fn = noRetryWait },
                        null,
                    );
                    return;
                }

                const descriptor = read_transport.ResourceDescriptor.forType(KlientType);
                const list_path = try descriptor.listPath(control.allocator, self.namespace);
                defer control.allocator.free(list_path);
                var transport_adapter = try lease.readTransport(io, &control.cancel_requested);
                var source_state = SourceState{
                    .allocator = control.allocator,
                    .io = io,
                    .client = client,
                    .transport = self.transport_override orelse transport_adapter.transport(),
                    .descriptor = descriptor,
                    .context_name = self.context_name,
                    .list_path = list_path,
                    .namespace = self.namespace,
                    .watch_override = self.watch_override,
                    .hold_watch = self.hold_watch,
                    .retry_wait_entered = self.retry_wait_entered,
                    .convert_allocator = self.convert_allocator,
                    .cancel_requested = &control.cancel_requested,
                    .diagnostic_writer = task15.Writer.initFromEnv(),
                };
                try self.runDriver(
                    control,
                    source_state.source(),
                    &sink_state,
                    .{ .context = &source_state, .wait_fn = SourceState.wait },
                    source_state.observer(),
                );
            }

            fn runDriver(
                self: *Spec,
                control: *lifecycle.ChildControl,
                source: list_watch.Source(Record),
                sink_state: *SinkState,
                retry_hooks: list_watch.RetryHooks,
                observer: ?list_watch.DiagnosticObserver,
            ) !void {
                var driver = list_watch.Driver(Record){
                    .allocator = control.allocator,
                    .source = source,
                    .sink = sink_state.sink(),
                    .retry_hooks = retry_hooks,
                    .cancel = .{
                        .context = control,
                        .is_canceled_fn = lifecycle.ChildControl.isCancelRequested,
                    },
                    .generation = self.generation,
                    .subscription_id = self.subscription_id,
                    .observer = observer,
                };
                defer driver.deinit();
                const outcome = try driver.run();
                control.finish(.{ .subscription_stopped = .{
                    .key = .{
                        .generation = self.generation,
                        .subscription_id = self.subscription_id,
                    },
                    .detail = list_watch.detailForRunOutcome(outcome),
                } });
            }

            fn noRetryWait(_: *anyopaque, _: u64, _: list_watch.CancelToken) anyerror!bool {
                return false;
            }

            fn deinit(raw: ?*anyopaque, _: std.mem.Alignment, allocator: std.mem.Allocator) void {
                const self: *Spec = @ptrCast(@alignCast(raw orelse return));
                allocator.free(self.context_name);
                if (self.namespace) |namespace| allocator.free(namespace);
                if (self.deinit_counter) |counter| _ = counter.fetchAdd(1, .acq_rel);
                allocator.destroy(self);
            }
        };

        pub fn ownedTaskSpec(
            allocator: std.mem.Allocator,
            options: Options,
        ) !lifecycle.OwnedTaskSpec {
            const spec = try allocator.create(Spec);
            errdefer allocator.destroy(spec);
            const context_name = try allocator.dupe(u8, options.context_name);
            errdefer allocator.free(context_name);
            const namespace = if (options.namespace) |value|
                try allocator.dupe(u8, value)
            else
                null;
            spec.* = .{
                .context_name = context_name,
                .namespace = namespace,
                .projection = options.projection,
                .deinit_counter = options.deinit_counter,
                .retry_wait_entered = options.retry_wait_entered,
                .source_override = options.source_override,
                .transport_override = options.transport_override,
                .watch_override = options.watch_override,
                .hold_watch = options.hold_watch,
                .convert_allocator = options.convert_allocator,
                .emit_allocator = options.emit_allocator,
            };
            return .{
                .ptr = spec,
                .alignment = .of(Spec),
                .owned_bytes = @sizeOf(Spec) + context_name.len +
                    (if (namespace) |value| value.len else 0),
                .bindFn = Spec.bind,
                .runFn = Spec.run,
                .deinitFn = Spec.deinit,
            };
        }

        pub fn listPath(
            allocator: std.mem.Allocator,
            namespace: ?[]const u8,
        ) ![]u8 {
            return read_transport.ResourceDescriptor.forType(KlientType).listPath(
                allocator,
                namespace,
            );
        }

        const SourceState = struct {
            allocator: std.mem.Allocator,
            io: std.Io,
            client: *klient.K8sClient,
            transport: read_transport.ReadTransport,
            descriptor: read_transport.ResourceDescriptor,
            context_name: []const u8 = "",
            list_path: []const u8,
            namespace: ?[]const u8,
            watch_override: ?list_watch.Source(Record),
            hold_watch: bool = false,
            retry_wait_entered: ?*std.atomic.Value(bool),
            convert_allocator: ?std.mem.Allocator = null,
            cancel_requested: ?*std.atomic.Value(bool) = null,
            diagnostic_writer: task15.Writer = .{},

            fn source(self: *SourceState) list_watch.Source(Record) {
                return .{ .context = self, .list_fn = list, .watch_fn = watch };
            }

            fn observer(self: *SourceState) list_watch.DiagnosticObserver {
                return .{ .context = self, .notify_fn = observe };
            }

            fn observe(raw: *anyopaque, kind: list_watch.DiagnosticKind, count: usize, value: []const u8) void {
                const self: *SourceState = @ptrCast(@alignCast(raw));
                self.diagnostic_writer.emit(.{
                    .event = switch (kind) {
                        .list_start => .list_start,
                        .list_page => .list_page,
                        .list_complete => .list_complete,
                        .watch_http_established => .watch_http_established,
                        .watch_event => .watch_event,
                        .watch_bookmark => .watch_bookmark,
                        .watch_disconnect => .watch_disconnect,
                        .reconnect_attempt => .reconnect_attempt,
                        .reconnect_success => .reconnect_success,
                        .gone_410 => .gone_410,
                        .relist => .relist,
                        .terminal_forbidden => .terminal_forbidden,
                        .terminal_unauthorized => .terminal_unauthorized,
                        .terminal_absent => .terminal_absent,
                        .terminal_malformed => .terminal_malformed,
                        .retries_exhausted => .retries_exhausted,
                        .transport_retry => .transport_retry,
                    },
                    .context = self.context_name,
                    .scope = if (self.namespace == null) "cluster-or-all" else "namespaced",
                    .family = task15.familyForResource(self.descriptor.resource_name),
                    .api_group = read_transport.apiGroup(self.descriptor.api_path),
                    .resource = self.descriptor.resource_name,
                    .page = if (kind == .list_page) count else 0,
                    .object_count = if (kind == .list_complete) count else 0,
                    .rv_fingerprint = if (value.len == 0) 0 else task15.fingerprint(value),
                });
            }

            fn convert(self: *SourceState, object: KlientType) !Record {
                const allocator = self.convert_allocator orelse self.allocator;
                return fromObject(allocator, object);
            }

            fn list(
                raw: *anyopaque,
                _: list_watch.CancelToken,
                receiver_context: *anyopaque,
                receiver: *const fn (*anyopaque, Record) anyerror!void,
                chunk_end: *const fn (*anyopaque) anyerror!void,
            ) anyerror!list_watch.ListOutcome {
                const self: *SourceState = @ptrCast(@alignCast(raw));
                const Batch = struct {
                    source: *SourceState,
                    receiver_context: *anyopaque,
                    receiver: *const fn (*anyopaque, Record) anyerror!void,
                    chunk_end: *const fn (*anyopaque) anyerror!void,

                    fn receive(ctx: *@This(), objects: []const KlientType) anyerror!void {
                        for (objects) |object| {
                            const record = try ctx.source.convert(object);
                            try ctx.receiver(ctx.receiver_context, record);
                        }
                        try ctx.chunk_end(ctx.receiver_context);
                    }
                };
                var batch = Batch{
                    .source = self,
                    .receiver_context = receiver_context,
                    .receiver = receiver,
                    .chunk_end = chunk_end,
                };
                var continue_token = try self.allocator.dupe(u8, "");
                defer self.allocator.free(continue_token);
                var final_rv: ?[]u8 = null;
                defer if (final_rv) |rv| self.allocator.free(rv);
                var pagination = read_transport.PaginationGuard.init(
                    self.allocator,
                    read_transport.default_max_list_pages,
                );
                defer pagination.deinit();
                var page: usize = 0;
                while (true) {
                    const page_path = try read_transport.paginatedListPath(
                        self.allocator,
                        self.list_path,
                        continue_token,
                    );
                    defer self.allocator.free(page_path);
                    var result = stream_list.stream(
                        KlientType,
                        self.allocator,
                        self.transport,
                        try read_transport.ReadRequest.init(page_path),
                        .{ .clock = .{ .ptr = self, .now_ns_fn = nowNs } },
                        &batch,
                        Batch.receive,
                    ) catch |err| return .{ .failure = classifyListError(err) };
                    defer result.deinit();
                    page += 1;
                    const has_next = pagination.advance(result.continue_token) catch |err|
                        return .{ .failure = classifyListError(err) };
                    if (final_rv) |rv| self.allocator.free(rv);
                    final_rv = try self.allocator.dupe(u8, result.resource_version);
                    self.allocator.free(continue_token);
                    continue_token = try self.allocator.dupe(u8, result.continue_token);
                    self.diagnostic_writer.emit(.{
                        .event = if (continue_token.len == 0) .list_page else .list_continue,
                        .context = self.context_name,
                        .scope = if (self.namespace == null) "cluster-or-all" else "namespaced",
                        .family = task15.familyForResource(self.descriptor.resource_name),
                        .api_group = self.descriptor.api_path,
                        .resource = self.descriptor.resource_name,
                        .page = page,
                        .token_fingerprint = if (continue_token.len == 0) 0 else task15.fingerprint(continue_token),
                    });
                    if (!has_next) break;
                }
                return .{ .complete = try keys.OwnedBytes.clone(
                    self.allocator,
                    final_rv orelse return .{ .failure = .transport },
                ) };
            }

            fn watch(
                raw: *anyopaque,
                resource_version: []const u8,
                cancel: list_watch.CancelToken,
                receiver_context: *anyopaque,
                receiver: *const fn (*anyopaque, *list_watch.WatchEvent(Record)) anyerror!void,
            ) anyerror!list_watch.Failure {
                const self: *SourceState = @ptrCast(@alignCast(raw));
                if (self.hold_watch) {
                    while (true) {
                        if (self.cancel_requested) |flag| {
                            if (flag.load(.acquire)) return .canceled;
                        }
                        if (cancel.isCanceled()) return .canceled;
                        self.io.sleep(.{ .nanoseconds = std.time.ns_per_ms }, .awake) catch return .canceled;
                    }
                }
                if (self.watch_override) |watch_source| {
                    var established_event: list_watch.WatchEvent(Record) = .established;
                    try receiver(receiver_context, &established_event);
                    return watch_source.watch(
                        resource_version,
                        cancel,
                        receiver_context,
                        receiver,
                    );
                }
                const family = task15.familyForResource(self.descriptor.resource_name);
                const effective_rv = if (family) |value|
                    if (task15.consumeStaleRv(value)) "1" else resource_version
                else
                    resource_version;
                var watcher = klient.Watcher(KlientType).init(
                    self.client,
                    self.descriptor.api_path,
                    self.descriptor.resource_name,
                    self.namespace,
                    .{ .resource_version = effective_rv, .allow_watch_bookmarks = true },
                );
                defer watcher.deinit();
                const Callback = struct {
                    source: *SourceState,
                    receiver_context: *anyopaque,
                    receiver: *const fn (*anyopaque, *list_watch.WatchEvent(Record)) anyerror!void,

                    fn receive(
                        ctx: *@This(),
                        event_value: *klient.watch.WatchEvent(KlientType),
                    ) anyerror!void {
                        defer event_value.deinit();
                        var event: list_watch.WatchEvent(Record) = switch (event_value.type_) {
                            .ADDED => .{ .added = try ctx.source.convert(event_value.object) },
                            .MODIFIED => .{ .modified = try ctx.source.convert(event_value.object) },
                            .DELETED => blk: {
                                var record = try ctx.source.convert(event_value.object);
                                defer record.deinit(ctx.source.allocator);
                                break :blk .{ .deleted = try record.key.clone(ctx.source.allocator) };
                            },
                            .ERROR, .BOOKMARK => return,
                        };
                        defer event.deinit(ctx.source.allocator);
                        try ctx.receiver(ctx.receiver_context, &event);
                    }

                    fn established(ctx: *@This(), meta: klient.StreamResponseMeta) anyerror!void {
                        const target = try task15.enforceRequest(.WATCH, ctx.source.list_path);
                        ctx.source.diagnostic_writer.emit(.{
                            .event = .request_audit,
                            .context = ctx.source.context_name,
                            .scope = target.scope,
                            .family = task15.familyForResource(target.resource),
                            .method = .WATCH,
                            .api_group = target.api_group,
                            .resource = target.resource,
                            .subresource = target.subresource,
                            .endpoint_class = target.endpoint_class,
                            .status = @intFromEnum(meta.status),
                            .retry_class = "none",
                            .identity_fingerprint = target.identity_fingerprint,
                        });
                        var event: list_watch.WatchEvent(Record) = .established;
                        try ctx.receiver(ctx.receiver_context, &event);
                    }

                    fn bookmark(ctx: *@This(), rv: []const u8) anyerror!void {
                        var event: list_watch.WatchEvent(Record) = .{
                            .bookmark = try keys.OwnedBytes.clone(ctx.source.allocator, rv),
                        };
                        defer event.deinit(ctx.source.allocator);
                        try ctx.receiver(ctx.receiver_context, &event);
                    }
                };
                var callback = Callback{
                    .source = self,
                    .receiver_context = receiver_context,
                    .receiver = receiver,
                };
                const outcome = watcher.watchWithContextOutcomeObservedUsing(
                    *Callback,
                    &callback,
                    Callback.receive,
                    Callback.established,
                    Callback.bookmark,
                    read_transport.WatchStream{ .transport = self.transport },
                ) catch |err| {
                    if (classifyWatchObjectError(err)) |failure| return failure;
                    return err;
                };
                return list_watch.failureFromKlient(outcome) orelse .transport;
            }

            fn wait(raw: *anyopaque, delay_ns: u64, _: list_watch.CancelToken) anyerror!bool {
                const self: *SourceState = @ptrCast(@alignCast(raw));
                if (self.retry_wait_entered) |entered| entered.store(true, .release);
                var remaining: i96 = @intCast(delay_ns);
                while (remaining > 0) {
                    if (self.cancel_requested) |flag| {
                        if (flag.load(.acquire)) return false;
                    }
                    const slice = @min(remaining, std.time.ns_per_ms);
                    self.io.sleep(.{ .nanoseconds = slice }, .awake) catch return false;
                    remaining -= slice;
                }
                return true;
            }

            fn nowNs(_: *anyopaque) u64 {
                return @intCast(@max(clock.nanoTimestamp(), 0));
            }
        };

        const SinkState = struct {
            allocator: std.mem.Allocator,
            emit_allocator: ?std.mem.Allocator = null,
            control: *lifecycle.ChildControl,
            projection: *Projection,

            fn sink(self: *SinkState) list_watch.BatchSink(Record) {
                return .{ .context = self, .emit_fn = emit };
            }

            fn emit(raw: *anyopaque, batch: *keys.TypedBatch(Record)) anyerror!void {
                const self: *SinkState = @ptrCast(@alignCast(raw));
                const heap_batch = self.allocator.create(keys.TypedBatch(Record)) catch |err| {
                    batch.deinit(self.allocator);
                    return err;
                };
                heap_batch.* = batch.*;
                batch.* = undefined;
                const envelope = keys.eraseBatch(
                    Record,
                    self.emit_allocator orelse self.allocator,
                    heap_batch,
                    Projection.handler(),
                    @ptrCast(self.projection),
                ) catch |err| {
                    heap_batch.deinit(self.allocator);
                    self.allocator.destroy(heap_batch);
                    return err;
                };
                if (try self.control.publishDelivery(envelope) == .abandoned)
                    return error.Canceled;
            }
        };

        pub const Task14MalformedWatch = struct {
            allocator: std.mem.Allocator,
            watch_calls: usize = 0,

            pub fn source(self: *@This()) list_watch.Source(Record) {
                return .{ .context = self, .list_fn = unusedList, .watch_fn = watch };
            }

            fn unusedList(
                _: *anyopaque,
                _: list_watch.CancelToken,
                _: *anyopaque,
                _: *const fn (*anyopaque, Record) anyerror!void,
                _: *const fn (*anyopaque) anyerror!void,
            ) anyerror!list_watch.ListOutcome {
                return error.Unused;
            }

            fn watch(
                raw: *anyopaque,
                _: []const u8,
                _: list_watch.CancelToken,
                _: *anyopaque,
                _: *const fn (*anyopaque, *list_watch.WatchEvent(Record)) anyerror!void,
            ) anyerror!list_watch.Failure {
                const self: *@This() = @ptrCast(@alignCast(raw));
                self.watch_calls += 1;
                var parsed = try std.json.parseFromSlice(
                    KlientType,
                    self.allocator,
                    "{\"metadata\":{\"namespace\":\"default\",\"name\":\"broken\",\"uid\":\"\"}}",
                    .{ .ignore_unknown_fields = true },
                );
                defer parsed.deinit();
                _ = keys.requireUid(parsed.value.metadata.uid) catch |err| {
                    return classifyWatchObjectError(err) orelse .transport;
                };
                _ = fromObject(self.allocator, parsed.value) catch |err| {
                    return classifyWatchObjectError(err) orelse .transport;
                };
                return error.ExpectedMalformedUid;
            }
        };

        pub fn runTask14EmitAllocationOrdinalsGate() !void {
            const Exercise = struct {
                fn run(allocator: std.mem.Allocator) !void {
                    const List = struct { items: []KlientType };
                    var parsed = try std.json.parseFromSlice(
                        List,
                        allocator,
                        task14TypeShapedListBody(Record),
                        .{ .ignore_unknown_fields = true },
                    );
                    defer parsed.deinit();
                    var record = try fromObject(allocator, parsed.value.items[0]);
                    var record_owned = true;
                    errdefer if (record_owned) record.deinit(allocator);
                    const changes = try allocator.alloc(keys.TypedChange(Record), 1);
                    changes[0] = .{ .initial_upsert = record };
                    record_owned = false;
                    var batch = keys.TypedBatch(Record){
                        .generation = 1,
                        .subscription_id = 1,
                        .revision = 1,
                        .changes = changes,
                        .sync = null,
                        .owned_bytes = 1,
                    };
                    const Match = struct {
                        fn call(_: *const Record, _: []const u8) bool {
                            return true;
                        }
                    };
                    const Sort = struct {
                        fn call(value: *const Record, _: u8) []const u8 {
                            return value.key.uid;
                        }
                    };
                    var projection = Projection.init(allocator, .{
                        .matchFn = Match.call,
                        .sortKeyFn = Sort.call,
                    });
                    defer projection.deinit();
                    var event: std.Io.Event = .unset;
                    var control = lifecycle.ChildControl{
                        .key = .{ .slot = 0, .generation = 1 },
                        .kind = .resource_subscription,
                        .io = @import("../core/runtime.zig").io(),
                        .shared_event = &event,
                        .allocator = allocator,
                    };
                    control.cancel_requested.store(true, .release);
                    var sink_state = SinkState{
                        .allocator = allocator,
                        .emit_allocator = allocator,
                        .control = &control,
                        .projection = &projection,
                    };
                    sink_state.sink().emit(&batch) catch |err| {
                        if (err == error.Canceled) return;
                        return err;
                    };
                    return error.ExpectedCanceledDelivery;
                }
            };
            if (comptime @import("builtin").zig_version.minor >= 17) {
                // 0.17's threaded I/O performs nondeterministic internal allocations,
                // which is incompatible with checkAllAllocationFailures' fixed ordinal model.
                try Exercise.run(std.testing.allocator);
            } else {
                try std.testing.checkAllAllocationFailures(
                    std.testing.allocator,
                    Exercise.run,
                    .{},
                );
            }
        }
    };
}

fn classifyListError(err: anyerror) list_watch.Failure {
    return switch (err) {
        error.Canceled => .canceled,
        error.OutOfMemory => .transport,
        error.HttpUnauthorized => .unauthorized,
        error.HttpForbidden => .forbidden,
        error.HttpNotFound => .absent,
        error.HttpGone => .gone,
        error.HttpThrottled => .{ .throttled = null },
        error.HttpStatus => .server,
        error.MalformedOuterJson,
        error.ItemsNotArray,
        error.MalformedItem,
        error.MissingItems,
        error.MissingResourceVersion,
        error.ObjectTooLarge,
        error.ResponseTooLarge,
        error.MissingUid,
        error.MissingController,
        error.RepeatedContinueToken,
        error.ListPageLimitExceeded,
        => .{ .malformed = detail(err) },
        else => .transport,
    };
}

fn classifyWatchObjectError(err: anyerror) ?list_watch.Failure {
    return switch (err) {
        error.MissingUid,
        error.MissingController,
        error.MalformedWatchEvent,
        => .{ .malformed = detail(err) },
        else => null,
    };
}

pub fn runTask14ResourceEmitAllocationOrdinalsGate() !void {
    const ServiceRecord = @import("ServiceRecord.zig");
    try ResourceSubscription(
        klient.Service,
        ServiceRecord,
        ServiceRecord.fromService,
    ).runTask14EmitAllocationOrdinalsGate();
    const NodeRecord = @import("NodeRecord.zig");
    try ResourceSubscription(
        klient.Node,
        NodeRecord,
        NodeRecord.fromNode,
    ).runTask14EmitAllocationOrdinalsGate();
    const GatewayRecord = @import("GatewayRecord.zig");
    try ResourceSubscription(
        klient.Gateway,
        GatewayRecord,
        GatewayRecord.fromGateway,
    ).runTask14EmitAllocationOrdinalsGate();
}

fn detail(err: anyerror) keys.ErrorDetail {
    const name = @errorName(err);
    var result: keys.ErrorDetail = .{ .code = .decode };
    result.len = @intCast(@min(name.len, result.bytes.len));
    @memcpy(result.bytes[0..result.len], name[0..result.len]);
    return result;
}

test "cluster subscription specs own context and clean up independently" {
    const NodeRecord = @import("NodeRecord.zig");
    const NamespaceRecord = @import("NamespaceRecord.zig");
    const NodeProjection = projection_mod.ResourceProjection(NodeRecord);
    const NamespaceProjection = projection_mod.ResourceProjection(NamespaceRecord);
    const NodeSubscription = ResourceSubscription(
        klient.Node,
        NodeRecord,
        NodeRecord.fromNode,
    );
    const NamespaceSubscription = ResourceSubscription(
        klient.Namespace,
        NamespaceRecord,
        NamespaceRecord.fromNamespace,
    );
    var node_projection: NodeProjection = undefined;
    var namespace_projection: NamespaceProjection = undefined;
    var node_destroyed: std.atomic.Value(usize) = .init(0);
    var namespace_destroyed: std.atomic.Value(usize) = .init(0);
    var node_task = try NodeSubscription.ownedTaskSpec(std.testing.allocator, .{
        .context_name = "dev",
        .projection = &node_projection,
        .deinit_counter = &node_destroyed,
    });
    var namespace_task = try NamespaceSubscription.ownedTaskSpec(std.testing.allocator, .{
        .context_name = "dev",
        .projection = &namespace_projection,
        .deinit_counter = &namespace_destroyed,
    });
    node_task.bindFn(node_task.ptr, 7, 11);
    namespace_task.bindFn(namespace_task.ptr, 7, 12);
    node_task.deinit(std.testing.allocator);
    namespace_task.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 1), node_destroyed.load(.acquire));
    try std.testing.expectEqual(@as(usize, 1), namespace_destroyed.load(.acquire));
}

test "cluster subscription malformed policy includes UID-less objects" {
    try std.testing.expect(classifyListError(error.MissingUid) == .malformed);
    try std.testing.expect(classifyWatchObjectError(error.MissingUid).? == .malformed);
}

test "resource LIST rejects repeated tokens and page-cap exhaustion" {
    try std.testing.expect(classifyListError(error.RepeatedContinueToken) == .malformed);
    try std.testing.expect(classifyListError(error.ListPageLimitExceeded) == .malformed);
}

pub fn runTask14MalformedListGate() !void {
    const ServiceRecord = @import("ServiceRecord.zig");
    const Subscription = ResourceSubscription(
        klient.Service,
        ServiceRecord,
        ServiceRecord.fromService,
    );
    const FakeTransport = @import("FakeTransport.zig").FakeTransport;
    const allocator = std.testing.allocator;
    var fake = FakeTransport.init(allocator, &.{.{
        .body =
        \\{"apiVersion":"v1","kind":"ServiceList","metadata":{"resourceVersion":"10"},"items":[{"metadata":{"namespace":"default","name":"missing-uid"}}]}
        ,
    }});
    defer fake.deinit();
    var source_state = Subscription.SourceState{
        .allocator = allocator,
        .io = @import("../core/runtime.zig").io(),
        .client = undefined,
        .transport = fake.transport(),
        .descriptor = read_transport.ResourceDescriptor.forType(klient.Service),
        .list_path = "/api/v1/namespaces/default/services",
        .namespace = "default",
        .watch_override = null,
        .retry_wait_entered = null,
    };
    const Capture = struct {
        allocator: std.mem.Allocator,
        rows: usize = 0,
        boundaries: usize = 0,

        fn sink(self: *@This()) list_watch.BatchSink(ServiceRecord) {
            return .{ .context = self, .emit_fn = emit };
        }

        fn emit(raw: *anyopaque, batch: *keys.TypedBatch(ServiceRecord)) anyerror!void {
            const self: *@This() = @ptrCast(@alignCast(raw));
            self.rows += batch.changes.len;
            if (batch.sync != null) self.boundaries += 1;
            batch.deinit(self.allocator);
        }
    };
    var capture = Capture{ .allocator = allocator };
    var driver = list_watch.Driver(ServiceRecord){
        .allocator = allocator,
        .source = source_state.source(),
        .sink = capture.sink(),
        .retry_hooks = .{ .context = &source_state, .wait_fn = Subscription.SourceState.wait },
        .cancel = list_watch.CancelToken.never(),
        .generation = 1,
        .subscription_id = 1,
    };
    defer driver.deinit();
    const outcome = try driver.run();
    try std.testing.expect(outcome == .malformed);
    try std.testing.expectEqual(@as(usize, 0), capture.rows);
    try std.testing.expectEqual(@as(usize, 1), capture.boundaries);
    try std.testing.expectEqual(@as(usize, 1), fake.requests.items.len);
}

pub fn runTask14MalformedWatchGate() !void {
    const ServiceRecord = @import("ServiceRecord.zig");
    const Subscription = ResourceSubscription(
        klient.Service,
        ServiceRecord,
        ServiceRecord.fromService,
    );
    const FakeTransport = @import("FakeTransport.zig").FakeTransport;
    const allocator = std.testing.allocator;
    var fake = FakeTransport.init(allocator, &.{.{
        .body = "{\"metadata\":{\"resourceVersion\":\"10\"},\"items\":[]}",
    }});
    defer fake.deinit();
    const Script = struct {
        allocator: std.mem.Allocator,

        fn source(self: *@This()) list_watch.Source(ServiceRecord) {
            return .{ .context = self, .list_fn = unusedList, .watch_fn = watch };
        }

        fn unusedList(
            _: *anyopaque,
            _: list_watch.CancelToken,
            _: *anyopaque,
            _: *const fn (*anyopaque, ServiceRecord) anyerror!void,
            _: *const fn (*anyopaque) anyerror!void,
        ) anyerror!list_watch.ListOutcome {
            return error.Unused;
        }

        fn watch(
            raw: *anyopaque,
            _: []const u8,
            _: list_watch.CancelToken,
            _: *anyopaque,
            _: *const fn (*anyopaque, *list_watch.WatchEvent(ServiceRecord)) anyerror!void,
        ) anyerror!list_watch.Failure {
            const self: *@This() = @ptrCast(@alignCast(raw));
            var parsed = try std.json.parseFromSlice(
                klient.Service,
                self.allocator,
                "{\"metadata\":{\"namespace\":\"default\",\"name\":\"broken\",\"uid\":\"\"}}",
                .{ .ignore_unknown_fields = true },
            );
            defer parsed.deinit();
            var converter = Subscription.SourceState{
                .allocator = self.allocator,
                .io = @import("../core/runtime.zig").io(),
                .client = undefined,
                .transport = undefined,
                .descriptor = read_transport.ResourceDescriptor.forType(klient.Service),
                .list_path = "",
                .namespace = "default",
                .watch_override = null,
                .retry_wait_entered = null,
            };
            _ = converter.convert(parsed.value) catch |err| {
                return classifyWatchObjectError(err) orelse .transport;
            };
            return error.ExpectedMalformedUid;
        }
    };
    var script = Script{ .allocator = allocator };
    var source_state = Subscription.SourceState{
        .allocator = allocator,
        .io = @import("../core/runtime.zig").io(),
        .client = undefined,
        .transport = fake.transport(),
        .descriptor = read_transport.ResourceDescriptor.forType(klient.Service),
        .list_path = "/api/v1/namespaces/default/services",
        .namespace = "default",
        .watch_override = script.source(),
        .retry_wait_entered = null,
    };
    const Capture = struct {
        allocator: std.mem.Allocator,
        rows: usize = 0,
        retries: usize = 0,

        fn sink(self: *@This()) list_watch.BatchSink(ServiceRecord) {
            return .{ .context = self, .emit_fn = emit };
        }

        fn emit(raw: *anyopaque, batch: *keys.TypedBatch(ServiceRecord)) anyerror!void {
            const self: *@This() = @ptrCast(@alignCast(raw));
            self.rows += batch.changes.len;
            batch.deinit(self.allocator);
        }
    };
    var capture = Capture{ .allocator = allocator };
    const Wait = struct {
        retries: *usize,
        fn wait(raw: *anyopaque, _: u64, _: list_watch.CancelToken) anyerror!bool {
            const count: *usize = @ptrCast(@alignCast(raw));
            count.* += 1;
            return true;
        }
    };
    var driver = list_watch.Driver(ServiceRecord){
        .allocator = allocator,
        .source = source_state.source(),
        .sink = capture.sink(),
        .retry_hooks = .{ .context = &capture.retries, .wait_fn = Wait.wait },
        .cancel = list_watch.CancelToken.never(),
        .generation = 1,
        .subscription_id = 1,
    };
    defer driver.deinit();
    const outcome = try driver.run();
    try std.testing.expect(outcome == .malformed);
    try std.testing.expectEqual(@as(usize, 0), capture.rows);
    try std.testing.expectEqual(@as(usize, 0), capture.retries);
    try std.testing.expectEqual(@as(usize, 1), fake.requests.items.len);
}

fn exerciseTask14RecordContract(
    comptime KlientType: type,
    comptime Record: type,
    comptime from_object: fn (std.mem.Allocator, KlientType) anyerror!Record,
) !void {
    const List = struct { items: []KlientType };
    var parsed = try std.json.parseFromSlice(
        List,
        std.testing.allocator,
        task14TypeShapedListBody(Record),
        .{ .ignore_unknown_fields = true },
    );
    defer parsed.deinit();
    try std.testing.expectEqual(@as(usize, 2), parsed.value.items.len);

    const original_uid = parsed.value.items[0].metadata.uid;
    parsed.value.items[0].metadata.uid = null;
    try std.testing.expectError(error.MissingUid, from_object(std.testing.allocator, parsed.value.items[0]));
    parsed.value.items[0].metadata.uid = "";
    try std.testing.expectError(error.MissingUid, from_object(std.testing.allocator, parsed.value.items[0]));
    parsed.value.items[0].metadata.uid = original_uid;

    const Exercise = struct {
        fn run(allocator: std.mem.Allocator, object: KlientType) !void {
            var record = try from_object(allocator, object);
            defer record.deinit(allocator);
            var copy = try record.clone(allocator);
            copy.deinit(allocator);
        }
    };
    try std.testing.checkAllAllocationFailures(
        std.testing.allocator,
        Exercise.run,
        .{parsed.value.items[0]},
    );
}

pub fn runTask14RecordContractGate() !void {
    const PodRecord = @import("PodRecord.zig");
    const podFrom = struct {
        fn call(allocator: std.mem.Allocator, value: klient.Pod) !PodRecord {
            return PodRecord.fromPod(allocator, value, .{});
        }
    }.call;
    try exerciseTask14RecordContract(klient.Pod, PodRecord, podFrom);
    try exerciseTask14RecordContract(klient.Node, @import("NodeRecord.zig"), @import("NodeRecord.zig").fromNode);
    try exerciseTask14RecordContract(klient.Namespace, @import("NamespaceRecord.zig"), @import("NamespaceRecord.zig").fromNamespace);
    try exerciseTask14RecordContract(klient.Service, @import("ServiceRecord.zig"), @import("ServiceRecord.zig").fromService);
    try exerciseTask14RecordContract(klient.Endpoints, @import("EndpointRecord.zig"), @import("EndpointRecord.zig").fromEndpoints);
    try exerciseTask14RecordContract(klient.EndpointSlice, @import("EndpointSliceRecord.zig"), @import("EndpointSliceRecord.zig").fromEndpointSlice);
    try exerciseTask14RecordContract(klient.ConfigMap, @import("ConfigMapRecord.zig"), @import("ConfigMapRecord.zig").fromConfigMap);
    try exerciseTask14RecordContract(klient.Secret, @import("SecretRecord.zig"), @import("SecretRecord.zig").fromSecret);
    try exerciseTask14RecordContract(klient.ServiceAccount, @import("ServiceAccountRecord.zig"), @import("ServiceAccountRecord.zig").fromServiceAccount);
    try exerciseTask14RecordContract(klient.ResourceQuota, @import("ResourceQuotaRecord.zig"), @import("ResourceQuotaRecord.zig").fromResourceQuota);
    try exerciseTask14RecordContract(klient.LimitRange, @import("LimitRangeRecord.zig"), @import("LimitRangeRecord.zig").fromLimitRange);
    try exerciseTask14RecordContract(klient.Deployment, @import("DeploymentRecord.zig"), @import("DeploymentRecord.zig").fromDeployment);
    try exerciseTask14RecordContract(klient.StatefulSet, @import("StatefulSetRecord.zig"), @import("StatefulSetRecord.zig").fromStatefulSet);
    try exerciseTask14RecordContract(klient.DaemonSet, @import("DaemonSetRecord.zig"), @import("DaemonSetRecord.zig").fromDaemonSet);
    try exerciseTask14RecordContract(klient.ReplicaSet, @import("ReplicaSetRecord.zig"), @import("ReplicaSetRecord.zig").fromReplicaSet);
    try exerciseTask14RecordContract(klient.Job, @import("JobRecord.zig"), @import("JobRecord.zig").fromJob);
    try exerciseTask14RecordContract(klient.CronJob, @import("CronJobRecord.zig"), @import("CronJobRecord.zig").fromCronJob);
    try exerciseTask14RecordContract(klient.HorizontalPodAutoscaler, @import("HPARecord.zig"), @import("HPARecord.zig").fromHorizontalPodAutoscaler);
    try exerciseTask14RecordContract(klient.PodDisruptionBudget, @import("PDBRecord.zig"), @import("PDBRecord.zig").fromPodDisruptionBudget);
    try exerciseTask14RecordContract(klient.types.Ingress, @import("IngressRecord.zig"), @import("IngressRecord.zig").fromIngress);
    try exerciseTask14RecordContract(klient.IngressClass, @import("IngressClassRecord.zig"), @import("IngressClassRecord.zig").fromIngressClass);
    try exerciseTask14RecordContract(klient.NetworkPolicy, @import("NetworkPolicyRecord.zig"), @import("NetworkPolicyRecord.zig").fromNetworkPolicy);
    try exerciseTask14RecordContract(klient.IPAddress, @import("IPAddressRecord.zig"), @import("IPAddressRecord.zig").fromIPAddress);
    try exerciseTask14RecordContract(klient.ServiceCIDR, @import("ServiceCIDRRecord.zig"), @import("ServiceCIDRRecord.zig").fromServiceCIDR);
    try exerciseTask14RecordContract(klient.PersistentVolume, @import("PVRecord.zig"), @import("PVRecord.zig").fromPersistentVolume);
    try exerciseTask14RecordContract(klient.PersistentVolumeClaim, @import("PVCRecord.zig"), @import("PVCRecord.zig").fromPersistentVolumeClaim);
    try exerciseTask14RecordContract(klient.StorageClass, @import("StorageClassRecord.zig"), @import("StorageClassRecord.zig").fromStorageClass);
    try exerciseTask14RecordContract(klient.VolumeAttributesClass, @import("VolumeAttributesClassRecord.zig"), @import("VolumeAttributesClassRecord.zig").fromVolumeAttributesClass);
    try exerciseTask14RecordContract(klient.CSIDriver, @import("CSIDriverRecord.zig"), @import("CSIDriverRecord.zig").fromCSIDriver);
    try exerciseTask14RecordContract(klient.GatewayClass, @import("GatewayClassRecord.zig"), @import("GatewayClassRecord.zig").fromGatewayClass);
    try exerciseTask14RecordContract(klient.Gateway, @import("GatewayRecord.zig"), @import("GatewayRecord.zig").fromGateway);
    try exerciseTask14RecordContract(klient.HTTPRoute, @import("HTTPRouteRecord.zig"), @import("HTTPRouteRecord.zig").fromHTTPRoute);
    try exerciseTask14RecordContract(klient.GRPCRoute, @import("GRPCRouteRecord.zig"), @import("GRPCRouteRecord.zig").fromGRPCRoute);
    try exerciseTask14RecordContract(klient.ReferenceGrant, @import("ReferenceGrantRecord.zig"), @import("ReferenceGrantRecord.zig").fromReferenceGrant);
    try exerciseTask14RecordContract(klient.TCPRoute, @import("TCPRouteRecord.zig"), @import("TCPRouteRecord.zig").fromTCPRoute);
    try exerciseTask14RecordContract(klient.TLSRoute, @import("TLSRouteRecord.zig"), @import("TLSRouteRecord.zig").fromTLSRoute);
    try exerciseTask14RecordContract(klient.UDPRoute, @import("UDPRouteRecord.zig"), @import("UDPRouteRecord.zig").fromUDPRoute);
    try exerciseTask14RecordContract(klient.BackendTLSPolicy, @import("BackendTLSPolicyRecord.zig"), @import("BackendTLSPolicyRecord.zig").fromBackendTLSPolicy);
    try exerciseTask14RecordContract(klient.ListenerSet, @import("ListenerSetRecord.zig"), @import("ListenerSetRecord.zig").fromListenerSet);
    try exerciseTask14RecordContract(klient.Role, @import("RoleRecord.zig").RoleRecord, @import("RoleRecord.zig").fromRole);
    try exerciseTask14RecordContract(klient.RoleBinding, @import("RoleBindingRecord.zig").RoleBindingRecord, @import("RoleBindingRecord.zig").fromRoleBinding);
    try exerciseTask14RecordContract(klient.ClusterRole, @import("ClusterRoleRecord.zig").ClusterRoleRecord, @import("ClusterRoleRecord.zig").fromClusterRole);
    try exerciseTask14RecordContract(klient.ClusterRoleBinding, @import("ClusterRoleBindingRecord.zig").ClusterRoleBindingRecord, @import("ClusterRoleBindingRecord.zig").fromClusterRoleBinding);
    try exerciseTask14RecordContract(klient.ValidatingAdmissionPolicy, @import("ValidatingAdmissionPolicyRecord.zig").ValidatingAdmissionPolicyRecord, @import("ValidatingAdmissionPolicyRecord.zig").fromValidatingAdmissionPolicy);
    try exerciseTask14RecordContract(klient.ValidatingAdmissionPolicyBinding, @import("ValidatingAdmissionPolicyBindingRecord.zig").ValidatingAdmissionPolicyBindingRecord, @import("ValidatingAdmissionPolicyBindingRecord.zig").fromValidatingAdmissionPolicyBinding);
    try exerciseTask14RecordContract(klient.MutatingAdmissionPolicy, @import("MutatingAdmissionPolicyRecord.zig").MutatingAdmissionPolicyRecord, @import("MutatingAdmissionPolicyRecord.zig").fromMutatingAdmissionPolicy);
    try exerciseTask14RecordContract(klient.MutatingAdmissionPolicyBinding, @import("MutatingAdmissionPolicyBindingRecord.zig").MutatingAdmissionPolicyBindingRecord, @import("MutatingAdmissionPolicyBindingRecord.zig").fromMutatingAdmissionPolicyBinding);
    try exerciseTask14RecordContract(klient.ValidatingWebhookConfiguration, @import("ValidatingWebhookConfigurationRecord.zig").ValidatingWebhookConfigurationRecord, @import("ValidatingWebhookConfigurationRecord.zig").fromValidatingWebhookConfiguration);
    try exerciseTask14RecordContract(klient.MutatingWebhookConfiguration, @import("MutatingWebhookConfigurationRecord.zig").MutatingWebhookConfigurationRecord, @import("MutatingWebhookConfigurationRecord.zig").fromMutatingWebhookConfiguration);
    try exerciseTask14RecordContract(klient.ResourceClaim, @import("ResourceClaimRecord.zig"), @import("ResourceClaimRecord.zig").fromResourceClaim);
    try exerciseTask14RecordContract(klient.DeviceClass, @import("DeviceClassRecord.zig"), @import("DeviceClassRecord.zig").fromDeviceClass);
    try exerciseTask14RecordContract(klient.PriorityClass, @import("PriorityClassRecord.zig"), @import("PriorityClassRecord.zig").fromPriorityClass);
    try exerciseTask14RecordContract(klient.RuntimeClass, @import("RuntimeClassRecord.zig"), @import("RuntimeClassRecord.zig").fromRuntimeClass);
    try exerciseTask14RecordContract(klient.Lease, @import("LeaseRecord.zig"), @import("LeaseRecord.zig").fromLease);
    try exerciseTask14RecordContract(klient.CertificateSigningRequest, @import("CSRRecord.zig"), @import("CSRRecord.zig").fromCSR);
    try exerciseTask14RecordContract(klient.StorageVersionMigration, @import("StorageVersionMigrationRecord.zig"), @import("StorageVersionMigrationRecord.zig").fromStorageVersionMigration);
    try exerciseTask14RecordContract(klient.Event, @import("EventRecord.zig"), @import("EventRecord.zig").fromEvent);
}

fn exerciseQueueRestart(
    comptime Record: type,
    comptime Subscription: type,
    comptime discriminating_rows: bool,
    comptime name_column: u8,
    comptime evidence_column: ?usize,
    projection: *projection_mod.ResourceProjection(Record),
    table_context: *anyopaque,
    comptime sync_table: fn (*anyopaque) anyerror!void,
) !void {
    const runtime = @import("../core/runtime.zig");
    const DataPlane = @import("DataPlane.zig").DataPlane;
    const ChangeQueue = @import("ChangeQueue.zig").ChangeQueue;
    const Supervisor = @import("LifecycleSupervisor.zig").LifecycleSupervisor;
    const active_context = @import("ActiveContextSession.zig");
    const ActiveSessionSlot = @import("ActiveSessionSlot.zig").ActiveSessionSlot;
    const FakeTransport = @import("FakeTransport.zig").FakeTransport;
    const NodeRecord = @import("NodeRecord.zig");
    const NamespaceRecord = @import("NamespaceRecord.zig");
    const ServiceRecord = @import("ServiceRecord.zig");
    const EndpointRecord = @import("EndpointRecord.zig");
    const EndpointSliceRecord = @import("EndpointSliceRecord.zig");
    const ConfigMapRecord = @import("ConfigMapRecord.zig");
    const SecretRecord = @import("SecretRecord.zig");
    const ServiceAccountRecord = @import("ServiceAccountRecord.zig");
    const ResourceQuotaRecord = @import("ResourceQuotaRecord.zig");
    const LimitRangeRecord = @import("LimitRangeRecord.zig");
    const DeploymentRecord = @import("DeploymentRecord.zig");
    const StatefulSetRecord = @import("StatefulSetRecord.zig");
    const DaemonSetRecord = @import("DaemonSetRecord.zig");
    const ReplicaSetRecord = @import("ReplicaSetRecord.zig");
    const JobRecord = @import("JobRecord.zig");
    const CronJobRecord = @import("CronJobRecord.zig");
    const HPARecord = @import("HPARecord.zig");
    const PDBRecord = @import("PDBRecord.zig");
    const IngressRecord = @import("IngressRecord.zig");
    const IngressClassRecord = @import("IngressClassRecord.zig");
    const NetworkPolicyRecord = @import("NetworkPolicyRecord.zig");
    const IPAddressRecord = @import("IPAddressRecord.zig");
    const ServiceCIDRRecord = @import("ServiceCIDRRecord.zig");
    const PVRecord = @import("PVRecord.zig");
    const PVCRecord = @import("PVCRecord.zig");
    const StorageClassRecord = @import("StorageClassRecord.zig");
    const VolumeAttributesClassRecord = @import("VolumeAttributesClassRecord.zig");
    const CSIDriverRecord = @import("CSIDriverRecord.zig");
    const GatewayClassRecord = @import("GatewayClassRecord.zig");
    const GatewayRecord = @import("GatewayRecord.zig");
    const HTTPRouteRecord = @import("HTTPRouteRecord.zig");
    const GRPCRouteRecord = @import("GRPCRouteRecord.zig");
    const ReferenceGrantRecord = @import("ReferenceGrantRecord.zig");
    const TCPRouteRecord = @import("TCPRouteRecord.zig");
    const TLSRouteRecord = @import("TLSRouteRecord.zig");
    const UDPRouteRecord = @import("UDPRouteRecord.zig");
    const BackendTLSPolicyRecord = @import("BackendTLSPolicyRecord.zig");
    const ListenerSetRecord = @import("ListenerSetRecord.zig");
    const RoleRecord = @import("RoleRecord.zig").RoleRecord;
    const RoleBindingRecord = @import("RoleBindingRecord.zig").RoleBindingRecord;
    const ClusterRoleRecord = @import("ClusterRoleRecord.zig").ClusterRoleRecord;
    const ClusterRoleBindingRecord = @import("ClusterRoleBindingRecord.zig").ClusterRoleBindingRecord;
    const ValidatingAdmissionPolicyRecord = @import("ValidatingAdmissionPolicyRecord.zig").ValidatingAdmissionPolicyRecord;
    const ValidatingAdmissionPolicyBindingRecord = @import("ValidatingAdmissionPolicyBindingRecord.zig").ValidatingAdmissionPolicyBindingRecord;
    const MutatingAdmissionPolicyRecord = @import("MutatingAdmissionPolicyRecord.zig").MutatingAdmissionPolicyRecord;
    const MutatingAdmissionPolicyBindingRecord = @import("MutatingAdmissionPolicyBindingRecord.zig").MutatingAdmissionPolicyBindingRecord;
    const ValidatingWebhookConfigurationRecord = @import("ValidatingWebhookConfigurationRecord.zig").ValidatingWebhookConfigurationRecord;
    const MutatingWebhookConfigurationRecord = @import("MutatingWebhookConfigurationRecord.zig").MutatingWebhookConfigurationRecord;
    const ResourceClaimRecord = @import("ResourceClaimRecord.zig");
    const DeviceClassRecord = @import("DeviceClassRecord.zig");
    const PriorityClassRecord = @import("PriorityClassRecord.zig");
    const RuntimeClassRecord = @import("RuntimeClassRecord.zig");
    const LeaseRecord = @import("LeaseRecord.zig");
    const CSRRecord = @import("CSRRecord.zig");
    const StorageVersionMigrationRecord = @import("StorageVersionMigrationRecord.zig");
    const EventRecord = @import("EventRecord.zig");
    const allocator = std.testing.allocator;
    const io = runtime.io();
    const list_body = task14TypeShapedListBody(Record);
    var fake = FakeTransport.init(allocator, &.{
        .{ .body = list_body },
        .{ .body = list_body },
    });
    defer fake.deinit();

    const Script = struct {
        allocator: std.mem.Allocator,
        list_value: []const u8,
        watch_value: []const u8,
        watch_release: *std.atomic.Value(bool),
        watch_entered: *std.atomic.Value(bool),
        watch_calls: usize = 0,

        fn source(self: *@This()) list_watch.Source(Record) {
            return .{ .context = self, .list_fn = list, .watch_fn = watch };
        }

        fn makeRecord(
            self: *@This(),
            uid: []const u8,
            name: []const u8,
            value: []const u8,
            timestamp: []const u8,
        ) !Record {
            const key = try (keys.ObjectKey{
                .uid = uid,
                .namespace = if (Record == NodeRecord or
                    Record == NamespaceRecord or
                    Record == IngressClassRecord or
                    Record == IPAddressRecord or
                    Record == ServiceCIDRRecord or
                    Record == PVRecord or
                    Record == StorageClassRecord or
                    Record == VolumeAttributesClassRecord or
                    Record == CSIDriverRecord or
                    Record == GatewayClassRecord or
                    Record == ClusterRoleRecord or
                    Record == ClusterRoleBindingRecord or
                    Record == ValidatingAdmissionPolicyRecord or
                    Record == ValidatingAdmissionPolicyBindingRecord or
                    Record == MutatingAdmissionPolicyRecord or
                    Record == MutatingAdmissionPolicyBindingRecord or
                    Record == ValidatingWebhookConfigurationRecord or
                    Record == MutatingWebhookConfigurationRecord or
                    Record == DeviceClassRecord or
                    Record == PriorityClassRecord or
                    Record == RuntimeClassRecord or
                    Record == CSRRecord or
                    Record == StorageVersionMigrationRecord) "" else "default",
                .name = name,
            }).clone(self.allocator);
            if (comptime Record == NodeRecord) {
                return .{
                    .key = key,
                    .status = try self.allocator.dupe(u8, value),
                    .roles = try self.allocator.dupe(u8, "worker"),
                    .version = try self.allocator.dupe(u8, "v1.31.0"),
                    .internal_ip = try self.allocator.dupe(u8, "10.0.0.1"),
                    .creation_timestamp = try self.allocator.dupe(u8, timestamp),
                };
            }
            if (comptime Record == NamespaceRecord)
                return .{
                    .key = key,
                    .status = try self.allocator.dupe(u8, value),
                    .creation_timestamp = try self.allocator.dupe(u8, timestamp),
                };
            if (comptime Record == ServiceRecord)
                return .{
                    .key = key,
                    .service_type = try self.allocator.dupe(u8, value),
                    .cluster_ip = try self.allocator.dupe(u8, "10.96.0.1"),
                    .external_ip = try self.allocator.dupe(u8, "1.2.3.4"),
                    .ports = try self.allocator.dupe(u8, "80/TCP"),
                    .creation_timestamp = try self.allocator.dupe(u8, timestamp),
                };
            if (comptime Record == EndpointRecord)
                return .{
                    .key = key,
                    .endpoints = try self.allocator.dupe(u8, value),
                    .creation_timestamp = try self.allocator.dupe(u8, timestamp),
                };
            if (comptime Record == EndpointSliceRecord)
                return .{
                    .key = key,
                    .address_type = try self.allocator.dupe(u8, "IPv4"),
                    .endpoints = try self.allocator.dupe(u8, value),
                    .creation_timestamp = try self.allocator.dupe(u8, timestamp),
                };
            if (comptime Record == ConfigMapRecord)
                return .{
                    .key = key,
                    .data_count = if (std.mem.endsWith(u8, value, "watch")) 3 else if (std.mem.eql(u8, value, "secondary")) 2 else 1,
                    .data_sort_key = ConfigMapRecord.numericSortKey(if (std.mem.endsWith(u8, value, "watch")) 3 else if (std.mem.eql(u8, value, "secondary")) 2 else 1),
                    .creation_timestamp = try self.allocator.dupe(u8, timestamp),
                };
            if (comptime Record == SecretRecord)
                return .{
                    .key = key,
                    .secret_type = try self.allocator.dupe(u8, value),
                    .data_count = if (std.mem.endsWith(u8, value, "watch")) 3 else 1,
                    .data_sort_key = ConfigMapRecord.numericSortKey(if (std.mem.endsWith(u8, value, "watch")) 3 else 1),
                    .creation_timestamp = try self.allocator.dupe(u8, timestamp),
                };
            if (comptime Record == ServiceAccountRecord)
                return .{
                    .key = key,
                    .secret_count = if (std.mem.endsWith(u8, value, "watch")) 3 else if (std.mem.eql(u8, value, "secondary")) 2 else 1,
                    .secret_sort_key = ConfigMapRecord.numericSortKey(if (std.mem.endsWith(u8, value, "watch")) 3 else if (std.mem.eql(u8, value, "secondary")) 2 else 1),
                    .creation_timestamp = try self.allocator.dupe(u8, timestamp),
                };
            if (comptime Record == ResourceQuotaRecord or Record == LimitRangeRecord)
                return .{
                    .key = key,
                    .creation_timestamp = try self.allocator.dupe(u8, timestamp),
                };
            const count: i32 = if (std.mem.endsWith(u8, value, "watch")) 7 else if (std.mem.eql(u8, value, "secondary")) 4 else 2;
            if (comptime Record == DeploymentRecord)
                return .{
                    .key = key,
                    .ready_replicas = count,
                    .desired_replicas = 8,
                    .updated_replicas = count + 1,
                    .available_replicas = count - 1,
                    .ready_sort_key = DeploymentRecord.ratioSortKey(count, 8),
                    .updated_sort_key = DeploymentRecord.countSortKey(count + 1),
                    .available_sort_key = DeploymentRecord.countSortKey(count - 1),
                    .creation_timestamp = try self.allocator.dupe(u8, timestamp),
                };
            if (comptime Record == StatefulSetRecord)
                return .{
                    .key = key,
                    .ready_replicas = count,
                    .desired_replicas = 8,
                    .ready_sort_key = DeploymentRecord.ratioSortKey(count, 8),
                    .creation_timestamp = try self.allocator.dupe(u8, timestamp),
                };
            if (comptime Record == DaemonSetRecord)
                return .{
                    .key = key,
                    .desired = count,
                    .current = count - 1,
                    .ready = count - 2,
                    .updated = count - 3,
                    .desired_sort_key = DeploymentRecord.countSortKey(count),
                    .current_sort_key = DeploymentRecord.countSortKey(count - 1),
                    .ready_sort_key = DeploymentRecord.countSortKey(count - 2),
                    .updated_sort_key = DeploymentRecord.countSortKey(count - 3),
                    .creation_timestamp = try self.allocator.dupe(u8, timestamp),
                };
            if (comptime Record == ReplicaSetRecord)
                return .{
                    .key = key,
                    .desired = count,
                    .current = count - 1,
                    .ready = count - 2,
                    .desired_sort_key = DeploymentRecord.countSortKey(count),
                    .current_sort_key = DeploymentRecord.countSortKey(count - 1),
                    .ready_sort_key = DeploymentRecord.countSortKey(count - 2),
                    .creation_timestamp = try self.allocator.dupe(u8, timestamp),
                };
            if (comptime Record == JobRecord)
                return .{
                    .key = key,
                    .succeeded = count,
                    .desired = 8,
                    .completions_sort_key = JobRecord.ratioSortKey(count, 8),
                    .start_time = try self.allocator.dupe(u8, "2024-01-01T00:00:00Z"),
                    .completion_time = try self.allocator.dupe(u8, "2024-01-01T01:00:00Z"),
                    .creation_timestamp = try self.allocator.dupe(u8, timestamp),
                };
            if (comptime Record == CronJobRecord)
                return .{
                    .key = key,
                    .schedule = try self.allocator.dupe(u8, "0 0 * * *"),
                    .@"suspend" = false,
                    .active = count,
                    .active_sort_key = CronJobRecord.countSortKey(count),
                    .last_schedule_time = try self.allocator.dupe(u8, timestamp),
                    .creation_timestamp = try self.allocator.dupe(u8, timestamp),
                };
            if (comptime Record == HPARecord)
                return .{
                    .key = key,
                    .min_replicas = 1,
                    .max_replicas = 8,
                    .current_replicas = count,
                    .min_sort_key = HPARecord.countSortKey(1),
                    .max_sort_key = HPARecord.countSortKey(8),
                    .current_sort_key = HPARecord.countSortKey(count),
                    .creation_timestamp = try self.allocator.dupe(u8, timestamp),
                };
            if (comptime Record == PDBRecord)
                return .{
                    .key = key,
                    .min_available = try self.allocator.dupe(u8, "1"),
                    .max_unavailable = try self.allocator.dupe(u8, "1"),
                    .allowed_disruptions = count,
                    .allowed_sort_key = PDBRecord.countSortKey(count),
                    .creation_timestamp = try self.allocator.dupe(u8, timestamp),
                };
            if (comptime Record == IngressRecord)
                return .{
                    .key = key,
                    .class = try self.allocator.dupe(u8, "nginx"),
                    .hosts = try self.allocator.dupe(u8, value),
                    .address = try self.allocator.dupe(u8, value),
                    .ports = try self.allocator.dupe(u8, "80, 443"),
                    .creation_timestamp = try self.allocator.dupe(u8, timestamp),
                };
            if (comptime Record == IngressClassRecord)
                return .{
                    .key = key,
                    .controller = try self.allocator.dupe(u8, value),
                    .creation_timestamp = try self.allocator.dupe(u8, timestamp),
                };
            if (comptime Record == NetworkPolicyRecord)
                return .{
                    .key = key,
                    .pod_selector = try self.allocator.dupe(u8, value),
                    .creation_timestamp = try self.allocator.dupe(u8, timestamp),
                };
            if (comptime Record == IPAddressRecord)
                return .{
                    .key = key,
                    .parent = try self.allocator.dupe(u8, value),
                    .creation_timestamp = try self.allocator.dupe(u8, timestamp),
                };
            if (comptime Record == ServiceCIDRRecord)
                return .{
                    .key = key,
                    .cidrs = try self.allocator.dupe(u8, value),
                    .creation_timestamp = try self.allocator.dupe(u8, timestamp),
                };
            if (comptime Record == PVRecord)
                return .{
                    .key = key,
                    .capacity = try self.allocator.dupe(u8, value),
                    .capacity_sort_key = PVRecord.capacitySortKey(value),
                    .access = try self.allocator.dupe(u8, "RWO"),
                    .reclaim = try self.allocator.dupe(u8, "Retain"),
                    .status = try self.allocator.dupe(u8, value),
                    .claim = try self.allocator.dupe(u8, "default/cache"),
                    .storage_class = try self.allocator.dupe(u8, "fast"),
                    .creation_timestamp = try self.allocator.dupe(u8, timestamp),
                };
            if (comptime Record == PVCRecord)
                return .{
                    .key = key,
                    .status = try self.allocator.dupe(u8, value),
                    .volume = try self.allocator.dupe(u8, "pv-1"),
                    .capacity = try self.allocator.dupe(u8, value),
                    .capacity_sort_key = PVRecord.capacitySortKey(value),
                    .access = try self.allocator.dupe(u8, "RWX"),
                    .storage_class = try self.allocator.dupe(u8, "fast"),
                    .creation_timestamp = try self.allocator.dupe(u8, timestamp),
                };
            if (comptime Record == StorageClassRecord)
                return .{
                    .key = key,
                    .provisioner = try self.allocator.dupe(u8, value),
                    .reclaim_policy = try self.allocator.dupe(u8, "Retain"),
                    .bind_mode = try self.allocator.dupe(u8, "Immediate"),
                    .expansion = true,
                    .creation_timestamp = try self.allocator.dupe(u8, timestamp),
                };
            if (comptime Record == VolumeAttributesClassRecord)
                return .{
                    .key = key,
                    .driver = try self.allocator.dupe(u8, value),
                    .creation_timestamp = try self.allocator.dupe(u8, timestamp),
                };
            if (comptime Record == CSIDriverRecord)
                return .{
                    .key = key,
                    .attach_required = !std.mem.endsWith(u8, value, "watch"),
                    .pod_info = std.mem.endsWith(u8, value, "watch"),
                    .creation_timestamp = try self.allocator.dupe(u8, timestamp),
                };
            if (comptime Record == GatewayClassRecord)
                return .{ .key = key, .controller = try self.allocator.dupe(u8, value), .creation_timestamp = try self.allocator.dupe(u8, timestamp) };
            if (comptime Record == GatewayRecord)
                return .{ .key = key, .gateway_class = try self.allocator.dupe(u8, "envoy"), .address = try self.allocator.dupe(u8, value), .creation_timestamp = try self.allocator.dupe(u8, timestamp) };
            if (comptime Record == HTTPRouteRecord or Record == GRPCRouteRecord or Record == TLSRouteRecord)
                return .{ .key = key, .parent = try self.allocator.dupe(u8, "public"), .hostnames = try self.allocator.dupe(u8, value), .creation_timestamp = try self.allocator.dupe(u8, timestamp) };
            if (comptime Record == ReferenceGrantRecord)
                return .{ .key = key, .from_kind = try self.allocator.dupe(u8, value), .to_kind = try self.allocator.dupe(u8, "Service"), .creation_timestamp = try self.allocator.dupe(u8, timestamp) };
            if (comptime Record == TCPRouteRecord or Record == UDPRouteRecord)
                return .{ .key = key, .parent = try self.allocator.dupe(u8, value), .creation_timestamp = try self.allocator.dupe(u8, timestamp) };
            if (comptime Record == BackendTLSPolicyRecord)
                return .{ .key = key, .target = try self.allocator.dupe(u8, value), .creation_timestamp = try self.allocator.dupe(u8, timestamp) };
            if (comptime Record == ListenerSetRecord)
                return .{ .key = key, .parent = try self.allocator.dupe(u8, value), .listener_count = if (std.mem.endsWith(u8, value, "watch")) 7 else 2, .creation_timestamp = try self.allocator.dupe(u8, timestamp) };
            if (comptime Record == RoleRecord or Record == ClusterRoleRecord)
                return .{ .key = key, .extra = .{}, .creation_timestamp = try self.allocator.dupe(u8, timestamp) };
            if (comptime Record == RoleBindingRecord or Record == ClusterRoleBindingRecord)
                return .{
                    .key = key,
                    .extra = .{
                        .kind = try self.allocator.dupe(u8, if (Record == RoleBindingRecord) "Role" else "ClusterRole"),
                        .name = try self.allocator.dupe(u8, value),
                    },
                    .creation_timestamp = try self.allocator.dupe(u8, timestamp),
                };
            if (comptime Record == ValidatingAdmissionPolicyRecord or Record == MutatingAdmissionPolicyRecord)
                return .{
                    .key = key,
                    .extra = .{
                        .failure_policy = try self.allocator.dupe(u8, value),
                        .count = if (std.mem.endsWith(u8, value, "watch")) 7 else 2,
                    },
                    .creation_timestamp = try self.allocator.dupe(u8, timestamp),
                };
            if (comptime Record == ValidatingAdmissionPolicyBindingRecord or Record == MutatingAdmissionPolicyBindingRecord)
                return .{
                    .key = key,
                    .extra = .{ .value = try self.allocator.dupe(u8, value) },
                    .creation_timestamp = try self.allocator.dupe(u8, timestamp),
                };
            if (comptime Record == ValidatingWebhookConfigurationRecord or Record == MutatingWebhookConfigurationRecord)
                return .{
                    .key = key,
                    .extra = .{ .count = if (std.mem.endsWith(u8, value, "watch")) 7 else 2 },
                    .creation_timestamp = try self.allocator.dupe(u8, timestamp),
                };
            if (comptime Record == ResourceClaimRecord)
                return .{ .key = key, .status = try self.allocator.dupe(u8, value), .creation_timestamp = try self.allocator.dupe(u8, timestamp) };
            if (comptime Record == DeviceClassRecord)
                return .{ .key = key, .selector_count = if (std.mem.endsWith(u8, value, "watch")) 7 else 2, .creation_timestamp = try self.allocator.dupe(u8, timestamp) };
            if (comptime Record == PriorityClassRecord)
                return .{ .key = key, .value = count, .global_default = std.mem.endsWith(u8, value, "watch"), .creation_timestamp = try self.allocator.dupe(u8, timestamp) };
            if (comptime Record == RuntimeClassRecord)
                return .{ .key = key, .handler = try self.allocator.dupe(u8, value), .creation_timestamp = try self.allocator.dupe(u8, timestamp) };
            if (comptime Record == LeaseRecord)
                return .{ .key = key, .holder = try self.allocator.dupe(u8, value), .creation_timestamp = try self.allocator.dupe(u8, timestamp) };
            if (comptime Record == CSRRecord)
                return .{ .key = key, .signer = try self.allocator.dupe(u8, value), .issued = std.mem.endsWith(u8, value, "watch"), .creation_timestamp = try self.allocator.dupe(u8, timestamp) };
            if (comptime Record == StorageVersionMigrationRecord)
                return .{ .key = key, .resource_version = try self.allocator.dupe(u8, value), .creation_timestamp = try self.allocator.dupe(u8, timestamp) };
            if (comptime Record == EventRecord)
                return .{
                    .key = key,
                    .last_seen_timestamp = try self.allocator.dupe(u8, timestamp),
                    .event_type = try self.allocator.dupe(u8, "Warning"),
                    .reason = try self.allocator.dupe(u8, "BackOff"),
                    .object = try self.allocator.dupe(u8, value),
                    .count = count,
                    .message = try self.allocator.dupe(u8, "restarting"),
                };
            unreachable;
        }

        fn list(
            raw: *anyopaque,
            _: list_watch.CancelToken,
            receiver_context: *anyopaque,
            receiver: *const fn (*anyopaque, Record) anyerror!void,
            chunk_end: *const fn (*anyopaque) anyerror!void,
        ) anyerror!list_watch.ListOutcome {
            const self: *@This() = @ptrCast(@alignCast(raw));
            try receiver(receiver_context, try self.makeRecord(
                "stable-uid",
                "alpha-resource",
                self.list_value,
                "2024-01-01T00:00:00Z",
            ));
            if (comptime discriminating_rows) {
                try receiver(receiver_context, try self.makeRecord(
                    "other-uid",
                    "beta-resource",
                    "secondary",
                    "2024-02-01T00:00:00Z",
                ));
            }
            try chunk_end(receiver_context);
            return .{ .complete = try keys.OwnedBytes.clone(self.allocator, "10") };
        }

        fn watch(
            raw: *anyopaque,
            resource_version: []const u8,
            cancel: list_watch.CancelToken,
            receiver_context: *anyopaque,
            receiver: *const fn (*anyopaque, *list_watch.WatchEvent(Record)) anyerror!void,
        ) anyerror!list_watch.Failure {
            const self: *@This() = @ptrCast(@alignCast(raw));
            try std.testing.expectEqualStrings("10", resource_version);
            self.watch_entered.store(true, .release);
            while (!self.watch_release.load(.acquire)) {
                if (cancel.isCanceled()) return .canceled;
                @import("../core/runtime.zig").io().sleep(.{ .nanoseconds = std.time.ns_per_ms }, .awake) catch
                    return .canceled;
            }
            self.watch_calls += 1;
            var event: list_watch.WatchEvent(Record) = .{
                .modified = try self.makeRecord(
                    "stable-uid",
                    "alpha-resource",
                    self.watch_value,
                    "2025-01-01T00:00:00Z",
                ),
            };
            defer event.deinit(self.allocator);
            try receiver(receiver_context, &event);
            var deleted_record = try self.makeRecord(
                "other-uid",
                "beta-resource",
                "secondary",
                "2024-02-01T00:00:00Z",
            );
            defer deleted_record.deinit(self.allocator);
            var deleted: list_watch.WatchEvent(Record) = .{
                .deleted = try deleted_record.key.clone(self.allocator),
            };
            defer deleted.deinit(self.allocator);
            try receiver(receiver_context, &deleted);
            return .canceled;
        }
    };

    const Route = struct {
        plane: *DataPlane,
        projection: *projection_mod.ResourceProjection(Record),
        active: lifecycle.SubscriptionKey,
        table_context: *anyopaque,
        io: std.Io,
        completed: bool = false,
        watch_connected: bool = false,

        fn target(raw: *anyopaque, target_value: keys.EnvelopeTarget) ?*anyopaque {
            const self: *@This() = @ptrCast(@alignCast(raw));
            return switch (target_value) {
                .resource => self.plane.resourceTarget(
                    target_value,
                    self.active,
                    @ptrCast(self.projection),
                ),
                .lifecycle => @ptrCast(self.plane),
                else => null,
            };
        }

        fn lifecycleObserved(
            raw: *anyopaque,
            _: *anyopaque,
            identity: ?keys.ResourceIdentity,
        ) void {
            const self: *@This() = @ptrCast(@alignCast(raw));
            const exact = identity orelse return;
            if (exact.generation == self.active.generation and
                exact.subscription_id == self.active.subscription_id)
            {
                self.completed = true;
            }
        }

        fn drain(self: *@This(), queue: *ChangeQueue) !void {
            var router = keys.UiRouter{
                .context = self,
                .targetFn = target,
                .lifecycleFn = lifecycleObserved,
            };
            var attempts: usize = 0;
            while (!self.completed and attempts < 200) : (attempts += 1) {
                while (queue.pop()) |value| {
                    var envelope = value;
                    if (!self.plane.acceptsEnvelope(envelope)) {
                        envelope.deinit(allocator);
                        continue;
                    }
                    const target_value = envelope.target;
                    try envelope.apply(&router, allocator);
                    if (target_value == .resource) {
                        try sync_table(self.table_context);
                    }
                }
                if (!self.completed) try self.io.sleep(.{ .nanoseconds = std.time.ns_per_ms }, .awake);
            }
            try std.testing.expect(self.completed);
        }

        fn drainInitial(self: *@This(), queue: *ChangeQueue) !void {
            var router = keys.UiRouter{
                .context = self,
                .targetFn = target,
                .lifecycleFn = lifecycleObserved,
            };
            var attempts: usize = 0;
            while (!self.watch_connected and attempts < 10_000) : (attempts += 1) {
                var envelope = queue.pop() orelse {
                    try self.io.sleep(.{ .nanoseconds = std.time.ns_per_ms }, .awake);
                    continue;
                };
                if (!self.plane.acceptsEnvelope(envelope)) {
                    envelope.deinit(allocator);
                    continue;
                }
                const target_value = envelope.target;
                const sync_kind = envelope.sync_kind;
                try envelope.apply(&router, allocator);
                if (target_value == .resource) try sync_table(self.table_context);
                if (sync_kind == .watch_connected) self.watch_connected = true;
            }
            try std.testing.expect(self.watch_connected);
        }
    };

    var shared_event: std.Io.Event = .unset;
    var inbox = lifecycle.LifecycleInbox.init(io, &shared_event);
    defer inbox.deinit(allocator);
    var cancellations = lifecycle.CancellationIntents.init();
    var slot = ActiveSessionSlot.init(io, &shared_event);
    defer slot.deinit();
    var queue = ChangeQueue.init(io, allocator, keys.Limits.default, &shared_event, null);
    defer queue.deinit();
    const client = try allocator.create(klient.K8sClient);
    var client_owned = true;
    errdefer if (client_owned) allocator.destroy(client);
    client.* = try klient.K8sClient.init(allocator, io, .{
        .server = "http://127.0.0.1",
        .namespace = "default",
    });
    errdefer if (client_owned) client.deinit();
    const session = try active_context.ActiveContextSession.adopt(
        allocator,
        io,
        1,
        .{
            .context_name = "test",
            .kubeconfig_path = null,
            .default_namespace = "default",
            .force_proxy = false,
            .readonly = true,
        },
        .{
            .shared_event = &shared_event,
            .client = client,
            .cluster_name = "cluster",
            .user_name = "user",
            .readiness_verified = true,
        },
    );
    client_owned = false;
    _ = try slot.commit(session);
    var supervisor = try Supervisor.init(
        allocator,
        io,
        &shared_event,
        &inbox,
        &cancellations,
        &slot,
        &queue,
        active_context.SessionFactory.production(),
        session,
    );
    try supervisor.startRoot();
    var producer = lifecycle.LifecycleProducer.init(&inbox, &cancellations, allocator);
    defer {
        producer.enqueueShutdown() catch {};
        _ = supervisor.awaitRoot();
    }
    var plane = DataPlane.init(allocator, producer, &queue);
    var watch_release: std.atomic.Value(bool) = .init(false);
    var watch_entered: std.atomic.Value(bool) = .init(false);
    var script = Script{
        .allocator = allocator,
        .list_value = "first-list",
        .watch_value = "first-watch",
        .watch_release = &watch_release,
        .watch_entered = &watch_entered,
    };
    var destroyed: std.atomic.Value(usize) = .init(0);
    var first_spec = try Subscription.ownedTaskSpec(allocator, .{
        .context_name = "test",
        .projection = projection,
        .deinit_counter = &destroyed,
        .transport_override = fake.transport(),
        .watch_override = script.source(),
    });
    defer first_spec.deinit(allocator);
    const first_key = try plane.startSubscription(1, &first_spec);
    try std.testing.expectEqual(@as(usize, 0), projection.count());
    var first_route = Route{
        .plane = &plane,
        .projection = projection,
        .active = first_key,
        .table_context = table_context,
        .io = io,
    };
    try first_route.drainInitial(&queue);
    var watch_attempts: usize = 0;
    while (!watch_entered.load(.acquire) and watch_attempts < 10_000) : (watch_attempts += 1) {
        try io.sleep(.{ .nanoseconds = std.time.ns_per_ms }, .awake);
    }
    try std.testing.expect(watch_entered.load(.acquire));
    try std.testing.expectEqual(@as(usize, 2), projection.count());
    try std.testing.expect(projection.record("stable-uid") != null);
    try std.testing.expect(projection.record("other-uid") != null);
    var list_value: ?[]u8 = null;
    if (comptime evidence_column) |column| {
        const columns = try projection.record("stable-uid").?.columns(allocator);
        defer for (columns) |value| allocator.free(value);
        list_value = try allocator.dupe(u8, columns[column]);
    }
    defer if (list_value) |value| allocator.free(value);
    watch_release.store(true, .release);
    try first_route.drain(&queue);
    if (comptime evidence_column) |column| {
        const columns = try projection.record("stable-uid").?.columns(allocator);
        defer for (columns) |value| allocator.free(value);
        try std.testing.expect(!std.mem.eql(u8, list_value.?, columns[column]));
    }
    if (comptime discriminating_rows) {
        try std.testing.expectEqual(@as(usize, 1), projection.count());
        try projection.setView("alpha", name_column, true);
        try std.testing.expectEqual(@as(usize, 1), projection.visibleCount());
        try std.testing.expectEqualStrings("stable-uid", projection.visibleUid(0).?);
    }
    try std.testing.expect(projection.selectUid("stable-uid"));
    try sync_table(table_context);

    script.list_value = "second-list";
    script.watch_value = "second-watch";
    watch_release.store(false, .release);
    watch_entered.store(false, .release);
    var second_spec = try Subscription.ownedTaskSpec(allocator, .{
        .context_name = "test",
        .projection = projection,
        .deinit_counter = &destroyed,
        .transport_override = fake.transport(),
        .watch_override = script.source(),
    });
    defer second_spec.deinit(allocator);
    const second_key = try plane.startSubscription(1, &second_spec);
    try std.testing.expect(second_key.subscription_id != first_key.subscription_id);
    var second_route = Route{
        .plane = &plane,
        .projection = projection,
        .active = second_key,
        .table_context = table_context,
        .io = io,
    };
    try second_route.drainInitial(&queue);
    watch_attempts = 0;
    while (!watch_entered.load(.acquire) and watch_attempts < 10_000) : (watch_attempts += 1) {
        try io.sleep(.{ .nanoseconds = std.time.ns_per_ms }, .awake);
    }
    try std.testing.expect(watch_entered.load(.acquire));
    try std.testing.expectEqual(@as(usize, 2), projection.count());
    watch_release.store(true, .release);
    try second_route.drain(&queue);
    try std.testing.expectEqualStrings("stable-uid", projection.selectedUid().?);
    try std.testing.expectEqual(@as(usize, 1), projection.visibleCount());
    try std.testing.expectEqualStrings("stable-uid", projection.visibleUid(0).?);
    try std.testing.expectEqual(@as(usize, 2), fake.requests.items.len);
    const base_path = try Subscription.listPath(allocator, null);
    defer allocator.free(base_path);
    const expected_path = try read_transport.paginatedListPath(allocator, base_path, "");
    defer allocator.free(expected_path);
    for (fake.requests.items) |request| {
        try std.testing.expectEqualStrings(expected_path, request.path);
    }
    try std.testing.expectEqual(@as(usize, 2), script.watch_calls);
    try std.testing.expectEqual(@as(usize, 2), destroyed.load(.acquire));
}

test "node LIST WATCH supervisor queue populates table and preserves selection on restart" {
    const NodeRecord = @import("NodeRecord.zig");
    const Projection = projection_mod.ResourceProjection(NodeRecord);
    const Subscription = ResourceSubscription(klient.Node, NodeRecord, NodeRecord.fromNode);
    const NodesView = @import("../view/resource_configs.zig").NodesView;
    const K8sService = @import("../services/K8sService.zig").K8sService;
    const Theme = @import("../model/theme_loader.zig").ThemeColors;
    const ProjectionFns = struct {
        fn match(_: *const NodeRecord, _: []const u8) bool {
            return true;
        }
        fn sort(record: *const NodeRecord, _: u8) []const u8 {
            return record.key.name;
        }
        fn columns(_: *Projection, record: *const NodeRecord, allocator: std.mem.Allocator) ![6][]const u8 {
            return record.columns(allocator);
        }
        fn sync(raw: *anyopaque) !void {
            const view: *NodesView = @ptrCast(@alignCast(raw));
            try view.syncProjection();
        }
    };
    var projection = Projection.init(std.testing.allocator, .{
        .matchFn = ProjectionFns.match,
        .sortKeyFn = ProjectionFns.sort,
    });
    defer projection.deinit();
    var service: K8sService = undefined;
    var theme: Theme = undefined;
    var view = try NodesView.init(std.testing.allocator, &theme, &service);
    defer view.deinit();
    view.bindProjection(NodesView.ProjectionAdapter.init(
        NodeRecord,
        &projection,
        ProjectionFns.columns,
    ));
    try exerciseQueueRestart(
        NodeRecord,
        Subscription,
        false,
        0,
        null,
        &projection,
        @ptrCast(&view),
        ProjectionFns.sync,
    );
    try std.testing.expectEqual(@as(usize, 1), view.table.items.items.len);
    try std.testing.expectEqualStrings("second-watch", view.table.items.items[0].columns[1]);
}

test "namespace LIST WATCH supervisor queue populates table and preserves selection on restart" {
    const NamespaceRecord = @import("NamespaceRecord.zig");
    const Projection = projection_mod.ResourceProjection(NamespaceRecord);
    const Subscription = ResourceSubscription(
        klient.Namespace,
        NamespaceRecord,
        NamespaceRecord.fromNamespace,
    );
    const NamespacesView = @import("../view/NamespacesView.zig").NamespacesView;
    const K8sService = @import("../services/K8sService.zig").K8sService;
    const Theme = @import("../model/theme_loader.zig").ThemeColors;
    const ProjectionFns = struct {
        fn match(_: *const NamespaceRecord, _: []const u8) bool {
            return true;
        }
        fn sort(record: *const NamespaceRecord, _: u8) []const u8 {
            return record.key.name;
        }
        fn sync(raw: *anyopaque) !void {
            const view: *NamespacesView = @ptrCast(@alignCast(raw));
            try view.syncProjection();
        }
    };
    var projection = Projection.init(std.testing.allocator, .{
        .matchFn = ProjectionFns.match,
        .sortKeyFn = ProjectionFns.sort,
    });
    defer projection.deinit();
    var service = try K8sService.init(std.testing.allocator);
    defer service.deinit();
    var theme: Theme = undefined;
    var view = try NamespacesView.init(std.testing.allocator, &theme, &service);
    defer view.deinit();
    view.bindProjection(&projection);
    try exerciseQueueRestart(
        NamespaceRecord,
        Subscription,
        false,
        0,
        null,
        &projection,
        @ptrCast(&view),
        ProjectionFns.sync,
    );
    try std.testing.expectEqual(@as(usize, 1), view.table.items.items.len);
    try std.testing.expectEqualStrings("second-watch", view.table.items.items[0].status);
}

fn exerciseNamespacedFamily(
    comptime Record: type,
    comptime Subscription: type,
    comptime ViewType: type,
    comptime value_column: ?usize,
    expected_value: []const u8,
) !void {
    const Projection = projection_mod.ResourceProjection(Record);
    const K8sService = @import("../services/K8sService.zig").K8sService;
    const Theme = @import("../model/theme_loader.zig").ThemeColors;
    const Fns = struct {
        fn containsIgnoreCase(value: []const u8, needle: []const u8) bool {
            if (needle.len > value.len) return false;
            var index: usize = 0;
            while (index + needle.len <= value.len) : (index += 1) {
                if (std.ascii.eqlIgnoreCase(value[index .. index + needle.len], needle))
                    return true;
            }
            return false;
        }
        fn match(record: *const Record, filter: []const u8) bool {
            return filter.len == 0 or
                containsIgnoreCase(record.key.namespace, filter) or
                containsIgnoreCase(record.key.name, filter);
        }
        fn sort(record: *const Record, column: u8) []const u8 {
            const ServiceRecord = @import("ServiceRecord.zig");
            const EndpointRecord = @import("EndpointRecord.zig");
            const ConfigMapRecord = @import("ConfigMapRecord.zig");
            const SecretRecord = @import("SecretRecord.zig");
            const ServiceAccountRecord = @import("ServiceAccountRecord.zig");
            const ResourceQuotaRecord = @import("ResourceQuotaRecord.zig");
            const LimitRangeRecord = @import("LimitRangeRecord.zig");
            const DeploymentRecord = @import("DeploymentRecord.zig");
            const StatefulSetRecord = @import("StatefulSetRecord.zig");
            const DaemonSetRecord = @import("DaemonSetRecord.zig");
            const ReplicaSetRecord = @import("ReplicaSetRecord.zig");
            const JobRecord = @import("JobRecord.zig");
            const CronJobRecord = @import("CronJobRecord.zig");
            const HPARecord = @import("HPARecord.zig");
            const PDBRecord = @import("PDBRecord.zig");
            const IngressRecord = @import("IngressRecord.zig");
            const IngressClassRecord = @import("IngressClassRecord.zig");
            const NetworkPolicyRecord = @import("NetworkPolicyRecord.zig");
            const IPAddressRecord = @import("IPAddressRecord.zig");
            const ServiceCIDRRecord = @import("ServiceCIDRRecord.zig");
            const PVRecord = @import("PVRecord.zig");
            const PVCRecord = @import("PVCRecord.zig");
            const StorageClassRecord = @import("StorageClassRecord.zig");
            const VolumeAttributesClassRecord = @import("VolumeAttributesClassRecord.zig");
            const CSIDriverRecord = @import("CSIDriverRecord.zig");
            const GatewayClassRecord = @import("GatewayClassRecord.zig");
            const GatewayRecord = @import("GatewayRecord.zig");
            const HTTPRouteRecord = @import("HTTPRouteRecord.zig");
            const GRPCRouteRecord = @import("GRPCRouteRecord.zig");
            const ReferenceGrantRecord = @import("ReferenceGrantRecord.zig");
            const TCPRouteRecord = @import("TCPRouteRecord.zig");
            const TLSRouteRecord = @import("TLSRouteRecord.zig");
            const UDPRouteRecord = @import("UDPRouteRecord.zig");
            const BackendTLSPolicyRecord = @import("BackendTLSPolicyRecord.zig");
            const ListenerSetRecord = @import("ListenerSetRecord.zig");
            const RoleRecord = @import("RoleRecord.zig").RoleRecord;
            const RoleBindingRecord = @import("RoleBindingRecord.zig").RoleBindingRecord;
            const ClusterRoleRecord = @import("ClusterRoleRecord.zig").ClusterRoleRecord;
            const ClusterRoleBindingRecord = @import("ClusterRoleBindingRecord.zig").ClusterRoleBindingRecord;
            const ValidatingAdmissionPolicyRecord = @import("ValidatingAdmissionPolicyRecord.zig").ValidatingAdmissionPolicyRecord;
            const ValidatingAdmissionPolicyBindingRecord = @import("ValidatingAdmissionPolicyBindingRecord.zig").ValidatingAdmissionPolicyBindingRecord;
            const MutatingAdmissionPolicyRecord = @import("MutatingAdmissionPolicyRecord.zig").MutatingAdmissionPolicyRecord;
            const MutatingAdmissionPolicyBindingRecord = @import("MutatingAdmissionPolicyBindingRecord.zig").MutatingAdmissionPolicyBindingRecord;
            const ValidatingWebhookConfigurationRecord = @import("ValidatingWebhookConfigurationRecord.zig").ValidatingWebhookConfigurationRecord;
            const MutatingWebhookConfigurationRecord = @import("MutatingWebhookConfigurationRecord.zig").MutatingWebhookConfigurationRecord;
            const ResourceClaimRecord = @import("ResourceClaimRecord.zig");
            const DeviceClassRecord = @import("DeviceClassRecord.zig");
            const PriorityClassRecord = @import("PriorityClassRecord.zig");
            const RuntimeClassRecord = @import("RuntimeClassRecord.zig");
            const LeaseRecord = @import("LeaseRecord.zig");
            const CSRRecord = @import("CSRRecord.zig");
            const StorageVersionMigrationRecord = @import("StorageVersionMigrationRecord.zig");
            const EventRecord = @import("EventRecord.zig");
            if (comptime Record == ServiceRecord) {
                return switch (column) {
                    0 => record.key.namespace,
                    1 => record.key.name,
                    2 => record.service_type,
                    3 => record.cluster_ip,
                    4 => record.external_ip,
                    5 => record.ports,
                    6 => record.creation_timestamp orelse "",
                    else => record.key.name,
                };
            }
            if (comptime Record == EndpointRecord) {
                return switch (column) {
                    0 => record.key.namespace,
                    1 => record.key.name,
                    2 => record.endpoints,
                    3 => record.creation_timestamp orelse "",
                    else => record.key.name,
                };
            }
            if (comptime Record == ConfigMapRecord or Record == ServiceAccountRecord) {
                return switch (column) {
                    0 => record.key.namespace,
                    1 => record.key.name,
                    2 => if (Record == ConfigMapRecord) &record.data_sort_key else &record.secret_sort_key,
                    3 => record.creation_timestamp orelse "",
                    else => record.key.name,
                };
            }
            if (comptime Record == SecretRecord) {
                return switch (column) {
                    0 => record.key.namespace,
                    1 => record.key.name,
                    2 => record.secret_type,
                    3 => &record.data_sort_key,
                    4 => record.creation_timestamp orelse "",
                    else => record.key.name,
                };
            }
            if (comptime Record == ResourceQuotaRecord or Record == LimitRangeRecord) {
                return switch (column) {
                    0 => record.key.namespace,
                    1 => record.key.name,
                    2 => record.creation_timestamp orelse "",
                    else => record.key.name,
                };
            }
            if (comptime Record == DeploymentRecord) return switch (column) {
                0 => record.key.namespace,
                1 => record.key.name,
                2 => &record.ready_sort_key,
                3 => &record.updated_sort_key,
                4 => &record.available_sort_key,
                5 => record.creation_timestamp orelse "",
                else => record.key.name,
            };
            if (comptime Record == StatefulSetRecord) return switch (column) {
                0 => record.key.namespace,
                1 => record.key.name,
                2 => &record.ready_sort_key,
                3 => record.creation_timestamp orelse "",
                else => record.key.name,
            };
            if (comptime Record == DaemonSetRecord) return switch (column) {
                0 => record.key.namespace,
                1 => record.key.name,
                2 => &record.desired_sort_key,
                3 => &record.current_sort_key,
                4 => &record.ready_sort_key,
                5 => &record.updated_sort_key,
                6 => record.creation_timestamp orelse "",
                else => record.key.name,
            };
            if (comptime Record == ReplicaSetRecord) return switch (column) {
                0 => record.key.namespace,
                1 => record.key.name,
                2 => &record.desired_sort_key,
                3 => &record.current_sort_key,
                4 => &record.ready_sort_key,
                5 => record.creation_timestamp orelse "",
                else => record.key.name,
            };
            if (comptime Record == JobRecord) return switch (column) {
                0 => record.key.namespace,
                1 => record.key.name,
                2 => &record.completions_sort_key,
                3 => record.start_time orelse "",
                4 => record.creation_timestamp orelse "",
                else => record.key.name,
            };
            if (comptime Record == CronJobRecord) return switch (column) {
                0 => record.key.namespace,
                1 => record.key.name,
                2 => record.schedule,
                3 => if (record.@"suspend") "True" else "False",
                4 => &record.active_sort_key,
                5 => record.last_schedule_time orelse "",
                else => record.key.name,
            };
            if (comptime Record == HPARecord) return switch (column) {
                0 => record.key.namespace,
                1 => record.key.name,
                2 => &record.min_sort_key,
                3 => &record.max_sort_key,
                4 => &record.current_sort_key,
                5 => record.creation_timestamp orelse "",
                else => record.key.name,
            };
            if (comptime Record == PDBRecord) return switch (column) {
                0 => record.key.namespace,
                1 => record.key.name,
                2 => &record.min_available_sort_key,
                3 => &record.max_unavailable_sort_key,
                4 => &record.allowed_sort_key,
                5 => record.creation_timestamp orelse "",
                else => record.key.name,
            };
            if (comptime Record == IngressRecord) return switch (column) {
                0 => record.key.namespace,
                1 => record.key.name,
                2 => record.class,
                3 => record.hosts,
                4 => record.address,
                5 => record.ports,
                6 => record.creation_timestamp orelse "",
                else => record.key.name,
            };
            if (comptime Record == IngressClassRecord) return switch (column) {
                0 => record.key.name,
                1 => record.controller,
                2 => record.creation_timestamp orelse "",
                else => record.key.name,
            };
            if (comptime Record == NetworkPolicyRecord) return switch (column) {
                0 => record.key.namespace,
                1 => record.key.name,
                2 => record.pod_selector,
                3 => record.creation_timestamp orelse "",
                else => record.key.name,
            };
            if (comptime Record == IPAddressRecord) return switch (column) {
                0 => record.key.name,
                1 => record.parent,
                2 => record.creation_timestamp orelse "",
                else => record.key.name,
            };
            if (comptime Record == ServiceCIDRRecord) return switch (column) {
                0 => record.key.name,
                1 => record.cidrs,
                2 => record.creation_timestamp orelse "",
                else => record.key.name,
            };
            if (comptime Record == PVRecord) return switch (column) {
                0 => record.key.name,
                1 => &record.capacity_sort_key,
                2 => record.access,
                3 => record.reclaim,
                4 => record.status,
                5 => record.claim,
                6 => record.storage_class,
                7 => record.creation_timestamp orelse "",
                else => record.key.name,
            };
            if (comptime Record == PVCRecord) return switch (column) {
                0 => record.key.namespace,
                1 => record.key.name,
                2 => record.status,
                3 => record.volume,
                4 => &record.capacity_sort_key,
                5 => record.access,
                6 => record.storage_class,
                7 => record.creation_timestamp orelse "",
                else => record.key.name,
            };
            if (comptime Record == StorageClassRecord) return switch (column) {
                0 => record.key.name,
                1 => record.provisioner,
                2 => record.reclaim_policy,
                3 => record.bind_mode,
                4 => if (record.expansion) "true" else "false",
                5 => record.creation_timestamp orelse "",
                else => record.key.name,
            };
            if (comptime Record == VolumeAttributesClassRecord) return switch (column) {
                0 => record.key.name,
                1 => record.driver,
                2 => record.creation_timestamp orelse "",
                else => record.key.name,
            };
            if (comptime Record == CSIDriverRecord) return switch (column) {
                0 => record.key.name,
                1 => if (record.attach_required) "true" else "false",
                2 => if (record.pod_info) "true" else "false",
                3 => record.creation_timestamp orelse "",
                else => record.key.name,
            };
            if (comptime Record == GatewayClassRecord) return switch (column) {
                0 => record.key.name,
                1 => record.controller,
                2 => record.creation_timestamp orelse "",
                else => record.key.name,
            };
            if (comptime Record == GatewayRecord) return switch (column) {
                0 => record.key.namespace,
                1 => record.key.name,
                2 => record.gateway_class,
                3 => record.address,
                4 => record.creation_timestamp orelse "",
                else => record.key.name,
            };
            if (comptime Record == HTTPRouteRecord or Record == GRPCRouteRecord or Record == TLSRouteRecord) return switch (column) {
                0 => record.key.namespace,
                1 => record.key.name,
                2 => record.parent,
                3 => record.hostnames,
                4 => record.creation_timestamp orelse "",
                else => record.key.name,
            };
            if (comptime Record == ReferenceGrantRecord) return switch (column) {
                0 => record.key.namespace,
                1 => record.key.name,
                2 => record.from_kind,
                3 => record.to_kind,
                4 => record.creation_timestamp orelse "",
                else => record.key.name,
            };
            if (comptime Record == TCPRouteRecord or Record == UDPRouteRecord) return switch (column) {
                0 => record.key.namespace,
                1 => record.key.name,
                2 => record.parent,
                3 => record.creation_timestamp orelse "",
                else => record.key.name,
            };
            if (comptime Record == BackendTLSPolicyRecord) return switch (column) {
                0 => record.key.namespace,
                1 => record.key.name,
                2 => record.target,
                3 => record.creation_timestamp orelse "",
                else => record.key.name,
            };
            if (comptime Record == ListenerSetRecord) return switch (column) {
                0 => record.key.namespace,
                1 => record.key.name,
                2 => record.parent,
                4 => record.creation_timestamp orelse "",
                else => record.key.name,
            };
            if (comptime Record == RoleRecord) return switch (column) {
                0 => record.key.namespace,
                1 => record.key.name,
                2 => record.creation_timestamp orelse "",
                else => record.key.name,
            };
            if (comptime Record == RoleBindingRecord) return switch (column) {
                0 => record.key.namespace,
                1 => record.key.name,
                2 => record.extra.name,
                3 => record.creation_timestamp orelse "",
                else => record.key.name,
            };
            if (comptime Record == ClusterRoleRecord) return switch (column) {
                0 => record.key.name,
                1 => record.creation_timestamp orelse "",
                else => record.key.name,
            };
            if (comptime Record == ClusterRoleBindingRecord) return switch (column) {
                0 => record.key.name,
                1 => record.extra.name,
                2 => record.creation_timestamp orelse "",
                else => record.key.name,
            };
            if (comptime Record == ValidatingAdmissionPolicyRecord or Record == MutatingAdmissionPolicyRecord) return switch (column) {
                0 => record.key.name,
                1 => record.extra.failure_policy,
                3 => record.creation_timestamp orelse "",
                else => record.key.name,
            };
            if (comptime Record == ValidatingAdmissionPolicyBindingRecord or Record == MutatingAdmissionPolicyBindingRecord) return switch (column) {
                0 => record.key.name,
                1 => record.extra.value,
                2 => record.creation_timestamp orelse "",
                else => record.key.name,
            };
            if (comptime Record == ValidatingWebhookConfigurationRecord or Record == MutatingWebhookConfigurationRecord) return switch (column) {
                0 => record.key.name,
                2 => record.creation_timestamp orelse "",
                else => record.key.name,
            };
            if (comptime Record == ResourceClaimRecord) return switch (column) {
                0 => record.key.namespace,
                1 => record.key.name,
                2 => record.status,
                3 => record.creation_timestamp orelse "",
                else => record.key.name,
            };
            if (comptime Record == DeviceClassRecord or Record == PriorityClassRecord) return record.key.name;
            if (comptime Record == RuntimeClassRecord) return if (column == 1) record.handler else record.key.name;
            if (comptime Record == LeaseRecord) return switch (column) {
                0 => record.key.namespace,
                1 => record.key.name,
                2 => record.holder,
                3 => record.creation_timestamp orelse "",
                else => record.key.name,
            };
            if (comptime Record == CSRRecord) return if (column == 1) record.signer else record.key.name;
            if (comptime Record == StorageVersionMigrationRecord) return if (column == 1) record.resource_version else record.key.name;
            if (comptime Record == EventRecord) return switch (column) {
                0 => record.key.namespace,
                2 => record.event_type,
                3 => record.reason,
                4 => record.object,
                6 => record.message,
                else => record.key.name,
            };
            return switch (column) {
                0 => record.key.namespace,
                1 => record.key.name,
                2 => record.address_type,
                3 => record.endpoints,
                4 => record.creation_timestamp orelse "",
                else => record.key.name,
            };
        }
        fn columns(
            _: *Projection,
            record: *const Record,
            allocator: std.mem.Allocator,
        ) ![ViewType.view_config.columns.len][]const u8 {
            return record.columns(allocator);
        }
        fn sync(raw: *anyopaque) !void {
            const view: *ViewType = @ptrCast(@alignCast(raw));
            try view.syncProjection();
        }
    };
    var projection = Projection.init(std.testing.allocator, .{
        .matchFn = Fns.match,
        .sortKeyFn = Fns.sort,
    });
    defer projection.deinit();
    var service = try K8sService.init(std.testing.allocator);
    defer service.deinit();
    var theme: Theme = undefined;
    var view = try ViewType.init(std.testing.allocator, &theme, &service);
    defer view.deinit();
    view.bindProjection(ViewType.ProjectionAdapter.init(
        Record,
        &projection,
        Fns.columns,
    ));
    try std.testing.expectEqual(@as(usize, 0), view.table.items.items.len);
    try exerciseQueueRestart(
        Record,
        Subscription,
        true,
        ViewType.view_config.name_column,
        value_column,
        &projection,
        @ptrCast(&view),
        Fns.sync,
    );
    try std.testing.expectEqual(@as(usize, 1), view.table.items.items.len);
    if (value_column) |column| {
        if (expected_value.len > 0) {
            try std.testing.expectEqualStrings(
                expected_value,
                view.table.items.items[0].columns[column],
            );
        }
    } else {
        const expected_age = try @import("../viewmodel/age.zig").calculateAge(
            std.testing.allocator,
            "2025-01-01T00:00:00Z",
        );
        defer std.testing.allocator.free(expected_age);
        try std.testing.expectEqualStrings(
            expected_age,
            view.table.items.items[0].columns[ViewType.view_config.columns.len - 1],
        );
    }
}

test "services family LIST WATCH supervisor queue populates tables across restart" {
    const configs = @import("../view/resource_configs.zig");
    try exerciseNamespacedFamily(
        @import("ServiceRecord.zig"),
        ResourceSubscription(klient.Service, @import("ServiceRecord.zig"), @import("ServiceRecord.zig").fromService),
        configs.ServicesView,
        2,
        "second-watch",
    );
    try exerciseNamespacedFamily(
        @import("EndpointRecord.zig"),
        ResourceSubscription(klient.Endpoints, @import("EndpointRecord.zig"), @import("EndpointRecord.zig").fromEndpoints),
        configs.EndpointsView,
        2,
        "second-watch",
    );
    try exerciseNamespacedFamily(
        @import("EndpointSliceRecord.zig"),
        ResourceSubscription(klient.EndpointSlice, @import("EndpointSliceRecord.zig"), @import("EndpointSliceRecord.zig").fromEndpointSlice),
        configs.EndpointSlicesView,
        3,
        "second-watch",
    );
}

test "config family LIST WATCH supervisor queue populates tables across restart" {
    const configs = @import("../view/resource_configs.zig");
    try exerciseNamespacedFamily(
        @import("ConfigMapRecord.zig"),
        ResourceSubscription(klient.ConfigMap, @import("ConfigMapRecord.zig"), @import("ConfigMapRecord.zig").fromConfigMap),
        configs.ConfigMapsView,
        2,
        "3",
    );
    try exerciseNamespacedFamily(
        @import("SecretRecord.zig"),
        ResourceSubscription(klient.Secret, @import("SecretRecord.zig"), @import("SecretRecord.zig").fromSecret),
        configs.SecretsView,
        2,
        "second-watch",
    );
    try exerciseNamespacedFamily(
        @import("ServiceAccountRecord.zig"),
        ResourceSubscription(klient.ServiceAccount, @import("ServiceAccountRecord.zig"), @import("ServiceAccountRecord.zig").fromServiceAccount),
        configs.ServiceAccountsView,
        2,
        "3",
    );
    try exerciseNamespacedFamily(
        @import("ResourceQuotaRecord.zig"),
        ResourceSubscription(klient.ResourceQuota, @import("ResourceQuotaRecord.zig"), @import("ResourceQuotaRecord.zig").fromResourceQuota),
        configs.ResourceQuotasView,
        null,
        "",
    );
    try exerciseNamespacedFamily(
        @import("LimitRangeRecord.zig"),
        ResourceSubscription(klient.LimitRange, @import("LimitRangeRecord.zig"), @import("LimitRangeRecord.zig").fromLimitRange),
        configs.LimitRangesView,
        null,
        "",
    );
}

test "workloads family LIST WATCH supervisor queue populates tables across restart" {
    const configs = @import("../view/resource_configs.zig");
    try exerciseNamespacedFamily(
        @import("DeploymentRecord.zig"),
        ResourceSubscription(klient.Deployment, @import("DeploymentRecord.zig"), @import("DeploymentRecord.zig").fromDeployment),
        configs.DeploymentsView,
        2,
        "7/8",
    );
    try exerciseNamespacedFamily(
        @import("StatefulSetRecord.zig"),
        ResourceSubscription(klient.StatefulSet, @import("StatefulSetRecord.zig"), @import("StatefulSetRecord.zig").fromStatefulSet),
        configs.StatefulSetsView,
        2,
        "7/8",
    );
    try exerciseNamespacedFamily(
        @import("DaemonSetRecord.zig"),
        ResourceSubscription(klient.DaemonSet, @import("DaemonSetRecord.zig"), @import("DaemonSetRecord.zig").fromDaemonSet),
        configs.DaemonSetsView,
        2,
        "7",
    );
    try exerciseNamespacedFamily(
        @import("ReplicaSetRecord.zig"),
        ResourceSubscription(klient.ReplicaSet, @import("ReplicaSetRecord.zig"), @import("ReplicaSetRecord.zig").fromReplicaSet),
        configs.ReplicaSetsView,
        2,
        "7",
    );
}

test "batch family LIST WATCH supervisor queue populates tables across restart" {
    const configs = @import("../view/resource_configs.zig");
    try exerciseNamespacedFamily(
        @import("JobRecord.zig"),
        ResourceSubscription(klient.Job, @import("JobRecord.zig"), @import("JobRecord.zig").fromJob),
        configs.JobsView,
        2,
        "7/8",
    );
    try exerciseNamespacedFamily(
        @import("CronJobRecord.zig"),
        ResourceSubscription(klient.CronJob, @import("CronJobRecord.zig"), @import("CronJobRecord.zig").fromCronJob),
        configs.CronJobsView,
        4,
        "7",
    );
    try exerciseNamespacedFamily(
        @import("HPARecord.zig"),
        ResourceSubscription(klient.HorizontalPodAutoscaler, @import("HPARecord.zig"), @import("HPARecord.zig").fromHorizontalPodAutoscaler),
        configs.HPAView,
        4,
        "7",
    );
    try exerciseNamespacedFamily(
        @import("PDBRecord.zig"),
        ResourceSubscription(klient.PodDisruptionBudget, @import("PDBRecord.zig"), @import("PDBRecord.zig").fromPodDisruptionBudget),
        configs.PodDisruptionBudgetsView,
        4,
        "7",
    );
}

test "networking family LIST WATCH supervisor queue populates tables across restart" {
    const configs = @import("../view/resource_configs.zig");
    try exerciseNamespacedFamily(
        @import("IngressRecord.zig"),
        ResourceSubscription(klient.types.Ingress, @import("IngressRecord.zig"), @import("IngressRecord.zig").fromIngress),
        configs.IngressesView,
        3,
        "second-watch",
    );
    try exerciseNamespacedFamily(
        @import("IngressClassRecord.zig"),
        ResourceSubscription(klient.IngressClass, @import("IngressClassRecord.zig"), @import("IngressClassRecord.zig").fromIngressClass),
        configs.IngressClassesView,
        1,
        "second-watch",
    );
    try exerciseNamespacedFamily(
        @import("NetworkPolicyRecord.zig"),
        ResourceSubscription(klient.NetworkPolicy, @import("NetworkPolicyRecord.zig"), @import("NetworkPolicyRecord.zig").fromNetworkPolicy),
        configs.NetworkPoliciesView,
        2,
        "second-watch",
    );
    try exerciseNamespacedFamily(
        @import("IPAddressRecord.zig"),
        ResourceSubscription(klient.IPAddress, @import("IPAddressRecord.zig"), @import("IPAddressRecord.zig").fromIPAddress),
        configs.IPAddressesView,
        1,
        "second-watch",
    );
    try exerciseNamespacedFamily(
        @import("ServiceCIDRRecord.zig"),
        ResourceSubscription(klient.ServiceCIDR, @import("ServiceCIDRRecord.zig"), @import("ServiceCIDRRecord.zig").fromServiceCIDR),
        configs.ServiceCIDRsView,
        1,
        "second-watch",
    );
}

test "storage family LIST WATCH supervisor queue populates tables across restart" {
    const configs = @import("../view/resource_configs.zig");
    try exerciseNamespacedFamily(
        @import("PVRecord.zig"),
        ResourceSubscription(klient.PersistentVolume, @import("PVRecord.zig"), @import("PVRecord.zig").fromPersistentVolume),
        configs.PersistentVolumesView,
        4,
        "second-watch",
    );
    try exerciseNamespacedFamily(
        @import("PVCRecord.zig"),
        ResourceSubscription(klient.PersistentVolumeClaim, @import("PVCRecord.zig"), @import("PVCRecord.zig").fromPersistentVolumeClaim),
        configs.PersistentVolumeClaimsView,
        2,
        "second-watch",
    );
    try exerciseNamespacedFamily(
        @import("StorageClassRecord.zig"),
        ResourceSubscription(klient.StorageClass, @import("StorageClassRecord.zig"), @import("StorageClassRecord.zig").fromStorageClass),
        configs.StorageClassesView,
        1,
        "second-watch",
    );
    try exerciseNamespacedFamily(
        @import("VolumeAttributesClassRecord.zig"),
        ResourceSubscription(klient.VolumeAttributesClass, @import("VolumeAttributesClassRecord.zig"), @import("VolumeAttributesClassRecord.zig").fromVolumeAttributesClass),
        configs.VolumeAttributesClassesView,
        1,
        "second-watch",
    );
    try exerciseNamespacedFamily(
        @import("CSIDriverRecord.zig"),
        ResourceSubscription(klient.CSIDriver, @import("CSIDriverRecord.zig"), @import("CSIDriverRecord.zig").fromCSIDriver),
        configs.CSIDriversView,
        2,
        "true",
    );
}

test "Gateway API core LIST WATCH supervisor queue populates tables across restart" {
    const configs = @import("../view/resource_configs.zig");
    try exerciseNamespacedFamily(@import("GatewayClassRecord.zig"), ResourceSubscription(klient.GatewayClass, @import("GatewayClassRecord.zig"), @import("GatewayClassRecord.zig").fromGatewayClass), configs.GatewayClassesView, 1, "second-watch");
    try exerciseNamespacedFamily(@import("GatewayRecord.zig"), ResourceSubscription(klient.Gateway, @import("GatewayRecord.zig"), @import("GatewayRecord.zig").fromGateway), configs.GatewaysView, 3, "second-watch");
    try exerciseNamespacedFamily(@import("HTTPRouteRecord.zig"), ResourceSubscription(klient.HTTPRoute, @import("HTTPRouteRecord.zig"), @import("HTTPRouteRecord.zig").fromHTTPRoute), configs.HTTPRoutesView, 3, "second-watch");
    try exerciseNamespacedFamily(@import("GRPCRouteRecord.zig"), ResourceSubscription(klient.GRPCRoute, @import("GRPCRouteRecord.zig"), @import("GRPCRouteRecord.zig").fromGRPCRoute), configs.GRPCRoutesView, 3, "second-watch");
    try exerciseNamespacedFamily(@import("ReferenceGrantRecord.zig"), ResourceSubscription(klient.ReferenceGrant, @import("ReferenceGrantRecord.zig"), @import("ReferenceGrantRecord.zig").fromReferenceGrant), configs.ReferenceGrantsView, 2, "second-watch");
}

test "Gateway API extensions LIST WATCH supervisor queue populates tables across restart" {
    const configs = @import("../view/resource_configs.zig");
    try exerciseNamespacedFamily(@import("TCPRouteRecord.zig"), ResourceSubscription(klient.TCPRoute, @import("TCPRouteRecord.zig"), @import("TCPRouteRecord.zig").fromTCPRoute), configs.TCPRoutesView, 2, "second-watch");
    try exerciseNamespacedFamily(@import("TLSRouteRecord.zig"), ResourceSubscription(klient.TLSRoute, @import("TLSRouteRecord.zig"), @import("TLSRouteRecord.zig").fromTLSRoute), configs.TLSRoutesView, 3, "second-watch");
    try exerciseNamespacedFamily(@import("UDPRouteRecord.zig"), ResourceSubscription(klient.UDPRoute, @import("UDPRouteRecord.zig"), @import("UDPRouteRecord.zig").fromUDPRoute), configs.UDPRoutesView, 2, "second-watch");
    try exerciseNamespacedFamily(@import("BackendTLSPolicyRecord.zig"), ResourceSubscription(klient.BackendTLSPolicy, @import("BackendTLSPolicyRecord.zig"), @import("BackendTLSPolicyRecord.zig").fromBackendTLSPolicy), configs.BackendTLSPoliciesView, 2, "second-watch");
    try exerciseNamespacedFamily(@import("ListenerSetRecord.zig"), ResourceSubscription(klient.ListenerSet, @import("ListenerSetRecord.zig"), @import("ListenerSetRecord.zig").fromListenerSet), configs.ListenerSetsView, 3, "7");
}

test "RBAC family LIST WATCH supervisor queue populates tables across restart" {
    const configs = @import("../view/resource_configs.zig");
    try exerciseNamespacedFamily(@import("RoleRecord.zig").RoleRecord, ResourceSubscription(klient.Role, @import("RoleRecord.zig").RoleRecord, @import("RoleRecord.zig").fromRole), configs.RolesView, null, "");
    try exerciseNamespacedFamily(@import("RoleBindingRecord.zig").RoleBindingRecord, ResourceSubscription(klient.RoleBinding, @import("RoleBindingRecord.zig").RoleBindingRecord, @import("RoleBindingRecord.zig").fromRoleBinding), configs.RoleBindingsView, 2, "Role/second-watch");
    try exerciseNamespacedFamily(@import("ClusterRoleRecord.zig").ClusterRoleRecord, ResourceSubscription(klient.ClusterRole, @import("ClusterRoleRecord.zig").ClusterRoleRecord, @import("ClusterRoleRecord.zig").fromClusterRole), configs.ClusterRolesView, null, "");
    try exerciseNamespacedFamily(@import("ClusterRoleBindingRecord.zig").ClusterRoleBindingRecord, ResourceSubscription(klient.ClusterRoleBinding, @import("ClusterRoleBindingRecord.zig").ClusterRoleBindingRecord, @import("ClusterRoleBindingRecord.zig").fromClusterRoleBinding), configs.ClusterRoleBindingsView, 1, "ClusterRole/second-watch");
}

test "admission family LIST WATCH supervisor queue populates tables across restart" {
    const configs = @import("../view/resource_configs.zig");
    try exerciseNamespacedFamily(@import("ValidatingAdmissionPolicyRecord.zig").ValidatingAdmissionPolicyRecord, ResourceSubscription(klient.ValidatingAdmissionPolicy, @import("ValidatingAdmissionPolicyRecord.zig").ValidatingAdmissionPolicyRecord, @import("ValidatingAdmissionPolicyRecord.zig").fromValidatingAdmissionPolicy), configs.ValidatingAdmissionPoliciesView, 1, "second-watch");
    try exerciseNamespacedFamily(@import("ValidatingAdmissionPolicyBindingRecord.zig").ValidatingAdmissionPolicyBindingRecord, ResourceSubscription(klient.ValidatingAdmissionPolicyBinding, @import("ValidatingAdmissionPolicyBindingRecord.zig").ValidatingAdmissionPolicyBindingRecord, @import("ValidatingAdmissionPolicyBindingRecord.zig").fromValidatingAdmissionPolicyBinding), configs.ValidatingAdmissionPolicyBindingsView, 1, "second-watch");
    try exerciseNamespacedFamily(@import("MutatingAdmissionPolicyRecord.zig").MutatingAdmissionPolicyRecord, ResourceSubscription(klient.MutatingAdmissionPolicy, @import("MutatingAdmissionPolicyRecord.zig").MutatingAdmissionPolicyRecord, @import("MutatingAdmissionPolicyRecord.zig").fromMutatingAdmissionPolicy), configs.MutatingAdmissionPoliciesView, 2, "7");
    try exerciseNamespacedFamily(@import("MutatingAdmissionPolicyBindingRecord.zig").MutatingAdmissionPolicyBindingRecord, ResourceSubscription(klient.MutatingAdmissionPolicyBinding, @import("MutatingAdmissionPolicyBindingRecord.zig").MutatingAdmissionPolicyBindingRecord, @import("MutatingAdmissionPolicyBindingRecord.zig").fromMutatingAdmissionPolicyBinding), configs.MutatingAdmissionPolicyBindingsView, 1, "second-watch");
    try exerciseNamespacedFamily(@import("ValidatingWebhookConfigurationRecord.zig").ValidatingWebhookConfigurationRecord, ResourceSubscription(klient.ValidatingWebhookConfiguration, @import("ValidatingWebhookConfigurationRecord.zig").ValidatingWebhookConfigurationRecord, @import("ValidatingWebhookConfigurationRecord.zig").fromValidatingWebhookConfiguration), configs.ValidatingWebhookConfigurationsView, 1, "7");
    try exerciseNamespacedFamily(@import("MutatingWebhookConfigurationRecord.zig").MutatingWebhookConfigurationRecord, ResourceSubscription(klient.MutatingWebhookConfiguration, @import("MutatingWebhookConfigurationRecord.zig").MutatingWebhookConfigurationRecord, @import("MutatingWebhookConfigurationRecord.zig").fromMutatingWebhookConfiguration), configs.MutatingWebhookConfigurationsView, 1, "7");
}

test "DRA family LIST WATCH supervisor queue populates tables across restart" {
    const configs = @import("../view/resource_configs.zig");
    try exerciseNamespacedFamily(@import("ResourceClaimRecord.zig"), ResourceSubscription(klient.ResourceClaim, @import("ResourceClaimRecord.zig"), @import("ResourceClaimRecord.zig").fromResourceClaim), configs.ResourceClaimsView, 2, "second-watch");
    try exerciseNamespacedFamily(@import("DeviceClassRecord.zig"), ResourceSubscription(klient.DeviceClass, @import("DeviceClassRecord.zig"), @import("DeviceClassRecord.zig").fromDeviceClass), configs.DeviceClassesView, 1, "7");
}

test "platform family LIST WATCH supervisor queue populates tables across restart" {
    const configs = @import("../view/resource_configs.zig");
    try exerciseNamespacedFamily(@import("PriorityClassRecord.zig"), ResourceSubscription(klient.PriorityClass, @import("PriorityClassRecord.zig"), @import("PriorityClassRecord.zig").fromPriorityClass), configs.PriorityClassesView, 1, "7");
    try exerciseNamespacedFamily(@import("RuntimeClassRecord.zig"), ResourceSubscription(klient.RuntimeClass, @import("RuntimeClassRecord.zig"), @import("RuntimeClassRecord.zig").fromRuntimeClass), configs.RuntimeClassesView, 1, "second-watch");
    try exerciseNamespacedFamily(@import("LeaseRecord.zig"), ResourceSubscription(klient.Lease, @import("LeaseRecord.zig"), @import("LeaseRecord.zig").fromLease), configs.LeasesView, 2, "second-watch");
    try exerciseNamespacedFamily(@import("CSRRecord.zig"), ResourceSubscription(klient.CertificateSigningRequest, @import("CSRRecord.zig"), @import("CSRRecord.zig").fromCSR), configs.CertificateSigningRequestsView, 2, "Issued");
    try exerciseNamespacedFamily(@import("StorageVersionMigrationRecord.zig"), ResourceSubscription(klient.StorageVersionMigration, @import("StorageVersionMigrationRecord.zig"), @import("StorageVersionMigrationRecord.zig").fromStorageVersionMigration), configs.StorageVersionMigrationsView, 1, "second-watch");
    try exerciseNamespacedFamily(@import("EventRecord.zig"), ResourceSubscription(klient.Event, @import("EventRecord.zig"), @import("EventRecord.zig").fromEvent), configs.EventsView, 4, "second-watch");
}

pub fn runTask14FamilyStackGate() !void {
    const configs = @import("../view/resource_configs.zig");
    try exerciseNamespacedFamily(@import("ServiceRecord.zig"), ResourceSubscription(klient.Service, @import("ServiceRecord.zig"), @import("ServiceRecord.zig").fromService), configs.ServicesView, 2, "second-watch");
    try exerciseNamespacedFamily(@import("EndpointRecord.zig"), ResourceSubscription(klient.Endpoints, @import("EndpointRecord.zig"), @import("EndpointRecord.zig").fromEndpoints), configs.EndpointsView, 2, "second-watch");
    try exerciseNamespacedFamily(@import("EndpointSliceRecord.zig"), ResourceSubscription(klient.EndpointSlice, @import("EndpointSliceRecord.zig"), @import("EndpointSliceRecord.zig").fromEndpointSlice), configs.EndpointSlicesView, 3, "second-watch");
    try exerciseNamespacedFamily(@import("ConfigMapRecord.zig"), ResourceSubscription(klient.ConfigMap, @import("ConfigMapRecord.zig"), @import("ConfigMapRecord.zig").fromConfigMap), configs.ConfigMapsView, 2, "3");
    try exerciseNamespacedFamily(@import("SecretRecord.zig"), ResourceSubscription(klient.Secret, @import("SecretRecord.zig"), @import("SecretRecord.zig").fromSecret), configs.SecretsView, 2, "second-watch");
    try exerciseNamespacedFamily(@import("ServiceAccountRecord.zig"), ResourceSubscription(klient.ServiceAccount, @import("ServiceAccountRecord.zig"), @import("ServiceAccountRecord.zig").fromServiceAccount), configs.ServiceAccountsView, 2, "3");
    try exerciseNamespacedFamily(@import("ResourceQuotaRecord.zig"), ResourceSubscription(klient.ResourceQuota, @import("ResourceQuotaRecord.zig"), @import("ResourceQuotaRecord.zig").fromResourceQuota), configs.ResourceQuotasView, 2, "");
    try exerciseNamespacedFamily(@import("LimitRangeRecord.zig"), ResourceSubscription(klient.LimitRange, @import("LimitRangeRecord.zig"), @import("LimitRangeRecord.zig").fromLimitRange), configs.LimitRangesView, 2, "");
    try exerciseNamespacedFamily(@import("DeploymentRecord.zig"), ResourceSubscription(klient.Deployment, @import("DeploymentRecord.zig"), @import("DeploymentRecord.zig").fromDeployment), configs.DeploymentsView, 2, "7/8");
    try exerciseNamespacedFamily(@import("StatefulSetRecord.zig"), ResourceSubscription(klient.StatefulSet, @import("StatefulSetRecord.zig"), @import("StatefulSetRecord.zig").fromStatefulSet), configs.StatefulSetsView, 2, "7/8");
    try exerciseNamespacedFamily(@import("DaemonSetRecord.zig"), ResourceSubscription(klient.DaemonSet, @import("DaemonSetRecord.zig"), @import("DaemonSetRecord.zig").fromDaemonSet), configs.DaemonSetsView, 2, "7");
    try exerciseNamespacedFamily(@import("ReplicaSetRecord.zig"), ResourceSubscription(klient.ReplicaSet, @import("ReplicaSetRecord.zig"), @import("ReplicaSetRecord.zig").fromReplicaSet), configs.ReplicaSetsView, 2, "7");
    try exerciseNamespacedFamily(@import("JobRecord.zig"), ResourceSubscription(klient.Job, @import("JobRecord.zig"), @import("JobRecord.zig").fromJob), configs.JobsView, 2, "7/8");
    try exerciseNamespacedFamily(@import("CronJobRecord.zig"), ResourceSubscription(klient.CronJob, @import("CronJobRecord.zig"), @import("CronJobRecord.zig").fromCronJob), configs.CronJobsView, 4, "7");
    try exerciseNamespacedFamily(@import("HPARecord.zig"), ResourceSubscription(klient.HorizontalPodAutoscaler, @import("HPARecord.zig"), @import("HPARecord.zig").fromHorizontalPodAutoscaler), configs.HPAView, 4, "7");
    try exerciseNamespacedFamily(@import("PDBRecord.zig"), ResourceSubscription(klient.PodDisruptionBudget, @import("PDBRecord.zig"), @import("PDBRecord.zig").fromPodDisruptionBudget), configs.PodDisruptionBudgetsView, 4, "7");
    try exerciseNamespacedFamily(@import("IngressRecord.zig"), ResourceSubscription(klient.types.Ingress, @import("IngressRecord.zig"), @import("IngressRecord.zig").fromIngress), configs.IngressesView, 3, "second-watch");
    try exerciseNamespacedFamily(@import("IngressClassRecord.zig"), ResourceSubscription(klient.IngressClass, @import("IngressClassRecord.zig"), @import("IngressClassRecord.zig").fromIngressClass), configs.IngressClassesView, 1, "second-watch");
    try exerciseNamespacedFamily(@import("NetworkPolicyRecord.zig"), ResourceSubscription(klient.NetworkPolicy, @import("NetworkPolicyRecord.zig"), @import("NetworkPolicyRecord.zig").fromNetworkPolicy), configs.NetworkPoliciesView, 2, "second-watch");
    try exerciseNamespacedFamily(@import("IPAddressRecord.zig"), ResourceSubscription(klient.IPAddress, @import("IPAddressRecord.zig"), @import("IPAddressRecord.zig").fromIPAddress), configs.IPAddressesView, 1, "second-watch");
    try exerciseNamespacedFamily(@import("ServiceCIDRRecord.zig"), ResourceSubscription(klient.ServiceCIDR, @import("ServiceCIDRRecord.zig"), @import("ServiceCIDRRecord.zig").fromServiceCIDR), configs.ServiceCIDRsView, 1, "second-watch");
    try exerciseNamespacedFamily(@import("PVRecord.zig"), ResourceSubscription(klient.PersistentVolume, @import("PVRecord.zig"), @import("PVRecord.zig").fromPersistentVolume), configs.PersistentVolumesView, 4, "second-watch");
    try exerciseNamespacedFamily(@import("PVCRecord.zig"), ResourceSubscription(klient.PersistentVolumeClaim, @import("PVCRecord.zig"), @import("PVCRecord.zig").fromPersistentVolumeClaim), configs.PersistentVolumeClaimsView, 2, "second-watch");
    try exerciseNamespacedFamily(@import("StorageClassRecord.zig"), ResourceSubscription(klient.StorageClass, @import("StorageClassRecord.zig"), @import("StorageClassRecord.zig").fromStorageClass), configs.StorageClassesView, 1, "second-watch");
    try exerciseNamespacedFamily(@import("VolumeAttributesClassRecord.zig"), ResourceSubscription(klient.VolumeAttributesClass, @import("VolumeAttributesClassRecord.zig"), @import("VolumeAttributesClassRecord.zig").fromVolumeAttributesClass), configs.VolumeAttributesClassesView, 1, "second-watch");
    try exerciseNamespacedFamily(@import("CSIDriverRecord.zig"), ResourceSubscription(klient.CSIDriver, @import("CSIDriverRecord.zig"), @import("CSIDriverRecord.zig").fromCSIDriver), configs.CSIDriversView, 2, "true");
    try exerciseNamespacedFamily(@import("GatewayClassRecord.zig"), ResourceSubscription(klient.GatewayClass, @import("GatewayClassRecord.zig"), @import("GatewayClassRecord.zig").fromGatewayClass), configs.GatewayClassesView, 1, "second-watch");
    try exerciseNamespacedFamily(@import("GatewayRecord.zig"), ResourceSubscription(klient.Gateway, @import("GatewayRecord.zig"), @import("GatewayRecord.zig").fromGateway), configs.GatewaysView, 3, "second-watch");
    try exerciseNamespacedFamily(@import("HTTPRouteRecord.zig"), ResourceSubscription(klient.HTTPRoute, @import("HTTPRouteRecord.zig"), @import("HTTPRouteRecord.zig").fromHTTPRoute), configs.HTTPRoutesView, 3, "second-watch");
    try exerciseNamespacedFamily(@import("GRPCRouteRecord.zig"), ResourceSubscription(klient.GRPCRoute, @import("GRPCRouteRecord.zig"), @import("GRPCRouteRecord.zig").fromGRPCRoute), configs.GRPCRoutesView, 3, "second-watch");
    try exerciseNamespacedFamily(@import("ReferenceGrantRecord.zig"), ResourceSubscription(klient.ReferenceGrant, @import("ReferenceGrantRecord.zig"), @import("ReferenceGrantRecord.zig").fromReferenceGrant), configs.ReferenceGrantsView, 2, "second-watch");
    try exerciseNamespacedFamily(@import("TCPRouteRecord.zig"), ResourceSubscription(klient.TCPRoute, @import("TCPRouteRecord.zig"), @import("TCPRouteRecord.zig").fromTCPRoute), configs.TCPRoutesView, 2, "second-watch");
    try exerciseNamespacedFamily(@import("TLSRouteRecord.zig"), ResourceSubscription(klient.TLSRoute, @import("TLSRouteRecord.zig"), @import("TLSRouteRecord.zig").fromTLSRoute), configs.TLSRoutesView, 3, "second-watch");
    try exerciseNamespacedFamily(@import("UDPRouteRecord.zig"), ResourceSubscription(klient.UDPRoute, @import("UDPRouteRecord.zig"), @import("UDPRouteRecord.zig").fromUDPRoute), configs.UDPRoutesView, 2, "second-watch");
    try exerciseNamespacedFamily(@import("BackendTLSPolicyRecord.zig"), ResourceSubscription(klient.BackendTLSPolicy, @import("BackendTLSPolicyRecord.zig"), @import("BackendTLSPolicyRecord.zig").fromBackendTLSPolicy), configs.BackendTLSPoliciesView, 2, "second-watch");
    try exerciseNamespacedFamily(@import("ListenerSetRecord.zig"), ResourceSubscription(klient.ListenerSet, @import("ListenerSetRecord.zig"), @import("ListenerSetRecord.zig").fromListenerSet), configs.ListenerSetsView, 3, "7");
    try exerciseNamespacedFamily(@import("RoleRecord.zig").RoleRecord, ResourceSubscription(klient.Role, @import("RoleRecord.zig").RoleRecord, @import("RoleRecord.zig").fromRole), configs.RolesView, null, "");
    try exerciseNamespacedFamily(@import("RoleBindingRecord.zig").RoleBindingRecord, ResourceSubscription(klient.RoleBinding, @import("RoleBindingRecord.zig").RoleBindingRecord, @import("RoleBindingRecord.zig").fromRoleBinding), configs.RoleBindingsView, 2, "Role/second-watch");
    try exerciseNamespacedFamily(@import("ClusterRoleRecord.zig").ClusterRoleRecord, ResourceSubscription(klient.ClusterRole, @import("ClusterRoleRecord.zig").ClusterRoleRecord, @import("ClusterRoleRecord.zig").fromClusterRole), configs.ClusterRolesView, null, "");
    try exerciseNamespacedFamily(@import("ClusterRoleBindingRecord.zig").ClusterRoleBindingRecord, ResourceSubscription(klient.ClusterRoleBinding, @import("ClusterRoleBindingRecord.zig").ClusterRoleBindingRecord, @import("ClusterRoleBindingRecord.zig").fromClusterRoleBinding), configs.ClusterRoleBindingsView, 1, "ClusterRole/second-watch");
    try exerciseNamespacedFamily(@import("ValidatingAdmissionPolicyRecord.zig").ValidatingAdmissionPolicyRecord, ResourceSubscription(klient.ValidatingAdmissionPolicy, @import("ValidatingAdmissionPolicyRecord.zig").ValidatingAdmissionPolicyRecord, @import("ValidatingAdmissionPolicyRecord.zig").fromValidatingAdmissionPolicy), configs.ValidatingAdmissionPoliciesView, 1, "second-watch");
    try exerciseNamespacedFamily(@import("ValidatingAdmissionPolicyBindingRecord.zig").ValidatingAdmissionPolicyBindingRecord, ResourceSubscription(klient.ValidatingAdmissionPolicyBinding, @import("ValidatingAdmissionPolicyBindingRecord.zig").ValidatingAdmissionPolicyBindingRecord, @import("ValidatingAdmissionPolicyBindingRecord.zig").fromValidatingAdmissionPolicyBinding), configs.ValidatingAdmissionPolicyBindingsView, 1, "second-watch");
    try exerciseNamespacedFamily(@import("MutatingAdmissionPolicyRecord.zig").MutatingAdmissionPolicyRecord, ResourceSubscription(klient.MutatingAdmissionPolicy, @import("MutatingAdmissionPolicyRecord.zig").MutatingAdmissionPolicyRecord, @import("MutatingAdmissionPolicyRecord.zig").fromMutatingAdmissionPolicy), configs.MutatingAdmissionPoliciesView, 2, "7");
    try exerciseNamespacedFamily(@import("MutatingAdmissionPolicyBindingRecord.zig").MutatingAdmissionPolicyBindingRecord, ResourceSubscription(klient.MutatingAdmissionPolicyBinding, @import("MutatingAdmissionPolicyBindingRecord.zig").MutatingAdmissionPolicyBindingRecord, @import("MutatingAdmissionPolicyBindingRecord.zig").fromMutatingAdmissionPolicyBinding), configs.MutatingAdmissionPolicyBindingsView, 1, "second-watch");
    try exerciseNamespacedFamily(@import("ValidatingWebhookConfigurationRecord.zig").ValidatingWebhookConfigurationRecord, ResourceSubscription(klient.ValidatingWebhookConfiguration, @import("ValidatingWebhookConfigurationRecord.zig").ValidatingWebhookConfigurationRecord, @import("ValidatingWebhookConfigurationRecord.zig").fromValidatingWebhookConfiguration), configs.ValidatingWebhookConfigurationsView, 1, "7");
    try exerciseNamespacedFamily(@import("MutatingWebhookConfigurationRecord.zig").MutatingWebhookConfigurationRecord, ResourceSubscription(klient.MutatingWebhookConfiguration, @import("MutatingWebhookConfigurationRecord.zig").MutatingWebhookConfigurationRecord, @import("MutatingWebhookConfigurationRecord.zig").fromMutatingWebhookConfiguration), configs.MutatingWebhookConfigurationsView, 1, "7");
    try exerciseNamespacedFamily(@import("ResourceClaimRecord.zig"), ResourceSubscription(klient.ResourceClaim, @import("ResourceClaimRecord.zig"), @import("ResourceClaimRecord.zig").fromResourceClaim), configs.ResourceClaimsView, 2, "second-watch");
    try exerciseNamespacedFamily(@import("DeviceClassRecord.zig"), ResourceSubscription(klient.DeviceClass, @import("DeviceClassRecord.zig"), @import("DeviceClassRecord.zig").fromDeviceClass), configs.DeviceClassesView, 1, "7");
    try exerciseNamespacedFamily(@import("PriorityClassRecord.zig"), ResourceSubscription(klient.PriorityClass, @import("PriorityClassRecord.zig"), @import("PriorityClassRecord.zig").fromPriorityClass), configs.PriorityClassesView, 1, "7");
    try exerciseNamespacedFamily(@import("RuntimeClassRecord.zig"), ResourceSubscription(klient.RuntimeClass, @import("RuntimeClassRecord.zig"), @import("RuntimeClassRecord.zig").fromRuntimeClass), configs.RuntimeClassesView, 1, "second-watch");
    try exerciseNamespacedFamily(@import("LeaseRecord.zig"), ResourceSubscription(klient.Lease, @import("LeaseRecord.zig"), @import("LeaseRecord.zig").fromLease), configs.LeasesView, 2, "second-watch");
    try exerciseNamespacedFamily(@import("CSRRecord.zig"), ResourceSubscription(klient.CertificateSigningRequest, @import("CSRRecord.zig"), @import("CSRRecord.zig").fromCSR), configs.CertificateSigningRequestsView, 2, "Issued");
    try exerciseNamespacedFamily(@import("StorageVersionMigrationRecord.zig"), ResourceSubscription(klient.StorageVersionMigration, @import("StorageVersionMigrationRecord.zig"), @import("StorageVersionMigrationRecord.zig").fromStorageVersionMigration), configs.StorageVersionMigrationsView, 1, "second-watch");
    try exerciseNamespacedFamily(@import("EventRecord.zig"), ResourceSubscription(klient.Event, @import("EventRecord.zig"), @import("EventRecord.zig").fromEvent), configs.EventsView, 4, "second-watch");
}

pub fn runTask14DeferredDisplayGate() !void {
    const configs = @import("../view/resource_configs.zig");
    try exerciseNamespacedFamily(@import("ResourceQuotaRecord.zig"), ResourceSubscription(klient.ResourceQuota, @import("ResourceQuotaRecord.zig"), @import("ResourceQuotaRecord.zig").fromResourceQuota), configs.ResourceQuotasView, 2, "");
    try exerciseNamespacedFamily(@import("LimitRangeRecord.zig"), ResourceSubscription(klient.LimitRange, @import("LimitRangeRecord.zig"), @import("LimitRangeRecord.zig").fromLimitRange), configs.LimitRangesView, 2, "");
}

pub fn runTask14PdbHeaderSortGate() !void {
    const Record = @import("PDBRecord.zig");
    const Projection = projection_mod.ResourceProjection(Record);
    const ViewType = @import("../view/resource_configs.zig").PodDisruptionBudgetsView;
    const K8sService = @import("../services/K8sService.zig").K8sService;
    const Theme = @import("../model/theme_loader.zig").ThemeColors;
    const Fns = struct {
        fn match(_: *const Record, _: []const u8) bool {
            return true;
        }
        fn sort(record: *const Record, column: u8) []const u8 {
            return switch (column) {
                0 => record.key.namespace,
                1 => record.key.name,
                2 => &record.min_available_sort_key,
                3 => &record.max_unavailable_sort_key,
                4 => &record.allowed_sort_key,
                5 => record.creation_timestamp orelse "",
                else => record.key.name,
            };
        }
        fn columns(_: *Projection, record: *const Record, allocator: std.mem.Allocator) ![6][]const u8 {
            return record.columns(allocator);
        }
    };
    var projection = Projection.init(std.testing.allocator, .{
        .matchFn = Fns.match,
        .sortKeyFn = Fns.sort,
    });
    defer projection.deinit();
    var service = try K8sService.init(std.testing.allocator);
    defer service.deinit();
    var theme: Theme = undefined;
    var view = try ViewType.init(std.testing.allocator, &theme, &service);
    defer view.deinit();
    view.bindProjection(ViewType.ProjectionAdapter.init(Record, &projection, Fns.columns));

    const values = [_][]const u8{ "10%", "10", "2" };
    const uids = [_][]const u8{ "pdb-percent", "pdb-ten", "pdb-two" };
    const changes = try std.testing.allocator.alloc(keys.TypedChange(Record), values.len);
    for (changes, values, 0..) |*change, value, index| {
        const key = try (keys.ObjectKey{
            .uid = uids[index],
            .namespace = "default",
            .name = value,
        }).clone(std.testing.allocator);
        change.* = .{ .initial_upsert = .{
            .key = key,
            .min_available = try std.testing.allocator.dupe(u8, value),
            .max_unavailable = try std.testing.allocator.dupe(u8, value),
            .min_available_sort_key = Record.intOrStringSortKey(value),
            .max_unavailable_sort_key = Record.intOrStringSortKey(value),
            .allowed_disruptions = @intCast(index),
            .allowed_sort_key = Record.countSortKey(@intCast(index)),
        } };
    }
    var batch = keys.TypedBatch(Record){
        .generation = 1,
        .subscription_id = 1,
        .revision = 1,
        .changes = changes,
        .sync = null,
        .owned_bytes = 1,
    };
    defer batch.deinit(std.testing.allocator);
    var plan = try Projection.handler().preflight(@ptrCast(&projection), &batch, std.testing.allocator);
    Projection.handler().commit(@ptrCast(&projection), &batch, &plan);
    plan.deinit(std.testing.allocator);

    view.table.toggleSort(2);
    if (!view.table.sort_ascending) view.table.toggleSort(2);
    try view.applyFilter("");
    var two_index: ?usize = null;
    var ten_index: ?usize = null;
    var percent_index: ?usize = null;
    for (view.table.items.items, 0..) |row, index| {
        if (std.mem.eql(u8, row.columns[2], "2")) two_index = index;
        if (std.mem.eql(u8, row.columns[2], "10")) ten_index = index;
        if (std.mem.eql(u8, row.columns[2], "10%")) percent_index = index;
    }
    try std.testing.expect(two_index.? < ten_index.?);
    try std.testing.expect(percent_index.? != ten_index.?);
}
