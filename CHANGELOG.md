# Changelog

All notable changes to this project will be documented in this file.

This project follows **Semantic Versioning**
(`MAJOR.MINOR.PATCH`).

---

## v1.0.0 — Initial Stable Release

### Added

- Grafana-style terminal dashboard
- Flicker-free real-time rendering engine
- CPU usage monitoring (total + per-core)
- Memory and swap usage statistics
- Disk usage overview
- Network RX/TX live speed detection
- Active TCP connection tracking
- Total and active process monitoring
- Top CPU-consuming process list
- Service status monitoring
- Configurable refresh interval
- Network interface override support

### Architecture

- Pure Bash (4+)
- No background services or daemons
- No configuration files required
- Read-only system access
- Compatible with most Linux distributions

### Security

- No outbound network requests
- No telemetry or data collection
- No persistent processes after exit

---
