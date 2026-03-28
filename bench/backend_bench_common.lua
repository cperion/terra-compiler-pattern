local M = {}

local ffi = require("ffi")

ffi.cdef [[
    typedef long time_t;
    typedef struct timespec {
        time_t tv_sec;
        long tv_nsec;
    } timespec;
    int clock_gettime(int clk_id, struct timespec *tp);
]]

local CLOCK_MONOTONIC = 1
local ts = ffi.new("struct timespec[1]")

function M.now_ns()
    assert(ffi.C.clock_gettime(CLOCK_MONOTONIC, ts) == 0)
    return tonumber(ts[0].tv_sec) * 1000000000 + tonumber(ts[0].tv_nsec)
end

function M.getenv_number(name, default)
    local raw = os.getenv(name)
    if raw == nil or raw == "" then return default end
    local n = tonumber(raw)
    return n or default
end

function M.compute_lowpass_coeffs(freq, q, sr)
    local omega = 2.0 * math.pi * freq / sr
    local cosw = math.cos(omega)
    local alpha = math.sin(omega) / (2.0 * q)

    local b0 = (1.0 - cosw) * 0.5
    local b1 = 1.0 - cosw
    local b2 = (1.0 - cosw) * 0.5
    local a0 = 1.0 + alpha
    local a1 = -2.0 * cosw
    local a2 = 1.0 - alpha

    return b0 / a0, b1 / a0, b2 / a0, a1 / a0, a2 / a0
end

function M.fill_source(buf, n)
    for i = 0, n - 1 do
        local x = 0.6 * math.sin(i * 0.011)
            + 0.3 * math.sin(i * 0.071)
            + 0.1 * ((i % 17) - 8)
        buf[i] = x
    end
end

function M.print_metrics(metrics)
    local keys = {}
    for k, _ in pairs(metrics) do
        keys[#keys + 1] = k
    end
    table.sort(keys)

    for _, k in ipairs(keys) do
        io.write(string.format("METRIC %s %s\n", k, tostring(metrics[k])))
    end
end

function M.parse_metrics(path)
    local out = {}
    local f = assert(io.open(path, "rb"))
    for line in f:lines() do
        local k, v = line:match("^METRIC%s+(%S+)%s+(.+)$")
        if k then
            local n = tonumber(v)
            out[k] = n or v
        end
    end
    f:close()
    return out
end

function M.fmt_ns_per_sample(v)
    return string.format("%.3f ns/sample", v)
end

function M.fmt_us(v)
    return string.format("%.3f us", v / 1000.0)
end

return M
