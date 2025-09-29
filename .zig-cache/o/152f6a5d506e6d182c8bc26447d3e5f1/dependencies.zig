pub const packages = struct {
    pub const @"vaxis-0.5.1-BWNV_BMgCQDXdZzABeY4F_xwgE7nHFtYEP07KgEwJWo8" = struct {
        pub const build_root = "/Users/andreymaltsev/.cache/zig/p/vaxis-0.5.1-BWNV_BMgCQDXdZzABeY4F_xwgE7nHFtYEP07KgEwJWo8";
        pub const build_zig = @import("vaxis-0.5.1-BWNV_BMgCQDXdZzABeY4F_xwgE7nHFtYEP07KgEwJWo8");
        pub const deps: []const struct { []const u8, []const u8 } = &.{
            .{ "zigimg", "zigimg-0.1.0-8_eo2vHnEwCIVW34Q14Ec-xUlzIoVg86-7FU2ypPtxms" },
            .{ "zg", "zg-0.15.1-oGqU3M0-tALZCy7boQS86znlBloyKx6--JriGlY0Paa9" },
        };
    };
    pub const @"zg-0.15.1-oGqU3M0-tALZCy7boQS86znlBloyKx6--JriGlY0Paa9" = struct {
        pub const build_root = "/Users/andreymaltsev/.cache/zig/p/zg-0.15.1-oGqU3M0-tALZCy7boQS86znlBloyKx6--JriGlY0Paa9";
        pub const build_zig = @import("zg-0.15.1-oGqU3M0-tALZCy7boQS86znlBloyKx6--JriGlY0Paa9");
        pub const deps: []const struct { []const u8, []const u8 } = &.{
        };
    };
    pub const @"zigimg-0.1.0-8_eo2vHnEwCIVW34Q14Ec-xUlzIoVg86-7FU2ypPtxms" = struct {
        pub const build_root = "/Users/andreymaltsev/.cache/zig/p/zigimg-0.1.0-8_eo2vHnEwCIVW34Q14Ec-xUlzIoVg86-7FU2ypPtxms";
        pub const build_zig = @import("zigimg-0.1.0-8_eo2vHnEwCIVW34Q14Ec-xUlzIoVg86-7FU2ypPtxms");
        pub const deps: []const struct { []const u8, []const u8 } = &.{
        };
    };
};

pub const root_deps: []const struct { []const u8, []const u8 } = &.{
    .{ "vaxis", "vaxis-0.5.1-BWNV_BMgCQDXdZzABeY4F_xwgE7nHFtYEP07KgEwJWo8" },
};
