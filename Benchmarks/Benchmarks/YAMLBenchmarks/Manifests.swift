// Kubernetes Deployments in one list, generated at a fixed size, for Codable: the shape most YAML read into Swift types has
// (nested mappings, sequences of mappings, string maps, integers, optional fields).

struct DeploymentList: Codable, Equatable {
    struct Deployment: Codable, Equatable {
        struct Metadata: Codable, Equatable {
            var name: String
            var namespace: String
            var labels: [String: String]
        }

        struct Container: Codable, Equatable {
            struct Port: Codable, Equatable {
                var containerPort: Int
                var `protocol`: String
            }

            struct Variable: Codable, Equatable {
                var name: String
                var value: String
            }

            struct Resources: Codable, Equatable {
                var limits: [String: String]
                var requests: [String: String]
            }

            var name: String
            var image: String
            var ports: [Port]
            var env: [Variable]?
            var resources: Resources
        }

        struct Spec: Codable, Equatable {
            struct Template: Codable, Equatable {
                struct PodSpec: Codable, Equatable {
                    var containers: [Container]
                    var serviceAccountName: String?
                }

                var metadata: Metadata
                var spec: PodSpec
            }

            var replicas: Int
            var paused: Bool
            var template: Template
        }

        var apiVersion: String
        var kind: String
        var metadata: Metadata
        var spec: Spec
    }

    var items: [Deployment]
}

/// `count` Deployments in block style, as `kubectl get -o yaml` writes them; a few flow mappings and quoted scalars, as people write.
func deploymentList(count: Int) -> [UInt8] {
    var lines = ["items:"]
    func add(_ depth: Int, _ text: String) { lines.append(String(repeating: "  ", count: depth) + text) }
    for index in 0 ..< count {
        let name = "service-\(index)"
        func metadata(_ depth: Int) {
            add(depth, "name: \(name)")
            add(depth, "namespace: team-\(index % 7)")
            add(depth, "labels:")
            add(depth + 1, "app: \(name)")
            add(depth + 1, "tier: \(index % 3 == 0 ? "frontend" : "backend")")
        }
        add(0, "- apiVersion: apps/v1")
        add(1, "kind: Deployment")
        add(1, "metadata:")
        metadata(2)
        add(1, "spec:")
        add(2, "replicas: \(index % 5 + 1)")
        add(2, "paused: \(index % 11 == 0)")
        add(2, "template:")
        add(3, "metadata:")
        metadata(4)
        add(3, "spec:")
        add(4, "containers:")
        add(5, "- name: \(name)")
        add(6, "image: \"registry.example.com/\(name):1.\(index % 10).\(index % 4)\"")
        add(6, "ports:")
        add(7, "- containerPort: \(8000 + index % 100)")
        add(8, "protocol: TCP")
        if index % 2 == 0 {
            add(6, "env:")
            add(7, "- name: LOG_LEVEL")
            add(8, "value: info")
            add(7, "- name: REGION")
            add(8, "value: eu-west-\(index % 3 + 1)")
        }
        add(6, "resources:")
        add(7, "limits: {cpu: \"\(index % 4 + 1)\", memory: \(256 * (index % 4 + 1))Mi}")
        add(7, "requests: {cpu: 250m, memory: 128Mi}")
        if index % 3 == 0 { add(4, "serviceAccountName: \(name)-account") }
    }
    return Array((lines.joined(separator: "\n") + "\n").utf8)
}
