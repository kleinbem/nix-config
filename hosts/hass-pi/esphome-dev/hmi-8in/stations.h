#pragma once
// Radio stations for the Media tab buttons and the wake-up alarm. The
// "Wake-up station" select lists the names in this order.
namespace stations {
struct Station {
  const char *name;
  const char *url;
};
inline constexpr Station LIST[] = {
    {"Radio Mirchi Hindi", "https://eu8.fastcast4u.com/proxy/clyedupq/stream"},
    {"Hits Of Bollywood", "http://stream.zeno.fm/8ty8szwpwfeuv"},
    {"RTÉ Radio 1", "http://icecast.rte.ie/radio1"},
    {"Today FM", "https://stream.audioxi.com/TD"},
    {"Bayern 3", "https://dispatcher.rndfnk.com/br/br3/live/mp3/mid"},
    {"1LIVE", "http://wdr-1live-live.icecast.wdr.de/wdr/1live/live/mp3/128/stream.mp3"},
    {"Hitradio Ö3", "https://orf-live.ors-shoutcast.at/oe3-q2a"},
    {"FM4", "https://orf-live.ors-shoutcast.at/fm4-q2a"},
};
inline constexpr int COUNT = sizeof(LIST) / sizeof(LIST[0]);
}  // namespace stations
