const std = @import("std");

/// Subsequence fuzzy score. Returns null if `query` is not a subsequence of
/// `candidate` (case-insensitive). Higher score = better match.
/// Heuristics: +contiguous runs, +match at start, +match after separator,
/// -gaps, prefer shorter candidates.
pub fn score(query: []const u8, candidate: []const u8) ?i32 {
    if (query.len == 0) return 0;
    var s: i32 = 0;
    var qi: usize = 0;
    var prev_match: ?usize = null;
    var ci: usize = 0;
    while (ci < candidate.len and qi < query.len) : (ci += 1) {
        const qc = std.ascii.toLower(query[qi]);
        const cc = std.ascii.toLower(candidate[ci]);
        if (qc == cc) {
            s += 10;
            if (ci == 0) s += 15; // start of string
            if (ci > 0 and (candidate[ci - 1] == '-' or candidate[ci - 1] == '/' or candidate[ci - 1] == '_')) s += 10; // after sep
            if (prev_match) |pm| {
                if (ci == pm + 1) {
                    s += 8; // contiguous
                } else {
                    const gap: i32 = @intCast(@min(@as(usize, 5), ci - pm - 1));
                    s -= gap; // gap penalty
                }
            }
            prev_match = ci;
            qi += 1;
        }
    }
    if (qi < query.len) return null; // not all query chars matched
    const shorter_bonus: i32 = @intCast(@min(@as(usize, 20), candidate.len));
    s -= shorter_bonus; // prefer shorter candidates
    return s;
}

const Scored = struct { idx: usize, score: i32 };

/// Rank `candidates` against `query`, writing the best up-to-`out.len` indices
/// into `out`. Returns the number written. Matches sorted by score desc, then
/// candidate length asc, then lexicographic for stability.
pub fn rank(query: []const u8, candidates: []const []const u8, out: []usize) usize {
    var scored: [512]Scored = undefined;
    var n: usize = 0;
    for (candidates, 0..) |c, i| {
        if (n >= scored.len) break;
        if (score(query, c)) |sc| {
            scored[n] = .{ .idx = i, .score = sc };
            n += 1;
        }
    }
    std.mem.sort(Scored, scored[0..n], candidates, struct {
        fn lt(cands: []const []const u8, a: Scored, b: Scored) bool {
            if (a.score != b.score) return a.score > b.score;
            if (cands[a.idx].len != cands[b.idx].len) return cands[a.idx].len < cands[b.idx].len;
            return std.mem.lessThan(u8, cands[a.idx], cands[b.idx]);
        }
    }.lt);
    const take = @min(n, out.len);
    for (0..take) |i| out[i] = scored[i].idx;
    return take;
}

test "fuzzy basic" {
    try std.testing.expect(score("dep", "deployments") != null);
    try std.testing.expect(score("xyz", "deployments") == null);
    // "dep" scores higher than "dp" because it has a contiguous prefix run
    // (dep matches d-e-p at positions 0-1-2)
    const score_dep = score("dep", "deployments").?;
    const score_dp = score("dp", "deployments").?;
    // Both match; "dep" has the better (higher) score
    try std.testing.expect(score_dep >= score_dp);
}

test "fuzzy rank empty query" {
    const candidates = [_][]const u8{ "pods", "deployments", "services" };
    var out: [3]usize = undefined;
    const n = rank("", &candidates, &out);
    try std.testing.expectEqual(@as(usize, 3), n);
}

test "fuzzy rank no match" {
    const candidates = [_][]const u8{ "pods", "deployments" };
    var out: [2]usize = undefined;
    const n = rank("xyz", &candidates, &out);
    try std.testing.expectEqual(@as(usize, 0), n);
}

test "fuzzy rank prefix wins" {
    // "d" is a subsequence of all three ("pods" has a 'd' at index 2)
    // so all three match; deployments and daemonsets should outscore pods
    // (they start with 'd', earning the start-of-string bonus).
    const candidates = [_][]const u8{ "deployments", "pods", "daemonsets" };
    var out: [3]usize = undefined;
    const n = rank("d", &candidates, &out);
    try std.testing.expectEqual(@as(usize, 3), n);
    // First result must be deployments or daemonsets (not pods), since pods
    // has no start-of-string bonus for 'd'.
    try std.testing.expect(out[0] == 0 or out[0] == 2); // deployments or daemonsets
}
