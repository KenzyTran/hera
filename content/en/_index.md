---
title: "Hera — AWS Voice Agent Workshop"
date: 2025-01-01
weight: 0
---

# Hera — AWS Voice Agent Workshop

### Introduction

Hera is an FCJ (First Cloud Journey) workshop that walks you through deploying a voice AI chatbot in your own AWS account, talking to it from your browser, and tearing it back down to $0 right after the session. Pure-AWS stack: Amazon Nova 2 Sonic for the voice model, Amazon Bedrock AgentCore Runtime for managed compute, S3 Vectors + Titan v2 for the knowledge base, Pipecat 1.1.0 as orchestrator.

| Info | Details |
|------|---------|
| Duration | ~3-4 hours hands-on |
| Level | Intermediate |
| Cost | ~$2-5 USD if you clean up per Chapter 4 |
| Default region | ap-northeast-1 |

### Requirements

- AWS Account (IAM user with Administrator access, not the root account).
- Basic familiarity with AWS CLI / IAM / Terraform / Docker.
- Local machine with AWS CLI v2, Terraform >= 1.9, Docker Desktop (multi-arch buildx), uv (Python package manager), jq.
- Basic English reading ability (chatbot speech is English; documentation is bilingual vi/en).

### Content

{{% children depth="1" %}}
