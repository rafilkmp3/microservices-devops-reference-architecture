# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Context

This is a DevOps challenge repository for deploying a microservices-based application. The challenge involves containerizing, orchestrating, and setting up CI/CD pipelines for two Node.js microservices that interact with MySQL and Redis.

## System Architecture

The target system consists of:
- **Configuration Service**: Node.js service with Express.js and MySQL client for managing centralized system configuration
- **Log Aggregator Service**: Node.js service with Express.js and MySQL client for combining logs from different sources
- **MySQL Database**: Data storage layer that should be configured during service initialization
- **Redis Cache**: Caching layer that should be configured during service initialization

## Challenge Requirements

The main deliverables for this challenge are:

1. **Dockerization**: Create Dockerfiles for both microservices with clear build/run instructions
2. **Container Orchestration**: Set up Kubernetes or Docker Swarm to deploy and scale services
3. **CI/CD Pipeline**: Automate build and deployment processes with Jenkins, GitLab CI/CD, or similar tools
4. **Networking**: Configure service communication within the orchestration platform
5. **Documentation**: Brief document outlining improvements and further steps

## Development Approach

When implementing this challenge:
- Each microservice should be containerized independently
- Services must be able to connect to MySQL and Redis during initialization
- Container orchestration should support horizontal scaling
- CI/CD pipelines should trigger on repository changes
- Focus on production-ready configurations with proper networking and security

## Repository Status

This repository currently contains only the challenge specification. Implementation should include:
- Source code for Configuration Service and Log Aggregator Service
- Dockerfiles for each service
- Container orchestration manifests (Kubernetes YAML or Docker Compose)
- CI/CD pipeline configurations
- Service-specific README files with build/run instructions