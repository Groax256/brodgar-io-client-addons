-- Current client curiosity times are seconds; the old Purus 3.29 conversion does not apply.
StudyMetrics = {}
local metrics = StudyMetrics

function metrics.ratio(value, divisor)
  if value == nil or divisor == nil or divisor <= 0 then return nil end
  return value / divisor
end

function metrics.rate(profile)
  local rate = profile and metrics.ratio(profile.lp, profile.time)
  return rate and rate * 3600 or nil
end

function metrics.number(value)
  if value == nil then return "?" end
  return string.format("%d", math.floor(value + 0.5))
end

function metrics.compact(value)
  if value == nil then return "?" end
  if value >= 1000000 then return string.format("%.1fm", value / 1000000) end
  if value >= 10000 then return string.format("%.1fk", value / 1000) end
  return metrics.number(value)
end

function metrics.duration(seconds)
  if seconds == nil then return "?" end
  local minutes = math.ceil(math.max(0, seconds) / 60)
  return string.format("%dh %02dm", math.floor(minutes / 60), minutes % 60)
end

function metrics.remaining(profile, progress)
  if not profile or not profile.time or profile.time <= 0 or progress == nil then return nil end
  return profile.time * (1 - math.max(0, math.min(1, progress)))
end

function metrics.total(profiles)
  local total = {lp = 0, attention = 0, cost = 0, rate = 0, known = 0, unknown = 0}
  for _, profile in ipairs(profiles) do
    total.lp = total.lp + profile.lp
    total.attention = total.attention + profile.attention
    total.cost = total.cost + profile.cost
    local rate = metrics.rate(profile)
    if rate then
      total.rate, total.known = total.rate + rate, total.known + 1
    else
      total.unknown = total.unknown + 1
    end
  end
  return total
end

function metrics.overlap(left, right)
  return left.x < right.x + right.w and right.x < left.x + left.w
      and left.y < right.y + right.h and right.y < left.y + left.h
end
