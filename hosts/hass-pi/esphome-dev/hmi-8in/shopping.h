#pragma once
#include <string>
#include <vector>
#include "esphome/core/hal.h"
// Home Assistant's shopping list, as last read for the Shopping tab.
namespace shopping {
struct Item {
  std::string uid, summary;
  bool done;
};
inline std::vector<Item> items;

// A request waiting for its answer. Expires after 10 s, so a lost answer
// (Home Assistant disconnected) doesn't block it for good.
struct Pending {
  uint32_t since = 0;
  bool active = false, again = false;
  bool busy() const { return active && esphome::millis() - since < 10000; }
  void start() { active = true; again = false; since = esphome::millis(); }
  // True when another call came in meanwhile and should run now.
  bool finish() {
    active = false;
    return again;
  }
};
inline Pending fetch, adding;
inline std::string added;  // the text the pending add sent
}  // namespace shopping
