# shellcheck shell=bash
# Manual on-device builds on orin-nano share the GPU runner's build window
# (modules/nixos/services/mesh-llm-gpu-runner.nix): the window stops
# mesh-llm and marks it, and only a marked node is started again. A shared
# lock tells the runner's window end that a manual build still needs the RAM.

MESH_WINDOW_LOCK=/run/mesh-llm-build-window/manual.lock

mesh_window_open() {
  exec 9>"$MESH_WINDOW_LOCK"
  flock -s 9
  trap mesh_window_close EXIT
  sudo systemctl start mesh-llm-build-window-start.service
}

mesh_window_close() {
  if pgrep -x Runner.Worker >/dev/null; then
    echo "ℹ️  A GPU runner build is running; its window end restarts mesh-llm."
  elif ! flock -n -x 9; then
    echo "ℹ️  Another manual build still runs; the last one restarts mesh-llm."
  else
    flock -u 9
    sudo systemctl start mesh-llm-build-window-end.service
  fi
}
