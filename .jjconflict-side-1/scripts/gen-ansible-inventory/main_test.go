package main

import (
	"strings"
	"testing"
)

func TestParseAndFormat(t *testing.T) {
	// A mock JSON representing the output of 'nix eval --json -f inventory.nix'
	mockJSON := []byte(`{
		"hosts": {
			"router1": {
				"ip": "192.168.1.1",
				"tags": ["physical", "gateway"]
			},
			"node2": {
				"ip": "192.168.1.2",
				"tags": ["physical", "lxc-host"]
			},
			"brain1": {
				"ip": "10.0.0.1",
				"tags": ["brain"]
			}
		}
	}`)

	// The exact expected string output from the parseAndFormat logic
	expectedOutput := `# Generated from nix-config/inventory.nix - DO NOT EDIT MANUALLY

[mediatek]
node2 ansible_host=192.168.1.2
router1 ansible_host=192.168.1.1

[mediatek:vars]
ansible_user=root
ansible_python_interpreter=/usr/bin/python3
wan_iface=eth1
lan_iface=eth0

[routers]
node2
router1

[gateways]
router1

[access_points]
node2

[brains]
brain1 ansible_host=10.0.0.1 ansible_user=root
`

	result, err := parseAndFormat(mockJSON)
	if err != nil {
		t.Fatalf("Unexpected error during parsing: %v", err)
	}

	// We compare the stripped strings to avoid newline discrepancies making the test brittle
	if strings.TrimSpace(result) != strings.TrimSpace(expectedOutput) {
		t.Errorf("Output did not match expected.\nGot:\n%s\nExpected:\n%s", result, expectedOutput)
	}
}
