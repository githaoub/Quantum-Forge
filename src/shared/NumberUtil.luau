--!strict
-- Number formatting and safe arithmetic for an incremental economy.
--
-- Design note: this deliberately does NOT implement a mantissa/exponent BigNum
-- struct. IEEE doubles are exact to 2^53 (~9e15) and stay finite to 1.8e308,
-- which covers every value this game can reach. A custom struct would add an
-- allocation per operation across the hot click path for no reachable gain.
-- Above the suffix table we fall back to scientific notation.

local NumberUtil = {}

-- Grouped in threes so the index is math.floor(log10(v) / 3).
local SUFFIXES = {
	"",
	"K",
	"M",
	"B",
	"T",
	"Qa",
	"Qi",
	"Sx",
	"Sp",
	"Oc",
	"No",
	"Dc",
	"Ud",
	"Dd",
	"Td",
	"Qad",
	"Qid",
	"Sxd",
	"Spd",
	"Ocd",
	"Nod",
	"Vg",
	"Uvg",
	"Dvg",
	"Tvg",
	"Qavg",
	"Qivg",
	"Sxvg",
	"Spvg",
	"Ocvg",
	"Novg",
	"Tg",
}

local THOUSAND = 1000

--- Clamps a value into a sane finite range. Guards against NaN leaking in from
--- corrupted saves.
function NumberUtil.sanitize(value: number): number
	if value ~= value then
		return 0 -- NaN
	end
	if value == math.huge then
		return 1e308
	end
	if value == -math.huge then
		return -1e308
	end
	return value
end

--- Compact human-readable form: 1234 -> "1.23K", 5.6e9 -> "5.60B".
function NumberUtil.abbreviate(value: number): string
	value = NumberUtil.sanitize(value)

	if value < 0 then
		return "-" .. NumberUtil.abbreviate(-value)
	end
	if value < THOUSAND then
		if value >= 100 then
			return string.format("%d", math.floor(value))
		elseif value >= 10 then
			if value % 1 == 0 then
				return string.format("%d", value)
			end
			return string.format("%.1f", value)
		elseif value >= 1 then
			if value % 1 == 0 then
				return string.format("%d", value)
			end
			return string.format("%.2f", value)
		elseif value == 0 then
			return "0"
		end
		return string.format("%.2f", value)
	end

	local tierIndex = math.floor(math.log10(value) / 3)
	if tierIndex >= #SUFFIXES then
		return string.format("%.3e", value)
	end

	local scaled = value / (THOUSAND ^ tierIndex)

	-- float error can push 999_999 into "1000.00K"; nudge it up a tier instead.
	if scaled >= THOUSAND and tierIndex + 1 < #SUFFIXES then
		tierIndex += 1
		scaled /= THOUSAND
	end

	return string.format("%.2f%s", scaled, SUFFIXES[tierIndex + 1])
end

--- "1.24K/s" style. Used on HUD counters.
function NumberUtil.abbreviateRate(value: number): string
	return NumberUtil.abbreviate(value) .. "/s"
end

--- Abbreviated without the forced decimals when they are zero: 10000 -> "10K",
--- 1500 -> "1.5K", 1240 -> "1.24K". Live counters keep the two decimals so a
--- rising number does not jitter in width; a headline or a price reads better
--- with the trailing zeros gone.
function NumberUtil.compact(value: number): string
	local text = NumberUtil.abbreviate(value)
	local number, suffix = string.match(text, "^([%d%.%-]+)(.*)$")
	if number == nil then
		return text
	end
	if string.find(number, ".", 1, true) then
		number = string.gsub(number, "0+$", "")
		number = string.gsub(number, "%.$", "")
	end
	return number .. suffix
end

--- 3725 -> "1h 2m". For offline modal and playtime rewards.
function NumberUtil.abbreviateTime(totalSeconds: number): string
	local seconds = math.max(0, math.floor(totalSeconds))
	local days = math.floor(seconds / 86400)
	local hours = math.floor((seconds % 86400) / 3600)
	local minutes = math.floor((seconds % 3600) / 60)

	if days > 0 then
		return string.format("%dd %dh", days, hours)
	elseif hours > 0 then
		return string.format("%dh %dm", hours, minutes)
	elseif minutes > 0 then
		return string.format("%dm %ds", minutes, seconds % 60)
	end
	return string.format("%ds", seconds)
end

--- Multipliers read better as "x2.50" than "2.5". Sub-1 values keep decimals.
function NumberUtil.abbreviateMultiplier(value: number): string
	value = NumberUtil.sanitize(value)
	if value < 1000 then
		return string.format("x%.2f", value)
	end
	return "x" .. NumberUtil.abbreviate(value)
end

--- Adds while refusing to overflow past the representation ceiling.
function NumberUtil.add(a: number, b: number): number
	return math.min(NumberUtil.sanitize(a) + NumberUtil.sanitize(b), 1e308)
end

--- Multiplies with the same ceiling, and short-circuits on zero so we never
--- produce NaN from 0 * inf.
function NumberUtil.multiply(a: number, b: number): number
	a = NumberUtil.sanitize(a)
	b = NumberUtil.sanitize(b)
	if a == 0 or b == 0 then
		return 0
	end
	if a >= 1e308 or b >= 1e308 then
		return 1e308
	end
	return math.min(a * b, 1e308)
end

--- Percentage of a whole, 0..100, clamped. Used by heat UI.
function NumberUtil.percent(value: number, total: number): number
	if total <= 0 then
		return 0
	end
	return math.clamp(value / total * 100, 0, 100)
end

return NumberUtil
