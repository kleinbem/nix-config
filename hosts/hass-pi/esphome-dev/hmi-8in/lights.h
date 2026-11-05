#pragma once
#include <string>
// WiZ lamps on the lights pop-up. Names are shown on the target buttons;
// the first one is also the Home tab's Light button.
namespace lights {
struct Lamp {
  const char *name;
  const char *entity;
};
inline constexpr Lamp LIST[] = {
    {"Lamp 1", "light.wiz_rgbw_tunable_241e14"},
    {"Lamp 2", "light.wiz_rgbw_tunable_1f19dc"},
    {"Lamp 3", "light.wiz_rgbw_tunable_20bfd2"},
};
inline constexpr int COUNT = sizeof(LIST) / sizeof(LIST[0]);

// sel 0 = all lamps (comma list, which HA accepts as entity_id), else one.
inline std::string target(int sel) {
  if (sel > 0 && sel <= COUNT) return LIST[sel - 1].entity;
  std::string s;
  for (const auto &l : LIST) {
    if (!s.empty()) s += ",";
    s += l.entity;
  }
  return s;
}
}  // namespace lights
