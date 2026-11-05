#pragma once
// Home Assistant weather conditions as Material Design Icons, and the daily
// forecast kept for the Home tab's forecast overlay.
#include <cmath>
#include <cstdio>
#include <ctime>
#include <string>
#include <vector>

namespace weather {
inline const char *icon(const std::string &s) {
  if (s == "sunny") return "\U000F0599";
  if (s == "clear-night") return "\U000F0594";
  if (s == "partlycloudy") return "\U000F0595";
  if (s == "rainy") return "\U000F0597";
  if (s == "pouring") return "\U000F0596";
  if (s == "snowy" || s == "snowy-rainy") return "\U000F0598";
  if (s == "fog") return "\U000F0591";
  if (s == "windy" || s == "windy-variant") return "\U000F059D";
  if (s == "lightning" || s == "lightning-rainy") return "\U000F0593";
  if (s == "hail") return "\U000F0592";
  return "\U000F0590";
}

// Missing values are NAN.
struct Day {
  time_t ts;
  std::string cond;
  float hi, lo, mm;
};
inline std::vector<Day> days;

// ISO 8601 with offset ("2026-11-05T12:00:00+00:00", "...Z") to a UTC epoch;
// Home Assistant gives forecast times in UTC. 0 if unparsable.
inline time_t parse_iso(const char *s) {
  int y, m, d, hh = 0, mm = 0, ss = 0, n = 0;
  if (!s || sscanf(s, "%d-%d-%dT%d:%d:%d%n", &y, &m, &d, &hh, &mm, &ss, &n) < 6 || m < 1 || m > 12) return 0;
  // Days since 1970-01-01 (Howard Hinnant's days_from_civil).
  y -= m <= 2;
  long era = (y >= 0 ? y : y - 399) / 400;
  long yoe = y - era * 400;
  long doy = (153 * (m + (m > 2 ? -3 : 9)) + 2) / 5 + d - 1;
  long doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
  long days = era * 146097 + doe - 719468;
  long t = days * 86400 + hh * 3600 + mm * 60 + ss;
  const char *z = s + n;
  while (*z == '.' || (*z >= '0' && *z <= '9')) z++;  // fractional seconds
  int oh = 0, om = 0;
  if ((*z == '+' || *z == '-') && sscanf(z + 1, "%d:%d", &oh, &om) >= 1) t -= (*z == '+' ? 1 : -1) * (oh * 3600 + om * 60);
  return (time_t) t;
}

// Local calendar day, comparable across years.
inline int local_day(time_t t) {
  struct tm tm;
  localtime_r(&t, &tm);
  return (tm.tm_year + 1900) * 1000 + tm.tm_yday;
}

inline std::string deg(float v) { return std::isnan(v) ? std::string("–") : std::to_string((int) std::lround(v)) + "°"; }
}  // namespace weather
