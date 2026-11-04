package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"sort"
	"strings"
)

type HostData struct {
	IP    string   `json:"ip"`
	Board string   `json:"board"`
	Tags  []string `json:"tags"`
}

type Inventory struct {
	Hosts map[string]HostData `json:"hosts"`
}

func fetchInventory(inventoryNix string) ([]byte, error) {
	cmd := exec.Command("nix", "eval", "--json", "-f", inventoryNix)
	var out bytes.Buffer
	var stderr bytes.Buffer
	cmd.Stdout = &out
	cmd.Stderr = &stderr
	if err := cmd.Run(); err != nil {
		return nil, fmt.Errorf("error evaluating inventory.nix: %v\nstderr: %s", err, stderr.String())
	}
	return out.Bytes(), nil
}

// boardGroup maps an inventory.nix `board` ("bpi-r4") to its Ansible group
// name ("board_bpi_r4"); openwrt-config keys group_vars/board_<board>.yml on it.
func boardGroup(board string) string {
	return "board_" + strings.ReplaceAll(board, "-", "_")
}

func parseAndFormat(data []byte) (string, error) {
	var inventory Inventory
	if err := json.Unmarshal(data, &inventory); err != nil {
		return "", fmt.Errorf("error unmarshaling json: %v", err)
	}

	// Every physical OpenWrt device lands in `openwrt` (connection vars) and
	// in one `board_<board>` group (per-hardware vars: interface names, Wi-Fi
	// modes, port map). Role groups below are tag-driven as before.
	groups := map[string][]string{
		"openwrt":       {},
		"routers":       {},
		"gateways":      {},
		"access_points": {},
		"lxc_hosts":     {},
		// Wireless backhaul roles (openwrt-config group_vars/mesh_*.yml): the
		// one Orbi wired to a BPI-R4 is the 802.11s gate, the free-standing
		// satellites are nodes.
		"mesh_gates": {},
		"mesh_nodes": {},
	}
	boardGroups := map[string][]string{}

	// Sort host names to ensure deterministic output
	var hostNames []string
	for name := range inventory.Hosts {
		hostNames = append(hostNames, name)
	}
	sort.Strings(hostNames)

	for _, name := range hostNames {
		data := inventory.Hosts[name]
		hasTag := func(t string) bool {
			for _, tag := range data.Tags {
				if tag == t {
					return true
				}
			}
			return false
		}

		if !hasTag("physical") {
			continue
		}
		if data.Board == "" {
			return "", fmt.Errorf("host %q is tagged physical but has no `board` in inventory.nix (needed for the board_<board> group / group_vars)", name)
		}

		// mgmt_ip is the device's own infra-VLAN address (its inventory ip),
		// separate from ansible_host so a bench run that reaches the board
		// at 192.168.1.1 (`-e ansible_host=...`) still configures the right
		// management IP.
		groups["openwrt"] = append(groups["openwrt"], fmt.Sprintf("%s ansible_host=%s mgmt_ip=%s", name, data.IP, data.IP))
		bg := boardGroup(data.Board)
		boardGroups[bg] = append(boardGroups[bg], name)
		groups["routers"] = append(groups["routers"], name)
		if hasTag("gateway") {
			groups["gateways"] = append(groups["gateways"], name)
		}
		if hasTag("ap") {
			groups["access_points"] = append(groups["access_points"], name)
		}
		if hasTag("lxc-host") {
			groups["lxc_hosts"] = append(groups["lxc_hosts"], name)
		}
		if hasTag("mesh-gate") && hasTag("mesh-node") {
			return "", fmt.Errorf("host %q is tagged both mesh-gate and mesh-node", name)
		}
		if hasTag("mesh-gate") {
			groups["mesh_gates"] = append(groups["mesh_gates"], name)
		}
		if hasTag("mesh-node") {
			groups["mesh_nodes"] = append(groups["mesh_nodes"], name)
		}
	}

	var sb strings.Builder
	sb.WriteString("# Generated from nix-config/inventory.nix - DO NOT EDIT MANUALLY\n\n")

	openwrtVars := []string{
		"ansible_user=root",
		"ansible_python_interpreter=/usr/bin/python3",
	}

	writeGroup := func(groupName string, members []string) {
		sb.WriteString(fmt.Sprintf("[%s]\n", groupName))
		for _, member := range members {
			sb.WriteString(member + "\n")
		}
		sb.WriteString("\n")
	}

	if len(groups["openwrt"]) > 0 {
		writeGroup("openwrt", groups["openwrt"])
		sb.WriteString("[openwrt:vars]\n")
		for _, v := range openwrtVars {
			sb.WriteString(v + "\n")
		}
		sb.WriteString("\n")
	}

	var boardNames []string
	for bg := range boardGroups {
		boardNames = append(boardNames, bg)
	}
	sort.Strings(boardNames)
	for _, bg := range boardNames {
		writeGroup(bg, boardGroups[bg])
	}

	for _, groupName := range []string{"routers", "gateways", "access_points", "lxc_hosts", "mesh_gates", "mesh_nodes"} {
		if members := groups[groupName]; len(members) > 0 {
			writeGroup(groupName, members)
		}
	}

	return sb.String(), nil
}

func main() {
	if len(os.Args) < 2 {
		fmt.Println("Usage: gen-ansible-inventory <path-to-inventory.nix>")
		os.Exit(1)
	}
	inventoryNix := os.Args[1]

	data, err := fetchInventory(inventoryNix)
	if err != nil {
		fmt.Println(err)
		os.Exit(1)
	}

	output, err := parseAndFormat(data)
	if err != nil {
		fmt.Println(err)
		os.Exit(1)
	}

	fmt.Print(output)
}
