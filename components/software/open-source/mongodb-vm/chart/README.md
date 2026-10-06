# MongoDB Enterprise Advanced VM Helm Chart

This Helm chart deploys MongoDB Enterprise Advanced 8.3.2 as an OpenShift Virtualization (`VirtualMachine`) on IBM Z (`s390x`).

## Features
- **Standalone Mode**: Single VirtualMachine + DataVolume.
- **High-Availability (HA) Mode**: Multi-node Replica Set (3, 5, or 7 members) with pod anti-affinity across s390x nodes and automated replica set initiation.
- **Cloud-Init Credential Injection**: Automated first-boot database and user initialization.

## Architecture
- **Machine Type**: `s390-ccw-virtio`
- **Architecture**: `s390x`
- **Storage**: KubeVirt CDI `DataVolume` (Block mode, RWO)

## Installation

```bash
helm install mongodb-vm ./chart \
  --set mongodb.databaseName=mydb \
  --set mongodb.databaseUser=myuser \
  --set mongodb.databasePassword=secret \
  --set mongodb.rootPassword=rootsecret \
  --set mongodb.vmRootPassword=vmsecret
```
