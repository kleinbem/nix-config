#pragma once
// Infra tab: the fleet's services as Gatus (status.kleinbem.dev) last saw them.
#include <algorithm>
#include <string>
#include <vector>
#include "esphome/components/json/json_util.h"

namespace infra {
enum State { DOWN, UNKNOWN, UP };  // sort order: problems first
struct Service {
  std::string name, group;
  State state;
  int status, ms;
};
inline std::vector<Service> services;
inline uint32_t last_ok_ms = 0;

// Gatus /api/v1/endpoints/statuses with pageSize=1: one result per endpoint.
inline bool parse(const std::string &body) {
  auto doc = esphome::json::parse_json(body);
  JsonArrayConst list = doc.as<JsonArrayConst>();
  if (list.isNull() || list.size() == 0) return false;  // nothing to show is not "all up"
  services.clear();
  for (JsonObjectConst e : list) {
    Service s{e["name"].as<std::string>(), e["group"].as<std::string>(), UNKNOWN, 0, 0};
    // No result yet (endpoint just added): shown as unknown, not dropped.
    JsonArrayConst r = e["results"];
    if (r.size() > 0) {
      JsonObjectConst last = r[r.size() - 1];
      s.state = (last["success"] | false) ? UP : DOWN;
      s.status = last["status"] | 0;
      s.ms = (int) ((last["duration"] | 0LL) / 1000000);
    }
    services.push_back(s);
  }
  std::stable_sort(services.begin(), services.end(), [](const Service &a, const Service &b) {
    if (a.state != b.state) return a.state < b.state;
    return a.group != b.group ? a.group < b.group : a.name < b.name;
  });
  return true;
}

inline int count(State st) {
  return std::count_if(services.begin(), services.end(), [st](const Service &s) { return s.state == st; });
}

constexpr uint32_t GREEN = 0x66BB6A, RED = 0xEF5350, CARD = 0x161B21, MUTED = 0x8A949E, ACTIVE = 0x4FC3F7;

// Updates tiles in place when the count matches to avoid reallocating 48 LVGL widgets each minute.
inline void render(lv_obj_t *grid, const lv_font_t *name_font, const lv_font_t *small_font) {
  lv_obj_set_style_opa(grid, LV_OPA_COVER, 0);
  if (lv_obj_get_child_count(grid) != services.size()) {
    lv_obj_clean(grid);
    for (size_t i = 0; i < services.size(); i++) {
      lv_obj_t *t = lv_obj_create(grid);
      lv_obj_set_size(t, 298, 130);
      lv_obj_set_scrollable(t, false);
      lv_obj_set_style_border_width(t, 6, 0);
      lv_obj_set_style_border_side(t, LV_BORDER_SIDE_LEFT, 0);
      lv_obj_set_style_radius(t, 10, 0);
      lv_obj_set_style_pad_all(t, 14, 0);

      lv_obj_t *n = lv_label_create(t);
      lv_label_set_long_mode(n, LV_LABEL_LONG_MODE_DOTS);
      lv_obj_set_width(n, 258);
      lv_obj_set_style_text_font(n, name_font, 0);
      lv_obj_set_style_text_color(n, lv_color_hex(0xFFFFFF), 0);
      lv_obj_align(n, LV_ALIGN_TOP_LEFT, 0, 0);

      lv_obj_t *g = lv_label_create(t);
      lv_obj_set_style_text_font(g, small_font, 0);
      lv_obj_set_style_text_color(g, lv_color_hex(MUTED), 0);
      lv_obj_align(g, LV_ALIGN_BOTTOM_LEFT, 0, 0);

      lv_obj_t *st = lv_label_create(t);
      lv_obj_set_style_text_font(st, small_font, 0);
      lv_obj_align(st, LV_ALIGN_BOTTOM_RIGHT, 0, 0);
    }
  }
  for (size_t i = 0; i < services.size(); i++) {
    const auto &s = services[i];
    uint32_t c = s.state == UP ? GREEN : s.state == DOWN ? RED : MUTED;
    lv_obj_t *t = lv_obj_get_child(grid, i);
    lv_obj_set_style_bg_color(t, lv_color_hex(s.state == DOWN ? 0x3A1A1A : CARD), 0);
    lv_obj_set_style_border_color(t, lv_color_hex(c), 0);

    lv_label_set_text(lv_obj_get_child(t, 0), s.name.c_str());
    lv_label_set_text(lv_obj_get_child(t, 1), s.group.c_str());

    lv_obj_t *st = lv_obj_get_child(t, 2);
    std::string txt = s.state == UP        ? std::to_string(s.ms) + " ms"
                      : s.state == UNKNOWN ? "not checked yet"
                      : s.status           ? "HTTP " + std::to_string(s.status)
                                           : "no answer";
    lv_label_set_text(st, txt.c_str());
    lv_obj_set_style_text_color(st, lv_color_hex(c), 0);
  }
}

// The tab button shows the number of services down, in red, from any tab
// and also while selected (ACTIVE and MUTED are the tab_style colours).
inline void mark_tab(lv_obj_t *tv, uint32_t idx, const char *text, bool alert) {
  lv_obj_t *b = lv_tabview_get_tab_button(tv, idx);
  lv_tabview_set_tab_text(tv, idx, text);
  lv_obj_set_style_text_color(b, lv_color_hex(alert ? RED : MUTED), LV_STATE_DEFAULT);
  lv_obj_set_style_text_color(b, lv_color_hex(alert ? RED : ACTIVE), LV_STATE_CHECKED);
}
inline void mark_tab(lv_obj_t *tv, uint32_t idx) {
  int d = count(DOWN);
  mark_tab(tv, idx, (d ? "Infra " + std::to_string(d) : std::string("Infra")).c_str(), d > 0);
}

// No fresh status: dim the old tiles and drop the badge, so nothing old
// looks current.
inline void stale(lv_obj_t *grid, lv_obj_t *head, lv_obj_t *tv, uint32_t idx, const std::string &why) {
  lv_obj_set_style_opa(grid, LV_OPA_40, 0);
  lv_label_set_text(head, why.c_str());
  lv_obj_set_style_text_color(head, lv_color_hex(MUTED), 0);
  mark_tab(tv, idx, "Infra ?", false);
}
}  // namespace infra
