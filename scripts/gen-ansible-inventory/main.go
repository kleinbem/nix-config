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
	IP   string   `json:"ip"`
	Tags []string `json:"tags"`
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

func parseAndFormat(data []byte) (string, error) {
	var inventory Inventory
	if err := json.Unmarshal(data, &inventory); err != nil {
		return "", fmt.Errorf("error unmarshaling json: %v", err)
	}

	groups := map[string][]string{
		"mediatek":      {},
		"routers":       {},
		"gateways":      {},
		"access_points": {},
		"brains":        {},
	}

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

		if hasTag("physical") {
			groups["mediatek"] = append(groups["mediatek"], fmt.Sprintf("%s ansible_host=%s", name, data.IP))
			groups["routers"] = append(groups["routers"], name)
			if hasTag("gateway") {
				groups["gateways"] = append(groups["gateways"], name)
			}
			if hasTag("lxc-host") {
				groups["access_points"] = append(groups["access_points"], name)
			}
		}

		if hasTag("brain") {
			groups["brains"] = append(groups["brains"], fmt.Sprintf("%s ansible_host=%s ansible_user=root", name, data.IP))
		}
	}

	var sb strings.Builder
	sb.WriteString("# Generated from nix-config/inventory.nix - DO NOT EDIT MANUALLY\n\n")

	mediatekVars := []string{
		"ansible_user=root",
		"ansible_python_interpreter=/usr/bin/python3",
		"wan_iface=eth1",
		"lan_iface=eth0",
	}

	order := []string{"mediatek", "routers", "gateways", "access_points", "brains"}
	for _, groupName := range order {
		members := groups[groupName]
		if len(members) == 0 {
			continue
		}
		sb.WriteString(fmt.Sprintf("[%s]\n", groupName))
		for _, member := range members {
			sb.WriteString(member + "\n")
		}

		if groupName == "mediatek" {
			sb.WriteString(fmt.Sprintf("\n[%s:vars]\n", groupName))
			for _, v := range mediatekVars {
				sb.WriteString(v + "\n")
			}
		}
		sb.WriteString("\n")
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
