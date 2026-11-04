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
				"board": "bpi-r4",
				"tags": ["physical", "gateway"]
			},
			"node2": {
				"ip": "192.168.1.2",
				"board": "bpi-r4",
				"tags": ["physical", "lxc-host"]
			},
			"ap1": {
				"ip": "192.168.1.3",
				"board": "orbi-rbr50",
				"tags": ["physical", "ap", "mesh-gate"]
			},
			"ap2": {
				"ip": "192.168.1.4",
				"board": "orbi-rbs50",
				"tags": ["physical", "ap", "mesh-node"]
			},
			"brain1": {
				"ip": "10.0.0.1",
				"tags": ["brain"]
			}
		}
	}`)

	// The exact expected string output from the parseAndFormat logic
	expectedOutput := `# Generated from nix-config/inventory.nix - DO NOT EDIT MANUALLY

[openwrt]
ap1 ansible_host=192.168.1.3 mgmt_ip=192.168.1.3
ap2 ansible_host=192.168.1.4 mgmt_ip=192.168.1.4
node2 ansible_host=192.168.1.2 mgmt_ip=192.168.1.2
router1 ansible_host=192.168.1.1 mgmt_ip=192.168.1.1

[openwrt:vars]
ansible_user=root
ansible_python_interpreter=/usr/bin/python3

[board_bpi_r4]
node2
router1

[board_orbi_rbr50]
ap1

[board_orbi_rbs50]
ap2

[routers]
ap1
ap2
node2
router1

[gateways]
router1

[access_points]
ap1
ap2

[lxc_hosts]
node2

[mesh_gates]
ap1

[mesh_nodes]
ap2
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

// A physical device without a `board` has no group_vars to land in — the
// generator must refuse rather than emit a half-configured host.
func TestPhysicalHostWithoutBoardFails(t *testing.T) {
	mockJSON := []byte(`{"hosts": {"ap9": {"ip": "10.0.0.9", "tags": ["physical", "ap"]}}}`)
	if _, err := parseAndFormat(mockJSON); err == nil {
		t.Fatalf("expected an error for a physical host without board, got none")
	}
}

// Non-physical hosts never need a board.
func TestNonPhysicalHostsAreIgnored(t *testing.T) {
	mockJSON := []byte(`{"hosts": {"nas": {"ip": "10.0.0.30", "tags": ["server"]}}}`)
	result, err := parseAndFormat(mockJSON)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if strings.Contains(result, "[") {
		t.Errorf("expected no groups for a non-physical-only inventory, got:\n%s", result)
	}
}

// A host can't be gate and node at once.
func TestMeshGateAndNodeConflict(t *testing.T) {
	mockJSON := []byte(`{"hosts": {"ap9": {"ip": "10.0.0.9", "board": "orbi-rbs50", "tags": ["physical", "ap", "mesh-gate", "mesh-node"]}}}`)
	if _, err := parseAndFormat(mockJSON); err == nil {
		t.Fatalf("expected an error for a host tagged mesh-gate and mesh-node, got none")
	}
}
