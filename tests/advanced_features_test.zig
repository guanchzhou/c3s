const std = @import("std");
const src = @import("src");
const tls = src.k8s_tls;
const crd = src.k8s_crd;
// Note: ConnectionPool tests removed — the pool was deleted in zig-klient
// v0.3.0 (std.http.Client pools internally).

test "TLS Config - Basic structure" {
    const config = tls.TlsConfig{
        .client_cert_path = "/path/to/cert.pem",
        .client_key_path = "/path/to/key.pem",
        .ca_cert_path = "/path/to/ca.pem",
        .insecure_skip_verify = false,
    };

    try std.testing.expectEqualStrings("/path/to/cert.pem", config.client_cert_path.?);
    try std.testing.expectEqualStrings("/path/to/key.pem", config.client_key_path.?);
    try std.testing.expectEqualStrings("/path/to/ca.pem", config.ca_cert_path.?);
    try std.testing.expect(!config.insecure_skip_verify);

    std.debug.print("✅ TLS Config structure test passed\n", .{});
}

// The "TLS - PEM validation" test was removed here: it exercised
// klient.tls.validateCertKeyPair, which zig-klient deleted in 0.4.0 when the
// mTLS-only TLS helpers were dropped (tls.zig went 201 -> 80 lines). A test for a
// function that no longer exists cannot be repaired, only deleted. klient's tls
// surface is now addCaCertData + decodeBase64Cert; the latter is covered by the
// Base64 test below.

test "TLS - Base64 decoding" {
    const allocator = std.testing.allocator;

    const base64_data = "SGVsbG8gV29ybGQh"; // "Hello World!"
    const decoded = try tls.decodeBase64Cert(allocator, base64_data);
    defer allocator.free(decoded);

    try std.testing.expectEqualStrings("Hello World!", decoded);

    std.debug.print("✅ TLS Base64 decoding test passed\n", .{});
}

test "CRD - API path construction" {
    const allocator = std.testing.allocator;

    // Core API (no group)
    const core_crd = crd.CRDInfo{
        .group = "",
        .version = "v1",
        .kind = "MyResource",
        .plural = "myresources",
    };

    const core_path = try core_crd.apiPath(allocator);
    defer allocator.free(core_path);
    try std.testing.expectEqualStrings("/api/v1", core_path);

    // Custom API group
    const custom_crd = crd.CRDInfo{
        .group = "example.com",
        .version = "v1alpha1",
        .kind = "CustomResource",
        .plural = "customresources",
    };

    const custom_path = try custom_crd.apiPath(allocator);
    defer allocator.free(custom_path);
    try std.testing.expectEqualStrings("/apis/example.com/v1alpha1", custom_path);

    std.debug.print("✅ CRD API path construction test passed\n", .{});
}

test "CRD - Resource path construction" {
    const allocator = std.testing.allocator;

    const namespaced_crd = crd.CRDInfo{
        .group = "cert-manager.io",
        .version = "v1",
        .kind = "Certificate",
        .plural = "certificates",
        .namespaced = true,
    };

    // List path (namespaced)
    const list_path = try namespaced_crd.resourcePath(allocator, "production", null);
    defer allocator.free(list_path);
    try std.testing.expectEqualStrings("/apis/cert-manager.io/v1/namespaces/production/certificates", list_path);

    // Get path (namespaced)
    const get_path = try namespaced_crd.resourcePath(allocator, "production", "my-cert");
    defer allocator.free(get_path);
    try std.testing.expectEqualStrings("/apis/cert-manager.io/v1/namespaces/production/certificates/my-cert", get_path);

    // Cluster-scoped CRD
    const cluster_crd = crd.CRDInfo{
        .group = "custom.io",
        .version = "v1",
        .kind = "ClusterResource",
        .plural = "clusterresources",
        .namespaced = false,
    };

    const cluster_list_path = try cluster_crd.resourcePath(allocator, null, null);
    defer allocator.free(cluster_list_path);
    try std.testing.expectEqualStrings("/apis/custom.io/v1/clusterresources", cluster_list_path);

    const cluster_get_path = try cluster_crd.resourcePath(allocator, null, "my-resource");
    defer allocator.free(cluster_get_path);
    try std.testing.expectEqualStrings("/apis/custom.io/v1/clusterresources/my-resource", cluster_get_path);

    std.debug.print("✅ CRD resource path construction test passed\n", .{});
}

test "CRD - Predefined CRDs" {
    const allocator = std.testing.allocator;

    // Test Cert-Manager Certificate
    const cert_path = try crd.CertManagerCertificate.apiPath(allocator);
    defer allocator.free(cert_path);
    try std.testing.expectEqualStrings("/apis/cert-manager.io/v1", cert_path);
    try std.testing.expectEqualStrings("Certificate", crd.CertManagerCertificate.kind);

    // Test Istio VirtualService
    const istio_path = try crd.IstioVirtualService.apiPath(allocator);
    defer allocator.free(istio_path);
    try std.testing.expectEqualStrings("/apis/networking.istio.io/v1beta1", istio_path);
    try std.testing.expectEqualStrings("VirtualService", crd.IstioVirtualService.kind);

    // Test Prometheus ServiceMonitor
    const prom_path = try crd.PrometheusServiceMonitor.apiPath(allocator);
    defer allocator.free(prom_path);
    try std.testing.expectEqualStrings("/apis/monitoring.coreos.com/v1", prom_path);
    try std.testing.expectEqualStrings("ServiceMonitor", crd.PrometheusServiceMonitor.kind);

    std.debug.print("✅ Predefined CRDs test passed\n", .{});
}

test "CRD - Argo and Knative" {
    // Test Argo Rollout
    try std.testing.expectEqualStrings("argoproj.io", crd.ArgoRollout.group);
    try std.testing.expectEqualStrings("v1alpha1", crd.ArgoRollout.version);
    try std.testing.expectEqualStrings("rollouts", crd.ArgoRollout.plural);

    // Test Knative Service
    try std.testing.expectEqualStrings("serving.knative.dev", crd.KnativeService.group);
    try std.testing.expectEqualStrings("v1", crd.KnativeService.version);
    try std.testing.expectEqualStrings("services", crd.KnativeService.plural);

    std.debug.print("✅ Argo and Knative CRDs test passed\n", .{});
}
