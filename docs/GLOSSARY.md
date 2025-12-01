# StarForge Glossary — Abbreviations, Acronyms & Technical Terms

This glossary collects **abbreviations**, **acronyms** and **technical** terms used throughout the PRD (Product
Requirement Document) and the repository. It is intended as a single source of truth for **engineers**, **product**,
**QA**, **operations** and **community contributors**.

## Cross-reference

- Primary PRD: [docs/PRD.md](./PRD.md)
- (See Section 23.1 in the PRD which lists a short glossary; this file expands and formalizes those entries.)

## Usage

- Terms are alphabetical.
- Each entry includes: short definition, an example or context note, and where applicable a pointer to the PRD.

---

# A

- `ADR` — **Architecture Decision Record**
    - _Definition:_ A short document recording an architectural decision, rationale and consequences.
    - _Context:_ Use for documented choices (e.g., queue choice). See PRD sections on architecture and decisions.

- `API` — **Application Programming Interface**
    - _Definition:_ A programmatic interface for services to communicate (`HTTP`/`REST` in this project).
    - _Example:_ `POST /api/v1/internal/snapshots`.

- `App / application` (context)  
  _Definition:_ The backend service components (`API service`, `ETL worker`, `bot`) that implement product features.

- `AWS` — **Amazon Web Services**
    - _Definition:_ Cloud provider often used for `S3`, `compute`, etc. (`S3` is commonly mentioned for archival).

---

# B

- `BLOB` / **Binary Large Object**
    - _Definition:_ Generic term for large binary objects; in this PRD `JSON payloads` are stored in Postgres `JSONB` (
      `TOASTed`), similar concept.

- `Backfill`
    - _Definition:_ Batch reprocessing of historical data (`snapshots`) to populate or recompute normalized tables.
    - _Context:_ See PRD Section 15 (`Migration & Backfill Plan`).

- `Batch` / `Batching`
    - _Definition:_ Grouping many small operations into a single operation for efficiency in `ETL` and DB writes.

- `BH` / `BullMQ` (**Bull Message Queue**)
    - _Definition:_ Popular `Node.js` + `Redis-based` job queue library (the PRD suggests `BullMQ` as an option).
    - _Context:_ Used as example for enqueueing snapshot processing jobs.

---

# C

- `CDN` — **Content Delivery Network**
    - _Definition:_ Distributed caching layer for static assets (`Cloudflare`, `Fastly` etc.). Mentioned as an option
      for UI assets.

- `CI` — **Continuous Integration**
    - _Definition:_ Automated process that builds, tests and validates code on each change (`GitHub Actions` in this
      repo).

- `CLI` — **Command Line Interface**
    - Definition: Shell scripts and tools provided to interact with upstream `APIs` and `ingestion endpoints` (e.g.,
      `get_hero_profile.sh`).

- `CI/CD` — **Continuous Integration / Continuous Delivery**
    - _Definition:_ Combined automation for building, testing and deploying code.

- `COOP / CORP` (not used frequently) — **Cross-Origin isolation concepts**
    - _Note:_ Not a central term in PRD but sometimes relevant for `frontends`; included only if needed.

---

# D

- `DB` — **Database** (`Postgres` in this project)
    - _Definition:_ Primary relational store used to persist `snapshots`, `normalized tables` and `metadata`.

- `DPA` — **Data Processing Agreement**
    - _Definition:_ Contract with cloud providers for handling personal data (`GDPR-related`). Refer to PRD legal
      sections.

- `DPoP / DSR` — **Data Subject Request**
    - _Definition:_ User requests under privacy laws (access, deletion). See PRD privacy & compliance.

- `DCO` — **Developer Certificate of Origin**
    - _Definition:_ Lightweight contributor sign‑off process for contributions. Alternative to `CLA`.

- `DAG` — **Directed Acyclic Graph** (general `ETL` concept)
    - _Definition:_ Job dependency graph; not a required term but relevant if using orchestrators.

---

# E

- `E2E` — **End-to-End testing**
    - _Definition:_ Tests that exercise the full flow (`ingest → ETL → summary`). See PRD testing section.

- `ETL` — **Extract, Transform, Load**
    - _Definition:_ Background worker processing that parses raw `snapshots` (extract), maps/normalizes fields (
      transform),
      and writes relational data (load).

- `ERD` — **Entity Relationship Diagram**  
  _Definition:_ Visual representation of `DB schema` (refer to [docs/DB_MODEL.md](DB_MODEL.md)).

- `E2E smoke` / `smoke tests`
    - _Definition:_ Quick `end-to-end` checks performed after deploys.

---

# F

- `FIFO / LIFO` — **Queue ordering concepts**
    - _Definition:_ First-In-First-Out is typical queue behavior (jobs processed in arrival order).

- `Feature flag`
    - _Definition:_ Configurable toggle that enables/disables a feature at runtime (DB table `feature_flags` in PRD).

- `FQDN` — **Fully Qualified Domain Name**
    - _Definition:_ Hostname format — included here for network/config references.

---

# G

- `GIN` — **Generalized Inverted Index** (Postgres index type)
    - _Definition:_ An index type useful for `jsonb` search. The PRD suggests `GIN` indexes on `hero_snapshots.raw`.

- `GitHub Actions / GH Actions`
    - _Definition:_ `CI` system used in repository; used also to run manual `db-bootstrap.yml` with environment
      protection.

- `GHCR` — **GitHub Container Registry**
    - _Definition:_ Registry for built `container images` (`CI` publishes `worker/API` images).

- `GCP` — **Google Cloud Platform**
    - _Definition:_ Cloud provider; related to `GOOGLE_SA_JSON` references in PRD.

- `GET` / `POST` / `PUT` / `PATCH` / `DELETE`
    - _Definition:_ HTTP verbs for `API endpoints`.

---

# H

- `HA` — **High Availability**
    - _Definition:_ Infrastructure design to avoid single points of failure (multi-AZ DB etc.).

- `HTTP` — **HyperText Transfer Protocol**
    - _Definition:_ Protocol used by `REST API` endpoints.

---

# I

- `ID` — **Identifier** (`UUID` preferred for entities)
    - _Definition:_ Unique identifier. PRD prefers `gen_random_uuid()` from `pgcrypto`.

- `Idempotent / idempotency`
    - _Definition:_ Property of operations to be safely retried without causing duplicate effects (`ETL` upserts must be
      idempotent). The PRD recommends `Idempotency-Key` header for `POSTs`.

- `IAM` — **Identity and Access Management**
    - _Definition:_ Cloud access control system; applies to `S3`, service accounts, secrets.

- `IDS` / `IPS` — **intrusion detection / prevention**
    - _Definition:_ Security systems; mentioned generally for security posture.

---

# J

- `JSON` — **JavaScript Object Notation**
    - _Definition:_ Text data format used by upstream `get_hero_profile` payloads.

- `JSONB` — **Postgres binary JSON storage type**
    - _Definition:_ Efficient column type in Postgres used for `hero_snapshots.raw`. Supports `GIN` indexing and `TOAST`
      compression.

- `JQ` — **Command-line JSON processor**
    - _Definition:_ Tool recommended for extracting fields from large `JSON` locally (used in `CLI flows`).

---

# K

- `k6` — **Load-testing tool**
    - _Definition:_ Used in PRD for performance testing.

---

# L

- `LTS` — **Long Term Support** (Node LTS recommended)
    - _Definition:_ Stable `Node.js` runtime line used for services.

- `LB` — **Load Balancer**
    - _Definition:_ Component that routes `HTTP` traffic to `API` replicas.

---

# M

- `MB` / `GB` — **Megabyte / Gigabyte**
    - _Definition:_ Data size units; snapshots can be `~2–3MB` (login flow).

- `Migrations` — **DB schema migrations** (`node-pg-migrate`)
    - _Definition:_ Versioned schema changes; PRD mandates `node-pg-migrate` for `JS migrations`.

- `Materialized view`
    - _Definition:_ DB object precomputed from queries (used for analytics).

- `MIT / Apache-2.0` — **Licenses**
    - _Definition:_ Recommended permissive licenses for the repository.

---

# N

- `NameCode` — **Game-specific user code**
    - _Definition:_ Player identifier used in upstream `API` and PRD flows.

- `NFR` — **Non-Functional Requirements**
    - _Definition:_ Requirements like performance, security, reliability (PRD Section 6).

- `Node` / `Node.js`
    - _Definition:_ Runtime for API and worker code. PNPM used as package manager.

- `NPM` / `PNPM` — **package managers for Node**
    - _Definition:_ `PNPM` recommended in PRD; `npm` is standard Node package manager.

---

# O

- `OIDC` — **OpenID Connect**
    - _Definition:_ Identity federation method recommended for `GitHub Actions` → cloud authentication (avoid long-lived
      keys).

- `Ops / SRE — Operations` - **Site Reliability Engineering**
    - _Definition:_ Team responsible for `infra`, `backups`, `runbooks`, `monitoring`.

- `OOM` — **Out of Memory**
    - _Definition:_ Worker failure mode when parsing very large snapshots if streaming is not implemented.

---

# P

- `pgcrypto` — **Postgres extension for cryptographic functions**
    - _Definition:_ Preferred extension for `UUID` generation; may be restricted on some managed providers.

- `PITR` — **Point-In-Time Recovery**
    - _Definition:_ DB restore capability to a specific time (required for `RPO` objectives).

- `PII` — **Personal Identifiable Information**
    - _Definition:_ Sensitive user data subject to privacy rules (emails, real names, tokens).

- `PK / FK` — **Primary Key / Foreign Key**
    - _Definition:_ DB constraints.

- `P0 / P1 / P2` — **Priority / Severity levels**
    - _Definition:_ Incident severity levels used in runbooks (P0 = critical).

- `PR` — **Pull Request** (GitHub)
    - _Definition:_ Source code change proposal workflow.

- `PRD` — **Product Requirement Document**
    - _Definition:_ [This document](./PRD.md). The glossary is referenced from Section 23.1.

- `Prometheus`
    - _Definition:_ Metrics collection system; workers and `API` should expose `/metrics`.

- `PostgreSQL / Postgres`
    - _Definition:_ Relational DB used (`Supabase` or equivalent managed `Postgres`).

---

# Q

- `QA` — **Quality Assurance**
    - _Definition:_ Team and testing effort (unit, integration, E2E, performance). See PRD testing sections.

- `QPS` — **Queries per Second**
    - _Definition:_ Load metric used for planning capacity.

---

# R

- `RTO` — **Recovery Time Objective**
    - _Definition:_ Target time to recover after failure (PRD suggests 1 hour for critical failures).

- `RPO` — **Recovery Point Objective**
    - _Definition:_ Target acceptable data loss window (PRD suggests ~1 hour).

- `RBAC` — **Role-Based Access Control**
    - _Definition:_ Authorization model for admin endpoints and secrets.

- `Redis`
    - _Definition:_ In-memory data store used as queue broker (`BullMQ`) and caching store.

- `REST` — **Representational State Transfer**
    - _Definition:_ API design approach used in PRD (versioned `api/v1`).

- `RLS` — **Row-Level Security**
    - _Definition:_ Not central in PRD but relevant if more granular access control is required.

---

# S

- `S3` — **AWS Simple Storage Service** (or S3-compatible)
    - _Definition:_ Object storage used for archival and exports.

- `Sentry`
    - _Definition:_ Error tracking product (used for exceptions). Must be configured to scrub `PII`.

- `SBOM` — **Software Bill Of Materials**
    - _Definition:_ Inventory of dependencies and licenses (recommended for legal/compliance).

- `SHA256` — **Secure Hash Algorithm** (256-bit)
    - _Definition:_ Hash algorithm used for snapshot content hashing/deduplication.

- `SLA` — **Service Level Agreement**
    - _Definition:_ Formal availability/latency commitment.

- `SLO` — **Service Level Objective**
    - _Definition:_ Targeted operational objective (e.g., `p95 < 200ms` for reads).

- `SQL` — **Structured Query Language**
    - _Definition:_ DB query language.

- `SRE` — **Site Reliability Engineering**

- `SSD / HDD` — **Storage types**
    - _Definition:_ Underlying storage media considerations for DB.

- `Supabase`
    - _Definition:_ Example managed `Postgres` provider mentioned in PRD; some providers may restrict extensions.

- `SSL / TLS` — **Secure Sockets Layer / Transport Layer Security**
    - _Definition:_ Encryption for in-transit data; require `TLS` for all connections.

---

# T

- `TOAST` — **The Oversized-Attribute Storage Technique** (Postgres)
    - _Definition:_ Postgres mechanism to store large `jsonb` fields efficiently (used for `hero_snapshots.raw`).

- `TD` / **Tech Debt**
    - _Definition:_ Technical debt — items to manage over time.

- `TPM` / `Telemetry` / `Trace`
    - _Definition:_ Observability signals for tracing and metrics.

- `TTL` — **Time To Live**
    - _Definition:_ Cache expiry value (e.g., summary cache `TTL`).

---

# U

- `UUID` — **Universally Unique Identifier**
    - _Definition:_ Primary identifier format used in tables; preferably generated via `gen_random_uuid()`.

- `Upstream`
    - _Definition:_ External game `API` (e.g., `get_hero_profile` endpoint) that supplies snapshots; may have rate
      limits.

- `UX` — **User Experience**
    - _Definition:_ UI/interaction design.

---

# V

- `VA / VAC` — **Vulnerability Assessment / Vulnerability and Configuration scanning**
    - _Definition:_ Security scans and dependency checks (`Dependabot`, `Snyk`).

- `VPC` — **Virtual Private Cloud**
    - _Definition:_ Network isolation for DB and services.

---

# W

- `WAL` — **Write-Ahead Log** (Postgres)
    - _Definition:_ Transaction log used for `PITR` and replication.

- `WAF` — **Web Application Firewall**
    - _Definition:_ Security layer protecting `API` endpoints.

---

# X / Y / Z

- `zstd / gzip` — **Compression algorithms**
    - _Definition:_ Potential compression for archived snapshots.

---
